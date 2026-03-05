#!/usr/bin/env python3
from __future__ import annotations

import json
import random
import re
from pathlib import Path

SEED = 73
random.seed(SEED)

DATA_DIR = Path(__file__).resolve().parent
CHAT_DATASET = DATA_DIR / "chatDatasetV2.jsonl"

intents = [
    "greeting",
    "gratitude",
    "smalltalk",
    "farewell",
    "listDevices",
    "listOnline",
    "queryStatus",
    "controlDevice",
    "applyProfile",
    "outOfDomain",
    "ambiguous",
]

tones = ["minimalist", "cheerful", "direct", "professional", "empathetic", "calm"]
moods = ["neutral", "warm", "confident", "excited", "focused", "urgent", "relaxed"]
emotions = ["none", "joy", "empathy", "confidence", "curiosity", "gratitude"]

devices = {
    "ac": ["ac", "air conditioner", "climate", "hvac", "ar condicionado"],
    "lamp": ["lamp", "light", "lights", "luz", "lâmpada"],
    "curtain": ["curtain", "blinds", "shade", "cortina", "persiana"],
    "lock": ["lock", "door lock", "fechadura", "tranca"],
    "fridge": ["fridge", "refrigerator", "geladeira"],
    "freezer": ["freezer", "congelador"],
}

capabilities = {
    "power": ["power", "on", "off", "ligado", "desligado"],
    "brightness": ["brightness", "brilho", "intensity", "luminosidade"],
    "temperature": ["temperature", "temp", "temperatura"],
    "temperatureFridge": ["fridge temperature", "geladeira temperatura"],
    "temperatureFreezer": ["freezer temperature", "congelador temperatura"],
    "position": ["position", "open", "close", "posição", "abrir", "fechar"],
    "color": ["color", "colour", "cor"],
    "colorTemperature": ["color temperature", "kelvin", "temperatura de cor"],
    "mode": ["mode", "preset", "profile", "modo"],
    "lock": ["lock", "unlock", "trancar", "destrancar"],
    "timestamp": ["timestamp", "time", "hora", "horário"],
}

colors = [
    "blue", "green", "red", "purple", "yellow", "orange", "white", "cyan",
    "azul", "verde", "vermelho", "roxo", "amarelo", "laranja", "branco",
    "#FFAA00", "#00AEEF", "0x33CC99", "rgb(255,120,20)",
]

profiles = ["game", "movie", "relax", "sleep", "focus", "arrival", "night-security"]

greetings = ["hello", "hi", "hey", "good morning", "good evening", "oi", "olá", "bom dia", "boa noite"]
thanks = ["thanks", "thank you", "thx", "valeu", "obrigado", "obrigada"]
smalltalk = [
    "how are you", "how is it going", "what can you do", "can you help me automate my home",
    "tudo bem", "você consegue me ajudar", "quais tarefas você faz",
]
farewells = ["bye", "see you", "good night", "tchau", "até mais", "até depois"]
outOfDomain = [
    "who won the world cup in 2002",
    "write a poem about the ocean",
    "what is the derivative of x squared",
    "recommend a restaurant near me",
    "qual a capital da frança",
    "me ensina física quântica",
    "best stock for 2026",
]
ambiguous = ["make it better", "too hot here", "fix this", "deixa confortável", "resolve isso"]

statusTemplates = [
    "what is {capability} on {device}",
    "check {device} {capability}",
    "show {capability} of {device}",
    "qual o {capability} do {device}",
    "me diga {capability} do {device}",
]

actionTemplates = [
    "set {device} {capability} to {value}",
    "please adjust {device} {capability} to {value}",
    "change {device} {capability} -> {value}",
    "defina {capability} do {device} para {value}",
    "ajusta {device} {capability} para {value}",
]


def detectLanguage(text: str) -> str:
    t = text.lower()
    if re.search(r"\b(qual|quais|você|obrigado|obrigada|cortina|fechadura|temperatura|modo|agora|por favor)\b", t):
        return "pt"
    return "en"


def maybeNoise(text: str) -> str:
    out = text
    if random.random() < 0.2:
        out = "please " + out
    if random.random() < 0.18:
        out += random.choice([" now", " right now", " asap", " agora", " por favor"])
    if random.random() < 0.08:
        out = out.replace("temperature", "tempeature")
    if random.random() < 0.06:
        out = out.replace("brightness", "brighness")
    return out


def sampleValue(capability: str):
    if capability == "power":
        return random.choice(["on", "off", "true", "false"])
    if capability == "brightness":
        return random.choice([0, 5, 10, 20, 35, 50, 65, 80, 95, 100])
    if capability == "temperature":
        return random.choice([16, 18, 20, 21, 22, 23, 24, 25, 26, 28, 30])
    if capability == "temperatureFridge":
        return random.choice([1, 2, 3, 4, 5, 6, 7, 8])
    if capability == "temperatureFreezer":
        return random.choice([-24, -22, -20, -18, -16, -14])
    if capability == "position":
        return random.choice([0, 10, 25, 35, 50, 65, 75, 90, 100])
    if capability == "color":
        return random.choice(colors)
    if capability == "colorTemperature":
        return random.choice([1800, 2200, 2700, 3000, 4000, 5000, 6500, 8000])
    if capability == "mode":
        return random.choice(["eco", "turbo", "sleep", "comfort", "auto", "focus"])
    if capability == "lock":
        return random.choice(["lock", "unlock"])
    if capability == "timestamp":
        return random.choice([1700000000, 1700003600, 1712345678, 1720000000])
    return random.choice([0, 1])


def responseSeed(intent: str) -> str:
    if intent in {"greeting", "gratitude", "smalltalk", "farewell", "outOfDomain", "ambiguous"}:
        words = [
            "understood", "context", "ready", "interpreting", "request", "safely", "analysis",
            "assistant", "workflow", "device", "state", "automation", "available", "guidance",
        ]
        return " ".join(random.sample(words, k=random.randint(4, 8)))
    return " ".join(random.sample([
        "command", "parsed", "context", "validated", "execution", "action", "capability", "value", "device", "ready"
    ], k=random.randint(4, 8)))


def buildRow(idx: int, text: str, intent: str, entities: dict | None = None, actions: list | None = None):
    return {
        "id": f"chatV2_{idx:08d}",
        "text": text,
        "language": detectLanguage(text),
        "intent": intent,
        "entities": entities or {},
        "canonicalActions": actions or [],
        "responseStyle": random.choice(tones),
        "mood": random.choice(moods),
        "emotion": random.choice(emotions),
        "targetResponse": responseSeed(intent),
    }


def generateChatDataset(targetSize: int = 300000):
    rows: list[dict] = []
    idx = 1

    for item in greetings:
        rows.append(buildRow(idx, item, "greeting")); idx += 1
    for item in thanks:
        rows.append(buildRow(idx, item, "gratitude")); idx += 1
    for item in smalltalk:
        rows.append(buildRow(idx, item, "smalltalk")); idx += 1
    for item in farewells:
        rows.append(buildRow(idx, item, "farewell")); idx += 1
    for item in outOfDomain:
        rows.append(buildRow(idx, item, "outOfDomain")); idx += 1
    for item in ambiguous:
        rows.append(buildRow(idx, item, "ambiguous")); idx += 1

    while len(rows) < targetSize:
        p = random.random()

        if p < 0.10:
            phrase = random.choice(greetings + thanks + smalltalk + farewells)
            if phrase in greetings:
                intent = "greeting"
            elif phrase in thanks:
                intent = "gratitude"
            elif phrase in smalltalk:
                intent = "smalltalk"
            else:
                intent = "farewell"
            rows.append(buildRow(idx, maybeNoise(phrase), intent)); idx += 1
            continue

        if p < 0.16:
            rows.append(buildRow(idx, maybeNoise(random.choice(outOfDomain)), "outOfDomain")); idx += 1
            continue

        if p < 0.20:
            rows.append(buildRow(idx, maybeNoise(random.choice(ambiguous)), "ambiguous")); idx += 1
            continue

        if p < 0.26:
            text = maybeNoise(random.choice([
                "list devices", "show all devices", "what devices do i have", "listar dispositivos",
                "show online devices", "quais dispositivos estao online",
            ]))
            rows.append(buildRow(idx, text, "listOnline" if "online" in text.lower() else "listDevices")); idx += 1
            continue

        if p < 0.31:
            profile = random.choice(profiles)
            text = maybeNoise(random.choice([
                f"apply {profile} profile",
                f"activate {profile} profile",
                f"aplicar perfil {profile}",
                f"ativar perfil {profile}",
            ]))
            rows.append(buildRow(idx, text, "applyProfile", entities={"profile": profile})); idx += 1
            continue

        deviceKey = random.choice(list(devices.keys()))
        device = random.choice(devices[deviceKey])
        capabilityKey = random.choice(list(capabilities.keys()))
        capability = random.choice(capabilities[capabilityKey])

        if random.random() < 0.46:
            text = maybeNoise(random.choice(statusTemplates).format(device=device, capability=capability))
            rows.append(
                buildRow(
                    idx,
                    text,
                    "queryStatus",
                    entities={"deviceHint": deviceKey, "capability": capabilityKey},
                )
            )
            idx += 1
            continue

        value = sampleValue(capabilityKey)
        text = maybeNoise(random.choice(actionTemplates).format(device=device, capability=capability, value=value))
        actions = [{
            "deviceHint": deviceKey,
            "capability": capabilityKey,
            "operation": "set",
            "value": value,
        }]

        if random.random() < 0.30:
            deviceKey2 = random.choice(list(devices.keys()))
            device2 = random.choice(devices[deviceKey2])
            capabilityKey2 = random.choice(["power", "brightness", "position", "lock", "color", "mode"])
            capability2 = random.choice(capabilities[capabilityKey2])
            value2 = sampleValue(capabilityKey2)
            text += random.choice([" and ", " then ", "; ", " e depois "]) + f"set {device2} {capability2} to {value2}"
            actions.append({
                "deviceHint": deviceKey2,
                "capability": capabilityKey2,
                "operation": "set",
                "value": value2,
            })

        rows.append(
            buildRow(
                idx,
                text,
                "controlDevice",
                entities={"deviceHint": deviceKey, "capability": capabilityKey, "value": value},
                actions=actions,
            )
        )
        idx += 1

    with CHAT_DATASET.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"dataset={CHAT_DATASET}")
    print(f"rows={len(rows)}")


if __name__ == "__main__":
    generateChatDataset()
