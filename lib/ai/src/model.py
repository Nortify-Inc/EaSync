from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import torch
import torch.nn.functional as F
from safetensors.torch import load_file


@dataclass
class AgentConfig:
	vocab_size: int
	hidden_size: int
	intermediate_size: int
	num_hidden_layers: int
	num_attention_heads: int
	num_key_value_heads: int
	max_position_embeddings: int
	rms_norm_eps: float
	rope_theta: float
	tie_word_embeddings: bool = True
	bos_token_id: int = 0
	eos_token_id: int = 0

	@property
	def head_dim(self) -> int:
		return self.hidden_size // self.num_attention_heads

	@classmethod
	def from_json_file(cls, config_path: Path) -> "AgentConfig":
		data = json.loads(config_path.read_text(encoding="utf-8"))
		return cls(
			vocab_size=int(data["vocab_size"]),
			hidden_size=int(data["hidden_size"]),
			intermediate_size=int(data["intermediate_size"]),
			num_hidden_layers=int(data["num_hidden_layers"]),
			num_attention_heads=int(data["num_attention_heads"]),
			num_key_value_heads=int(data["num_key_value_heads"]),
			max_position_embeddings=int(data["max_position_embeddings"]),
			rms_norm_eps=float(data["rms_norm_eps"]),
			rope_theta=float(data.get("rope_theta", 10000.0)),
			tie_word_embeddings=bool(data.get("tie_word_embeddings", True)),
			bos_token_id=int(data.get("bos_token_id", 0)),
			eos_token_id=int(data.get("eos_token_id", 0)),
		)


def _rms_norm(x: torch.Tensor, weight: torch.Tensor, eps: float) -> torch.Tensor:
	return (x * torch.rsqrt(x.pow(2).mean(dim=-1, keepdim=True) + eps)) * weight


def _rotate_half(x: torch.Tensor) -> torch.Tensor:
	half = x.shape[-1] // 2
	return torch.cat([-x[..., half:], x[..., :half]], dim=-1)


def _build_rope(head_dim: int, seq_len: int, base: float, device: torch.device, dtype: torch.dtype) -> Tuple[torch.Tensor, torch.Tensor]:
	inv_freq = 1.0 / (base ** (torch.arange(0, head_dim, 2, dtype=torch.float32, device=device) / head_dim))
	positions = torch.arange(seq_len, dtype=torch.float32, device=device)
	freqs = torch.outer(positions, inv_freq)
	emb = torch.cat([freqs, freqs], dim=-1)
	return emb.cos().to(dtype=dtype), emb.sin().to(dtype=dtype)


class AgentLM:
	def __init__(self, state_dict: Dict[str, torch.Tensor], config: AgentConfig, device: str = "cpu") -> None:
		self.config = config
		self.device = torch.device(device)
		self.state_dict = {k: v.to(self.device) for k, v in state_dict.items()}

	@classmethod
	def load(cls, model_path: str | Path, device: str = "cpu", dtype: torch.dtype = torch.float32) -> "AgentLM":
		path = Path(model_path)
		if path.is_dir():
			config_path = path / "config.json"
			safetensors_path = path / "model.safetensors"
		else:
			safetensors_path = path
			config_path = path.with_name("config.json")

		if not safetensors_path.exists():
			raise FileNotFoundError(f"model.safetensors not found: {safetensors_path}")
		if not config_path.exists():
			raise FileNotFoundError(f"config.json not found: {config_path}")

		config = AgentConfig.from_json_file(config_path)
		state_dict = load_file(str(safetensors_path), device="cpu")
		state_dict = {k: v.to(dtype=dtype) for k, v in state_dict.items()}

		return cls(state_dict=state_dict, config=config, device=device)

	def _linear(self, x: torch.Tensor, prefix: str) -> torch.Tensor:
		weight = self.state_dict[f"{prefix}.weight"]
		bias_name = f"{prefix}.bias"
		out = x @ weight.T
		if bias_name in self.state_dict:
			out = out + self.state_dict[bias_name]
		return out

	def _attn(
		self,
		hidden: torch.Tensor,
		layer_idx: int,
		cos: torch.Tensor,
		sin: torch.Tensor,
		mask: Optional[torch.Tensor],
		kv_cache: Optional[Tuple[torch.Tensor, torch.Tensor]],
	) -> Tuple[torch.Tensor, Tuple[torch.Tensor, torch.Tensor]]:
		cfg = self.config
		t = hidden.shape[0]
		prefix = f"model.layers.{layer_idx}.self_attn"

		q = self._linear(hidden, f"{prefix}.q_proj")
		k = self._linear(hidden, f"{prefix}.k_proj")
		v = self._linear(hidden, f"{prefix}.v_proj")

		q = q.view(t, cfg.num_attention_heads, cfg.head_dim).transpose(0, 1)
		k = k.view(t, cfg.num_key_value_heads, cfg.head_dim).transpose(0, 1)
		v = v.view(t, cfg.num_key_value_heads, cfg.head_dim).transpose(0, 1)

		cos_u = cos.unsqueeze(0)
		sin_u = sin.unsqueeze(0)
		q = q * cos_u + _rotate_half(q) * sin_u
		k = k * cos_u + _rotate_half(k) * sin_u

		if kv_cache is not None:
			k = torch.cat([kv_cache[0], k], dim=1)
			v = torch.cat([kv_cache[1], v], dim=1)
		new_cache = (k, v)

		if cfg.num_attention_heads > cfg.num_key_value_heads:
			repeats = cfg.num_attention_heads // cfg.num_key_value_heads
			k_attn = k.repeat_interleave(repeats, dim=0)
			v_attn = v.repeat_interleave(repeats, dim=0)
		else:
			k_attn = k
			v_attn = v

		scores = (q @ k_attn.transpose(-2, -1)) * (cfg.head_dim ** -0.5)
		if mask is not None:
			scores = scores + mask

		probs = F.softmax(scores, dim=-1)
		out = (probs @ v_attn).transpose(0, 1).contiguous().view(t, cfg.hidden_size)
		out = self._linear(out, f"{prefix}.o_proj")
		return out, new_cache

	def _mlp(self, hidden: torch.Tensor, layer_idx: int) -> torch.Tensor:
		prefix = f"model.layers.{layer_idx}.mlp"
		gate = F.silu(self._linear(hidden, f"{prefix}.gate_proj"))
		up = self._linear(hidden, f"{prefix}.up_proj")
		return self._linear(gate * up, f"{prefix}.down_proj")

	def forward(
		self,
		input_ids: torch.Tensor,
		kv_caches: Optional[List[Tuple[torch.Tensor, torch.Tensor]]] = None,
		offset: int = 0,
	) -> Dict[str, Any]:
		cfg = self.config
		sd = self.state_dict

		if input_ids.ndim != 2 or input_ids.shape[0] != 1:
			raise ValueError("input_ids must have shape [1, seq_len]")

		seq_len = input_ids.shape[1]
		hidden = sd["model.embed_tokens.weight"][input_ids[0]]

		cos, sin = _build_rope(
			head_dim=cfg.head_dim,
			seq_len=offset + seq_len,
			base=cfg.rope_theta,
			device=hidden.device,
			dtype=hidden.dtype,
		)
		cos = cos[offset:]
		sin = sin[offset:]

		mask = None
		if seq_len > 1:
			mask = torch.full((seq_len, seq_len), float("-inf"), device=hidden.device, dtype=hidden.dtype).triu(1)

		next_kv_caches: List[Tuple[torch.Tensor, torch.Tensor]] = []

		for i in range(cfg.num_hidden_layers):
			layer_prefix = f"model.layers.{i}"
			x_norm = _rms_norm(hidden, sd[f"{layer_prefix}.input_layernorm.weight"], cfg.rms_norm_eps)

			layer_cache = kv_caches[i] if kv_caches is not None else None
			attn_out, new_cache = self._attn(
				hidden=x_norm,
				layer_idx=i,
				cos=cos,
				sin=sin,
				mask=mask,
				kv_cache=layer_cache,
			)
			hidden = hidden + attn_out

			x_norm = _rms_norm(hidden, sd[f"{layer_prefix}.post_attention_layernorm.weight"], cfg.rms_norm_eps)
			hidden = hidden + self._mlp(x_norm, i)
			next_kv_caches.append(new_cache)

		hidden = _rms_norm(hidden, sd["model.norm.weight"], cfg.rms_norm_eps)
		if "lm_head.weight" in sd:
			logits = hidden @ sd["lm_head.weight"].T
		else:
			logits = hidden @ sd["model.embed_tokens.weight"].T

		return {"logits": logits.unsqueeze(0), "kv_caches": next_kv_caches}

	def __call__(self, *args: Any, **kwargs: Any) -> Dict[str, Any]:
		return self.forward(*args, **kwargs)

	@torch.no_grad()
	def generate(
		self,
		prompt_ids: torch.Tensor,
		max_new_tokens: int = 128,
		temperature: float = 0.8,
		top_k: int = 50,
		top_p: float = 0.95,
		eos_token_id: Optional[int] = None,
		stop_token_ids: Optional[List[int]] = None,
		repetition_penalty: float = 1.1,
		no_repeat_ngram_size: int = 3,
	) -> torch.Tensor:
		if temperature < 0:
			raise ValueError("temperature must be >= 0")
		if repetition_penalty < 1.0:
			raise ValueError("repetition_penalty must be >= 1.0")
		if no_repeat_ngram_size < 0:
			raise ValueError("no_repeat_ngram_size must be >= 0")

		eos_id = self.config.eos_token_id if eos_token_id is None else eos_token_id
		stop_ids = set(stop_token_ids or [])
		stop_ids.add(eos_id)
		output = self.forward(prompt_ids)
		logits = output["logits"]
		kv_caches = output["kv_caches"]
		offset = prompt_ids.shape[1]

		generated: List[int] = []
		seen_ids = set(int(x) for x in prompt_ids[0].tolist())
		all_token_ids = [int(x) for x in prompt_ids[0].tolist()]
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
				sorted_probs = F.softmax(sorted_logits, dim=-1)
				cumulative_probs = torch.cumsum(sorted_probs, dim=-1)
				to_remove = cumulative_probs > top_p
				to_remove[..., 1:] = to_remove[..., :-1].clone()
				to_remove[..., 0] = False
				sorted_logits[to_remove] = float("-inf")
				next_logits = torch.scatter(next_logits, dim=0, index=sorted_indices, src=sorted_logits)

			if temperature == 0:
				next_token_id = int(torch.argmax(next_logits).item())
			else:
				probs = F.softmax(next_logits, dim=-1)
				next_token_id = torch.multinomial(probs, num_samples=1).item()

			if next_token_id in stop_ids:
				break

			generated.append(next_token_id)
			seen_ids.add(next_token_id)
			all_token_ids.append(next_token_id)
			next_input = torch.tensor([[next_token_id]], device=self.device, dtype=torch.long)
			output = self.forward(next_input, kv_caches=kv_caches, offset=offset)
			logits = output["logits"]
			kv_caches = output["kv_caches"]
			offset += 1

		return torch.tensor([generated], device=self.device, dtype=torch.long)

	@torch.no_grad()
	def generate_mirostat(
		self,
		prompt_ids: torch.Tensor,
		max_new_tokens: int = 128,
		tau: float = 5.0,
		eta: float = 0.1,
		eos_token_id: Optional[int] = None,
		stop_token_ids: Optional[List[int]] = None,
		repetition_penalty: float = 1.1,
		no_repeat_ngram_size: int = 3,
		min_temp: float = 0.2,
		max_temp: float = 1.5,
	) -> torch.Tensor:
		if tau <= 0:
			raise ValueError("tau must be > 0")
		if eta <= 0:
			raise ValueError("eta must be > 0")
		if repetition_penalty < 1.0:
			raise ValueError("repetition_penalty must be >= 1.0")

		eos_id = self.config.eos_token_id if eos_token_id is None else eos_token_id
		stop_ids = set(stop_token_ids or [])
		stop_ids.add(eos_id)

		output = self.forward(prompt_ids)
		logits = output["logits"]
		kv_caches = output["kv_caches"]
		offset = prompt_ids.shape[1]

		generated: List[int] = []
		seen_ids = set(int(x) for x in prompt_ids[0].tolist())
		all_token_ids = [int(x) for x in prompt_ids[0].tolist()]
		mu = 2.0 * tau

		for _ in range(max_new_tokens):
			next_logits = logits[0, -1, :]

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

			# Adaptive temperature from current target surprisal estimate.
			temp = max(min_temp, min(max_temp, mu / tau))
			log_probs = torch.log_softmax(next_logits / temp, dim=-1)
			probs = torch.exp(log_probs)

			next_token_id = int(torch.multinomial(probs, num_samples=1).item())
			if next_token_id in stop_ids:
				break

			surprise = -float(log_probs[next_token_id].item()) / math.log(2.0)
			mu = mu - eta * (surprise - tau)

			generated.append(next_token_id)
			seen_ids.add(next_token_id)
			all_token_ids.append(next_token_id)

			next_input = torch.tensor([[next_token_id]], device=self.device, dtype=torch.long)
			output = self.forward(next_input, kv_caches=kv_caches, offset=offset)
			logits = output["logits"]
			kv_caches = output["kv_caches"]
			offset += 1

		return torch.tensor([generated], device=self.device, dtype=torch.long)


def default_model_dir() -> Path:
	return Path(__file__).resolve().parent.parent / "data"

