**Conversão para GGML + Q4 (guia rápido)**

Objetivo: gerar um binário GGML quantizado em Q4 (Q4_0 / Q4_K_M) adequado para execução CPU móvel (e.g., com `llama.cpp`).

Pré-requisitos (dev machine):

```bash
# Python 3, git, make e um compilador C/C++
sudo apt install -y build-essential git python3 python3-venv
```

Passos resumidos:

1) Clone e compile `llama.cpp` (repositório oficial):

```bash
git clone https://github.com/ggerganov/llama.cpp lib/ai/third_party/llama.cpp
cd lib/ai/third_party/llama.cpp
make
```

2) Converter o modelo HuggingFace/Transformers (ou checkpoints suportados) para o formato GGML.
- Se você tiver os arquivos originais (pytorch), use o script de conversão incluído no `llama.cpp` (ou scripts recomendados pela comunidade):

```bash
# exemplo genérico — adapte conforme o formato do seu checkpoint
python3 convert.py --model your-model-dir --outtype ggml --outfile model.ggml
```

3) Quantizar para Q4 usando ferramentas do `llama.cpp` (ou scripts auxiliares):

```bash
# exemplo: usar utilitário de quantização (dependendo da versão do repo)
./quantize -i model.ggml -o model.q4_0.bin q4_0
```

Nota: os nomes `q4_0`, `q4_K_M`, `q8_0` etc. variam entre ferramentas/versões; verifique `./quantize --help` no `llama.cpp` local.

4) Copiar o binário resultante para `lib/ai/data/` como `model.q4_0.bin` e adicioná-lo aos assets (caso não esteja já listado em `pubspec.yaml`). O `Downloader` do app agora copia `model.q4_0.bin` automaticamente se estiver empacotado.

5) No app Android, carregue o modelo GGML com o runtime apropriado (por exemplo, integrando `llama.cpp` como biblioteca nativa ou usando um wrapper C++). A integração deve usar `ai_set_data_dir` apontando para o diretório contendo `model.q4_0.bin`.

Alternativas e observações:
- Se partir do `onnx` puro, pode ser necessário primeiro converter para um checkpoint compatível ou usar ferramentas específicas de conversão ONNX→GGML (nem sempre triviais).
- Q4 é uma quantização agressiva; teste a qualidade gerada e compare perplexidade/respostas.
- Para dispositivos muito limitados, considere Q4_K_M ou formatos Q2 se suportados.

Referências:
- https://github.com/ggerganov/llama.cpp
- Comunidade: ferramentas de conversão e scripts de quantização (procure `convert.py`, `quantize` utilities).