import torch
import torch.nn as nn
import torch.nn.functional as F
import math

class RMSNorm(nn.Module):
    def __init__(self, dim, eps=1e-8):
        super().__init__()
        self.eps = eps
        self.weight = nn.Parameter(torch.ones(dim))

    def forward(self, x):
        norm = x.pow(2).mean(-1, keepdim=True)
        x = x * torch.rsqrt(norm + self.eps)
        return self.weight * x


class RoPE(nn.Module):
    def __init__(self, dim):
        super().__init__()
        invFreq = 1.0 / (10000 ** (torch.arange(0, dim, 2).float() / dim))
        self.register_buffer("invFreq", invFreq)

    def forward(self, seqLen, device):
        t = torch.arange(seqLen, device=device).float()
        freqs = torch.einsum("i,j->ij", t, self.invFreq)
        emb = torch.cat((freqs, freqs), dim=-1)
        return emb.cos()[None, None, :, :], emb.sin()[None, None, :, :]


def applyRoPE(x, cos, sin):
    x1, x2 = x[..., ::2], x[..., 1::2]
    x = torch.stack((-x2, x1), dim=-1).reshape_as(x)
    return (x * sin) + (x * cos)


class GroupedQueryAttention(nn.Module):
    def __init__(self, dim, nHeads=4, kvHeads=2):
        super().__init__()
        self.nHeads = nHeads
        self.kvHeads = kvHeads
        self.headDim = dim // nHeads

        self.q = nn.Linear(dim, dim, bias=False)
        self.k = nn.Linear(dim, kvHeads * self.headDim, bias=False)
        self.v = nn.Linear(dim, kvHeads * self.headDim, bias=False)

        self.out = nn.Linear(dim, dim)

    def forward(self, x, cos, sin, mask=None):
        B, T, C = x.shape

        q = self.q(x).view(B, T, self.nHeads, self.headDim).transpose(1, 2)
        k = self.k(x).view(B, T, self.kvHeads, self.headDim).transpose(1, 2)
        v = self.v(x).view(B, T, self.kvHeads, self.headDim).transpose(1, 2)

        q = applyRoPE(q, cos, sin)
        k = applyRoPE(k, cos, sin)

        repeat = self.nHeads // self.kvHeads
        k = k.repeat_interleave(repeat, dim=1)
        v = v.repeat_interleave(repeat, dim=1)

        attn = (q @ k.transpose(-2, -1)) / math.sqrt(self.headDim)

        if mask is not None:
            attn = attn.masked_fill(mask == 0, -1e9)

        probs = F.softmax(attn, dim=-1)
        out = probs @ v

        out = out.transpose(1, 2).contiguous().view(B, T, C)
        return self.out(out)


class SwiGLU(nn.Module):
    def __init__(self, dim, hidden):
        super().__init__()
        self.w1 = nn.Linear(dim, hidden)
        self.w2 = nn.Linear(dim, hidden)
        self.w3 = nn.Linear(hidden, dim)

    def forward(self, x):
        return self.w3(F.silu(self.w1(x)) * self.w2(x))


class DualGatedDepthwiseConv(nn.Module):
    def __init__(self, dim, kernel=3):
        super().__init__()
        self.dw = nn.Conv1d(dim, dim, kernel, padding=kernel-1, groups=dim)
        self.gate1 = nn.Linear(dim, dim)
        self.gate2 = nn.Linear(dim, dim)

    def forward(self, x):
        xc = x.transpose(1,2)
        c = self.dw(xc)[:, :, :x.size(1)]
        c = c.transpose(1,2)

        g1 = torch.sigmoid(self.gate1(x))
        g2 = torch.sigmoid(self.gate2(x))

        return x + c * g1 * g2


class SGLMBlock(nn.Module):
    def __init__(self, dim, heads, kvHeads, hidden):
        super().__init__()
        self.norm1 = RMSNorm(dim)
        self.attn = GroupedQueryAttention(dim, heads, kvHeads)

        self.norm2 = RMSNorm(dim)
        self.conv = DualGatedDepthwiseConv(dim)

        self.norm3 = RMSNorm(dim)
        self.ff = SwiGLU(dim, hidden)

    def forward(self, x, cos, sin, mask):
        x = x + self.attn(self.norm1(x), cos, sin, mask)
        x = self.conv(self.norm2(x))
        x = x + self.ff(self.norm3(x))
        return x


class SGLM(nn.Module):
    def __init__(
        self,
        vocabSize,
        dim=256,
        layers=6,
        heads=4,
        kvHeads=2,
        hidden=1024,
        maxSeq=128
    ):
        super().__init__()

        self.tokenEmb = nn.Embedding(vocabSize, dim)
        self.rope = RoPE(dim // heads)

        self.layers = nn.ModuleList([
            SGLMBlock(dim, heads, kvHeads, hidden)
            for _ in range(layers)
        ])

        self.norm = RMSNorm(dim)
        self.head = nn.Linear(dim, vocabSize, bias=False)

        self.head.weight = self.tokenEmb.weight

        self.maxSeq = maxSeq

    def causalMask(self, T, device):
        mask = torch.tril(torch.ones(T, T, device=device))
        return mask[None, None, :, :]

    def forward(self, x):
        B, T = x.shape
        device = x.device

        h = self.tokenEmb(x)

        cos, sin = self.rope(T, device)

        mask = self.causalMask(T, device)

        for layer in self.layers:
            h = layer(h, cos, sin, mask)

        h = self.norm(h)

        logits = self.head(h)

        return logits


class Generator:
    def __init__(self, model, device=None):
        self.model = model
        self.device = device or next(model.parameters()).device
        self.model.eval()

    @torch.no_grad()
    def generate(
        self,
        seed,
        maxLen=50,
        temperature=0.8,
        topK=40,
        topP=0.9
    ):

        if isinstance(seed, list):
            seq = torch.tensor(seed, dtype=torch.long).unsqueeze(0).to(self.device)
        else:
            seq = seed.unsqueeze(0).to(self.device)

        for _ in range(maxLen):

            seq = seq[:, -128:]

            logits = self.model(seq)
            logits = logits[:, -1] / temperature

            probs = F.softmax(logits, dim=-1)

            if topK:
                v, i = torch.topk(probs, topK)
                mask = torch.zeros_like(probs)
                mask.scatter_(1, i, v)
                probs = mask

            if topP < 1.0:
                sorted_probs, sorted_idx = torch.sort(probs, descending=True)
                cumulative = torch.cumsum(sorted_probs, dim=-1)
                cutoff = cumulative > topP
                sorted_probs[cutoff] = 0
                probs = torch.zeros_like(probs).scatter(1, sorted_idx, sorted_probs)

            probs = probs / probs.sum(dim=-1, keepdim=True)

            nextToken = torch.multinomial(probs, 1)

            seq = torch.cat([seq, nextToken], dim=1)

        return seq.squeeze(0)