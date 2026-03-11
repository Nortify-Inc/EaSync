import argparse
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

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


def _rotate_half(x):
    h = x.shape[-1] // 2
    return torch.cat([-x[..., h:], x[..., :h]], dim=-1)


def _rope(head_dim, T, base, device, dtype):
    inv = 1.0 / (base ** (
        torch.arange(0, head_dim, 2, dtype=torch.float32, device=device) / head_dim))
    t     = torch.arange(T, dtype=torch.float32, device=device)
    freqs = torch.outer(t, inv)
    emb   = torch.cat([freqs, freqs], dim=-1)
    return emb.cos().to(dtype), emb.sin().to(dtype)


def _rms_norm(x, w, eps):
    return x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + eps) * w


class SGLMTrace(nn.Module):

    def __init__(self, sd: dict, args: ModelArgs):
        super().__init__()
        self.args = args

        for k, v in sd.items():
            self.register_buffer(k.replace(".", "__DOT__"), v)

    def _b(self, key: str) -> torch.Tensor:
        return getattr(self, key.replace(".", "__DOT__"))

    def forward(self, token_ids: torch.Tensor) -> torch.Tensor:
        a = self.args
        T = token_ids.shape[1]

        x = self._b("model.embed_tokens.weight")[token_ids[0]]

        cos, sin = _rope(a.head_dim, T, a.rope_base, x.device, x.dtype)

        mask = torch.full((T, T), float("-inf"), device=x.device, dtype=x.dtype).triu(1)

        for i in range(a.n_layer):
            lp = f"model.layers.{i}"
            xn = _rms_norm(x, self._b(f"{lp}.input_layernorm.weight"), a.rms_eps)

            x  = x + self._attn(xn, cos, sin, i, mask)
            xn = _rms_norm(x, self._b(f"{lp}.post_attention_layernorm.weight"), a.rms_eps)

            x  = x + self._ffn(xn, i)

        x = _rms_norm(x, self._b("model.norm.weight"), a.rms_eps)

        return (x @ self._b("model.embed_tokens.weight").T).unsqueeze(0)

    def _attn(self, x, cos, sin, i, mask):
        a = self.args; p = f"model.layers.{i}.self_attn"; T = x.shape[0]

        q = x @ self._b(f"{p}.q_proj.weight").T + self._b(f"{p}.q_proj.bias")
        k = x @ self._b(f"{p}.k_proj.weight").T + self._b(f"{p}.k_proj.bias")
        v = x @ self._b(f"{p}.v_proj.weight").T + self._b(f"{p}.v_proj.bias")

        q = q.view(T, a.n_heads,    a.head_dim).transpose(0, 1)
        k = k.view(T, a.n_kv_heads, a.head_dim).transpose(0, 1)
        v = v.view(T, a.n_kv_heads, a.head_dim).transpose(0, 1)

        c = cos.unsqueeze(0); s = sin.unsqueeze(0)

        q = q * c + _rotate_half(q) * s
        k = k * c + _rotate_half(k) * s

        if a.n_heads > a.n_kv_heads:
            r = a.n_heads // a.n_kv_heads
            k = k.repeat_interleave(r, 0); v = v.repeat_interleave(r, 0)

        attn = torch.matmul(q, k.transpose(-2, -1)) * (a.head_dim ** -0.5) + mask
        attn = F.softmax(attn, dim=-1)
        out  = torch.matmul(attn, v).transpose(0, 1).contiguous().view(T, -1)
        return out @ self._b(f"{p}.o_proj.weight").T

    def _ffn(self, x, i):
        p = f"model.layers.{i}.mlp"
        g = F.silu(x @ self._b(f"{p}.gate_proj.weight").T)
        u = x @ self._b(f"{p}.up_proj.weight").T
        return (g * u) @ self._b(f"{p}.down_proj.weight").T

def infer_args(sd: dict) -> ModelArgs:
    indices  = {int(k.split(".")[2]) for k in sd if k.startswith("model.layers.")}
    emb      = sd["model.embed_tokens.weight"]
    q_w      = sd["model.layers.0.self_attn.q_proj.weight"]
    k_w      = sd["model.layers.0.self_attn.k_proj.weight"]
    ffn_hid  = sd["model.layers.0.mlp.gate_proj.weight"].shape[0]
    n_embd   = emb.shape[1]; vocab = emb.shape[0]; n_layer = max(indices) + 1
    q_out    = q_w.shape[0]; k_out = k_w.shape[0]
    hd = 64
    for h in [64, 128, 32, 256]:
        nh = q_out // h
        if q_out % h == 0 and k_out % h == 0 and n_embd // nh == h:
            hd = h; break
    return ModelArgs(vocab_size=vocab, n_layer=n_layer, n_embd=n_embd,
                     n_heads=q_out // hd, n_kv_heads=k_out // hd, ffn_hidden=ffn_hid)

def load_sf(path: Path) -> dict:
    try:
        from safetensors.torch import load_file
    except ImportError:
        sys.exit("[ERRO] Execute: pip install safetensors")
    sf = (path / "model.safetensors") if path.is_dir() else path
    if not sf.exists():
        sys.exit(f"[ERRO] Não encontrado: {sf}")
    print(f"[INFO] Carregando {sf} …")
    sd = {k: v.float() for k, v in load_file(str(sf), device="cpu").items()}
    print(f"[INFO] {len(sd)} tensors carregados.")
    return sd

def do_export(sd: dict, args: ModelArgs, out: Path, dtype: torch.dtype, opset: int):
    module = SGLMTrace(sd, args)
    module.eval()
    if dtype != torch.float32:
        for n, b in module.named_buffers():
            if b.is_floating_point():
                module.register_buffer(n, b.to(dtype))

    dummy = torch.zeros(1, 8, dtype=torch.long)
    print(f"[INFO] Exportando ONNX (opset={opset}, dtype={dtype}) …")
    with torch.no_grad():
        torch.onnx.export(
            module, (dummy,), str(out),
            input_names=["token_ids"], output_names=["logits"],
            dynamic_axes={"token_ids": {1: "T"}, "logits": {1: "T"}},
            opset_version=opset, do_constant_folding=True,
        )
    print(f"[OK]  {out}  ({out.stat().st_size/1e6:.1f} MB)")
    return module   # retorna para validação


def do_validate(onnx_path: Path, module: SGLMTrace, seq_len: int, bench_runs: int):
    sep = "─" * 52

    print(f"\n{sep}\n  [1/4] Estrutura do grafo\n{sep}")
    try:
        import onnx
        m = onnx.load(str(onnx_path))
        onnx.checker.check_model(m)
        opset = m.opset_import[0].version
        print(f"  Opset  : {opset}")
        for inp in m.graph.input:
            sh = [d.dim_param or d.dim_value for d in inp.type.tensor_type.shape.dim]
            print(f"  Input  '{inp.name}' : {sh}")
        for out in m.graph.output:
            sh = [d.dim_param or d.dim_value for d in out.type.tensor_type.shape.dim]
            print(f"  Output '{out.name}' : {sh}")
        print(f"  Nós    : {len(m.graph.node)}   Weights: {len(m.graph.initializer)}")

        # NaN / Inf
        import onnx.numpy_helper as nph
        bad = [i.name for i in m.graph.initializer
               if np.isnan(nph.to_array(i)).any() or np.isinf(nph.to_array(i)).any()]
        if bad:
            for b in bad: print(f"  [WARN] NaN/Inf em: {b}")
        else:
            print(f"  [OK]  Nenhum NaN/Inf nos pesos.")
    except ImportError:
        print("  [SKIP] onnx não instalado.")

    print(f"\n{sep}\n  [2/4] Carregamento ONNX Runtime\n{sep}")
    sess = None
    try:
        import onnxruntime as ort
        t0   = time.perf_counter()
        sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
        print(f"  [OK]  Sessão em {(time.perf_counter()-t0):.2f}s")
        print(f"  Providers: {sess.get_providers()}")
    except ImportError:
        print("  [SKIP] onnxruntime não instalado.")

   
    print(f"\n{sep}\n  [3/4] Comparação numérica PyTorch vs ORT\n{sep}")
    if sess and module:
        dummy = torch.zeros(1, seq_len, dtype=torch.long)
        with torch.no_grad():
            pt = module(dummy).float().numpy()
        ort_out = sess.run(["logits"], {"token_ids": dummy.numpy()})[0]
        diff = np.abs(pt - ort_out)
        print(f"  max diff : {diff.max():.6f}")
        print(f"  mean diff: {diff.mean():.6f}")
        ok = diff.max() < 1e-3
        print(f"  {'[OK]  Saídas equivalentes.' if ok else '[WARN] Diferença acima do limiar (esperado em float16).'}")
        pt_tok  = pt[0, -1].argmax()
        ort_tok = ort_out[0, -1].argmax()
        print(f"  Argmax último token  PT={pt_tok}  ORT={ort_tok}  {'✓' if pt_tok==ort_tok else '✗'}")
    else:
        print("  [SKIP]")

    print(f"\n{sep}\n  [4/4] Benchmark (seq_len={seq_len})\n{sep}")

    if sess:
        dummy_np = np.zeros((1, seq_len), dtype=np.int64)
        for _ in range(3): sess.run(["logits"], {"token_ids": dummy_np})
        times = []

        for _ in range(bench_runs):
            t0 = time.perf_counter()
            sess.run(["logits"], {"token_ids": dummy_np})
            times.append(time.perf_counter() - t0)

        avg = sum(times)/len(times)*1000
        print(f"  média: {avg:.1f} ms   min: {min(times)*1000:.1f} ms   "
              f"p95: {sorted(times)[int(.95*len(times))]*1000:.1f} ms")

        print(f"  throughput prefill: {seq_len/(avg/1000):.0f} tokens/s")

    else:
        print("  [SKIP]")


def main():
    ap = argparse.ArgumentParser(description="Converte + valida safetensors → ONNX")
    ap.add_argument("--input",  "-i", required=True)
    ap.add_argument("--output", "-o", default="model.onnx")
    ap.add_argument("--dtype",  choices=["float32","float16"], default="float32")
    ap.add_argument("--opset",  type=int, default=17)
    ap.add_argument("--verify", action="store_true",
                    help="Roda validação completa após exportar")
    ap.add_argument("--seq-len",    type=int, default=16)
    ap.add_argument("--bench-runs", type=int, default=5)
    a = ap.parse_args()

    dtype   = torch.float16 if a.dtype == "float16" else torch.float32
    in_path = Path(a.input); out_path = Path(a.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    sd   = load_sf(in_path)
    args = infer_args(sd)

    total = sum(v.numel() for v in sd.values())
    
    print(f"\n  vocab={args.vocab_size}  layers={args.n_layer}  "
          f"d={args.n_embd}  heads={args.n_heads}(kv:{args.n_kv_heads})  "
          f"params={total/1e6:.1f}M\n")

    module = do_export(sd, args, out_path, dtype, a.opset)

    if a.verify:
        do_validate(out_path, module, a.seq_len, a.bench_runs)
        print(f"\n[DONE] {out_path.resolve()}\n")

if __name__ == "__main__":
    main()