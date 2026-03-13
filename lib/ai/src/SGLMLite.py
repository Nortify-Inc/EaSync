import math
import torch
import torch.nn as nn
import torch.nn.functional as F
from dataclasses import dataclass


@dataclass
class ModelArgs:
    vocab_size:  int   = 151936
    n_layer:     int   = 16
    n_embd:      int   = 512
    n_heads:     int   = 8
    n_kv_heads:  int   = 2
    ffn_hidden:  int   = 1536
    rms_eps:     float = 1e-6
    rope_base:   float = 1_000_000.0

    @property
    def head_dim(self) -> int:
        return self.n_embd // self.n_heads

class RMSNorm(nn.Module):
    def __init__(self, dim: int, eps: float = 1e-6):
        super().__init__()
        self.eps = eps
        self.weight = nn.Parameter(torch.ones(dim))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.eps)
        return self.weight * x


def _rotate_half(x: torch.Tensor) -> torch.Tensor:
    h = x.shape[-1] // 2
    return torch.cat([-x[..., h:], x[..., :h]], dim=-1)


def build_rope(head_dim: int, seq_len: int, base: float, device, dtype):
    inv_freq = 1.0 / (
        base ** (torch.arange(0, head_dim, 2, dtype=torch.float32, device=device) / head_dim)
    )

    t = torch.arange(seq_len, dtype=torch.float32, device=device)
    freqs = torch.outer(t, inv_freq)
    emb = torch.cat([freqs, freqs], dim=-1)

    return emb.cos().to(dtype), emb.sin().to(dtype)

class Attention(nn.Module):
    def __init__(self, args: ModelArgs):
        super().__init__()
        self.n_heads    = args.n_heads
        self.n_kv_heads = args.n_kv_heads

        self.head_dim   = args.head_dim
        self.scale      = self.head_dim ** -0.5

        self.rope_base  = args.rope_base

        self.q_proj = nn.Linear(args.n_embd, args.n_heads    * args.head_dim, bias=True)
        self.k_proj = nn.Linear(args.n_embd, args.n_kv_heads * args.head_dim, bias=True)
        self.v_proj = nn.Linear(args.n_embd, args.n_kv_heads * args.head_dim, bias=True)
        self.o_proj = nn.Linear(args.n_heads * args.head_dim, args.n_embd,    bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        B, T, _ = x.shape

        q = self.q_proj(x).view(B, T, self.n_heads,    self.head_dim).transpose(1, 2)
        k = self.k_proj(x).view(B, T, self.n_kv_heads, self.head_dim).transpose(1, 2)
        v = self.v_proj(x).view(B, T, self.n_kv_heads, self.head_dim).transpose(1, 2)

        cos, sin = build_rope(self.head_dim, T, self.rope_base, x.device, x.dtype)
        cos = cos.unsqueeze(0)
        sin = sin.unsqueeze(0)

        q = q * cos + _rotate_half(q) * sin
        k = k * cos + _rotate_half(k) * sin

        if self.n_heads > self.n_kv_heads:
            rep = self.n_heads // self.n_kv_heads
            k = k.repeat_interleave(rep, dim=1)
            v = v.repeat_interleave(rep, dim=1)

        attn = torch.matmul(q, k.transpose(-2, -1)) * self.scale
        mask = torch.full((T, T), float("-inf"), device=x.device, dtype=x.dtype).triu(1)
        attn = attn + mask
        attn = F.softmax(attn, dim=-1)

        out = torch.matmul(attn, v)
        out = out.transpose(1, 2).contiguous().view(B, T, -1)
        return self.o_proj(out)

class FeedForward(nn.Module):
    def __init__(self, args: ModelArgs):
        super().__init__()
        self.gate_proj = nn.Linear(args.n_embd, args.ffn_hidden, bias=False)
        self.up_proj   = nn.Linear(args.n_embd, args.ffn_hidden, bias=False)
        self.down_proj = nn.Linear(args.ffn_hidden, args.n_embd, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.down_proj(F.silu(self.gate_proj(x)) * self.up_proj(x))

class Block(nn.Module):
    def __init__(self, args: ModelArgs):
        super().__init__()
        self.input_layernorm          = RMSNorm(args.n_embd, args.rms_eps)
        self.self_attn                = Attention(args)
        self.post_attention_layernorm = RMSNorm(args.n_embd, args.rms_eps)
        self.mlp                      = FeedForward(args)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x + self.self_attn(self.input_layernorm(x))
        x = x + self.mlp(self.post_attention_layernorm(x))
        return x

class SGLMLite(nn.Module):
    def __init__(self, args: ModelArgs = None):
        super().__init__()
        if args is None:
            args = ModelArgs()

        self.args = args

        self.embed_tokens = nn.Embedding(args.vocab_size, args.n_embd)
        self.layers       = nn.ModuleList([Block(args) for _ in range(args.n_layer)])
        self.norm         = RMSNorm(args.n_embd, args.rms_eps)
        self.lm_head      = nn.Linear(args.n_embd, args.vocab_size, bias=False)

        self.lm_head.weight = self.embed_tokens.weight

        self._init_weights()

    def _init_weights(self):
        std = 0.02
        for name, p in self.named_parameters():
            if p.dim() < 2:
                continue

            if "embed" in name or "lm_head" in name:
                nn.init.normal_(p, mean=0.0, std=std)

            elif "weight" in name:
                nn.init.normal_(p, mean=0.0, std=std / math.sqrt(2 * self.args.n_layer))

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        x = self.embed_tokens(input_ids)

        for layer in self.layers:
            x = layer(x)

        x = self.norm(x)

        return self.lm_head(x)

    def num_params(self) -> int:
        seen = set()
        total = 0

        for p in self.parameters():
            if id(p) not in seen:
                seen.add(id(p))

                total += p.numel()

        return total


if __name__ == "__main__":
    args = ModelArgs()
    m = SGLMLite(args)

    print(f"Parâmetros totais: {m.num_params() / 1e6:.1f}M")

    ids = torch.randint(0, 100, (2, 32))
    out = m(ids)

    print(f"Output shape: {out.shape}")