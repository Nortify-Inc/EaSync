import sys, importlib.util, torch
from pathlib import Path
from tokenizers import Tokenizer

HERE = Path(__file__).parent.resolve()
for k in list(sys.modules.keys()):
    if "qwen" in k: del sys.modules[k]

tok = Tokenizer.from_file(str(HERE / "tokenizer.json"))
ids = torch.tensor([[151644, 872, 198, 13048, 151645, 198, 151644, 77091, 198]])

spec = importlib.util.spec_from_file_location("qwen2_final", str(HERE/"model.py"))
mod  = importlib.util.module_from_spec(spec)
sys.modules["qwen2_final"] = mod
spec.loader.exec_module(mod)

print(f"n_heads={mod._infer_args.__code__.co_consts}")
model = mod.Qwen2.load(str(HERE/"model.safetensors"), device="cpu")
print(f"args: {model.args}")

with torch.no_grad():
    out = model(ids)

logits = out["logits"][0, -1, :].float()
top5v, top5i = torch.topk(logits, 5)
print("\n=== Top-5 ===")
for v, i in zip(top5v.tolist(), top5i.tolist()):
    print(f"  id={i:<8} token={tok.id_to_token(i)!r:<25} logit={v:.4f}")