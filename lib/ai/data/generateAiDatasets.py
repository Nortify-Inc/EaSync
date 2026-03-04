#!/usr/bin/env python3
import json
import random
from pathlib import Path

random.seed(73)

DATA_DIR = Path(__file__).resolve().parent
CHAT_DATASET = DATA_DIR / "chatUnderstandingDataset.jsonl"
PATTERN_DATASET = DATA_DIR / "behaviorPatternDataset.jsonl"

DEVICE_SYNONYMS = {
    "ac": [
        "ac", "air conditioner", "aircon", "climate", "hvac", "ar", "ar condicionado",
        "meu ar", "ac unit", "quarto ac", "sala ac"
    ],
    "lamp": [
        "lamp", "light", "lights", "ceiling light", "desk lamp", "spotlight", "luz",
        "lâmpada", "iluminação", "luz da sala", "luz do quarto"
    ],
    "curtain": [
        "curtain", "curtains", "blind", "blinds", "shade", "cortina", "persiana",
        "cortinas", "persianas", "blackout"
    ],
    "lock": [
        "lock", "door lock", "front door lock", "smart lock", "fechadura",
        "fechadura da porta", "tranca"
    ],
    "fridge": [
        "fridge", "refrigerator", "geladeira", "refrigerador"
    ],
    "freezer": [
        "freezer", "congelador", "freezer compartment"
    ],
}

CAPABILITY_SYNONYMS = {
    "power": ["power", "on", "off", "turned on", "ligado", "desligado", "energia"],
    "brightness": ["brightness", "dimmer", "brilho", "intensity", "luminosidade"],
    "temperature": ["temperature", "temp", "temperatura", "tempeature", "thermo"],
    "temperatureFridge": ["fridge temp", "fridge temperature", "geladeira temperatura"],
    "temperatureFreezer": ["freezer temp", "freezer temperature", "congelador temperatura"],
    "position": ["position", "open", "close", "posição", "abrir", "fechar", "percent open"],
    "color": ["color", "colour", "cor", "tone"],
    "colorTemperature": ["color temperature", "kelvin", "temperatura de cor", "warm/cool"],
    "mode": ["mode", "preset", "profile", "modo"],
    "lock": ["lock", "unlock", "trancar", "destrancar"],
    "timestamp": ["timestamp", "time", "clock", "hora", "horário", "epoch"],
    "schedule": ["schedule", "routine schedule", "agendamento", "agenda", "cronograma"],
}

COLORS = [
    "blue", "light blue", "dark blue", "green", "light green", "dark green", "red",
    "light red", "dark red", "purple", "light purple", "dark purple", "pink", "light pink",
    "dark pink", "violet", "indigo", "brown", "black", "gray", "grey", "silver", "gold",
    "yellow", "light yellow", "dark yellow", "orange", "light orange", "dark orange", "cyan",
    "azul", "azul claro", "azul escuro", "verde", "verde claro", "verde escuro", "vermelho",
    "vermelho claro", "vermelho escuro", "roxo", "roxo claro", "roxo escuro", "rosa",
    "rosa claro", "rosa escuro", "violeta", "índigo", "marrom", "preto", "cinza", "prata",
    "dourado", "amarelo", "amarelo claro", "amarelo escuro", "laranja", "laranja claro",
    "laranja escuro", "ciano", "#FFAA00", "#00AEEF", "0x33CC99", "rgb(255,120,20)"
]

GREETINGS_CUSTOM = [
    "hi", "hello", "hey", "hey assistant", "yo", "good morning", "good afternoon", "good evening",
    "oi", "olá", "ola", "bom dia", "boa tarde", "boa noite", "e ai", "fala ai",
    "hello buddy", "hey there", "hi there, can you help me?", "hey! are you online?"
]

GREETING_VARIANTS = [
    "hello assistant", "hi assistant", "hey assistant, are you there?", "morning assistant",
    "good evening assistant", "yo assistant", "hello, can we start?", "hi, are you online now?",
    "oi assistente", "olá assistente", "bom dia assistente", "boa noite assistente",
    "e aí assistente", "fala assistente", "oi, você está online?", "olá, pode me ajudar?"
]

THANKS_CUSTOM = [
    "thanks", "thank you", "thanksss", "thx", "ty", "you are the best", "you're amazing",
    "nice, thanks", "great job", "awesome work", "you nailed it", "valeu", "obrigado",
    "obrigada", "brigadão", "mandou bem", "você é demais"
]

THANKS_VARIANTS = [
    "thanks a lot", "thank you so much", "many thanks", "thank you, assistant",
    "appreciate it", "that helped, thanks", "awesome, thank you", "great, thanks assistant",
    "valeu mesmo", "muito obrigado", "muito obrigada", "obrigado assistente",
    "valeu, ajudou bastante", "show, obrigado", "perfeito, valeu"
]

SMALLTALK_CUSTOM = [
    "how are you?", "how's it going?", "you good?", "what can you do?", "who are you?",
    "can you help me automate my home?", "do you support routines?", "what did you learn from my usage?",
    "o que você faz?", "você consegue controlar minha casa?", "quais tarefas você faz?",
    "me ajuda com automação?", "você aprende meus padrões?"
]

SMALLTALK_VARIANTS = [
    "how are you doing today?", "how you doing?", "are you working fine?", "are you available right now?",
    "what can you handle for me?", "can you manage my devices?", "what can i ask you to do?",
    "can you control lights and ac?", "can you check status for me?",
    "como você está hoje?", "você está funcionando?", "você está disponível agora?",
    "o que você consegue fazer por mim?", "você controla luz e ar?", "você consegue ver o status da casa?"
]

FAREWELL_CUSTOM = [
    "bye", "see you", "talk later", "good night", "have a good one", "catch you later",
    "tchau", "até mais", "falou", "até amanhã"
]

FAREWELL_VARIANTS = [
    "bye assistant", "see you soon assistant", "talk to you later", "goodbye",
    "have a nice day", "see you next time", "tchau assistente", "até depois",
    "até a próxima", "falamos depois"
]

LIST_CUSTOM = [
    "what are my devices?", "list devices", "which devices are online now?",
    "show me all devices", "what can i control?", "what's connected?", "list my smart home devices",
    "quais dispositivos eu tenho?", "listar dispositivos", "o que está online?",
    "me mostra os dispositivos conectados"
]

STATUS_TEMPLATES = [
    "what is the {cap} of my {device}?",
    "tell me the {cap} on {device}",
    "how is the {device} {cap} now?",
    "is {device} {cap} okay right now?",
    "check {device} {cap} for me",
    "qual o {cap} do {device}?",
    "me diz o {cap} do {device}",
    "como está o {cap} do {device} agora?",
    "{device} {cap}?",
]

ACTION_TEMPLATES = [
    "set {device} {cap} to {value}",
    "can you set my {device} {cap} to {value}?",
    "please adjust {device} {cap} to {value}",
    "change {device} {cap} -> {value}",
    "defina {cap} do {device} para {value}",
    "ajusta {device} {cap} para {value}",
    "muda {cap} do {device} para {value}",
    "seta o {cap} do {device} em {value}",
]

POSITION_ACTION_TEMPLATES = [
    "open {device}",
    "close {device}",
    "can you open my {device}?",
    "can you close my {device}?",
    "please open the {device}",
    "please close the {device}",
    "abrir {device}",
    "fechar {device}",
    "pode abrir a {device}?",
    "pode fechar a {device}?",
]

POSITION_STATUS_TEMPLATES = [
    "check {device} status",
    "check {device} position",
    "what is {device} position now?",
    "is {device} open or closed?",
    "show {device} open percentage",
    "status da {device}",
    "qual a posição da {device}?",
    "a {device} está aberta ou fechada?",
]

MODE_ACTION_TEMPLATES = [
    "set {device} mode to eco",
    "set {device} mode to turbo",
    "set {device} mode to sleep",
    "set {device} mode to comfort",
    "change {device} mode to auto",
    "now set mode of {device} to eco",
    "defina o modo do {device} para eco",
    "ajusta o modo do {device} para turbo",
]

POWER_STATUS_TEMPLATES = [
    "can you check if my {device} is on?",
    "is my {device} on right now?",
    "check whether {device} is on",
    "is {device} turned on?",
    "você pode verificar se {device} está ligado?",
    "o {device} está ligado agora?",
]

MULTI_ACTION_GLUE = [" and ", " then ", "; ", " e depois ", " e " ]

PROFILE_UTTERANCES = [
    "apply game profile", "activate relax profile", "run movie profile", "aplica perfil jogo",
    "ativar perfil dormir", "set profile to focus", "trigger evening profile"
]

TIME_SCHEDULE_CUSTOM = [
    "what time is configured on my lock?",
    "show timestamp from my device",
    "what is the current timestamp on ac?",
    "set lock schedule to 22:30",
    "schedule curtains to open at 07:00",
    "set a schedule for lights at 18:45",
    "qual o timestamp da fechadura?",
    "me mostra o horário configurado no dispositivo",
    "agendar cortina para abrir às 07:00",
    "defina agenda da luz para 18:30",
    "programa o ar para ligar às 19:00",
]

AMBIGUOUS_UTTERANCES = [
    "make it better", "too bright here", "it's too hot", "this room is dark", "fix this",
    "deixa confortável", "tá muito quente", "muito claro aqui", "resolve isso"
]

OUT_OF_DOMAIN_UTTERANCES = [
    "who won the world cup in 2002?",
    "write a poem about the ocean",
    "what is the derivative of x squared?",
    "recommend a restaurant near me",
    "how to fix my car engine?",
    "qual a capital da frança?",
    "me ensina cálculo diferencial",
    "escreva uma poesia romântica",
    "qual o melhor investimento para 2026?",
    "resolva essa questão de física",
]


def detect_language(text: str) -> str:
    t = text.lower()
    pt_markers = [
        "quais", "qual o", "dispositivos", "obrigado", "obrigada", "ajusta", "defina",
        "trancar", "destrancar", "você", "perfil", "horário", "agendar", "agenda",
        "cortina", "fechadura", "programa", "às ", " para ", "me mostra"
    ]
    return "pt" if any(m in t for m in pt_markers) else "en"


def maybe_typo(text: str) -> str:
    if random.random() > 0.12:
        return text
    swaps = {
        "temperature": "tempeature",
        "brightness": "brighness",
        "assistant": "assisstant",
        "please": "pls",
        "you": "u",
        "what": "wut",
    }
    out = text
    for k, v in swaps.items():
        if k in out.lower() and random.random() < 0.45:
            out = out.replace(k, v).replace(k.title(), v)
    return out


def maybe_style(text: str) -> str:
    out = text
    if random.random() < 0.22:
        out = "please " + out
    if random.random() < 0.18:
        out = out + random.choice(["", " now", " right now", " asap", " please"])
    if random.random() < 0.10:
        out = out + random.choice(["!", "!!", "?"])
    return out


def sample_value(cap: str):
    if cap == "power":
        return random.choice(["on", "off", "true", "false"])
    if cap == "brightness":
        return random.choice([0, 5, 10, 20, 35, 50, 65, 80, 95, 100])
    if cap == "temperature":
        return random.choice([16, 18, 20, 21, 22, 23, 24, 25, 26, 28, 30])
    if cap == "temperatureFridge":
        return random.choice([1, 2, 3, 4, 5, 6, 7, 8])
    if cap == "temperatureFreezer":
        return random.choice([-24, -22, -20, -18, -16, -14])
    if cap == "position":
        return random.choice([0, 10, 25, 35, 50, 65, 75, 90, 100])
    if cap == "color":
        return random.choice(COLORS)
    if cap == "colorTemperature":
        return random.choice([1800, 2200, 2700, 3000, 4000, 5000, 6500, 8000])
    if cap == "mode":
        return random.choice([0, 1, 2, 3, "eco", "turbo", "sleep", "comfort", "auto"])
    if cap == "lock":
        return random.choice(["lock", "unlock"])
    if cap == "timestamp":
        return random.choice([1700000000, 1700003600, 1712345678, 1720000000])
    if cap == "schedule":
        return random.choice(["06:30", "07:00", "18:00", "18:30", "21:45", "22:30"])
    return random.choice([0, 1])


def synthesize_target_response(intent: str, entities=None, actions=None, response_style="helpful") -> str:
    entities = entities or {}
    actions = actions or []
    capability = str(entities.get("capability") or "device")

    social_bank = {
        "greeting": [
            "hello i am online and ready to help with your home",
            "hi there i am active and can execute commands or check status",
            "hello i am ready to interpret your request",
        ],
        "gratitude": [
            "you are welcome i am glad to help",
            "happy to help send me the next request when you are ready",
            "anytime i can also verify the current device status now",
        ],
        "smalltalk": [
            "i am operating normally and ready to execute commands",
            "all systems are online i can control devices and report status",
            "i am active and ready to assist with automation tasks",
        ],
        "farewell": [
            "see you soon i will stay ready for your next message",
            "goodbye i will be here when you need another command",
            "talk soon i remain available for your smart home",
        ],
        "listDevices": [
            "i can list all registered devices and identify controllable capabilities",
            "i can provide the full list of devices currently configured",
        ],
        "listOnline": [
            "i can list only devices that are online right now",
            "i can report the online devices and their availability",
        ],
    }

    if intent in social_bank:
        return random.choice(social_bank[intent])

    if intent == "queryStatus":
        if capability and capability != "none":
            return random.choice([
                f"i understood a status request for {capability} and can return a precise value when device context is clear",
                f"i can check {capability} status now and report the current state",
            ])
        return random.choice([
            "i understood a status query but i still need the target device name",
            "please mention the device so i can provide an exact status response",
        ])

    if intent in {"controlDevice", "applyProfile"}:
        if actions:
            a0 = actions[0]
            cap = str(a0.get("capability") or capability or "device")
            op = str(a0.get("operation") or "set")
            value = a0.get("value")
            if value is not None:
                return random.choice([
                    f"i understood a command to {op} {cap} to {value} and i am ready to execute it",
                    f"command parsed successfully capability {cap} operation {op} value {value}",
                ])
            return random.choice([
                f"i understood a {op} command for {cap} and i am ready to execute",
                f"command recognized for {cap} with operation {op}",
            ])
        return random.choice([
            "i understood a device control request but i need more context to execute safely",
            "please provide device name capability and value to execute this command",
        ])

    if intent == "outOfDomain":
        return random.choice([
            "this request is outside my smart device domain i can only help with home automation and device status",
            "i do not have reliable knowledge for this topic please use a specialized source while i handle smart devices",
        ])

    if intent == "ambiguous" or response_style == "clarify":
        return random.choice([
            "i could not fully understand your request please provide device capability and target value",
            "i need more context to continue please specify what should be changed",
        ])

    return random.choice([
        "i interpreted your request and i am ready to continue",
        "request processed please provide more context if needed",
    ])


def build_nlu_row(idx: int, text: str, intent: str, entities=None, actions=None, response_style="helpful"):
    response_target = synthesize_target_response(
        intent=intent,
        entities=entities,
        actions=actions,
        response_style=response_style,
    )
    return {
        "id": f"chat_{idx:07d}",
        "text": text,
        "language": detect_language(text),
        "intent": intent,
        "entities": entities or {},
        "canonicalActions": actions or [],
        "responseStyle": response_style,
        "targetResponse": response_target,
    }


def generate_chat_dataset(target_size: int = 180000):
    rows = []
    idx = 1

    for g in GREETINGS_CUSTOM:
        rows.append(build_nlu_row(idx, g, "greeting", response_style="friendly")); idx += 1
    for t in THANKS_CUSTOM:
        rows.append(build_nlu_row(idx, t, "gratitude", response_style="warm")); idx += 1
    for t in SMALLTALK_CUSTOM:
        rows.append(build_nlu_row(idx, t, "smalltalk", response_style="friendly")); idx += 1
    for t in FAREWELL_CUSTOM:
        rows.append(build_nlu_row(idx, t, "farewell", response_style="friendly")); idx += 1
    for t in LIST_CUSTOM:
        intent = "listOnline" if "online" in t.lower() else "listDevices"
        rows.append(build_nlu_row(idx, t, intent)); idx += 1
    for t in PROFILE_UTTERANCES:
        rows.append(build_nlu_row(idx, t, "applyProfile", entities={"profileHint": t.lower()})); idx += 1
    for t in TIME_SCHEDULE_CUSTOM:
        lower = t.lower()
        if any(k in lower for k in ["schedule", "agendar", "agenda", "programa", "set "]):
            rows.append(
                build_nlu_row(
                    idx,
                    t,
                    "controlDevice",
                    entities={"capability": "schedule"},
                    actions=[{"capability": "schedule", "operation": "set"}],
                )
            )
        else:
            rows.append(build_nlu_row(idx, t, "queryStatus", entities={"capability": "timestamp"}))
        idx += 1
    for t in AMBIGUOUS_UTTERANCES:
        rows.append(build_nlu_row(idx, t, "ambiguous", response_style="clarify")); idx += 1
    for t in OUT_OF_DOMAIN_UTTERANCES:
        rows.append(build_nlu_row(idx, t, "outOfDomain", response_style="honest")); idx += 1

    social_seed = (
        [(t, "greeting", "friendly") for t in GREETINGS_CUSTOM + GREETING_VARIANTS] +
        [(t, "gratitude", "warm") for t in THANKS_CUSTOM + THANKS_VARIANTS] +
        [(t, "smalltalk", "friendly") for t in SMALLTALK_CUSTOM + SMALLTALK_VARIANTS] +
        [(t, "farewell", "friendly") for t in FAREWELL_CUSTOM + FAREWELL_VARIANTS]
    )

    for _ in range(8000):
        base_text, intent, style = random.choice(social_seed)
        text = maybe_typo(maybe_style(base_text))
        rows.append(build_nlu_row(idx, text, intent, response_style=style))
        idx += 1

    for _ in range(9000):
        text = maybe_typo(maybe_style(random.choice(OUT_OF_DOMAIN_UTTERANCES)))
        rows.append(build_nlu_row(idx, text, "outOfDomain", response_style="honest"))
        idx += 1

    dev_keys = list(DEVICE_SYNONYMS.keys())
    cap_keys = list(CAPABILITY_SYNONYMS.keys())

    while len(rows) < target_size:
        if random.random() < 0.08:
            dev_name = random.choice(DEVICE_SYNONYMS["ac"] + DEVICE_SYNONYMS["lamp"])
            if random.random() < 0.52:
                text = maybe_typo(maybe_style(random.choice(MODE_ACTION_TEMPLATES).format(device=dev_name)))
                mode_word = "eco"
                if "turbo" in text.lower():
                    mode_word = "turbo"
                elif "sleep" in text.lower():
                    mode_word = "sleep"
                elif "comfort" in text.lower():
                    mode_word = "comfort"
                elif "auto" in text.lower():
                    mode_word = "auto"
                rows.append(
                    build_nlu_row(
                        idx,
                        text,
                        "controlDevice",
                        entities={"capability": "mode", "mode": mode_word},
                        actions=[{
                            "deviceHint": "ac",
                            "capability": "mode",
                            "operation": "set",
                            "value": mode_word,
                        }],
                    )
                )
            else:
                text = maybe_typo(maybe_style(random.choice(POWER_STATUS_TEMPLATES).format(device=dev_name)))
                rows.append(
                    build_nlu_row(
                        idx,
                        text,
                        "queryStatus",
                        entities={"capability": "power"},
                    )
                )
            idx += 1
            continue

        if random.random() < 0.12:
            dev_name = random.choice(DEVICE_SYNONYMS["curtain"])
            if random.random() < 0.56:
                text = maybe_typo(maybe_style(random.choice(POSITION_ACTION_TEMPLATES).format(device=dev_name)))
                value = 100 if "open" in text.lower() or "abr" in text.lower() else 0
                rows.append(
                    build_nlu_row(
                        idx,
                        text,
                        "controlDevice",
                        entities={"deviceHint": "curtain", "capability": "position", "value": value},
                        actions=[{
                            "deviceHint": "curtain",
                            "capability": "position",
                            "operation": "set",
                            "value": value,
                        }],
                    )
                )
            else:
                text = maybe_typo(maybe_style(random.choice(POSITION_STATUS_TEMPLATES).format(device=dev_name)))
                rows.append(
                    build_nlu_row(
                        idx,
                        text,
                        "queryStatus",
                        entities={"deviceHint": "curtain", "capability": "position"},
                    )
                )
            idx += 1
            continue

        dev_key = random.choice(dev_keys)
        dev_name = random.choice(DEVICE_SYNONYMS[dev_key])
        cap_key = random.choice(cap_keys)
        cap_name = random.choice(CAPABILITY_SYNONYMS[cap_key])
        val = sample_value(cap_key)

        if random.random() < 0.45:
            text = random.choice(STATUS_TEMPLATES).format(device=dev_name, cap=cap_name)
            text = maybe_typo(maybe_style(text))
            rows.append(
                build_nlu_row(
                    idx,
                    text,
                    "queryStatus",
                    entities={"deviceHint": dev_key, "capability": cap_key},
                )
            )
            idx += 1
            continue

        base = random.choice(ACTION_TEMPLATES).format(device=dev_name, cap=cap_name, value=val)
        actions = [{
            "deviceHint": dev_key,
            "capability": cap_key,
            "operation": "set",
            "value": val,
        }]

        if random.random() < 0.35:
            dev_key2 = random.choice(dev_keys)
            dev_name2 = random.choice(DEVICE_SYNONYMS[dev_key2])
            cap_key2 = random.choice(["power", "brightness", "position", "lock", "color"])
            cap_name2 = random.choice(CAPABILITY_SYNONYMS[cap_key2])
            val2 = sample_value(cap_key2)
            base += random.choice(MULTI_ACTION_GLUE) + f"set {dev_name2} {cap_name2} to {val2}"
            actions.append({
                "deviceHint": dev_key2,
                "capability": cap_key2,
                "operation": "set",
                "value": val2,
            })

        text = maybe_typo(maybe_style(base))
        rows.append(
            build_nlu_row(
                idx,
                text,
                "controlDevice",
                entities={"deviceHint": dev_key, "capability": cap_key, "value": val},
                actions=actions,
            )
        )
        idx += 1

    with CHAT_DATASET.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def generate_pattern_dataset(target_size: int = 70000):
    routines = [
        "morning_start", "leave_home", "arrival_home", "evening_relax", "sleep_prep",
        "gaming_session", "movie_time", "work_focus", "weekend_cleaning", "night_security"
    ]
    days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    weather = ["hot", "mild", "cold", "humid", "dry", "rainy"]
    occupancy_states = ["home", "away", "arriving", "sleeping"]

    rows = []
    for i in range(1, target_size + 1):
        routine = random.choice(routines)
        hour = random.randint(0, 23)
        context = {
            "dayOfWeek": random.choice(days),
            "hour": hour,
            "weather": random.choice(weather),
            "occupancy": random.choice(occupancy_states),
            "routineHint": routine,
            "outsideTemp": random.choice([12, 14, 16, 18, 20, 22, 24, 26, 28, 31, 34]),
            "isHoliday": random.random() < 0.08,
        }

        history_len = random.randint(6, 20)
        history = []
        for _ in range(history_len):
            dkey = random.choice(list(DEVICE_SYNONYMS.keys()))
            cap = random.choice(list(CAPABILITY_SYNONYMS.keys()))
            history.append({
                "hour": random.randint(max(0, hour - 6), min(23, hour + 2)),
                "device": dkey,
                "capability": cap,
                "action": random.choice(["set", "toggle", "query", "applyProfile", "sceneActivate"]),
                "value": sample_value(cap),
                "success": random.random() > 0.05,
            })

        if routine == "morning_start":
            next_action = "openCurtainsThenWarmLight"
            conf = random.uniform(0.72, 0.98)
        elif routine == "leave_home":
            next_action = "turnOffLightsLockDoors"
            conf = random.uniform(0.70, 0.96)
        elif routine == "arrival_home":
            next_action = "prepareClimateAndLights"
            conf = random.uniform(0.68, 0.95)
        elif routine == "evening_relax":
            next_action = "dimLightsWarmColor"
            conf = random.uniform(0.66, 0.94)
        elif routine == "sleep_prep":
            next_action = "closeCurtainsNightSecurity"
            conf = random.uniform(0.74, 0.98)
        elif routine == "gaming_session":
            next_action = "applyGameProfile"
            conf = random.uniform(0.62, 0.92)
        elif routine == "movie_time":
            next_action = "movieSceneLowBrightness"
            conf = random.uniform(0.65, 0.93)
        elif routine == "work_focus":
            next_action = "neutralLightDeskFocus"
            conf = random.uniform(0.60, 0.90)
        elif routine == "weekend_cleaning":
            next_action = "maxBrightnessOpenCurtains"
            conf = random.uniform(0.58, 0.88)
        else:
            next_action = "ensureDoorsLocked"
            conf = random.uniform(0.70, 0.95)

        rows.append({
            "id": f"pattern_{i:07d}",
            "context": context,
            "history": history,
            "label": {
                "nextAction": next_action,
                "confidence": round(conf, 4),
            },
            "patternTargets": {
                "arrivalHour": random.choice([17, 18, 19, 20, 21]),
                "wakeHour": random.choice([5, 6, 7, 8, 9]),
                "sleepHour": random.choice([21, 22, 23, 0, 1]),
                "preferredTemperature": random.choice([19, 20, 21, 22, 23, 24, 25]),
                "preferredBrightness": random.choice([20, 30, 40, 50, 60, 70, 80]),
                "preferredCurtainPosition": random.choice([0, 20, 40, 60, 80, 100]),
                "preferredColorTemperature": random.choice([2200, 2700, 3000, 4000, 5000, 6500]),
            },
        })

    with PATTERN_DATASET.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def main():
    generate_chat_dataset()
    generate_pattern_dataset()
    print(f"Generated: {CHAT_DATASET}")
    print(f"Generated: {PATTERN_DATASET}")


if __name__ == "__main__":
    main()
