#!/usr/bin/env python3
"""Train patterns model and copy final weights to lib/ai/models.

Usage:
  /usr/bin/python lib/ai/models/trainPatternsModel.py
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

os.environ["CUDA_VISIBLE_DEVICES"] = ""

import patternsModel


def main() -> None:
    patternsModel.train()

    root = Path(__file__).resolve().parent
    src_pt = root / "artifacts" / "patterns" / "patternsModel.pt"
    src_maps = root / "artifacts" / "patterns" / "patternMaps.json"

    dst_pth = root / "patternsModel.pth"
    dst_maps = root / "patternsModelMaps.json"

    if not src_pt.exists():
        raise RuntimeError(f"Expected weights not found: {src_pt}")

    shutil.copy2(src_pt, dst_pth)
    if src_maps.exists():
        shutil.copy2(src_maps, dst_maps)

    print(f"Copied: {src_pt} -> {dst_pth}")
    if src_maps.exists():
        print(f"Copied: {src_maps} -> {dst_maps}")


if __name__ == "__main__":
    main()
