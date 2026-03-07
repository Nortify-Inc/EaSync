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

SMART_HOME_HINTS = {
    "device", "devices", "lamp", "light", "lights", "ac", "climate", "hvac", "curtain", "blind", "shade",
    "lock", "door", "fridge", "freezer", "temperature", "brightness", "color", "colour", "mode", "profile",
    "automation", "routine", "home", "luz", "lâmpada", "cortina", "fechadura", "geladeira", "temperatura",
    "brilho", "cor", "perfil", "dispositivo", "dispositivos", "automação", "casa",
}

OOD_HINTS = {
    "world cup", "capital", "derivative", "stock", "restaurant", "black hole", "poem", "physics", "história",
    "física", "futebol", "copa", "ações", "investimento", "matemática", "buraco negro",
}


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


def isPortuguese(text: str) -> bool:
    lower = text.lower()
    return bool(re.search(r"\b(qual|quais|você|por favor|cortina|fechadura|temperatura|modo|agora|obrigado|obrigada)\b", lower))


def isLikelyOutOfDomain(text: str) -> bool:
    lower = text.lower()
    hasOod = any(hint in lower for hint in OOD_HINTS)
    hasSmartHome = any(hint in lower for hint in SMART_HOME_HINTS)
    return hasOod and not hasSmartHome


def sanitizeWeakResponse(intent: str, response: str, text: str) -> str:
    cleaned = (response or "").strip()
    lower = cleaned.lower()
    weakReplies = {
        "i can handle that",
        "got it",
        "understood",
        "sure",
        "ok",
        "entendi",
        "certo",
    }

    if intent == "outOfDomain" or isLikelyOutOfDomain(text):
        if isPortuguese(text):
            return "Esse pedido está fora do escopo de automação residencial. Posso ajudar com dispositivos, status, cenas e perfis da sua casa."
        return "This request is outside home-automation scope. I can help with device control, status checks, scenes, and profiles."

    if lower in weakReplies and intent in {"ambiguous", "queryStatus", "controlDevice"}:
        if isPortuguese(text):
            return "Preciso de mais contexto para agir com precisão: dispositivo, capacidade e valor desejado."
        return "I need a bit more context to act precisely: device, capability, and desired value."

    return cleaned


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
    topP: float = 0.92,
    repetitionPenalty: float = 1.12,
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
        usedCounts: dict[int, int] = {}

        for _ in range(maxResponse):
            emb = model.decoderEmbedding(inputIds[:, -1])
            stepInput = torch.cat([emb, previousContext], dim=1).unsqueeze(1)
            stepOutput, state = model.decoderLstm(stepInput, state)
            decoderHidden = stepOutput[:, 0, :]
            context = model.attend(decoderHidden, memory, padMask)
            logits = model.outputProjection(torch.cat([decoderHidden, context], dim=1))

            logits = logits / max(0.35, temperature)

            for tokenId, count in usedCounts.items():
                if count > 0:
                    logits[0, tokenId] = logits[0, tokenId] / (repetitionPenalty ** count)

            if topK > 0:
                values, indices = torch.topk(logits, k=min(topK, logits.size(-1)), dim=-1)
                probs = torch.softmax(values, dim=-1)

                sortedProbs, sortedIdx = torch.sort(probs[0], descending=True)
                cumulative = torch.cumsum(sortedProbs, dim=0)
                keepMask = cumulative <= topP
                if keepMask.numel() > 0:
                    keepMask[0] = True
                filtered = sortedProbs * keepMask
                if float(filtered.sum().item()) <= 0:
                    filtered = sortedProbs
                filtered = filtered / filtered.sum()
                pick = torch.multinomial(filtered, num_samples=1)
                selected = indices[0, sortedIdx[pick]]
                nextId = int(selected.item())
            else:
                nextId = int(torch.argmax(logits, dim=-1).item())

            if nextId in {eos, tokenizer.tokenToIndex[PAD]}:
                break

            outputIds.append(nextId)
            usedCounts[nextId] = usedCounts.get(nextId, 0) + 1
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

    if isLikelyOutOfDomain(text):
        intent = "outOfDomain"
    response = sanitizeWeakResponse(intent, response, text)

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
