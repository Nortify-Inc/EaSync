#!/usr/bin/env python3
from __future__ import annotations

import random
from typing import Any

from chatInference import predictMessage

random.seed(73)

TARGET_CASES = 600
CASES: list[dict[str, Any]] = []

for color in ["blue", "green", "red", "purple", "orange", "azul", "vermelho", "#ffaa00"]:
    CASES.extend(
        [
            {"text": f"set light color to {color}", "intent": "controlDevice", "capability": "color", "operation": "set"},
            {"text": f"defina cor da luz para {color}", "intent": "controlDevice", "capability": "color", "operation": "set"},
        ]
    )

for brightness in [0, 10, 25, 40, 60, 80, 100]:
    CASES.extend(
        [
            {"text": f"set lamp brightness to {brightness}", "intent": "controlDevice", "capability": "brightness", "operation": "set"},
            {"text": f"ajusta brilho da luz para {brightness}", "intent": "controlDevice", "capability": "brightness", "operation": "set"},
        ]
    )

for position in [0, 20, 50, 80, 100]:
    CASES.extend(
        [
            {"text": f"set curtain position to {position}", "intent": "controlDevice", "capability": "position", "operation": "set"},
            {"text": f"posição da cortina {position}", "intent": "controlDevice", "capability": "position", "operation": "set"},
        ]
    )

for query in [
    "what is ac temperature",
    "check lock status",
    "check curtains position",
    "status da fechadura",
    "qual a temperatura do ar",
]:
    CASES.append({"text": query, "intent": "queryStatus"})

for text, intent in [
    ("hello", "greeting"),
    ("oi", "greeting"),
    ("thanks", "gratitude"),
    ("obrigado", "gratitude"),
    ("how are you", "smalltalk"),
    ("tudo bem", "smalltalk"),
    ("bye", "farewell"),
    ("tchau", "farewell"),
]:
    CASES.extend([
        {"text": text, "intent": intent},
        {"text": f"{text} please", "intent": intent},
    ])

for text in [
    "write a poem about stars",
    "who won world cup 2002",
    "agora who won the world cup in 2002",
    "before changing my lights, who won world cup 2002",
    "qual a capital da frança",
    "best stock to buy",
    "me explica buracos negros",
]:
    CASES.extend([
        {"text": text, "intent": "outOfDomain"},
        {"text": f"please answer: {text}", "intent": "outOfDomain"},
    ])

for text in ["make it better", "fix this", "resolve isso", "too hot here"]:
    CASES.append({"text": text, "intent": "ambiguous"})

while len(CASES) < TARGET_CASES:
    CASES.append(random.choice(CASES))

random.shuffle(CASES)
CASES = CASES[:TARGET_CASES]


def checkCase(case: dict[str, Any], prediction: dict[str, Any]) -> bool:
    if prediction.get("intent") != case["intent"]:
        return False

    expectedCapability = case.get("capability")
    if expectedCapability and prediction.get("predictedCapability") != expectedCapability:
        return False

    expectedOperation = case.get("operation")
    if expectedOperation and prediction.get("predictedOperation") != expectedOperation:
        return False

    response = str(prediction.get("generatedResponse") or "").strip()
    if len(response.split()) < 2:
        return False

    if case["intent"] == "outOfDomain":
        lower = response.lower()
        if (
            "outside home-automation scope" not in lower
            and "outside smart-home automation scope" not in lower
            and "fora do escopo" not in lower
        ):
            return False

    return True


def main() -> int:
    ok = 0
    failures: list[tuple[str, dict[str, Any]]] = []

    for case in CASES:
        prediction = predictMessage(case["text"])
        if checkCase(case, prediction):
            ok += 1
        else:
            failures.append((case["text"], prediction))

    accuracy = ok / len(CASES)
    print(f"cases={len(CASES)} ok={ok} acc={accuracy:.4f}")
    print(f"thresholdPass={accuracy >= 0.90}")
    if failures:
        print("sampleFailures=")
        for text, prediction in failures[:12]:
            print(
                f"- {text} -> intent={prediction.get('intent')} cap={prediction.get('predictedCapability')} "
                f"op={prediction.get('predictedOperation')} resp={prediction.get('generatedResponse')}"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
