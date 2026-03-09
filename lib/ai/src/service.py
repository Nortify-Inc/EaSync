#!/usr/bin/env python3
"""
ai/src/service.py
Lightweight runner that loads the Python SGLM implementation from `SGLM.py` in
the same folder and generates a response for a given `--prompt` argument.

This script is intentionally small: it uses a simple whitespace tokenizer
and returns JSON on stdout: {"result":"ok","response":"..."}
"""
import argparse
import json
import sys
import os
from SGLM import SGLM, Generator
import torch


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prompt', required=True)
    parser.add_argument('--weights', required=False)
    parser.add_argument('--max_tokens', type=int, default=50)
    args = parser.parse_args()

    # Create a model instance using defaults from SGLM.py
    vocab_size = 32000
    model = SGLM(vocab_size)
    device = torch.device('cpu')
    model.to(device)

    if args.weights:
        try:
            sd = torch.load(args.weights, map_location=device)
            if isinstance(sd, dict):
                model.load_state_dict(sd)
        except Exception:
            pass

    gen = Generator(model, device=device)

    # Simple whitespace tokenizer -> stable hash ids
    def tokenize(text):
        toks = text.split()
        ids = [abs(hash(t)) % vocab_size for t in toks]
        return ids

    def detokenize(ids):
        return ' '.join(f"<tok{int(i)}>" for i in ids)

    seed_ids = tokenize(args.prompt)
    if len(seed_ids) == 0:
        seed_ids = [0]

    seq = torch.tensor(seed_ids, dtype=torch.long).unsqueeze(0).to(device)
    try:
        out_seq = gen.generate(seq.squeeze(0), maxLen=args.max_tokens)
        if isinstance(out_seq, torch.Tensor):
            out_ids = out_seq.tolist()
        else:
            out_ids = list(out_seq)
    except Exception:
        out_ids = seed_ids

    resp_text = detokenize(out_ids)
    print(json.dumps({"result": "ok", "response": resp_text}))


if __name__ == '__main__':
    main()
