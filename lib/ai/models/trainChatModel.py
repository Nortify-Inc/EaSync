#!/usr/bin/env python3
from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset

from chatTokenizer import BOS, EOS, PAD, ChatTokenizer
from hybridChatModel import HybridChatModel

SEED = 73
random.seed(SEED)
torch.manual_seed(SEED)

ROOT = Path(__file__).resolve().parents[1]
DATASET_PATH = ROOT / "data" / "chatDatasetV2.jsonl"
ARTIFACT_DIR = ROOT / "models" / "artifacts" / "chat"

MAX_INPUT = 96
MAX_RESPONSE = 72
BATCH_SIZE = 80
EPOCHS = 12
LEARNING_RATE = 8e-4


@dataclass
class ChatRow:
    text: str
    intent: str
    style: str
    capability: str
    operation: str
    targetResponse: str


def loadRows(path: Path) -> list[ChatRow]:
    rows: list[ChatRow] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            raw = json.loads(line)
            actions = raw.get("canonicalActions") or []
            a0 = actions[0] if actions and isinstance(actions[0], dict) else {}
            rows.append(
                ChatRow(
                    text=str(raw.get("text", "")),
                    intent=str(raw.get("intent", "unknown")),
                    style=str(raw.get("responseStyle", "minimalist")),
                    capability=str(a0.get("capability") or "none"),
                    operation=str(a0.get("operation") or "none"),
                    targetResponse=str(raw.get("targetResponse", "")),
                )
            )
    return rows


def buildLabelMap(values: list[str]) -> tuple[dict[str, int], dict[int, str]]:
    unique = sorted(set(values))
    toIndex = {v: i for i, v in enumerate(unique)}
    fromIndex = {i: v for v, i in toIndex.items()}
    return toIndex, fromIndex


def splitRows(rows: list[ChatRow], valRatio: float = 0.12) -> tuple[list[ChatRow], list[ChatRow]]:
    rows = rows[:]
    random.shuffle(rows)
    cut = max(1, int(len(rows) * (1 - valRatio)))
    return rows[:cut], rows[cut:]


class ChatDataset(Dataset):
    def __init__(
        self,
        rows: list[ChatRow],
        tokenizer: ChatTokenizer,
        intentMap: dict[str, int],
        styleMap: dict[str, int],
        capabilityMap: dict[str, int],
        operationMap: dict[str, int],
        trainMode: bool = False,
    ):
        self.rows = rows
        self.tokenizer = tokenizer
        self.intentMap = intentMap
        self.styleMap = styleMap
        self.capabilityMap = capabilityMap
        self.operationMap = operationMap
        self.trainMode = trainMode
        self.padId = tokenizer.tokenToIndex[PAD]

    def __len__(self) -> int:
        return len(self.rows)

    def encodeResponse(self, text: str) -> tuple[list[int], list[int]]:
        ids = self.tokenizer.encode(text, maxLen=MAX_RESPONSE - 2, addBosEos=False)
        ids = [i for i in ids if i != self.padId]
        bos = self.tokenizer.tokenToIndex[BOS]
        eos = self.tokenizer.tokenToIndex[EOS]
        sequence = [bos] + ids + [eos]

        decoderInput = sequence[:-1][:MAX_RESPONSE]
        decoderOutput = sequence[1:][:MAX_RESPONSE]

        if len(decoderInput) < MAX_RESPONSE:
            decoderInput += [self.padId] * (MAX_RESPONSE - len(decoderInput))
            decoderOutput += [self.padId] * (MAX_RESPONSE - len(decoderOutput))

        return decoderInput, decoderOutput

    def __getitem__(self, index: int):
        row = self.rows[index]
        x = self.tokenizer.encode(row.text, maxLen=MAX_INPUT, addBosEos=False)

        if self.trainMode:
            for i in range(len(x)):
                if x[i] == self.padId:
                    break
                if random.random() < 0.02:
                    x[i] = self.tokenizer.tokenToIndex.get("<UNK>", 1)

        length = sum(1 for token in x if token != self.padId)
        decoderInput, decoderOutput = self.encodeResponse(row.targetResponse)

        return (
            torch.tensor(x, dtype=torch.long),
            torch.tensor(max(1, length), dtype=torch.long),
            torch.tensor(self.intentMap[row.intent], dtype=torch.long),
            torch.tensor(self.styleMap[row.style], dtype=torch.long),
            torch.tensor(self.capabilityMap.get(row.capability, self.capabilityMap["none"]), dtype=torch.long),
            torch.tensor(self.operationMap.get(row.operation, self.operationMap["none"]), dtype=torch.long),
            torch.tensor(decoderInput, dtype=torch.long),
            torch.tensor(decoderOutput, dtype=torch.long),
        )


def accuracy(logits: torch.Tensor, y: torch.Tensor) -> float:
    pred = torch.argmax(logits, dim=1)
    return float((pred == y).float().mean().item())


def main() -> int:
    if not DATASET_PATH.exists():
        raise FileNotFoundError(f"Dataset not found: {DATASET_PATH}")

    rows = loadRows(DATASET_PATH)
    if not rows:
        raise RuntimeError("Dataset is empty")

    trainRows, valRows = splitRows(rows)

    tokenizer = ChatTokenizer.build(
        [r.text for r in rows] + [r.targetResponse for r in rows],
        maxVocab=90000,
        minFreq=2,
    )

    intentMap, idxIntent = buildLabelMap([r.intent for r in rows])
    styleMap, idxStyle = buildLabelMap([r.style for r in rows])
    capabilityMap, idxCapability = buildLabelMap([r.capability for r in rows] + ["none"])
    operationMap, idxOperation = buildLabelMap([r.operation for r in rows] + ["none"])

    trainDataset = ChatDataset(trainRows, tokenizer, intentMap, styleMap, capabilityMap, operationMap, trainMode=True)
    valDataset = ChatDataset(valRows, tokenizer, intentMap, styleMap, capabilityMap, operationMap, trainMode=False)

    trainLoader = DataLoader(trainDataset, batch_size=BATCH_SIZE, shuffle=True)
    valLoader = DataLoader(valDataset, batch_size=BATCH_SIZE, shuffle=False)

    device = torch.device("cpu")

    model = HybridChatModel(
        vocabSize=len(tokenizer.tokenToIndex),
        intentClasses=len(intentMap),
        styleClasses=len(styleMap),
        capabilityClasses=len(capabilityMap),
        operationClasses=len(operationMap),
        maxLen=MAX_INPUT,
    ).to(device)

    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=2e-4)
    padId = tokenizer.tokenToIndex[PAD]

    bestScore = -1.0
    bestState: dict[str, Any] | None = None

    for epoch in range(1, EPOCHS + 1):
        model.train()
        lossSum = 0.0
        steps = 0

        for x, lengths, yIntent, yStyle, yCapability, yOperation, responseInput, responseOutput in trainLoader:
            x = x.to(device)
            lengths = lengths.to(device)
            yIntent = yIntent.to(device)
            yStyle = yStyle.to(device)
            yCapability = yCapability.to(device)
            yOperation = yOperation.to(device)
            responseInput = responseInput.to(device)
            responseOutput = responseOutput.to(device)

            out = model(x, lengths, responseInput)
            responseLogits = out["responseLogits"].reshape(-1, out["responseLogits"].size(-1))
            responseTargets = responseOutput.reshape(-1)

            loss = (
                F.cross_entropy(out["intent"], yIntent, label_smoothing=0.05)
                + F.cross_entropy(out["style"], yStyle, label_smoothing=0.03)
                + F.cross_entropy(out["capability"], yCapability, label_smoothing=0.03)
                + F.cross_entropy(out["operation"], yOperation, label_smoothing=0.03)
                + 0.85 * F.cross_entropy(responseLogits, responseTargets, ignore_index=padId)
            )

            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()

            lossSum += float(loss.item())
            steps += 1

        model.eval()
        valIntent = 0.0
        valStyle = 0.0
        valCapability = 0.0
        valOperation = 0.0
        valResponse = 0.0
        batches = 0

        with torch.no_grad():
            for x, lengths, yIntent, yStyle, yCapability, yOperation, responseInput, responseOutput in valLoader:
                x = x.to(device)
                lengths = lengths.to(device)
                yIntent = yIntent.to(device)
                yStyle = yStyle.to(device)
                yCapability = yCapability.to(device)
                yOperation = yOperation.to(device)
                responseInput = responseInput.to(device)
                responseOutput = responseOutput.to(device)

                out = model(x, lengths, responseInput)
                valIntent += accuracy(out["intent"], yIntent)
                valStyle += accuracy(out["style"], yStyle)
                valCapability += accuracy(out["capability"], yCapability)
                valOperation += accuracy(out["operation"], yOperation)

                pred = torch.argmax(out["responseLogits"], dim=-1)
                mask = responseOutput != padId
                if mask.any():
                    valResponse += float((pred[mask] == responseOutput[mask]).float().mean().item())
                batches += 1

        valIntent /= max(1, batches)
        valStyle /= max(1, batches)
        valCapability /= max(1, batches)
        valOperation /= max(1, batches)
        valResponse /= max(1, batches)

        score = 0.30 * valIntent + 0.15 * valStyle + 0.20 * valCapability + 0.15 * valOperation + 0.20 * valResponse

        print(
            f"epoch={epoch} loss={lossSum / max(1, steps):.4f} "
            f"val(intent/style/cap/op/respTok)={valIntent:.4f}/{valStyle:.4f}/{valCapability:.4f}/{valOperation:.4f}/{valResponse:.4f} "
            f"score={score:.4f}"
        )

        if score > bestScore:
            bestScore = score
            bestState = {k: v.detach().cpu() for k, v in model.state_dict().items()}

    if bestState is not None:
        model.load_state_dict(bestState)

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), ARTIFACT_DIR / "hybridChatModel.pt")
    tokenizer.save(ARTIFACT_DIR / "vocab.json")

    labelMaps = {
        "intentToIndex": intentMap,
        "styleToIndex": styleMap,
        "capabilityToIndex": capabilityMap,
        "operationToIndex": operationMap,
        "indexToIntent": {str(k): v for k, v in idxIntent.items()},
        "indexToStyle": {str(k): v for k, v in idxStyle.items()},
        "indexToCapability": {str(k): v for k, v in idxCapability.items()},
        "indexToOperation": {str(k): v for k, v in idxOperation.items()},
        "maxInput": MAX_INPUT,
        "maxResponse": MAX_RESPONSE,
    }
    with (ARTIFACT_DIR / "labelMaps.json").open("w", encoding="utf-8") as f:
        json.dump(labelMaps, f, ensure_ascii=False, indent=2)

    modelConfig = {
        "architecture": "transformerEncoderPlusLstmDecoder",
        "dModel": 256,
        "nHead": 8,
        "encoderLayers": 4,
        "ffDim": 768,
        "lstmHidden": 320,
        "dropout": 0.2,
        "seed": SEED,
    }
    with (ARTIFACT_DIR / "modelConfig.json").open("w", encoding="utf-8") as f:
        json.dump(modelConfig, f, ensure_ascii=False, indent=2)

    print(f"artifacts={ARTIFACT_DIR}")
    print(f"bestScore={bestScore:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
