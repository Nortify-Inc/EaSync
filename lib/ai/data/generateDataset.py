#!/usr/bin/env python3
from __future__ import annotations

import json
import random
import re
from pathlib import Path

SEED = 73
random.seed(SEED)

dataDir = Path(__file__).resolve().parent
chatDatasetPath = dataDir / "chatDatasetV2.jsonl"

tones = ["minimalist", "cheerful", "direct", "professional", "empathetic", "calm", "playful"]
moods = ["neutral", "warm", "confident", "excited", "focused", "urgent", "relaxed", "curious"]
emotions = ["none", "joy", "empathy", "confidence", "curiosity", "gratitude", "enthusiasm"]

devices = {
    "ac": ["ac", "air conditioner", "climate", "hvac", "ar condicionado"],
    "lamp": ["lamp", "light", "lights", "luz", "lâmpada", "spot light"],
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
    "#ffaa00", "#00aeef", "0x33cc99", "rgb(255,120,20)",
]

profiles = ["game", "movie", "relax", "sleep", "focus", "arrival", "night-security", "energy-save"]

greetings = ["hello", "hi", "hey", "good morning", "good evening", "oi", "olá", "bom dia", "boa noite"]
thanks = ["thanks", "thank you", "thx", "valeu", "obrigado", "obrigada"]
smalltalk = [
    "how are you",
    "how is it going",
    "what can you do",
    "can you help me automate my home",
    "tudo bem",
    "você consegue me ajudar",
    "quais tarefas você faz",
    "what are your capabilities",
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
    "explain black holes",
]
outOfDomainAdversarial = [
    "in my smart home, who won the world cup in 2002",
    "before changing my lights, tell me the capital of france",
    "in this automation context, write a poem about the ocean",
    "na minha casa inteligente, quem ganhou a copa de 2002",
    "antes de ajustar a cortina, qual a capital da frança",
]
ambiguous = ["make it better", "too hot here", "fix this", "deixa confortável", "resolve isso", "not good now"]
unsupportedComboPrompts = [
    "lock the ac",
    "trancar o ar condicionado",
    "set lock on fridge",
    "coloque modo turbo na fechadura",
    "set curtain temperature to 18",
    "defina brilho da fechadura para 60",
    "change lamp freezer temperature to -18",
]
correctionOpeners = [
    "actually, cancel that and",
    "wait, correction:",
    "mudando, agora",
    "corrigindo,",
    "ignore previous and",
]
codeSwitchSnippets = [
    "ajusta the living room lamp",
    "set a cortina da sala",
    "please trancar the main door lock",
    "deixa o ac em 22 celsius now",
]

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

assistantSeedShort = [
    "ok, entendi",
    "certo, vamos ajustar",
    "understood, proceeding",
    "got it, applying now",
    "perfeito, vou configurar",
    "all right, done",
]

conversationOpeners = [
    "Earlier the user said: {u0}.",
    "Context from previous turn: {u0}.",
    "Before this request, user said: {u0}.",
]

conversationBridges = [
    "Now the user asks: {u1}.",
    "Then the user continues: {u1}.",
    "In the next turn, user says: {u1}.",
    "Agora o usuário pede: {u1}.",
    "No turno seguinte, usuário diz: {u1}.",
]

contextTerms = [
    "context", "request", "state", "constraints", "intent", "clarity", "device", "capability",
    "automation", "safety", "consistency", "feedback", "workflow", "goal", "result", "precision",
    "adaptação", "interpretação", "coerência", "lógica",
]

warmTerms = [
    "friendly", "humanized", "natural", "helpful", "empathetic", "clear", "calm", "confident",
    "didático", "acolhedor", "objetivo", "assertivo",
]


def detectLanguage(text: str) -> str:
    lower = text.lower()
    if re.search(r"\b(qual|quais|você|obrigado|obrigada|cortina|fechadura|temperatura|modo|agora|por favor|entendi|certo)\b", lower):
        return "pt"
    return "en"


def maybeNoise(text: str) -> str:
    out = text
    if random.random() < 0.20:
        out = "please " + out
    if random.random() < 0.18:
        out += random.choice([" now", " right now", " asap", " agora", " por favor"])
    if random.random() < 0.08:
        out = out.replace("temperature", "tempeature")
    if random.random() < 0.06:
        out = out.replace("brightness", "brighness")
    if random.random() < 0.04:
        out = out.replace("assistant", "assisstant")
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


def formatValueVariant(capability: str, value, language: str) -> str:
    if capability in {"temperature", "temperatureFridge", "temperatureFreezer"}:
        unit = random.choice(["°C", "c", "celsius", "graus"])
        return f"{value}{'' if unit == '°C' else ' '}{unit}"
    if capability in {"brightness", "position"}:
        if isinstance(value, int):
            return random.choice([f"{value}", f"{value}%", f"{value} percent", f"{value} por cento"])
    if capability == "colorTemperature":
        return random.choice([f"{value}k", f"{value} kelvin", f"{value}"])
    if capability == "power":
        if language == "pt":
            return random.choice(["ligado", "desligado", "on", "off"])
        return random.choice(["on", "off", "enabled", "disabled"])
    return str(value)


def maybeCodeSwitch(text: str) -> str:
    if random.random() < 0.14:
        return f"{random.choice(codeSwitchSnippets)} and {text}"
    return text


def maybeCorrectionTurn(text: str) -> str:
    if random.random() < 0.18:
        return f"{random.choice(correctionOpeners)} {text}"
    return text


def buildDialogueText(currentUserText: str) -> str:
    if random.random() > 0.72:
        return currentUserText

    firstUser = random.choice(greetings + smalltalk + ambiguous + thanks)
    turns = [random.choice(conversationOpeners).format(u0=firstUser)]

    if random.random() < 0.88:
        turns.append(f"Assistant replied: {random.choice(assistantSeedShort)}.")

    turns.append(random.choice(conversationBridges).format(u1=currentUserText))

    if random.random() < 0.45:
        turns.append(f"Assistant answered: {random.choice(assistantSeedShort)}.")

    if random.random() < 0.30:
        followUp = random.choice(
            [
                "can you optimize this",
                "show me details",
                "apply safe mode",
                "and explain reasoning",
                "mostra os detalhes",
                "explique o raciocínio",
                "faça isso com segurança",
            ]
        )
        turns.append(f"Follow-up from user: {followUp}.")

    return " ".join(turns)


def stylePrefix(tone: str, mood: str) -> str:
    if tone in {"professional", "direct", "minimalist"} or mood in {"focused", "urgent"}:
        return "clear and concise"
    if tone in {"empathetic", "calm"} or mood in {"warm", "relaxed"}:
        return "supportive and calm"
    return "friendly and natural"


def buildLongResponse(intent: str, tone: str, mood: str, entities: dict | None, actions: list | None) -> str:
    entities = entities or {}
    actions = actions or []

    cap = str(entities.get("capability") or "general")
    deviceHint = str(entities.get("deviceHint") or "device")

    coreA = " ".join(random.sample(contextTerms, k=4))
    coreB = " ".join(random.sample(contextTerms, k=4))
    prefix = stylePrefix(tone, mood)

    if intent == "queryStatus":
        return (
            f"I understood this as a status request for {cap} on {deviceHint}. "
            f"I will check the latest available state and report it in a {prefix} way. "
            f"If the target device is unclear, I will ask a short clarification question."
        )

    if intent == "controlDevice":
        op = "set"
        if actions and isinstance(actions[0], dict):
            op = str(actions[0].get("operation") or "set")
        value = entities.get("value")
        valueText = f" value {value}" if value is not None else ""
        return (
            f"I interpreted this as a control command: operation {op} on {cap}{valueText}. "
            f"I will execute with validation and keep consistency across follow-up turns. "
            f"If anything is ambiguous, I will request missing parameters before changing a device."
        )

    if intent == "applyProfile":
        profile = str(entities.get("profile") or "custom")
        return (
            f"I recognized a profile activation request for {profile}. "
            f"I can apply the profile safely and summarize the expected device changes. "
            f"If needed, I can also suggest adjustments after activation."
        )

    if intent == "listDevices":
        return (
            "I understood that you want the device inventory. "
            "I can list registered devices and their main capabilities. "
            "If you want, I can filter by room, type, or protocol."
        )

    if intent == "listOnline":
        return (
            "I understood that you want online connectivity status. "
            "I can list online devices and flag unstable ones. "
            "Then I can continue with diagnostics if needed."
        )

    if intent == "outOfDomain":
        return (
            "This topic is outside smart-home automation scope. "
            "I cannot answer general knowledge questions here. "
            "I can help with device control, status checks, routines, and profiles."
        )

    if intent == "ambiguous":
        return (
            "Your request is ambiguous for safe execution. "
            "Please provide device, capability, and target value. "
            "With that, I can proceed accurately."
        )

    if intent == "unsupportedCapability":
        return (
            "This device-capability combination is not supported. "
            "I cannot apply that action safely on the selected device. "
            "Please choose a compatible capability or a different device."
        )

    if intent in {"greeting", "gratitude", "smalltalk", "farewell"}:
        return (
            "Great. I can help with your home automation tasks. "
            "Ask me to control a device, check status, or apply a profile. "
            "I will keep responses clear and practical."
        )

    return (
        "I interpreted your message and can proceed with structured automation support. "
        "If needed, I will ask a concise clarification to avoid wrong actions. "
        f"{coreA}."
    )


def buildRow(
    idx: int,
    text: str,
    intent: str,
    entities: dict | None = None,
    actions: list | None = None,
):
    tone = random.choice(tones)
    mood = random.choice(moods)
    return {
        "id": f"chatV2_{idx:08d}",
        "text": text,
        "language": detectLanguage(text),
        "intent": intent,
        "entities": entities or {},
        "canonicalActions": actions or [],
        "responseStyle": tone,
        "mood": mood,
        "emotion": random.choice(emotions),
        "targetResponse": buildLongResponse(intent, tone, mood, entities, actions),
    }


def generateChatDataset(targetSize: int = 220000):
    rows: list[dict] = []
    idx = 1
    intentCount: dict[str, int] = {}

    def push(row: dict):
        nonlocal idx
        rows.append(row)
        intent = str(row.get("intent") or "unknown")
        intentCount[intent] = intentCount.get(intent, 0) + 1
        idx += 1

    for item in greetings:
        push(buildRow(idx, item, "greeting"))
    for item in thanks:
        push(buildRow(idx, item, "gratitude"))
    for item in smalltalk:
        push(buildRow(idx, item, "smalltalk"))
    for item in farewells:
        push(buildRow(idx, item, "farewell"))
    for item in outOfDomain:
        push(buildRow(idx, item, "outOfDomain"))
    for item in outOfDomainAdversarial:
        push(buildRow(idx, item, "outOfDomain"))
    for item in ambiguous:
        push(buildRow(idx, item, "ambiguous"))
    for item in unsupportedComboPrompts:
        push(buildRow(idx, item, "unsupportedCapability"))

    while len(rows) < targetSize:
        p = random.random()

        maxApplyProfile = int(targetSize * 0.08)
        maxListOnline = int(targetSize * 0.05)
        minOutOfDomain = int(targetSize * 0.06)

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

            utterance = maybeCorrectionTurn(maybeCodeSwitch(buildDialogueText(maybeNoise(phrase))))
            push(buildRow(idx, utterance, intent))
            continue

        if p < 0.16:
            if intentCount.get("outOfDomain", 0) > minOutOfDomain and random.random() < 0.35:
                p = 0.40
                continue
            source = random.choice(outOfDomain + outOfDomainAdversarial)
            utterance = maybeCorrectionTurn(maybeCodeSwitch(buildDialogueText(maybeNoise(source))))
            push(buildRow(idx, utterance, "outOfDomain"))
            continue

        if p < 0.20:
            utterance = maybeCorrectionTurn(maybeCodeSwitch(buildDialogueText(maybeNoise(random.choice(ambiguous)))))
            push(buildRow(idx, utterance, "ambiguous"))
            continue

        if p < 0.22:
            utterance = maybeCorrectionTurn(maybeCodeSwitch(buildDialogueText(maybeNoise(random.choice(unsupportedComboPrompts)))))
            push(buildRow(idx, utterance, "unsupportedCapability"))
            continue

        if p < 0.29:
            if intentCount.get("listOnline", 0) >= maxListOnline and random.random() < 0.60:
                p = 0.45
                continue
            text = buildDialogueText(
                maybeNoise(
                    random.choice(
                        [
                            "list devices",
                            "show all devices",
                            "what devices do i have",
                            "listar dispositivos",
                            "show online devices",
                            "quais dispositivos estao online",
                        ]
                    )
                )
            )
            text = maybeCorrectionTurn(maybeCodeSwitch(text))
            push(buildRow(idx, text, "listOnline" if "online" in text.lower() else "listDevices"))
            continue

        if p < 0.34:
            if intentCount.get("applyProfile", 0) >= maxApplyProfile and random.random() < 0.70:
                p = 0.46
                continue
            profile = random.choice(profiles)
            text = buildDialogueText(
                maybeNoise(
                    random.choice(
                        [
                            f"apply {profile} profile",
                            f"activate {profile} profile",
                            f"aplicar perfil {profile}",
                            f"ativar perfil {profile}",
                        ]
                    )
                )
            )
            text = maybeCorrectionTurn(maybeCodeSwitch(text))
            push(buildRow(idx, text, "applyProfile", entities={"profile": profile}))
            continue

        deviceKey = random.choice(list(devices.keys()))
        device = random.choice(devices[deviceKey])
        capabilityKey = random.choice(list(capabilities.keys()))
        capability = random.choice(capabilities[capabilityKey])

        if random.random() < 0.46:
            text = buildDialogueText(maybeNoise(random.choice(statusTemplates).format(device=device, capability=capability)))
            text = maybeCorrectionTurn(maybeCodeSwitch(text))
            push(
                buildRow(
                    idx,
                    text,
                    "queryStatus",
                    entities={"deviceHint": deviceKey, "capability": capabilityKey},
                )
            )
            continue

        value = sampleValue(capabilityKey)
        lang = "pt" if random.random() < 0.50 else "en"
        valueVariant = formatValueVariant(capabilityKey, value, lang)
        text = buildDialogueText(
            maybeNoise(random.choice(actionTemplates).format(device=device, capability=capability, value=valueVariant))
        )
        text = maybeCorrectionTurn(maybeCodeSwitch(text))
        actions = [
            {
                "deviceHint": deviceKey,
                "capability": capabilityKey,
                "operation": "set",
                "value": value,
            }
        ]

        if random.random() < 0.30:
            deviceKey2 = random.choice(list(devices.keys()))
            device2 = random.choice(devices[deviceKey2])
            capabilityKey2 = random.choice(["power", "brightness", "position", "lock", "color", "mode"])
            capability2 = random.choice(capabilities[capabilityKey2])
            value2 = sampleValue(capabilityKey2)
            value2Variant = formatValueVariant(capabilityKey2, value2, "pt" if random.random() < 0.5 else "en")
            text += random.choice([" and ", " then ", "; ", " e depois "]) + f"set {device2} {capability2} to {value2Variant}"
            actions.append(
                {
                    "deviceHint": deviceKey2,
                    "capability": capabilityKey2,
                    "operation": "set",
                    "value": value2,
                }
            )

        push(
            buildRow(
                idx,
                text,
                "controlDevice",
                entities={"deviceHint": deviceKey, "capability": capabilityKey, "value": value},
                actions=actions,
            )
        )

    with chatDatasetPath.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"dataset={chatDatasetPath}")
    print(f"rows={len(rows)}")


if __name__ == "__main__":
    generateChatDataset()
