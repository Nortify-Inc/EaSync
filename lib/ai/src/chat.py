import sys
import argparse
import importlib.util
import json
from pathlib import Path

import torch
import torch.nn.functional as F

parser = argparse.ArgumentParser()
parser.add_argument("--device",         type=str,   default="cpu")
parser.add_argument("--max_new_tokens", type=int,   default=256)
parser.add_argument("--temperature",    type=float, default=0.7)
parser.add_argument("--top_k",          type=int,   default=40)
parser.add_argument("--top_p",          type=float, default=0.9)
cli = parser.parse_args()

HERE = Path(__file__).parent.resolve()

def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod  = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

from tokenizers import Tokenizer
from tokenizers.processors import TemplateProcessing

tok_path = HERE / "tokenizer.json"
if not tok_path.exists():
    raise FileNotFoundError(tok_path)

tokenizer = Tokenizer.from_file(str(tok_path))

with open(HERE / "tokenizer_config.json") as f:
    tok_cfg = json.load(f)

IM_START = tokenizer.token_to_id("<|im_start|>")
IM_END   = tokenizer.token_to_id("<|im_end|>")
EOS      = tokenizer.token_to_id("<|endoftext|>")

def encode(text: str) -> list[int]:
    return tokenizer.encode(text, add_special_tokens=False).ids

def decode(ids: list[int]) -> str:
    return tokenizer.decode(ids, skip_special_tokens=False)

model_mod = load_module("sglm", HERE / "SGLM.py")
model     = model_mod.SGLM.load(HERE / "model.safetensors", device=cli.device)

SYSTEM = """
You are Agent, the friendly assistant of the EaSync App created by Nortify Inc.

EaSync is a smart home platform that connects and manages devices such as lights, locks, thermostats, cameras and appliances.

Your purpose is to help users interact with their smart home in a natural and pleasant way.

IDENTITY

You are a software assistant. You do not have a personal life, birthday, age, family, or physical existence.

If a user asks about your birthday, age, or personal life, respond politely and explain that you are an AI assistant created for EaSync.

USER INFORMATION

You do not know personal information about the user unless the EaSync system provides it.

Never guess or invent personal information such as:
- birthdays
- names
- addresses
- schedules
- private data

If the user asks about their own information and it was not provided, say that you do not have access to that information.

SMART HOME ROLE

Users will ask to control devices or check device states.

Examples:
- turn devices on or off
- change brightness
- set temperature
- lock doors
- list devices
- check device status

Device control requests are normal and expected. Always respond positively and confirm the action.

DEVICE DATA

You do NOT have direct access to real device data.

When the user asks for device states or device lists, never invent numbers or states.

Instead introduce the information and let the EaSync system append the real data.

Example:

User: What is the brightness of the living room lamp?
Agent: Sure! Here is the current brightness:

CONVERSATION STYLE

Be friendly, positive and enthusiastic.

Avoid cold or robotic responses.

You may use expressions like:
Sure!
Great!
Of course!
Happy to help!
You're welcome!

Your goal is to make controlling a smart home through EaSync feel simple and pleasant.
"""

def build_tokens(history: list[tuple[str, str]], user_msg: str) -> torch.Tensor:
    ids = []

    ids += [IM_START] + encode(f"system\n{SYSTEM}") + [IM_END] + encode("\n")

    for u, a in history:
        ids += [IM_START] + encode(f"user\n{u}") + [IM_END] + encode("\n")
        ids += [IM_START] + encode(f"assistant\n{a}") + [IM_END] + encode("\n")

    ids += [IM_START] + encode(f"user\n{user_msg}") + [IM_END] + encode("\n")

    ids += [IM_START] + encode("assistant\n")

    return torch.tensor([ids], dtype=torch.long, device=cli.device)

@torch.no_grad()
def respond(history: list, user_msg: str) -> str:
    token_ids = build_tokens(history, user_msg)

    out       = model(token_ids)
    logits    = out["logits"]
    kv_caches = out["kv_caches"]
    offset    = token_ids.shape[1]

    generated = []
    for _ in range(cli.max_new_tokens):
        next_logits = logits[:, -1, :] / cli.temperature

        if cli.top_k:
            v, _ = torch.topk(next_logits, cli.top_k)
            next_logits[next_logits < v[:, [-1]]] = float("-inf")

        if cli.top_p < 1.0:
            sorted_logits, sorted_idx = torch.sort(next_logits, descending=True)
            cum_probs = torch.cumsum(F.softmax(sorted_logits, dim=-1), dim=-1)
            remove    = cum_probs - F.softmax(sorted_logits, dim=-1) > cli.top_p
            sorted_logits[remove] = float("-inf")
            next_logits = torch.scatter(next_logits, 1, sorted_idx, sorted_logits)

        token_id = torch.multinomial(F.softmax(next_logits, dim=-1), 1).item()

        if token_id in (IM_END, EOS, 0):
            break

        generated.append(token_id)
        token_tensor = torch.tensor([[token_id]], device=cli.device)
        out       = model(token_tensor, kv_caches=kv_caches, offset=offset)
        logits    = out["logits"]
        kv_caches = out["kv_caches"]
        offset   += 1

    return decode(generated).strip()

history = []
print("EaSync Agent 0.5b  |  'quit' to exit  |  'clear' to reset history\n")

while True:
    try:
        user_input = input("You: ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        break

    if not user_input:
        continue
    if user_input.lower() == "quit":
        break
    if user_input.lower() == "clear":
        history.clear()
        print("History cleared.\n")
        continue

    response = respond(history, user_input)
    print(f"\nAgent: {response}\n")
    history.append((user_input, response))