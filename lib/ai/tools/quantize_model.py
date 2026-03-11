#!/usr/bin/env python3
"""
Quantize an ONNX model using ONNX Runtime dynamic quantization.

Usage:
  python quantize_model.py --input model.onnx --output model.quant.onnx

Requirements:
  pip install onnx onnxruntime onnxruntime-tools

This script performs dynamic weight quantization (INT8) by default.
For more aggressive quantization (per-channel, static) see docs/QUANTIZE.md.
"""

import argparse
from pathlib import Path

try:
    from onnxruntime.quantization import quantize_dynamic, QuantType
except Exception as e:
    raise SystemExit("Missing dependency: install onnxruntime and onnxruntime-tools: pip install onnx onnxruntime onnxruntime-tools\n" + str(e))


def parse_args():
    p = argparse.ArgumentParser(description="Quantize an ONNX model (dynamic INT8)")
    p.add_argument("--input", "-i", required=True, help="Path to input ONNX model")
    p.add_argument("--output", "-o", required=True, help="Path for output quantized model")
    p.add_argument("--per-channel", action="store_true", help="Enable per-channel quantization (may improve accuracy)")
    p.add_argument("--weight-type", choices=["qint8", "quint8"], default="qint8", help="Weight quant type")
    p.add_argument("--op-types", nargs="*", default=None, help="List of op types to quantize (default: all)")
    return p.parse_args()


def main():
    args = parse_args()
    inp = Path(args.input)
    out = Path(args.output)
    if not inp.exists():
        raise SystemExit(f"Input model not found: {inp}")

    weight_type = QuantType.QInt8 if args.weight_type == "qint8" else QuantType.QUInt8

    print(f"Quantizing: {inp} -> {out}")
    print(f"per_channel={args.per_channel} weight_type={args.weight_type}")

    quantize_dynamic(
        model_input=str(inp),
        model_output=str(out),
        op_types_to_quantize=args.op_types,
        per_channel=args.per_channel,
        weight_type=weight_type,
    )

    print("Quantization complete")


if __name__ == '__main__':
    main()
