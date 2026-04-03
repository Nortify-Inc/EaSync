from __future__ import annotations

import random
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple

import torch
from transformers import AutoTokenizer

try:
	from .model import AgentLM, default_model_dir
except ImportError:
	from model import AgentLM, default_model_dir


CFG: Dict[str, Any] = {
	"model_dir": str(default_model_dir()),
	"device": "cpu",
	"dtype": "float32",
	"max_new_tokens": 1024,
	"temperature": 0.72,
	"top_k": 60,
	"top_p": 0.94,
	"repetition_penalty": 1.14,
	"no_repeat_ngram_size": 0,
	"max_history_turns": 5,
	"max_chars": 0,
	"prefer_tokenizer_chat_template": False,
	"candidate_count": 3,
	"typing_effect_enabled": True,
	"typing_chars_per_sec": 28,
	"typing_jitter": 0.25,
	"typing_punctuation_pause": 0.05,
	"thinking_text": "Thinking...",
	"thinking_min_tokens": 30,
}

SYSTEM_PROMPT = (
	"Your name is Agent."
	"You are a helpful AI created by Nortify Inc."
	"Be natural, conversational, and thoughtful."
	"You may answer with useful detail, practical examples, and clear reasoning."
	"If uncertain, state assumptions briefly and continue helping."
)


def build_prompt(tokenizer: AutoTokenizer, history: List[Tuple[str, str]]) -> str:
	chat_template = getattr(tokenizer, "chat_template", None)
	if CFG["prefer_tokenizer_chat_template"] and chat_template:
		messages: List[Dict[str, Any]] = [{"role": role, "content": content} for role, content in history]
		return tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)

	parts = []
	for role, content in history:
		parts.append(f"<|im_start|>{role}\n{content}\n<|im_end|>\n")
	parts.append("<|im_start|>assistant\n")
	return "".join(parts)


def _looks_like_garbage(text: str) -> bool:
	lower = text.lower()
	if not text or len(text) < 2:
		return True
	if lower.count(",") > 18:
		return True
	if "http://" in lower or "https://" in lower:
		return True
	if "[quote" in lower or "[quoted_text" in lower or "{{" in lower:
		return True
	if "blog" in lower or "forum" in lower or "talk)" in lower:
		return True
	if re.search(r"(.)\1{7,}", text):
		return True
	if len(text.split()) > 180:
		return True
	return False


def _postprocess_text(text: str, max_chars: int) -> str:
	text = text.split("<|im_end|>", 1)[0]
	text = text.split("<|im_start|>", 1)[0]
	text = text.replace("assistant\n", "").replace("Assistant\n", "")
	text = text.replace("<|endoftext|>", "")
	text = re.sub(r"\s+", " ", text).strip()
	text = re.sub(r"https?://\S+", "", text)
	text = re.sub(r"\[/?\w+[^\]]*\]", "", text)
	text = re.sub(r"\{\{[^}]*\}\}", "", text)
	text = re.split(r"\b(assistant|user|system)\b\s*[:\n]", text, maxsplit=1, flags=re.IGNORECASE)[0].strip()

	if max_chars > 0 and len(text) > max_chars:
		text = text[:max_chars].rsplit(" ", 1)[0].strip() + "..."

	return text.strip(" -\n\t")


def _keywords(text: str) -> List[str]:
	stop = {
		"the", "a", "an", "is", "are", "to", "of", "and", "or", "in", "on", "for", "with",
		"what", "who", "how", "much", "does", "do", "you", "your", "about", "was", "were",
	}
	words = re.findall(r"[a-zA-Z0-9]+", text.lower())
	return [w for w in words if w not in stop and len(w) > 2]


def _score_candidate(user_text: str, candidate: str) -> float:
	if not candidate:
		return -1e9

	words = candidate.split()
	score = 0.0

	if _looks_like_garbage(candidate):
		score -= 8.0

	word_count = len(words)
	if word_count < 3:
		score -= 2.0
	elif word_count <= 40:
		score += 1.8
	elif word_count <= 120:
		score += 2.6
	elif word_count <= 220:
		score += 1.2
	else:
		score -= 1.0

	user_keys = set(_keywords(user_text))
	if user_keys:
		cand_keys = set(_keywords(candidate))
		overlap = len(user_keys & cand_keys) / max(1, len(user_keys))
		score += overlap * 4.0

	if re.search(r"\b(i don't know|i do not know|not sure|uncertain)\b", candidate.lower()):
		score += 0.4

	if candidate.endswith(":"):
		score -= 0.8

	return score


def _sample_once(
	model: AgentLM,
	tokenizer: AutoTokenizer,
	prompt_ids: torch.Tensor,
	stop_token_ids: List[int],
	max_new_tokens: int,
	temperature: float,
	top_k: int,
	top_p: float,
	repetition_penalty: float,
	no_repeat_ngram_size: int,
	max_chars: int,
) -> str:
	generated_ids = model.generate(
		prompt_ids=prompt_ids,
		max_new_tokens=max_new_tokens,
		temperature=temperature,
		top_k=top_k,
		top_p=top_p,
		eos_token_id=tokenizer.eos_token_id,
		stop_token_ids=stop_token_ids,
		repetition_penalty=repetition_penalty,
		no_repeat_ngram_size=no_repeat_ngram_size,
	)

	if generated_ids.numel() == 0:
		return ""

	text = tokenizer.decode(generated_ids[0].tolist(), skip_special_tokens=False)
	return _postprocess_text(text, max_chars=max_chars)


def _type_chunk(text: str, cfg: Dict[str, Any]) -> None:
	if not text:
		return

	if not cfg.get("typing_effect_enabled", True):
		sys.stdout.write(text)
		sys.stdout.flush()
		return

	cps = max(5.0, float(cfg.get("typing_chars_per_sec", 28)))
	jitter = max(0.0, float(cfg.get("typing_jitter", 0.25)))
	punc_pause = max(0.0, float(cfg.get("typing_punctuation_pause", 0.05)))
	base_delay = 1.0 / cps

	for ch in text:
		sys.stdout.write(ch)
		sys.stdout.flush()
		delay = base_delay * random.uniform(1.0 - jitter, 1.0 + jitter)
		if ch in ".,;:!?":
			delay += punc_pause
		time.sleep(max(0.0, delay))


@torch.no_grad()
def _stream_generate_with_typing(
	model: AgentLM,
	tokenizer: AutoTokenizer,
	prompt_ids: torch.Tensor,
	stop_token_ids: List[int],
	max_new_tokens: int,
	temperature: float,
	top_k: int,
	top_p: float,
	repetition_penalty: float,
	no_repeat_ngram_size: int,
	max_chars: int,
	cfg: Dict[str, Any],
) -> str:
	thinking_text = str(cfg.get("thinking_text", "Thinking..."))
	thinking_min_tokens = max(1, int(cfg.get("thinking_min_tokens", 30)))


	sys.stdout.write(thinking_text)
	sys.stdout.flush()

	output = model.forward(prompt_ids)
	logits = output["logits"]
	kv_caches = output["kv_caches"]
	offset = prompt_ids.shape[1]

	generated: List[int] = []
	seen_ids = set(int(x) for x in prompt_ids[0].tolist())
	all_token_ids = [int(x) for x in prompt_ids[0].tolist()]

	started_typing = False
	pending_chunks: List[str] = []
	
	for _ in range(max_new_tokens):
		next_logits = logits[0, -1, :]
		if temperature > 0:
			next_logits = next_logits / temperature

		if repetition_penalty > 1.0 and seen_ids:
			for token_id in seen_ids:
				next_logits[token_id] = next_logits[token_id] / repetition_penalty

		if no_repeat_ngram_size >= 2 and len(all_token_ids) >= no_repeat_ngram_size - 1:
			prefix = tuple(all_token_ids[-(no_repeat_ngram_size - 1) :])
			blocked = set()
			upper = len(all_token_ids) - no_repeat_ngram_size + 1
			for i in range(max(0, upper)):
				if tuple(all_token_ids[i : i + no_repeat_ngram_size - 1]) == prefix:
					blocked.add(all_token_ids[i + no_repeat_ngram_size - 1])
			for token_id in blocked:
				next_logits[token_id] = float("-inf")

		if temperature > 0 and top_k > 0 and top_k < next_logits.shape[0]:
			values, _ = torch.topk(next_logits, top_k)
			next_logits[next_logits < values[-1]] = float("-inf")

		if temperature > 0 and 0.0 < top_p < 1.0:
			sorted_logits, sorted_indices = torch.sort(next_logits, descending=True)
			sorted_probs = torch.softmax(sorted_logits, dim=-1)
			cumulative_probs = torch.cumsum(sorted_probs, dim=-1)
			to_remove = cumulative_probs > top_p
			to_remove[..., 1:] = to_remove[..., :-1].clone()
			to_remove[..., 0] = False
			sorted_logits[to_remove] = float("-inf")
			next_logits = torch.scatter(next_logits, dim=0, index=sorted_indices, src=sorted_logits)

		if temperature == 0:
			next_token_id = int(torch.argmax(next_logits).item())
		else:
			probs = torch.softmax(next_logits, dim=-1)
			next_token_id = int(torch.multinomial(probs, num_samples=1).item())

		if next_token_id in stop_token_ids:
			break

		generated.append(next_token_id)
		seen_ids.add(next_token_id)
		all_token_ids.append(next_token_id)

		chunk = tokenizer.decode([next_token_id], skip_special_tokens=False)
		if any(t in chunk for t in ("<|im_end|>", "<|im_start|>", "<|endoftext|>")):
			break

		pending_chunks.append(chunk)

		if not started_typing and len(generated) >= thinking_min_tokens:
			started_typing = True
			sys.stdout.write("\r" + (" " * len(thinking_text)) + "\r")
			sys.stdout.flush()
			for buffered in pending_chunks:
				_type_chunk(buffered, cfg)
			pending_chunks.clear()
		elif started_typing:
			_type_chunk(chunk, cfg)

		next_input = torch.tensor([[next_token_id]], device=model.device, dtype=torch.long)
		output = model.forward(next_input, kv_caches=kv_caches, offset=offset)
		logits = output["logits"]
		kv_caches = output["kv_caches"]
		offset += 1

	if not started_typing:
		sys.stdout.write("\r" + (" " * len(thinking_text)) + "\r")
		sys.stdout.flush()
		for buffered in pending_chunks:
			_type_chunk(buffered, cfg)

	decoded = tokenizer.decode(generated, skip_special_tokens=False)
	return _postprocess_text(decoded, max_chars=max_chars)


def generate_reply(
	model: AgentLM,
	tokenizer: AutoTokenizer,
	history: List[Tuple[str, str]],
	max_new_tokens: int,
	temperature: float,
	top_k: int,
	top_p: float,
	repetition_penalty: float,
	no_repeat_ngram_size: int,
	max_chars: int,
) -> str:
	prompt = build_prompt(tokenizer, history)
	prompt_ids = tokenizer.encode(prompt, return_tensors="pt").to(model.device)
	stop_token_ids = []
	im_end_id = tokenizer.convert_tokens_to_ids("<|im_end|>")
	im_start_id = tokenizer.convert_tokens_to_ids("<|im_start|>")
	if isinstance(im_end_id, int) and im_end_id >= 0:
		stop_token_ids.append(im_end_id)
	if isinstance(im_start_id, int) and im_start_id >= 0:
		stop_token_ids.append(im_start_id)

	strategies = [
		{
			"temperature": temperature,
			"top_k": top_k,
			"top_p": top_p,
			"repetition_penalty": repetition_penalty,
		},
		{
			"temperature": max(0.15, temperature * 0.7),
			"top_k": max(20, min(70, top_k)),
			"top_p": min(0.92, max(0.82, top_p)),
			"repetition_penalty": max(1.1, repetition_penalty),
		},
		{
			"temperature": min(0.95, max(0.45, temperature * 1.35)),
			"top_k": max(30, top_k),
			"top_p": min(0.97, max(0.9, top_p)),
			"repetition_penalty": max(1.08, repetition_penalty - 0.02),
		},
	]

	candidates: List[str] = []
	for i, strategy in enumerate(strategies[: max(1, CFG["candidate_count"])]):
		if strategy["temperature"] > 0:
			torch.manual_seed(torch.seed() + i)
		candidate = _sample_once(
			model=model,
			tokenizer=tokenizer,
			prompt_ids=prompt_ids,
			stop_token_ids=stop_token_ids,
			max_new_tokens=max_new_tokens,
			temperature=strategy["temperature"],
			top_k=int(strategy["top_k"]),
			top_p=float(strategy["top_p"]),
			repetition_penalty=float(strategy["repetition_penalty"]),
			no_repeat_ngram_size=no_repeat_ngram_size,
			max_chars=max_chars,
		)
		if candidate:
			candidates.append(candidate)

	if not candidates:
		return ""

	best = max(candidates, key=lambda c: _score_candidate(history[-1][1], c))

	if _looks_like_garbage(best):
		best = _sample_once(
			model=model,
			tokenizer=tokenizer,
			prompt_ids=prompt_ids,
			stop_token_ids=stop_token_ids,
			max_new_tokens=max(24, max_new_tokens // 2),
			temperature=0.0,
			top_k=0,
			top_p=1.0,
			repetition_penalty=max(1.3, repetition_penalty),
			no_repeat_ngram_size=max(3, no_repeat_ngram_size),
			max_chars=max_chars,
		) or best

	return best


def main() -> None:
	model_dir = Path(CFG["model_dir"]).resolve()

	if not model_dir.exists():
		raise FileNotFoundError(f"Model directory not found: {model_dir}")

	dtype = {
		"float32": torch.float32,
		"float16": torch.float16,
		"bfloat16": torch.bfloat16,
	}[CFG["dtype"]]

	tokenizer = AutoTokenizer.from_pretrained(str(model_dir), local_files_only=True)
	model = AgentLM.load(model_dir, device=CFG["device"], dtype=dtype)

	print("Agent chat pronto. Digite 'exit' para sair.")
	history: List[Tuple[str, str]] = [("system", SYSTEM_PROMPT)]

	while True:
		user_text = input("You: ").strip()
		if not user_text:
			continue
		if user_text.lower() in {"exit", "quit", "sair"}:
			break

		history.append(("user", user_text))
		if len(history) > 1 + CFG["max_history_turns"] * 2:
			history = [history[0]] + history[-CFG["max_history_turns"] * 2 :]

		prompt = build_prompt(tokenizer, history)
		prompt_ids = tokenizer.encode(prompt, return_tensors="pt").to(model.device)
		stop_token_ids = []
		im_end_id = tokenizer.convert_tokens_to_ids("<|im_end|>")
		im_start_id = tokenizer.convert_tokens_to_ids("<|im_start|>")
		if isinstance(im_end_id, int) and im_end_id >= 0:
			stop_token_ids.append(im_end_id)
		if isinstance(im_start_id, int) and im_start_id >= 0:
			stop_token_ids.append(im_start_id)
		if tokenizer.eos_token_id is not None:
			stop_token_ids.append(int(tokenizer.eos_token_id))

		print("Agent:  ", end="", flush=True)
		reply = _stream_generate_with_typing(
			model=model,
			tokenizer=tokenizer,
			prompt_ids=prompt_ids,
			stop_token_ids=stop_token_ids,
			max_new_tokens=CFG["max_new_tokens"],
			temperature=CFG["temperature"],
			top_k=CFG["top_k"],
			top_p=CFG["top_p"],
			repetition_penalty=CFG["repetition_penalty"],
			no_repeat_ngram_size=CFG["no_repeat_ngram_size"],
			max_chars=CFG["max_chars"],
			cfg=CFG,
		)
		print("\n")

		if not reply:
			reply = "(sem resposta; tente reduzir temperature ou aumentar max-new-tokens)"

		history.append(("assistant", reply))


if __name__ == "__main__":
	main()

