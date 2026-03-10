import sys
import argparse
import importlib.util
import json
from pathlib import Path

import torch
import torch.nn.functional as F

# Configuration constants (tweak here instead of CLI params)
# Defaults chosen to favor speed on CPU
DEVICE = "cpu"
MAX_NEW_TOKENS = 128
TEMPERATURE = 0.7
TOP_K = 20
TOP_P = 0.95
REPETITION_PENALTY = 1.1
NUM_RETURN_SEQUENCES = 1
SELF_CONSISTENCY_N = 1
USE_BEAM_SEARCH = False
BEAM_WIDTH = 2
LENGTH_PENALTY = 1.0

parser = argparse.ArgumentParser()
# Keep only prompt (device is fixed to CPU)
parser.add_argument("--prompt", type=str, required=True)
cli = parser.parse_args()

HERE = Path(__file__).parent.resolve()

def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

from tokenizers import Tokenizer

tok_path = HERE.parent / "data" / "tokenizer.json"
if not tok_path.exists():
    raise FileNotFoundError(tok_path)

tokenizer = Tokenizer.from_file(str(tok_path))

with open(HERE.parent / "data" / "tokenizer_config.json") as f:
    tok_cfg = json.load(f)

IM_START = tokenizer.token_to_id("<|im_start|>")
IM_END = tokenizer.token_to_id("<|im_end|>")
EOS = tokenizer.token_to_id("<|endoftext|>")

# Precompute common token id sequences to avoid repeated tokenization
SYSTEM_IDS = encode(f"system\n{SYSTEM}")
USER_PREFIX_IDS = encode("user\n")
ASSISTANT_PREFIX_IDS = encode("assistant\n")
NEWLINE_IDS = encode("\n")

def encode(text: str) -> list[int]:
    return tokenizer.encode(text, add_special_tokens=False).ids

def decode(ids: list[int]) -> str:
    return tokenizer.decode(ids, skip_special_tokens=True)


def clean_text(text: str) -> str:
    # remove known special tokens and stray markers
    for t in ("<|im_end|>", "<|im_start|>", "<|endoftext|>"):
        text = text.replace(t, "")
    return text.replace("\x00", "").strip()

SEMANTIC_RERANKING = True
SEMANTIC_ALPHA = 0.6  # weight for semantic score in final ranking
LOGPROB_BETA = 0.4    # weight for model logprob score

model_mod = load_module("sglm", HERE / "SGLM.py")
model_path = HERE.parent / "data" / "model.safetensors"
if not model_path.exists():
    model_path = HERE.parent / "data" / "model"
model = model_mod.SGLM.load(model_path, device=DEVICE)

SYSTEM = (
    "You're a helpful, concise and creative personal assistant called Agent. "
    "You're part of EaSync and created by Nortify Inc. Provide clear answers, offer multiple options when relevant, "
    "and avoid unnecessary repetition. When asked for reasoning, be concise and structured."
)

def build_tokens(history: list[tuple[str, str]], user_msg: str) -> torch.Tensor:
    ids = []

    ids += [IM_START] + SYSTEM_IDS + [IM_END] + NEWLINE_IDS

    for u, a in history:
        ids += [IM_START] + USER_PREFIX_IDS + encode(u) + [IM_END] + NEWLINE_IDS
        ids += [IM_START] + ASSISTANT_PREFIX_IDS + encode(a) + [IM_END] + NEWLINE_IDS

    ids += [IM_START] + USER_PREFIX_IDS + encode(user_msg) + [IM_END] + NEWLINE_IDS

    ids += [IM_START] + ASSISTANT_PREFIX_IDS

    return torch.tensor([ids], dtype=torch.long, device=DEVICE)

@torch.no_grad()
def respond(history: list, user_msg: str) -> str:
    def sample_once(temperature: float) -> list[int]:
        token_ids = build_tokens(history, user_msg)
        out = model(token_ids)
        logits = out["logits"]
        kv_caches = out["kv_caches"]
        offset = token_ids.shape[1]

        generated = []
        logprob_sum = 0.0
        for _ in range(MAX_NEW_TOKENS):
            next_logits = logits[:, -1, :] / max(1e-6, temperature)

            # repetition penalty: discourage tokens already generated
            if REPETITION_PENALTY is not None and REPETITION_PENALTY != 1.0:
                for t in set(generated):
                    next_logits[0, t] = next_logits[0, t] / float(REPETITION_PENALTY)

            if TOP_K:
                v, _ = torch.topk(next_logits, TOP_K)
                next_logits[next_logits < v[:, [-1]]] = float("-inf")

            if TOP_P < 1.0:
                sorted_logits, sorted_idx = torch.sort(next_logits, descending=True)
                cum_probs = torch.cumsum(F.softmax(sorted_logits, dim=-1), dim=-1)
                remove = cum_probs - F.softmax(sorted_logits, dim=-1) > TOP_P
                sorted_logits[remove] = float("-inf")
                next_logits = torch.scatter(next_logits, 1, sorted_idx, sorted_logits)

            probs = F.softmax(next_logits, dim=-1)
            token_id = torch.multinomial(probs, 1).item()
            # accumulate log-prob for reranking
            token_logprob = float(torch.log(probs[0, token_id] + 1e-12).item())
            logprob_sum += token_logprob

            if token_id in (IM_END, EOS, 0):
                break

            generated.append(token_id)
            token_tensor = torch.tensor([[token_id]], device=DEVICE)
            out = model(token_tensor, kv_caches=kv_caches, offset=offset)
            logits = out["logits"]
            kv_caches = out["kv_caches"]
            offset += 1

        return generated, logprob_sum
    # If beam search is enabled, prefer it for higher-quality deterministic output
    if USE_BEAM_SEARCH:
        beam_result = beam_search(history, user_msg)
        # clean beam result before returning
        return clean_text(beam_result)

    # Generate multiple candidates to increase diversity / self-consistency
    candidates = []
    sample_infos = []
    for i in range(max(1, NUM_RETURN_SEQUENCES)):
        temp = TEMPERATURE
        gen, lp = sample_once(temp)
        candidates.append(clean_text(decode(gen).strip()))
        sample_infos.append((gen, lp))

    # If self-consistency mode requested, resample and pick the most frequent answer
    if SELF_CONSISTENCY_N and SELF_CONSISTENCY_N > 1:
        sc_samples = []
        for _ in range(SELF_CONSISTENCY_N):
            gen, lp = sample_once(max(TEMPERATURE, 0.8))
            sc_samples.append(clean_text(decode(gen).strip()))
        from collections import Counter

        most_common = Counter(sc_samples).most_common(1)
        if most_common:
            return most_common[0][0]

    # Rerank sampled candidates by average log-prob (prefer higher average logprob)
    if len(candidates) == 1:
        return candidates[0]
    else:
        scored = []
        for (gen, lp), text in zip(sample_infos, candidates):
            l = max(1, len(gen))
            logprob_score = lp / (l ** LENGTH_PENALTY)
            if SEMANTIC_RERANKING:
                sem = semantic_score(cli.prompt, text)
                final = SEMANTIC_ALPHA * sem + LOGPROB_BETA * (logprob_score)
            else:
                final = logprob_score
            scored.append((final, text))
        scored.sort(key=lambda x: x[0], reverse=True)
        # return distinct candidates ordered by score
        unique = []
        for _, c in scored:
            if c and c not in unique:
                unique.append(c)
        return "\n\n---\n\n".join(unique)


def normalize_words(s: str) -> list[str]:
    import re
    s = s.lower()
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    parts = [w for w in s.split() if len(w) > 1]
    return parts


def semantic_score(prompt: str, candidate: str) -> float:
    pset = set(normalize_words(prompt))
    cset = set(normalize_words(candidate))
    if not pset or not cset:
        return 0.0
    inter = pset.intersection(cset)
    union = pset.union(cset)
    return len(inter) / len(union)

def beam_search(history: list, user_msg: str) -> str:
    # simple beam search that expands top-K tokens at each step and keeps top BEAM_WIDTH beams
    init_out = model(build_tokens(history, user_msg))
    init_logits = init_out["logits"]
    init_kv = init_out["kv_caches"]
    offset = init_logits.shape[1]

    beams = [
        {"tokens": [], "kv": init_kv, "logprob": 0.0, "logits": init_logits, "offset": offset, "done": False}
    ]

    for _ in range(MAX_NEW_TOKENS):
        all_candidates = []
        for b in beams:
            if b["done"]:
                all_candidates.append(b)
                continue

            next_logits = b["logits"][:, -1, :] / max(1e-6, TEMPERATURE)
            # repetition penalty
            if REPETITION_PENALTY is not None and REPETITION_PENALTY != 1.0:
                for t in set(b["tokens"]):
                    next_logits[0, t] = next_logits[0, t] / float(REPETITION_PENALTY)

            if TOP_K:
                v, _ = torch.topk(next_logits, TOP_K)
                next_logits[next_logits < v[:, [-1]]] = float("-inf")

            probs = F.softmax(next_logits, dim=-1)
            topv, topi = torch.topk(probs, BEAM_WIDTH, dim=-1)
            topv = topv[0].tolist()
            topi = topi[0].tolist()

            for pv, pi in zip(topv, topi):
                token_tensor = torch.tensor([[pi]], device=DEVICE)
                out = model(token_tensor, kv_caches=b["kv"], offset=b["offset"])
                new_logits = out["logits"]
                new_kv = out["kv_caches"]
                cand = {
                    "tokens": b["tokens"] + [pi],
                    "kv": new_kv,
                    "logprob": b["logprob"] + float(torch.log(torch.tensor(pv) + 1e-12).item()),
                    "logits": new_logits,
                    "offset": b["offset"] + 1,
                    "done": pi in (IM_END, EOS, 0),
                }
                all_candidates.append(cand)

        # keep top BEAM_WIDTH by score (normalized by length)
        def score(b):
            l = max(1, len(b["tokens"]))
            return b["logprob"] / (l ** LENGTH_PENALTY)

        beams = sorted(all_candidates, key=score, reverse=True)[:BEAM_WIDTH]

        # stop if all beams done
        if all(b["done"] for b in beams):
            break

    # pick best finished beam or best beam
    finished = [b for b in beams if b["done"]]
    best = (finished or beams)[0]
    return decode(best["tokens"]).strip()
 

if __name__ == '__main__':
    history = []
    resp = respond(history, cli.prompt)
    print(resp)
