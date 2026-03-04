#!/usr/bin/env python3
"""Train chat model and copy final weights to lib/ai/models.

Usage:
  /usr/bin/python lib/ai/models/trainChatModel.py
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

os.environ["CUDA_VISIBLE_DEVICES"] = ""

import chatModel


def main() -> None:
    chatModel.train()

    root = Path(__file__).resolve().parent
    src_pt = root / "artifacts" / "chat" / "chatModel.pt"
    src_vocab = root / "artifacts" / "chat" / "vocab.json"
    src_maps = root / "artifacts" / "chat" / "labelMaps.json"

    dst_pth = root / "chatModel.pth"
    dst_vocab = root / "chatModelVocab.json"
    dst_maps = root / "chatModelLabelMaps.json"

    if not src_pt.exists():
        raise RuntimeError(f"Expected weights not found: {src_pt}")

    shutil.copy2(src_pt, dst_pth)
    if src_vocab.exists():
        shutil.copy2(src_vocab, dst_vocab)
    if src_maps.exists():
        shutil.copy2(src_maps, dst_maps)

    print(f"Copied: {src_pt} -> {dst_pth}")
    if src_vocab.exists():
        print(f"Copied: {src_vocab} -> {dst_vocab}")
    if src_maps.exists():
        print(f"Copied: {src_maps} -> {dst_maps}")


if __name__ == "__main__":
    main()
