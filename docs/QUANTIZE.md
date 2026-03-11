**Quantização do modelo ONNX**

- **Objetivo**: reduzir tamanho e memória do `model.onnx` para execução prática em dispositivos Android.

Requisitos (ambiente de desenvolvimento):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install onnx onnxruntime onnxruntime-tools
```

Quantização dinâmica (INT8) — rápida e simples:

```bash
python lib/ai/tools/quantize_model.py \
  --input path/to/model.onnx \
  --output path/to/model.quant.onnx
```

Opções úteis:
- `--per-channel`: habilita quantização por canal (melhora precisão em muitos modelos).
- `--weight-type qint8|quint8`: tipo de peso quantizado.
- `--op-types`: lista de tipos de op a quantizar.

Se a quantização dinâmica não for suficiente, considere:
- Quantização estática (requere dataset de calibração) via `onnxruntime.quantization.quantize_static`.
- Converter para formatos GGML / `llama.cpp` e usar Q4/Q2 quantizações agressivas (muito menores). Veja: https://github.com/ggerganov/llama.cpp

Integração no APK:
- Após gerar `model.quant.onnx`, substitua ou adicione `lib/ai/data/model.onnx` (ou `model.quant.onnx`) nos assets e atualize o fluxo de cópia se o nome mudou.

Benchmark:
- Meça memória e latência no dispositivo alvo; itere com `--per-channel` e/ou static quant.