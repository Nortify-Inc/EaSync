#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import torch

from chatTokenizer import BOS, EOS, PAD, ChatTokenizer
from hybridChatModel import HybridChatModel

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "models" / "artifacts" / "chat"


def extractEntities(text: str) -> dict[str, Any]:
    q = text.lower()
    entities: dict[str, Any] = {}

    numeric = re.search(r"-?\d{1,5}", q)
    if numeric:
        entities["numericValue"] = int(numeric.group(0))

    timeMatch = re.search(r"\b([01]?\d|2[0-3]):[0-5]\d\b", q)
    if timeMatch:
        entities["time"] = timeMatch.group(0)

    hexColor = re.search(r"#([0-9a-f]{6})\b", q)
    if hexColor:
        entities["hexColor"] = "#" + hexColor.group(1)

    return entities


def loadArtifacts() -> tuple[HybridChatModel, ChatTokenizer, dict[str, Any]]:
    with (ARTIFACT_DIR / "labelMaps.json").open("r", encoding="utf-8") as f:
        labelMaps = json.load(f)

    tokenizer = ChatTokenizer.load(ARTIFACT_DIR / "vocab.json")

    model = HybridChatModel(
        vocabSize=len(tokenizer.tokenToIndex),
        intentClasses=len(labelMaps["intentToIndex"]),
        styleClasses=len(labelMaps["styleToIndex"]),
        capabilityClasses=len(labelMaps["capabilityToIndex"]),
        operationClasses=len(labelMaps["operationToIndex"]),
        maxLen=int(labelMaps.get("maxInput", 96)),
    )

    state = torch.load(ARTIFACT_DIR / "hybridChatModel.pt", map_location="cpu")
    model.load_state_dict(state)
    model.eval()

    return model, tokenizer, labelMaps


def pickLabel(logits: torch.Tensor, indexMap: dict[str, str]) -> str:
    idx = int(torch.argmax(logits, dim=1).item())
    return indexMap[str(idx)]


def confidence(logits: torch.Tensor) -> float:
    probs = torch.softmax(logits, dim=1)
    return float(torch.max(probs, dim=1).values.item())


def generateResponse(
    model: HybridChatModel,
    tokenizer: ChatTokenizer,
    x: torch.Tensor,
    lengths: torch.Tensor,
    maxResponse: int,
    temperature: float = 0.85,
    topK: int = 20,
) -> str:
    with torch.no_grad():
        encoded = model(x, lengths)
        memory = encoded["memory"]
        shared = encoded["shared"]
        padMask = encoded["padMask"]

        batch = x.size(0)
        h0 = torch.tanh(model.initH(shared)).view(batch, 2, model.lstmHidden).transpose(0, 1).contiguous()
        c0 = torch.tanh(model.initC(shared)).view(batch, 2, model.lstmHidden).transpose(0, 1).contiguous()
        state = (h0, c0)

        bos = tokenizer.tokenToIndex[BOS]
        eos = tokenizer.tokenToIndex[EOS]
        inputIds = torch.tensor([[bos]], dtype=torch.long)
        previousContext = torch.zeros(1, model.dModel)

        outputIds: list[int] = []

        for _ in range(maxResponse):
            emb = model.decoderEmbedding(inputIds[:, -1])
            stepInput = torch.cat([emb, previousContext], dim=1).unsqueeze(1)
            stepOutput, state = model.decoderLstm(stepInput, state)
            decoderHidden = stepOutput[:, 0, :]
            context = model.attend(decoderHidden, memory, padMask)
            logits = model.outputProjection(torch.cat([decoderHidden, context], dim=1))

            logits = logits / max(0.35, temperature)

            if topK > 0:
                values, indices = torch.topk(logits, k=min(topK, logits.size(-1)), dim=-1)
                probs = torch.softmax(values, dim=-1)
                selected = indices[0, torch.multinomial(probs[0], num_samples=1)]
                nextId = int(selected.item())
            else:
                nextId = int(torch.argmax(logits, dim=-1).item())

            if nextId in {eos, tokenizer.tokenToIndex[PAD]}:
                break

            outputIds.append(nextId)
            inputIds = torch.cat([inputIds, torch.tensor([[nextId]], dtype=torch.long)], dim=1)
            previousContext = context

    return tokenizer.decode(outputIds)


def predictMessage(text: str) -> dict[str, Any]:
    temperament = ""
    match = re.search(r"\[TEMPERAMENT=([^\]]+)\]", text, re.IGNORECASE)
    if match:
        temperament = match.group(1).strip().lower()
        text = re.sub(r"\[TEMPERAMENT=[^\]]+\]", " ", text, flags=re.IGNORECASE)

    model, tokenizer, labelMaps = loadArtifacts()

    maxInput = int(labelMaps.get("maxInput", 96))
    maxResponse = int(labelMaps.get("maxResponse", 72))

    x = torch.tensor([tokenizer.encode(text, maxLen=maxInput, addBosEos=False)], dtype=torch.long)
    length = max(1, int((x[0] != tokenizer.tokenToIndex[PAD]).sum().item()))
    lengths = torch.tensor([length], dtype=torch.long)

    with torch.no_grad():
        out = model(x, lengths)

    intent = pickLabel(out["intent"], labelMaps["indexToIntent"])
    style = pickLabel(out["style"], labelMaps["indexToStyle"])
    capability = pickLabel(out["capability"], labelMaps["indexToCapability"])
    operation = pickLabel(out["operation"], labelMaps["indexToOperation"])

    if temperament in {"minimalist", "cheerful", "direct", "professional", "empathetic", "calm"}:
        style = temperament

    response = generateResponse(model, tokenizer, x, lengths, maxResponse=maxResponse)

    return {
        "intent": intent,
        "responseStyle": style,
        "predictedCapability": capability,
        "predictedOperation": operation,
        "generatedResponse": response,
        "needsClarification": intent in {"ambiguous", "unknown"} or confidence(out["intent"]) < 0.45,
        "intentConfidence": round(confidence(out["intent"]), 6),
        "entities": extractEntities(text),
    }
