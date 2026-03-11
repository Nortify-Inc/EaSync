**Q4 (4-bit) quantization via GPTQ / AutoGPTQ (guide)**

This document explains how to quantize a custom PyTorch model to 4-bit (Q4) using community tools such as AutoGPTQ or GPTQ-for-LLaMa. Because your model is custom, follow the steps carefully and validate outputs.

Prerequisites
- Python 3.8+ and pip
- Sufficient disk space (original checkpoint + quantized outputs)

Create a virtualenv and install common tools:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install torch transformers accelerate safetensors
# AutoGPTQ (recommended):
pip install auto-gptq
# Optional tools for conversion/gguf:
pip install gguf-helpers
```

AutoGPTQ workflow (recommended when you have PyTorch weights)

1. Prepare a directory that contains your model checkpoint (PyTorch `pytorch_model.bin` or `*.safetensors`) and `config.json`.
2. Run AutoGPTQ quantization (example skeleton — consult AutoGPTQ docs for exact API/flags):

```bash
# Example (adapt paths and options):
python - <<'PY'
from auto_gptq import AutoGPTQForCausalLM, BaseQuantizeConfig
from transformers import AutoModelForCausalLM

model_dir = '/path/to/your/pytorch_checkpoint'
output_dir = '/path/to/output_quant'

# Load fp16 for memory efficiency if available
model = AutoModelForCausalLM.from_pretrained(model_dir, torch_dtype='auto')

# Create quantizer wrapper
quantizer = AutoGPTQForCausalLM.from_pretrained(model, model_dir, use_safetensors=True)

# Build a 4-bit config
qconfig = BaseQuantizeConfig(bits=4, group_size=128, desc_act=False)
quantizer.quantize(qconfig)
quantizer.save_quantized(output_dir, use_safetensors=True)
print('Quantized saved to', output_dir)
PY
```

Notes:
- `group_size` controls quant grouping; tune for accuracy/perf tradeoffs (e.g., 128, 32).
- `desc_act` (or activation ordering) flags depend on model and quant library; consult AutoGPTQ docs.

Export / conversion
- AutoGPTQ usually saves quantized weights in a directory. To deploy on mobile, you can:
  - Convert the quantized model to ONNX (may require exporting a standard model wrapper first).
  - Convert to GGUF/GGML using community conversion tools if you plan to use `llama.cpp` or similar runtimes.

Example ONNX export (after loading quantized model):

```bash
# Load the quantized model with transformers+auto_gptq and run export via torch.onnx.export
python export_quant_to_onnx.py --model-dir /path/to/output_quant --output model_q4.onnx
```

If the export is not straightforward (some quant runtimes are custom), a robust alternative is to convert to GGUF/GGML (if your runtime supports it) and load with a native GGML runtime on-device.

AWQ / GPTQ-for-LLaMa notes
- AWQ and other GPTQ forks may offer different accuracy/speed tradeoffs; the process is similar: run the quantizer against the PyTorch weights, produce quantized weights, and convert for deployment.

Validation
- Always test the quantized model locally (small prompts) and compare outputs to the FP32/FP16 baseline to ensure acceptable quality.
- Benchmark memory and latency on a target device; 4-bit models will have lower memory but might need special kernels for fast inference.

If you want, I can:
- 1) Generate a runnable helper script that runs an AutoGPTQ quantization given your local checkpoint path (I won't run it unless you ask).
- 2) Try to run quantization here if you place the checkpoint in the workspace (note: large files may be impractical).

Tell me which you prefer and the local path to your PyTorch checkpoint if you want me to prepare a one-shot command/script for your exact model.