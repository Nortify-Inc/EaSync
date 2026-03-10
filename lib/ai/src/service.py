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
import sentencepiece as spm
try:
    from tokenizers import Tokenizer as HFTokenizer
except Exception:
    HFTokenizer = None
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prompt', required=True)
    args = parser.parse_args()

    # single-argument mode: decoding and file paths are fixed defaults
    max_tokens = 50
    decoding_method = 'typical'
    temperature = 0.6
    top_k = 40
    top_p = 0.9
    repetition_penalty = 1.2
    ban_ngram = 4
    typical_p = 0.95
    entropy_target = None
    entropy_lr = 0.1

    # Prefer HF Tokenizer (`tokenizer.json`) from lib/ai/data for chat-style formatting
    data_dir = Path(__file__).resolve().parents[1] / "data"
    hf_tok_path = data_dir / "tokenizer.json"
    sp_tok_path = Path(args.tokenizer) if args.tokenizer else data_dir / "tokenizer.model"

    hf_tokenizer = None
    tokenizer = None
    vocab_size = None

    if hf_tok_path.exists() and HFTokenizer is not None:
        try:
            hf_tokenizer = HFTokenizer.from_file(str(hf_tok_path))
            vocab_size = hf_tokenizer.get_vocab_size()
        except Exception:
            hf_tokenizer = None

    if hf_tokenizer is None:
        if not sp_tok_path.exists():
            print(json.dumps({"result": "error", "message": f"Tokenizer not found: {sp_tok_path} or {hf_tok_path}"}))
            sys.exit(1)
        tokenizer = spm.SentencePieceProcessor()
        ok = tokenizer.load(str(sp_tok_path))
        if not ok:
            print(json.dumps({"result": "error", "message": "Failed to load SentencePiece tokenizer"}))
            sys.exit(1)
        vocab_size = tokenizer.get_piece_size()
    # instantiate model with same architecture used during training (matches train.py)
    model = SGLM(vocab_size, dim=256, layers=6, heads=8, kvHeads=2)
    device = torch.device('cpu')
    model.to(device)

    # load weights: prefer explicit --weights, otherwise try common checkpoint locations
    def try_load(path):
        try:
            sd = torch.load(path, map_location=device)
        except Exception:
            return False
        # handle wrapped dicts or raw state_dicts
        if isinstance(sd, dict):
            if "model_state" in sd:
                try:
                    model.load_state_dict(sd["model_state"])
                    return True
                except Exception:
                    pass
            # try direct state dict
            try:
                model.load_state_dict(sd)
                return True
            except Exception:
                # maybe checkpoint contains extra keys or vocab mismatch; try common wrappers
                for k in ("state_dict", "model", "model_state_dict"):
                    if k in sd:
                        try:
                            model.load_state_dict(sd[k])
                            return True
                        except Exception:
                            pass
                # attempt to adapt embedding/head sizes when vocab differs
                cand = None
                for k in ("model_state", "state_dict", "model", "model_state_dict"):
                    if k in sd:
                        cand = sd[k]
                        break
                if cand is None:
                    cand = sd
                if isinstance(cand, dict):
                    ck_state = cand
                    model_state = model.state_dict()
                    new_state = {}
                    for kk, vv in ck_state.items():
                        if kk in model_state:
                            try:
                                if vv.shape == model_state[kk].shape:
                                    new_state[kk] = vv
                                else:
                                    # special-case token embedding and head: copy prefix rows
                                    if kk in ("tokenEmb.weight", "head.weight") and vv.dim() >= 2:
                                        min0 = min(vv.shape[0], model_state[kk].shape[0])
                                        tmp = model_state[kk].clone()
                                        tmp[:min0] = vv[:min0]
                                        new_state[kk] = tmp
                                    else:
                                        # skip incompatible key
                                        pass
                            except Exception:
                                pass
                    # fill remaining keys from model_state
                    for kk in model_state:
                        if kk not in new_state:
                            new_state[kk] = model_state[kk]
                    try:
                        model.load_state_dict(new_state)
                        return True
                    except Exception:
                        return False
        return False

    loaded = False
    if args.weights:
        loaded = try_load(args.weights)
    else:
        # common paths relative to project
        cand = [
            Path(__file__).resolve().parents[1] / "data" / "sglm_model.pt",
            Path(__file__).resolve().parents[1] / "data" / "sglm_model.pth",
            Path(__file__).resolve().parents[2] / "lib" / "ai" / "models" / "sglm.pth",
            Path(__file__).resolve().parents[1] / "models" / "sglm.pth",
        ]
        for p in cand:
            if p.exists():
                loaded = try_load(str(p))
                if loaded:
                    break

    if not loaded:
        # attempt to give a helpful diagnostic if a checkpoint exists but failed to load
        cand_path = Path(__file__).resolve().parents[1] / "data" / "sglm_model.pt"
        if cand_path.exists():
            try:
                sd = torch.load(str(cand_path), map_location=device)
                if isinstance(sd, dict):
                    # if raw state_dict stored as OrderedDict
                    if "tokenEmb.weight" in sd:
                        ck_vocab = sd["tokenEmb.weight"].shape[0]
                        if ck_vocab != vocab_size:
                            print(json.dumps({"result": "warning", "message": f"Checkpoint vocab ({ck_vocab}) != tokenizer vocab ({vocab_size}). Pass matching tokenizer or a matching checkpoint via --weights."}))
                else:
                    # sd may be state_dict-like
                    if hasattr(sd, "keys"):
                        if "tokenEmb.weight" in sd:
                            ck_vocab = sd["tokenEmb.weight"].shape[0]
                            if ck_vocab != vocab_size:
                                print(json.dumps({"result": "warning", "message": f"Checkpoint vocab ({ck_vocab}) != tokenizer vocab ({vocab_size}). Pass matching tokenizer or a matching checkpoint via --weights."}))
            except Exception:
                pass
        else:
            # no checkpoint found; model remains randomly initialized
            pass

    gen = Generator(model, device=device)

    # Use SentencePiece tokenizer for tokenization/detokenization
    # Provide a chat-style token builder if HF tokenizer is available
    SYSTEM = """
You are Agent, the friendly assistant of the EaSync App.
Be concise, helpful and avoid fabricating personal data.
"""

    def tokenize_sp(text):
        return tokenizer.encode(text)

    def detokenize_sp(ids):
        try:
            return tokenizer.decode(ids)
        except Exception:
            pieces = [tokenizer.id_to_piece(int(i)) for i in ids]
            return ''.join(pieces)

    def build_chat_tokens(user_text):
        # build tokens similar to `chat.py` using HF tokenizer special tokens
        im_start = None
        im_end = None
        eos = None
        try:
            im_start = hf_tokenizer.token_to_id("<|im_start|>")
            im_end = hf_tokenizer.token_to_id("<|im_end|>")
            eos = hf_tokenizer.token_to_id("<|endoftext|>")
        except Exception:
            # fallback to None
            pass

        pieces = []
        if hf_tokenizer is not None and im_start is not None:
            pieces += [im_start] + hf_tokenizer.encode(f"system\n{SYSTEM}").ids + [im_end]
            pieces += hf_tokenizer.encode("\n").ids
            pieces += [im_start] + hf_tokenizer.encode(f"user\n{user_text}").ids + [im_end]
            pieces += hf_tokenizer.encode("\n").ids
            pieces += [im_start] + hf_tokenizer.encode("assistant\n").ids
            return pieces
        else:
            # fallback to simple SentencePiece formatting
            text = "<bos> <sep> user: " + user_text + " <eos>"
            return tokenize_sp(text)

    def detokenize(ids):
        if hf_tokenizer is not None:
            try:
                return hf_tokenizer.decode(ids, skip_special_tokens=True)
            except Exception:
                pass
        return detokenize_sp(ids)

    # Role-aware history formatting helper
    def format_dialogue(history, user_text):
        # history: list of (role, text) where role in {"user","assistant","system"}
        # keep recent turns up to model.maxSeq tokens when possible
        pieces = ["<bos>"]
        for role, text in history[-6:]:
            if role == "user":
                pieces.append("<sep> user: ")
            elif role == "assistant":
                pieces.append("<sep> assistant: ")
            else:
                pieces.append("<sep> system: ")
            pieces.append(text)
        pieces.append("<sep> user: ")
        pieces.append(user_text)
        pieces.append("<eos>")
        return "".join(pieces)

    # build seed ids using chat-style tokens when available
    if hf_tokenizer is not None:
        seed_ids = build_chat_tokens(args.prompt)
    else:
        seed_ids = tokenize_sp(args.prompt)
    if len(seed_ids) == 0:
        seed_ids = [0]

    seq = torch.tensor(seed_ids, dtype=torch.long).unsqueeze(0).to(device)
    # primary generation attempt with advanced decoding defaults
    try:
        out_seq = gen.generate(
            seq.squeeze(0),
            maxLen=args.max_tokens,
            temperature=args.temperature,
            topK=args.top_k,
            topP=args.top_p,
            repetition_penalty=args.repetition_penalty,
            ban_ngram_size=args.ban_ngram,
            method=args.decoding_method,
            typical_p=args.typical_p,
        )
        if isinstance(out_seq, torch.Tensor):
            out_ids = out_seq.tolist()
        else:
            out_ids = list(out_seq)
    except Exception:
        out_ids = seed_ids

    # return only the continuation (tokens after the seed)
    cont_ids = out_ids[len(seed_ids):]

    # if continuation is empty or trivial, try aggressive fallback sampling
    def aggressive_sample():
        # expanded sampling strategies: vary temperature, top-k, top-p, and length
        tries = [
            {"method": "typical", "temperature": 0.8, "topK": 200, "topP": 0.97, "max_len": min(64, args.max_tokens)},
            {"method": "sample", "temperature": 1.2, "topK": 0, "topP": 0.0, "max_len": min(80, args.max_tokens)},
            {"method": "typical", "temperature": 0.8, "topK": 40, "topP": 0.9, "max_len": min(40, args.max_tokens)},
            {"method": "typical", "temperature": 0.6, "topK": 30, "topP": 0.85, "max_len": min(32, args.max_tokens)},
        ]
        for cfg in tries:
            try:
                s = gen.generate(
                    seq.squeeze(0),
                    maxLen=cfg["max_len"],
                    temperature=cfg.get("temperature", args.temperature),
                    topK=cfg.get("topK", args.top_k),
                    topP=cfg.get("topP", args.top_p),
                    repetition_penalty=args.repetition_penalty,
                    ban_ngram_size=args.ban_ngram,
                    method=cfg.get("method", args.decoding_method),
                    typical_p=args.typical_p,
                    entropy_target=args.entropy_target,
                    entropy_lr=args.entropy_lr,
                )
                if isinstance(s, torch.Tensor):
                    s_ids = s.tolist()
                else:
                    s_ids = list(s)
                c = s_ids[len(seed_ids):]
                if len(c) > 0:
                    return c
            except Exception:
                continue
        # try sample-and-rank: generate several candidates and pick best by log-prob (length-normalized)
        try:
            candidates = []
            for t in (0.6, 0.8, 1.0):
                for _ in range(3):
                    s = gen.generate(
                        seq.squeeze(0),
                        maxLen=min(32, args.max_tokens),
                        temperature=t,
                        topK=args.top_k,
                        topP=args.top_p,
                        repetition_penalty=args.repetition_penalty,
                        ban_ngram_size=args.ban_ngram,
                        method='sample',
                        typical_p=args.typical_p,
                    )
                    s_ids = s.tolist() if isinstance(s, list) or isinstance(s, tuple) else s.tolist()
                    cont = s_ids[len(seed_ids):]
                    if len(cont) == 0:
                        continue
                    # score candidate using model log-prob
                    try:
                        import math as _math
                        seq_ids = seed_ids + cont
                        t_in = torch.tensor([seq_ids], dtype=torch.long).to(device)
                        with torch.no_grad():
                            logits = model(t_in)
                            logp = torch.log_softmax(logits, dim=-1)
                        # sum log-probs for continuation tokens
                        cum = 0.0
                        L = len(seq_ids)
                        for i in range(len(seed_ids), L):
                            tok = seq_ids[i]
                            cum += float(logp[0, i - 0, tok])
                        # length-normalize and repetition penalty
                        rep_pen = len(cont) - len(set(cont))
                        score = cum / (len(cont) ** 0.7) - 0.1 * rep_pen
                        candidates.append((score, cont))
                    except Exception:
                        candidates.append(( -1e9, cont))
            if len(candidates) > 0:
                candidates.sort(key=lambda x: x[0], reverse=True)
                return candidates[0][1]
        except Exception:
            pass
        # last resort: sample random tokens from tokenizer vocab but bias towards frequent tokens
        import random
        vocab_n = tokenizer.get_piece_size()
        # sample from unigram frequency proxy by using tokenizer.get_score (if available)
        try:
            scores = [tokenizer.get_score(i) for i in range(vocab_n)]
            # convert to probabilities
            import math
            exps = [math.exp(s) if not math.isinf(s) and not math.isnan(s) else 0.0 for s in scores]
            total = sum(exps)
            if total > 0:
                probs = [e/total for e in exps]
                return random.choices(range(vocab_n), weights=probs, k=min(8,args.max_tokens))
        except Exception:
            pass
        return [random.randrange(vocab_n) for _ in range(min(8, args.max_tokens))]

    if len(cont_ids) == 0 or all((isinstance(x, int) and x == seed_ids[-1]) for x in cont_ids[:1]):
        cont_ids = aggressive_sample()

    resp_text = detokenize(cont_ids) if len(cont_ids) > 0 else detokenize(out_ids)
    print(json.dumps({"result": "ok", "response": resp_text}))


if __name__ == '__main__':
    main()
