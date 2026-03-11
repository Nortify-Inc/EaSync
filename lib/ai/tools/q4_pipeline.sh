#!/usr/bin/env bash
set -euo pipefail

# q4_pipeline.sh
# Helper to run an AutoGPTQ-based 4-bit quantization pipeline.
# Usage:
#   ./q4_pipeline.sh /path/to/pytorch_checkpoint /path/to/output_dir
# This script prints the recommended commands and will attempt to run
# AutoGPTQ quantization if `auto_gptq` is importable in the current env.

MODEL_DIR=${1:-}
OUT_DIR=${2:-}

if [ -z "$MODEL_DIR" ] || [ -z "$OUT_DIR" ]; then
  echo "Usage: $0 /path/to/pytorch_checkpoint /path/to/output_dir"
  exit 2
fi

echo "Model dir: $MODEL_DIR"
echo "Output dir: $OUT_DIR"

python - <<'PY'
import sys
try:
    import auto_gptq
    print('auto_gptq available — attempting quantization (this may take time)')
except Exception as e:
    print('auto_gptq not installed. Install it with: pip install auto-gptq')
    print('Or follow docs/Q4_GPTQ.md for manual steps')
    sys.exit(0)

from auto_gptq import AutoGPTQForCausalLM, BaseQuantizeConfig
from transformers import AutoModelForCausalLM
import os

model_dir = os.environ.get('MODEL_DIR') or '%s'
out_dir = os.environ.get('OUT_DIR') or '%s'

print('Loading model (this may require substantial RAM)')
model = AutoModelForCausalLM.from_pretrained(model_dir, torch_dtype='auto')
print('Wrapping into AutoGPTQ quantizer')
quantizer = AutoGPTQForCausalLM.from_pretrained(model, model_dir, use_safetensors=True)
qconfig = BaseQuantizeConfig(bits=4, group_size=128, desc_act=False)
print('Starting quantization...')
quantizer.quantize(qconfig)
print('Saving quantized model to', out_dir)
quantizer.save_quantized(out_dir, use_safetensors=True)
print('Done')
PY
