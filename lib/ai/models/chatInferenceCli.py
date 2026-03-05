#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys

from chatInference import predictMessage


def safe(value: object) -> str:
    if value is None:
        return ""
    return str(value).replace("\n", " ").strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--text", required=True)
    args = parser.parse_args()

    try:
        result = predictMessage(args.text)
    except Exception:
        return 2

    entities = result.get("entities") or {}
    print(f"INTENT={safe(result.get('intent'))}")
    print(f"STYLE={safe(result.get('responseStyle'))}")
    print(f"CAPABILITY={safe(result.get('predictedCapability'))}")
    print(f"OPERATION={safe(result.get('predictedOperation'))}")
    print(f"RESPONSE={safe(result.get('generatedResponse'))}")
    print(f"CLARIFY={safe(result.get('needsClarification'))}")
    print(f"CONFIDENCE={safe(result.get('intentConfidence'))}")
    print(f"NUMERIC={safe(entities.get('numericValue'))}")
    print(f"TIME={safe(entities.get('time'))}")
    print(f"HEX={safe(entities.get('hexColor'))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
