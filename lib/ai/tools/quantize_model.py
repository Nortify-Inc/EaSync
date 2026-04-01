#!/usr/bin/env python3
"""@file quantize_model.py
@brief Generate a smaller INT8 ONNX model for local mobile inference.

This script applies dynamic INT8 quantization (weights) with optional graph
optimization. It is the fastest path to a large size reduction without
retraining.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Tuple


def _bytes_to_human(n: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(n)
    for u in units:
        if size < 1024.0 or u == units[-1]:
            return f"{size:.2f} {u}"
        size /= 1024.0
    return f"{n} B"


def _artifact_size(base: Path) -> int:
    total = 0
    if base.exists():
        total += base.stat().st_size
    sidecar = base.with_suffix(base.suffix + ".data")
    if sidecar.exists():
        total += sidecar.stat().st_size
    return total


def _optimize_graph(input_model: Path, optimized_model: Path) -> Path:
    try:
        import onnxruntime as ort
    except ImportError as exc:
        raise RuntimeError(
            "onnxruntime is required for optimization. Install with: pip install onnxruntime"
        ) from exc

    so = ort.SessionOptions()
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    so.optimized_model_filepath = str(optimized_model)

    # Build session once to force graph rewrite.
    ort.InferenceSession(str(input_model), sess_options=so, providers=["CPUExecutionProvider"])
    return optimized_model


def _quantize_dynamic(
    input_model: Path,
    output_model: Path,
    per_channel: bool,
    reduce_range: bool,
) -> Path:
    try:
        from onnxruntime.quantization import QuantType, quantize_dynamic
    except ImportError as exc:
        raise RuntimeError(
            "onnxruntime quantization tools are required. Install with: pip install onnxruntime"
        ) from exc

    quantize_dynamic(
        model_input=str(input_model),
        model_output=str(output_model),
        weight_type=QuantType.QInt8,
        per_channel=per_channel,
        reduce_range=reduce_range,
    )
    return output_model


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Optimize and quantize ONNX model to reduce local runtime size"
    )
    parser.add_argument(
        "--input",
        default="lib/ai/data/model.onnx",
        help="Path to source ONNX model",
    )
    parser.add_argument(
        "--output",
        default="lib/ai/data/model_pruned_int8.onnx",
        help="Path to output quantized ONNX model",
    )
    parser.add_argument(
        "--skip-optimize",
        action="store_true",
        help="Skip pre-optimization step and quantize input directly",
    )
    parser.add_argument(
        "--per-channel",
        action="store_true",
        help="Enable per-channel weight quantization",
    )
    parser.add_argument(
        "--reduce-range",
        action="store_true",
        help="Use reduced quantization range for better compatibility",
    )
    parser.add_argument(
        "--keep-temp",
        action="store_true",
        help="Keep temporary optimized model file",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()

    input_model = Path(args.input).resolve()
    output_model = Path(args.output).resolve()
    temp_optimized = output_model.with_name(output_model.stem + ".optimized.onnx")

    if not input_model.exists():
        print(f"[quantize] Input model not found: {input_model}")
        return 1

    output_model.parent.mkdir(parents=True, exist_ok=True)

    before = _artifact_size(input_model)
    work_input = input_model

    if not args.skip_optimize:
        print(f"[quantize] Optimizing graph: {input_model} -> {temp_optimized}")
        work_input = _optimize_graph(input_model, temp_optimized)

    print(f"[quantize] Quantizing INT8: {work_input} -> {output_model}")
    _quantize_dynamic(
        work_input,
        output_model,
        per_channel=args.per_channel,
        reduce_range=args.reduce_range,
    )

    if temp_optimized.exists() and not args.keep_temp:
        temp_optimized.unlink()

    after = _artifact_size(output_model)
    ratio = (1.0 - (after / before)) * 100.0 if before > 0 else 0.0

    print("[quantize] Done")
    print(f"[quantize] Before: {_bytes_to_human(before)}")
    print(f"[quantize] After : {_bytes_to_human(after)}")
    print(f"[quantize] Reduction: {ratio:.2f}%")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
