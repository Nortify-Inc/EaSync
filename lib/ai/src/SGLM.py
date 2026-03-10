import torch
import torch.nn.functional as F
from dataclasses import dataclass
from typing import Optional, Tuple, List
from pathlib import Path


@dataclass
class ModelArgs:
    vocab_size:  int   = 151936
    n_layer:     int   = 24
    n_embd:      int   = 896
    n_heads:     int   = 14
    n_kv_heads:  int   = 2
    ffn_hidden:  int   = 4864
    rms_eps:     float = 1e-6
    rope_base:   float = 1_000_000.0

    @property
    def head_dim(self) -> int:
        return self.n_embd // self.n_heads


def _rms_norm(x: torch.Tensor, w: torch.Tensor, eps: float) -> torch.Tensor:
    return (x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + eps)) * w


def _rotate_half(x: torch.Tensor) -> torch.Tensor:
    h = x.shape[-1] // 2
    return torch.cat([-x[..., h:], x[..., :h]], dim=-1)


def _build_rope(head_dim: int, T: int, base: float, device, dtype):
    inv_freq = 1.0 / (base ** (torch.arange(0, head_dim, 2, dtype=torch.float32, device=device) / head_dim))
    t        = torch.arange(T, dtype=torch.float32, device=device)
    freqs    = torch.outer(t, inv_freq)
    emb      = torch.cat([freqs, freqs], dim=-1)
    return emb.cos().to(dtype), emb.sin().to(dtype)


class SGLM:
    def __init__(self, sd: dict, args: ModelArgs, device: str = "cpu"):
        self.sd     = {k: v.to(device) for k, v in sd.items()}
        self.args   = args
        self.device = device

    def _attn(
        self,
        x:        torch.Tensor,
        cos:      torch.Tensor,
        sin:      torch.Tensor,
        layer:    int,
        mask:     Optional[torch.Tensor],
        kv_cache: Optional[Tuple],

    ) -> Tuple[torch.Tensor, Tuple]:
        p  = f"model.layers.{layer}.self_attn"
        sd = self.sd
        a  = self.args
        T  = x.shape[0]

        q = x @ sd[f"{p}.q_proj.weight"].T + sd[f"{p}.q_proj.bias"]
        k = x @ sd[f"{p}.k_proj.weight"].T + sd[f"{p}.k_proj.bias"]
        v = x @ sd[f"{p}.v_proj.weight"].T + sd[f"{p}.v_proj.bias"]

        q = q.view(T, a.n_heads,    a.head_dim).transpose(0, 1)
        k = k.view(T, a.n_kv_heads, a.head_dim).transpose(0, 1)
        v = v.view(T, a.n_kv_heads, a.head_dim).transpose(0, 1)

        c = cos.unsqueeze(0); s = sin.unsqueeze(0)
        q = q * c + _rotate_half(q) * s
        k = k * c + _rotate_half(k) * s

        if kv_cache is not None:
            k = torch.cat([kv_cache[0], k], dim=1)
            v = torch.cat([kv_cache[1], v], dim=1)
        new_cache = (k, v)

        if a.n_heads > a.n_kv_heads:
            k = k.repeat_interleave(a.n_heads // a.n_kv_heads, dim=0)
            v = v.repeat_interleave(a.n_heads // a.n_kv_heads, dim=0)

        attn = torch.matmul(q, k.transpose(-2, -1)) * (a.head_dim ** -0.5)

        if mask is not None:
            attn = attn + mask

        attn = F.softmax(attn, dim=-1)

        out = torch.matmul(attn, v).transpose(0, 1).contiguous().view(T, -1)
        return out @ sd[f"{p}.o_proj.weight"].T, new_cache

    def _ffn(self, x: torch.Tensor, layer: int) -> torch.Tensor:
        p  = f"model.layers.{layer}.mlp"
        sd = self.sd

        g  = F.silu(x @ sd[f"{p}.gate_proj.weight"].T)
        u  = x @ sd[f"{p}.up_proj.weight"].T

        return (g * u) @ sd[f"{p}.down_proj.weight"].T

    def forward(
        self,
        token_ids: torch.Tensor,
        kv_caches: Optional[List] = None,
        offset:    int = 0,

    ) -> dict:
        a  = self.args
        sd = self.sd
        T  = token_ids.shape[1]

        x = sd["model.embed_tokens.weight"][token_ids[0]]

        cos, sin = _build_rope(a.head_dim, offset + T, a.rope_base, x.device, x.dtype)
        cos = cos[offset:]
        sin = sin[offset:]

        mask = None
        if T > 1:
            mask = torch.full((T, T), float("-inf"), device=x.device, dtype=x.dtype).triu(1)

        new_caches = []

        for i in range(a.n_layer):
            p   = f"model.layers.{i}"
            xn  = _rms_norm(x, sd[f"{p}.input_layernorm.weight"], a.rms_eps)

            cache = kv_caches[i] if kv_caches else None
            attn_out, new_cache = self._attn(xn, cos, sin, i, mask, cache)

            x  = x + attn_out
            xn = _rms_norm(x, sd[f"{p}.post_attention_layernorm.weight"], a.rms_eps)

            x  = x + self._ffn(xn, i)
            new_caches.append(new_cache)

        x = _rms_norm(x, sd["model.norm.weight"], a.rms_eps)
        logits = (x @ sd["model.embed_tokens.weight"].T).unsqueeze(0)

        return {"logits": logits, "kv_caches": new_caches}

    def __call__(self, *args, **kwargs):
        return self.forward(*args, **kwargs)

    @classmethod
    def load(cls, path: str, device: str = "cpu") -> "SGLM":
        from safetensors.torch import load_file

        p = Path(path)

        sf_file = (p / "model.safetensors") if p.is_dir() else p
        
        if not sf_file.exists():
            raise FileNotFoundError(sf_file)

        sd = load_file(str(sf_file), device="cpu")
        sd  = {k: v.float() for k, v in sd.items()}
        args = _infer_args(sd)

        return cls(sd, args, device)


    @torch.no_grad()
    def generate(
        self,
        prompt:         torch.Tensor,
        max_new_tokens: int   = 256,
        temperature:    float = 0.7,
        top_k:          int   = 40,
        top_p:          float = 0.9,

    ) -> torch.Tensor:
        out       = self.forward(prompt)
        logits    = out["logits"]
        kv_caches = out["kv_caches"]
        offset    = prompt.shape[1]
        generated = []

        for _ in range(max_new_tokens):
            next_logits = logits[0, -1, :] / temperature

            if top_k:
                v, _ = torch.topk(next_logits, top_k)
                next_logits[next_logits < v[-1]] = float("-inf")

            if top_p < 1.0:
                sl, si = torch.sort(next_logits, descending=True)
                cp     = torch.cumsum(F.softmax(sl, dim=-1), dim=-1)

                sl[cp - F.softmax(sl, dim=-1) > top_p] = float("-inf")
                next_logits = torch.scatter(next_logits, 0, si, sl)

            token_id = torch.multinomial(F.softmax(next_logits, dim=-1), 1).item()

            if token_id in (151643, 151645):
                break

            generated.append(token_id)
            nxt = torch.tensor([[token_id]], device=prompt.device)
            out = self.forward(nxt, kv_caches=kv_caches, offset=offset)

            logits = out["logits"]
            kv_caches = out["kv_caches"]
            offset += 1

        return torch.tensor([generated], device=prompt.device)

def _infer_args(sd: dict) -> ModelArgs:
    indices = { 
        int(k.split(".")[2]) 
        for k in sd 
        if k.startswith("model.layers.")
    }

    emb = sd["model.embed_tokens.weight"]
    q_w = sd["model.layers.0.self_attn.q_proj.weight"]
    k_w = sd["model.layers.0.self_attn.k_proj.weight"]
    ffn_hidden = sd["model.layers.0.mlp.gate_proj.weight"].shape[0]

    n_embd = emb.shape[1]
    vocab_size = emb.shape[0]
    n_layer = max(indices) + 1
    q_out, k_out = q_w.shape[0], k_w.shape[0]
    head_dim = 64

    for hd in [64, 128, 32, 256]:
        n_h = q_out // hd

        if q_out % hd == 0 and k_out % hd == 0 and n_embd // n_h == hd:
            head_dim = hd
            break

    return ModelArgs(
        vocab_size=vocab_size, n_layer=n_layer, n_embd=n_embd,
        n_heads=q_out // head_dim, n_kv_heads=k_out // head_dim,
        ffn_hidden=ffn_hidden,
    )