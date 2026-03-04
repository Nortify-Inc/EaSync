#!/usr/bin/env python3
"""CLI wrapper for chat model inference used by C++ runtime."""

from __future__ import annotations

import argparse
import sys

from chatModel import predict_message


def _safe(value: object) -> str:
    if value is None:
        return ""
    return str(value).replace("\n", " ").strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--text", required=True)
    args = parser.parse_args()

    try:
        result = predict_message(args.text)
    except Exception:
        return 2

    entities = result.get("entities") or {}
    print(f"INTENT={_safe(result.get('intent'))}")
    print(f"STYLE={_safe(result.get('responseStyle'))}")
    print(f"CAPABILITY={_safe(result.get('predictedCapability'))}")
    print(f"OPERATION={_safe(result.get('predictedOperation'))}")
    print(f"RESPONSE={_safe(result.get('generatedResponse'))}")
    print(f"CLARIFY={_safe(result.get('needsClarification'))}")
    print(f"CONFIDENCE={_safe(result.get('intentConfidence'))}")
    print(f"NUMERIC={_safe(entities.get('numericValue'))}")
    print(f"TIME={_safe(entities.get('time'))}")
    print(f"HEX={_safe(entities.get('hexColor'))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
