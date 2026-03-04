#!/usr/bin/env python3
from __future__ import annotations

import random
from typing import Any

from chatModel import predict_message

random.seed(73)

CASES: list[dict[str, Any]] = []

# 30 control cases
for color in ["red", "green", "blue", "purple", "yellow"]:
    CASES.append({"text": f"set color strip to {color}", "intent": "controlDevice", "cap": "color"})
for b in [0, 10, 25, 40, 55, 70, 85, 100]:
    CASES.append({"text": f"set lamp brightness to {b}", "intent": "controlDevice", "cap": "brightness"})
for p in [0, 20, 40, 60, 80, 100]:
    CASES.append({"text": f"set curtains position to {p}", "intent": "controlDevice", "cap": "position"})
for t in [-22, -19, -16, 2, 4, 7]:
    dev = "freezer" if t < 0 else "fridge"
    CASES.append({"text": f"set {dev} to {t}", "intent": "controlDevice"})
for m in ["eco", "turbo", "sleep", "comfort", "auto"]:
    CASES.append({"text": f"set ac mode to {m}", "intent": "controlDevice", "cap": "mode"})

# 30 status cases
for q in [
    "check curtains status", "what is curtain position now", "is the blind open",
    "check lamp brightness", "what is ac temperature", "is lock closed",
    "show online devices", "list devices", "what devices do i have",
    "what is freezer temperature", "what is fridge temperature", "check color strip color",
]:
    CASES.append({"text": q, "intent": "queryStatus" if "status" in q or "what is" in q or "check" in q or "is " in q else "listDevices"})

# 20 social cases
for q, intent in [
    ("hello", "greeting"), ("hey assistant", "greeting"), ("good morning", "greeting"),
    ("thanks", "gratitude"), ("thank you very much", "gratitude"), ("valeu", "gratitude"),
    ("how are you", "smalltalk"), ("how you doing", "smalltalk"), ("what can you do", "smalltalk"),
    ("bye", "farewell"), ("see you later", "farewell"), ("good night", "farewell"),
]:
    CASES.append({"text": q, "intent": intent})

# 20 out of domain
for q in [
    "who won the world cup in 2002", "write a poem", "solve this calculus equation",
    "what is the best stock today", "recommend a restaurant", "capital of japan",
    "me ensina física quântica", "como investir em renda fixa", "escreva um conto",
    "qual o melhor filme de 2025",
]:
    CASES.append({"text": q, "intent": "outOfDomain"})

while len(CASES) < 110:
    CASES.append(random.choice(CASES))

random.shuffle(CASES)
CASES = CASES[:110]


def check_case(case: dict[str, Any], pred: dict[str, Any]) -> bool:
    if pred.get("intent") != case["intent"]:
        return False
    expected_cap = case.get("cap")
    if expected_cap and pred.get("predictedCapability") != expected_cap:
        return False
    resp = str(pred.get("generatedResponse") or "").strip().lower()
    if len(resp.split()) < 5:
        return False
    return True


def main() -> int:
    ok = 0
    failures: list[tuple[str, dict[str, Any]]] = []
    for case in CASES:
        pred = predict_message(case["text"])
        if check_case(case, pred):
            ok += 1
        else:
            failures.append((case["text"], pred))

    acc = ok / len(CASES)
    print(f"cases={len(CASES)} ok={ok} acc={acc:.4f}")
    print(f"threshold_pass={acc >= 0.95}")
    if failures:
        print("sample_failures=")
        for text, pred in failures[:8]:
            print(f"- {text} -> intent={pred.get('intent')} cap={pred.get('predictedCapability')} resp={pred.get('generatedResponse')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
