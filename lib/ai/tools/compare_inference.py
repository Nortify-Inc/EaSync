#!/usr/bin/env python3
"""
Compare a short inference between original ONNX and quantized ONNX models.
Outputs max absolute difference, mean difference and whether outputs are exactly equal.

Usage:
  python compare_inference.py

It expects the following files in `lib/ai/data/`:
- model.onnx (quantized current)
- model_old.onnx.backup (original)
- tokenizer.json and vocab.json to get vocab size
"""
import json
import numpy as np
import onnx
import onnxruntime as ort
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[1] / 'data'
MODEL_Q = DATA_DIR / 'model.onnx'
MODEL_REF = DATA_DIR / 'model_old.onnx.backup'
VOCAB = DATA_DIR / 'vocab.json'

def load_vocab_size():
    with open(VOCAB, 'r', encoding='utf-8') as f:
        v = json.load(f)
    return len(v)


def make_dummy_input(vocab_size, seq_len=16):
    # create deterministic pseudo-random tokens
    rng = np.random.default_rng(12345)
    ids = rng.integers(low=0, high=vocab_size, size=(1, seq_len), dtype=np.int64)
    return ids


def run_model(path, input_ids):
    sess = ort.InferenceSession(str(path), providers=['CPUExecutionProvider'])
    # Inspect input names
    inps = sess.get_inputs()
    print(f'Model {path.name} inputs: {[ (i.name, i.shape, i.type) for i in inps ]}')
    # Common naming: input_ids or input
    input_name = inps[0].name
    # If model expects float input, cast
    input_type = inps[0].type
    if 'int' in input_type or 'tensor(int' in input_type:
        feed = {input_name: input_ids}
    else:
        # cast to float
        feed = {input_name: input_ids.astype(np.float32)}
    outs = sess.run(None, feed)
    return outs


def compare(out1, out2):
    if len(out1) != len(out2):
        print(f'Output count differs: {len(out1)} vs {len(out2)}')
    for i, (a,b) in enumerate(zip(out1, out2)):
        a = np.asarray(a)
        b = np.asarray(b)
        eq = np.array_equal(a, b)
        absdiff = np.max(np.abs(a - b))
        meandiff = np.mean(np.abs(a - b))
        print(f'Output[{i}]: exact_equal={eq} max_abs_diff={absdiff:.6f} mean_abs_diff={meandiff:.6f} shape={a.shape}')


def main():
    if not MODEL_Q.exists():
        print('Quantized model not found:', MODEL_Q)
        return
    if not MODEL_REF.exists():
        print('Reference model not found:', MODEL_REF)
        return
    vocab_size = load_vocab_size()
    print('Vocab size:', vocab_size)
    input_ids = make_dummy_input(vocab_size, seq_len=16)
    print('Running quantized model...')
    out_q = run_model(MODEL_Q, input_ids)
    print('Running reference model...')
    out_ref = run_model(MODEL_REF, input_ids)
    print('Comparing outputs...')
    compare(out_ref, out_q)

if __name__ == '__main__':
    main()
