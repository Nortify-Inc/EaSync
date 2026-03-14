# EaSync — Documentação de Arquitetura (atualizada)

Data: 2026-03-14

Resumo rápido
- EaSync é uma aplicação multiplataforma com UI Flutter (`lib/ui`) e um núcleo nativo em C++ (`lib/core`) que gerencia dispositivos, drivers e estado. O subsistema de IA vive em `lib/ai` e fornece tanto uma biblioteca nativa C++/ONNX quanto scripts Python para pesquisa/treino.

Objetivo deste documento
- Descrever de forma fiel a arquitetura atual do backend (núcleo C++ + motor de IA), o contrato FFI com o Flutter, fluxo de dados, artefatos, variáveis de ambiente relevantes e workflows de desenvolvimento e build.

1. Visão geral da arquitetura
- Componentes principais:
  - UI Flutter: `lib/ui` (páginas, widgets, `bridge.dart` — camada FFI).
  - Núcleo nativo (Core): `lib/core` (API C pública, registro de dispositivos, drivers, despacho de eventos, cache de estado).
  - IA: `lib/ai` (runtime nativo em C++ que carrega um modelo ONNX e tokenizador; scripts Python para pesquisa/treino).
  - Assets: `assets/` (templates JSON de dispositivos, imagens) e `lib/ai/data` (modelo/tokenizer) — a UI pode empacotar esses assets para copiar em tempo de execução.

2. Fluxo principal de dados
- UI ↔ Bridge (Dart FFI) ↔ Núcleo (`libeasync_core.so`) : operações de dispositivo (registro, estado, comandos), eventos e callbacks.
- UI ↔ Bridge (Dart FFI) ↔ IA (`libeasync_ai.so`) : consultas ao assistente, geração de texto síncrona e assíncrona (streaming).
- Drivers ↔ Núcleo ↔ Bridge ↔ UI : drivers de protocolos (BLE, Wi‑Fi, Zigbee, MQTT, Mock) conectam dispositivos físicos ao core.

3. Núcleo (lib/core)
- Localização-chave: `lib/core/include/core.h` (contrato público C) e `lib/core/src/core.cpp` (implementação).
- Responsabilidades:
  - Registro e remoção de dispositivos (`core_register_device[_ex]`, `core_remove_device`).
  - Consulta e atualização de estado (`core_get_state`, `core_set_power`, `core_set_brightness`, `core_set_color`, etc.).
  - Gerenciamento de drivers por protocolo e inicialização sob demanda.
  - Cache de estado local e despacho de eventos via `core_set_event_callback` (estrutura `CoreEvent`).
  - Operações utilitárias: simulação (`core_simulate`), provisionamento Wi‑Fi (`core_provision_wifi`), rastreamento de erros (`core_last_error`).
- Driver model:
  - Drivers vivem em `lib/core/drivers/` e implementam a interface comum `drivers::Driver` (mock, BLE, opcional MQTT/Wi‑Fi/Zigbee via defines de build).
  - O núcleo cria instâncias de driver (ex.: `MockDriver`, `BleDriver`) no `core_create()` e inicializa conforme necessário (`ensureDriverInitialized`).
- Concorrência e segurança:
  - `core.cpp` usa mutexes/locks para proteger mapa de dispositivos e dados compartilhados; eventos do driver são encaminhados por trampolins que comparam estados e disparam callbacks quando há mudanças.

4. IA (lib/ai)
- Localização-chave: `lib/ai/include/engine.hpp` (API C `ai_*`) e `lib/ai/src/engine.cpp` (implementação nativa principal).
- Papel do engine nativo:
  - Carregar `model.onnx` e `tokenizer.json` de `lib/ai/data` (pasta pesquisada automaticamente ou definida por `EASYNC_AI_DATA_DIR`).
  - Inicializar tokenizador (`Tokenizer`) e motor de inferência (classe `SGLM` / ONNX runtime wrapper).
  - Expor APIs C para o `Bridge` usar: `ai_initialize`, `ai_query`, `ai_query_async_start`/`ai_query_async_poll`, `ai_set_data_dir`, `ai_set_system_prompt`, `ai_set_decode_every`, `ai_shutdown`, entre outras auxiliares (`ai_record_pattern`, `ai_get_annotations`, etc.).
  - Suporte a geração síncrona (`ai_query`) e assíncrona (jobs com `ai_query_async_start` devolvendo handle e `ai_query_async_poll` para ler chunks/streaming).
- Artefatos e scripts auxiliares:
  - `lib/ai/src/chat.py`, `SGLMLite.py`, e outros scripts PyTorch existem para pesquisa/treino e como referência de implementação, mas a inferência de produção está implementada no runtime C++/ONNX quando disponível.
  - `lib/ai/data/` contém `model.onnx`, `tokenizer.json`, vocabulários e amostras; o engine procura automaticamente por esses arquivos e aceita override via `EASYNC_AI_DATA_DIR` ou `ai_set_data_dir()`.
- Variáveis de ambiente relevantes:
  - `EASYNC_AI_DATA_DIR` — local alternativo para `lib/ai/data`.
  - `EASYNC_SYSTEM_PROMPT` — prompt do sistema usado pelo motor.
  - `EASYNC_DECODE_EVERY` — controla frequência de decodificação durante geração streaming.
  - (ferramentas) `EASYNC_CHAT_INFER_SCRIPT` e `EASYNC_CHAT_INFER_PYTHON` — usados por componentes auxiliares que apontam para scripts Python (fallbacks/experimentais).

5. FFI / Bridge (Flutter ↔ Nativo)
- Implementação: `lib/ui/utils/bridge.dart`.
- Comportamento principal:
  - Abre dinamicamente as bibliotecas nativas (`libeasync_core.so` e `libeasync_ai.so`) procurando em múltiplos caminhos (build outputs, diretórios do executável, `/usr/lib` etc.).
  - Define typedefs e lookup das funções C (`core_*` e `ai_*`) e fornece wrappers Dart/OOP que o restante da UI consome (`aiQuery`, `aiQueryAsync`, `aiQueryStream`, `coreCreate`, `coreInit`, `registerDevice`, etc.).
  - Copia assets de IA empacotados (AssetManifest) para uma pasta de suporte da aplicação quando necessário (`_ensureAiAssetsCopied`).
  - Fornece abstrações de streaming: spawn de isolate para chamar `ai_query_async_start` / `ai_query_async_poll` e encaminhar chunks ao UI.
- Contratos importantes (exemplos):
  - `core_create()` / `core_destroy()` — criar/destuir contexto nativo.
  - `core_init()` — inicializar o núcleo.
  - `core_register_device[_ex]`, `core_set_power`, `core_set_brightness`, etc. — controle de dispositivos.
  - `ai_query`, `ai_query_async_start`, `ai_query_async_poll` — chamadas de inferência.

6. Assets e templates
- Templates de dispositivos JSON ficam em `assets/*.json` (ex.: `lamps.json`, `locks.json`, `mocks.json`). UI usa `TemplateRepository`/`manage.dart` para carregar templates e gerar fluxos de registro.
- Imagens e outros binários em `assets/images/`.

7. Build e execução (resumo prático)
- Pré-requisitos: Flutter toolchain (para UI) e compilador C++/CMake (para libs nativas). ONNX runtime e dependências devem estar disponíveis para construir `lib/ai` (você verá subpastas `thirdParty/onnxruntime-*`).
- Passos comuns:
  - Build do core nativo:
    ```bash
    cd lib/core
    ./build.sh
    ```
  - Build do engine AI (quando aplicável): siga scripts CMake em `lib/ai/CMakeLists.txt` (ex.: gerar `libeasync_ai.so`).
  - Dependências Flutter e execução:
    ```bash
    flutter pub get
    flutter run -d linux --target lib/ui/main.dart
    ```
  - Opcional: copiar assets AI para suporte da aplicação é feito automaticamente pelo `Bridge` se os assets estiverem empacotados.

8. Workflows de desenvolvimento
- Desenvolvimento UI: editar `lib/ui`, depende do contrato FFI em `bridge.dart`. Teste manual com `flutter run`.
- Desenvolvimento Core/Drivers: editar `lib/core/*`, use `lib/core/build.sh` e verifique se `libeasync_core.so` está acessível ao app (paths listados em `bridge.dart`).
- Desenvolvimento AI: treinar/experimentar com scripts em `lib/ai/` e gerar `model.onnx` para o runtime nativo. Use `EASYNC_AI_DATA_DIR` para apontar para dados locais durante testes.

9. Padrões e convenções importantes
- Mantenha as assinaturas FFI em `lib/ui/utils/bridge.dart` sincronizadas com os headers C (`lib/core/include/core.h` e `lib/ai/include/engine.hpp`).
- Não contornar o `Bridge` na UI: todas as chamadas nativas devem passar por `bridge.dart`.
- Docblocks no estilo do projeto: preserve `@file`, `@brief`, etc., em C++/Dart.

10. Pontos de integração cruciais e arquivos a checar
- `lib/ui/utils/bridge.dart` — carregamento dinâmico das bibliotecas e wrappers Dart.
- `lib/core/include/core.h` e `lib/core/src/core.cpp` — API do núcleo.
- `lib/core/drivers/*` — drivers (mock, ble.cpp, mqtt.cpp, wifi.cpp, zigbee.cpp).
- `lib/ai/include/engine.hpp` e `lib/ai/src/engine.cpp` — engine de inferência nativo (ONNX/tokenizer, async streaming).
- `lib/ai/data/*` — modelo/tokenizer/vocab (essenciais para o engine).
- `assets/*.json` — templates e mocks usados pelo `manage.dart`.

11. Observações e recomendações
- A inferência de produção é implementada no runtime nativo (C++/ONNX). Os scripts Python permanecem úteis para pesquisa, treino e debugging, mas não são o caminho primário para runtime embarcado em produção.
- Ao alterar assinaturas FFI, atualize simultaneamente `core.h`/`engine.hpp` e `bridge.dart` para evitar crashes em tempo de execução.
- Para testar mudanças de AI localmente sem empacotar assets, defina `EASYNC_AI_DATA_DIR` apontando para `lib/ai/data`.

12. Exemplos rápidos
- Registrar um dispositivo (conceitual): Flutter faz `Bridge.registerDevice(template)` → `core_register_device_ex(...)` → driver inicializa e `CoreEvent` com `CORE_EVENT_DEVICE_ADDED` é disparado → UI atualiza lista.
- Executar uma query de IA (conceitual): Flutter chama `aiQuery(prompt)` → `ai_query` no `libeasync_ai` → engine roda tokenização + inferência ONNX → resposta retornada (ou `ai_query_async_start`/`ai_query_async_poll` para streaming de chunks).

13. Onde checar quando algo quebra
- Erros de carregamento de bibliotecas: verifique caminhos listados em `lib/ui/utils/bridge.dart`.
- Falha de inferência: logs do engine C++ (stderr) indicam falta de `model.onnx` ou `tokenizer.json`.
- Falha de driver/conexão: `core_last_error()` lê a última mensagem do núcleo; drivers imprimem mensagens no stderr.

Fim — documento mantido por equipe EaSync. Contacto: ver autor nos docblocks dos arquivos principais.
# EaSync — Documentação de Arquitetura

> Recent updates (2026-03-11): repository now includes ONNX INT8 quantization tools (`lib/ai/tools/quantize_model.py`) and Q4/GPTQ guidance (`docs/Q4_GPTQ.md`). Android CMake ORT_ROOT normalization fix applied (`lib/CMakeLists.txt`). See docs for details.

---

## 1. Visão Geral

EaSync é uma plataforma de automação residencial inteligente, modular e multiplataforma. O projeto une uma interface Flutter moderna, um núcleo nativo C++ robusto e módulos C++ de IA para controle, automação, aprendizado de padrões e assistente virtual. O foco é flexibilidade, segurança, extensibilidade e facilidade de integração.

EaSync foi projetado para ser utilizado tanto por usuários finais quanto por desenvolvedores, permitindo customização, expansão de funcionalidades e integração com novos dispositivos e protocolos.

---

## 2. Estrutura de Pastas e Componentes

```
Raiz do projeto
├── assets/           # Templates, imagens, mocks, configurações
│   ├── acs.json      # Template de ar-condicionado
│   ├── curtains.json # Template de cortinas
│   ├── fridges.json  # Template de geladeiras
│   ├── heated_floors.json # Template de pisos aquecidos
│   ├── lamps.json    # Template de lâmpadas
│   ├── locks.json    # Template de fechaduras
│   ├── mocks.json    # Mock de dispositivos
│   └── images/       # Imagens de dispositivos
├── lib/
│   ├── ai/           # Inteligência Artificial
│   │   ├── include/  # Headers C++ (modelos, tokenizer, MoE, etc)
│   │   ├── models/   # Implementação dos modelos, scripts, tokenizer
│   │   ├── utils/    # Scripts utilitários (dataset, vocabulário)
│   │   ├── data/     # Vocabulário, comandos, interações
│   │   └── src/      # Motor de IA (chatModelRuntime.cpp)
│   ├── core/         # Núcleo nativo C++
│   │   ├── include/  # Headers do núcleo
│   │   ├── src/      # Implementação do núcleo
│   │   ├── drivers/  # Drivers de protocolos (BLE, WiFi, Zigbee, MQTT, Mock)
│   │   └── build/    # Artefatos de build
│   └── ui/           # Interface Flutter
│       ├── widgets/  # Componentes visuais reutilizáveis
│       ├── account.dart
│       ├── assistant_chat.dart
│       ├── assistant.dart
│       ├── bridge.dart
│       ├── dashboard.dart
│       ├── handler.dart
│       ├── home.dart
│       ├── i18n.dart
│       ├── main.dart
│       ├── manage.dart
│       ├── profiles.dart
│       ├── settings.dart
│       ├── splash.dart
│       ├── theme.dart
│       └── ...       # Outras páginas
├── docs/             # Documentação
│   ├── architecture.md
│   └── ...           # Outros documentos
├── android/, ios/, linux/, macos/, windows/, web/  # Plataformas
```

### Componentes principais:
- **assets/**: Templates de dispositivos, imagens, mocks, arquivos de configuração.
- **lib/ai/**: Núcleo C++ IA, modelos, scripts de treinamento, vocabulário.
- **lib/core/**: Núcleo C++ (drivers, API, eventos, build).
- **lib/ui/**: Interface Flutter (páginas, widgets, bridge FFI).
- **docs/**: Documentação técnica e de arquitetura.

---

## 3. Fluxo de Dados e Comunicação

### 3.1. Templates e Descoberta de Dispositivos
- Templates JSON são carregados da pasta `assets/`.
- Usuário registra/discover dispositivos via UI (`manage.dart`).
- UI chama `Bridge.registerDevice()` (Dart), que aciona o núcleo C++.
- Núcleo C++ valida, registra e retorna status/eventos.

#### Exemplo de template:
```json
{
  "name": "Lamp",
  "capabilities": ["on", "off", "dim"],
  "constrains": {"max_brightness": 100}
}
```

### 3.2. Comunicação com Dispositivos
- Drivers nativos implementam protocolos (BLE, WiFi, Zigbee, MQTT).
- Núcleo C++ gerencia conexões, eventos, comandos e telemetria.
- Eventos são propagados para Flutter via FFI (`bridge.dart`).

#### Diagrama textual do fluxo principal:
```
[UI Flutter] <-> [Bridge FFI] <-> [Núcleo C++] <-> [Drivers] <-> [Dispositivos]
      |                |
      |                +---> [IA C++/Python] <-> [Scripts/Modelos]
      |
      +---> [Persistência Local]
```

### 3.3. Assistente Virtual e IA
- Comandos do usuário são enviados pelo UI (`assistant.dart`) para `Bridge.aiExecuteCommandAsync()`.
- A lógica de inferência de IA vive em `lib/ai` e é oferecida tanto como uma biblioteca nativa C++ (exportando as funções `ai_*` descritas em `lib/ai/include/engine.hpp`) quanto por scripts Python usados para experimentação e ferramentas de treinamento (`lib/ai/src/chat.py`, `lib/ai/src/SGLMLite.py`, etc.).
- O runtime nativo (`lib/ai/src/engine.cpp`) carrega um modelo ONNX (`lib/ai/data/model.onnx`) e o `tokenizer.json`, expõe chamadas síncronas e assíncronas (streaming) como `ai_query`, `ai_query_async_start` / `ai_query_async_poll` e funções de configuração como `ai_set_data_dir`, `ai_set_system_prompt` e `ai_set_decode_every`.
  - O `Bridge` abre a biblioteca nativa de IA (`libeasync_ai`) e a biblioteca do núcleo (`libeasync_core`). As chamadas de IA vão diretamente para `libeasync_ai` (runtime C++/ONNX) — elas não passam pelo núcleo C++; scripts Python são apenas auxiliares/experimentais para pesquisa e treino.

#### Exemplo de comando:
- "Acenda a luz da sala e ajuste para 50% de brilho"

### 3.4. Aprendizado de Padrões
- Padrões de uso são salvos no Flutter (`SharedPreferences`) e sincronizados com o núcleo.
- Funções como `Bridge.aiRecordPattern()` e `Bridge.aiObserveProfileApply()` garantem persistência e telemetria.

---

## 4. Detalhamento dos Módulos

### 4.1. Flutter UI (`lib/ui`)
- **main.dart**: Entrypoint, inicializa o Bridge.
- **bridge.dart**: Interface FFI, conecta Dart ao núcleo C++.
- **dashboard.dart, manage.dart, profiles.dart, assistant.dart**: Páginas principais.
- **handler.dart**: Exporta módulos compartilhados.
- **widgets/**: Componentes visuais reutilizáveis.

#### Exemplo de fluxo UI:
1. Usuário acessa dashboard.
2. UI exibe status dos dispositivos.
3. Ao clicar em "Adicionar dispositivo", UI carrega templates e chama Bridge.

#### Detalhamento de páginas:
- **dashboard.dart**: Painel principal, status geral, gráficos de consumo, alertas.
- **manage.dart**: Gerenciamento de dispositivos, registro, edição, exclusão.
- **profiles.dart**: Perfis de automação, horários, rotinas.
- **assistant.dart**: Chat com assistente, comandos de voz/texto.
- **settings.dart**: Configurações gerais, idioma, temas, permissões.

#### Widgets principais:
- **skeleton.dart**: Placeholder para carregamento.
- **splash.dart**: Tela inicial.
- **theme.dart**: Temas visuais.

### 4.2. Núcleo C++ (`lib/core`)
- **core.h / core.cpp**: API nativa, gerenciamento de dispositivos e eventos.
- **drivers/**: Implementação de protocolos (BLE, WiFi, Zigbee, MQTT, Mock).
- **CMakeLists.txt**: Configuração de build.

#### Drivers:
- **ble.cpp**: Comunicação Bluetooth Low Energy.
- **wifi.cpp**: Comunicação WiFi.
- **zigbee.cpp**: Comunicação Zigbee.
- **mqtt.cpp**: Comunicação MQTT.
- **mock.cpp**: Simulação de dispositivos.

#### Exemplo de driver:
- `mqtt.cpp` implementa conexão, publicação e assinatura de tópicos MQTT.
- `mock.cpp` simula dispositivos para testes.

### 4.3. IA (`lib/ai`)
- **engine.cpp**: Motor de inferência nativo (implementado em `lib/ai/src/engine.cpp`) que carrega um modelo ONNX e o `tokenizer.json`, fornece geração síncrona e assíncrona (streaming) e expõe uma API C (`lib/ai/include/engine.hpp`) para uso pelo `Bridge`.
- **SGLM / SGLMLite**: Implementações e bindings do modelo (C++/ONNX e scripts PyTorch para pesquisa) usadas pelo `engine` ou por scripts experimentais.
- **tokenizer.cpp / tokenizer.json**: Tokenizador nativo (e artefatos JSON) usados para codificar/decodificar texto.
- **scripts Python**: `lib/ai/src/chat.py`, `SGLMLite.py` e scripts de treino/avaliação na pasta `lib/ai/models/` são mantidos para desenvolvimento, experimentação e treinamento, mas a inferência de produção é feita pelo runtime nativo quando disponível.
- **data/**: Vocabulário, `model.onnx`, `tokenizer.json` e arquivos relacionados. O runtime procura `lib/ai/data` por padrão, e pode ser apontado com `EASYNC_AI_DATA_DIR` ou via `ai_set_data_dir()`.

#### Exemplo de fluxo IA:
1. Usuário envia comando de voz.
2. UI chama Bridge → `libeasync_ai` (runtime ONNX nativo).
3. Engine nativo processa (tokenização + inferência ONNX) e retorna resposta.
4. UI exibe resultado.

#### Modelos e artefatos (em `lib/ai`):
- **`engine.cpp` / `engine.hpp`**: runtime nativo que orquestra tokenização e inferência ONNX e expõe as APIs C `ai_*` usadas pelo `Bridge`.
- **SGLM / SGLMLite** (`SGLM.cpp`, `SGLM.py`, `SGLMLite.py`): implementações do modelo e bindings usados para geração e pesquisa; `SGLM` é a implementação carregada pelo engine quando `model.onnx` estiver disponível.
- **`tokenizer.cpp` / `tokenizer.json`**: implementação do tokenizador e artefatos JSON usados para codificação/decodificação.
- **Modelos exportados** (`model.onnx`, `model.safetensors`, `model.onnx.data`): artefatos presentes em `lib/ai/data/` que o engine carrega em tempo de execução.

#### Scripts e utilitários:
- **`chat.py`**, **`distille.py`**, **`loadTeacher.py`**, **`SGLMLite.py`**: scripts Python para pesquisa, inferência experimental e preparação/treino de modelos.
- Existem utilitários e ferramentas de preparo/quantização no repositório (ex.: scripts sob `lib/ai/` e `lib/ai/tools`), porém o runtime de produção é o C++/ONNX implementado em `engine.cpp`.

---

## 5. FFI (Dart ↔ C++)

- O `Bridge` centraliza todas as chamadas entre Dart e C++.
- Assinaturas FFI são mantidas em `bridge.dart` e `core.h`.
- Eventos, comandos e respostas são serializados/deserializados.
- Compatibilidade garantida por enums, structs e contratos.

#### Exemplo de assinatura FFI:
- `Bridge.registerDevice()` → C++: `core_register_device()`
- `Bridge.aiExecuteCommandAsync()` → AI runtime (separado): `ai_query_async_start()` / `ai_query_async_poll()` (exports em `libeasync_ai.so`)

Note: The AI/runtime APIs were split out of the main core — device management remains in `libeasync_core` (core_*) while model/AI functions live in a separate native library (`libeasync_ai`) with `ai_*` exports. `bridge.dart` opens both libraries and forwards calls accordingly.

#### Diagrama de integração:
```
[Dart UI] <-> [Bridge] <-> [C++ Core] <-> [Drivers] <-> [Dispositivos]
           |
           +---> [IA C++/Python]
```

---

## 6. Drivers e Protocolos

- Cada protocolo tem um driver dedicado (BLE, WiFi, Zigbee, MQTT).
- Drivers implementam descoberta, conexão, envio/recebimento de dados.
- Mock driver permite testes sem hardware.
- Drivers são facilmente extensíveis: basta implementar a interface e registrar no núcleo.

#### Exemplo de extensão:
- Para adicionar um driver LoRa, crie `lora.cpp` e `lora.hpp` em `drivers/`, implemente interface, registre no núcleo.

#### Interface típica de driver:
```cpp
class Driver {
public:
    virtual bool connect(const std::string& address) = 0;
    virtual bool send(const std::vector<uint8_t>& data) = 0;
    virtual std::vector<uint8_t> receive() = 0;
    virtual void disconnect() = 0;
};
```

---

## 7. IA e Modelos

- Modelos são implementados em C++ e Python.
- Tokenizer, Attention, FeedForward, MoE, Transformer, etc.
- Scripts Python para treinamento e inferência.
- Dados de vocabulário e comandos em `data/`.
- Treinamento pode ser feito localmente ou em cloud.

#### Exemplo de treinamento:
- `python3 lib/ai/models/train_and_export.py` treina e exporta modelo.
- Modelo é carregado pelo núcleo C++ ou script Python.

#### Estrutura de um modelo:
```cpp
class Transformer {
public:
    Transformer(int numLayers);
    std::vector<float> forward(const std::vector<float>& input);
    // ...
};
```

#### Tokenizer:
- Tokeniza texto para IDs.
- Normaliza, gerencia vocabulário, suporta subword.

#### MoE (Mixture of Experts):
- Roteamento dinâmico de inputs para especialistas.
- Agrega outputs.

---

## 8. Persistência e Telemetria

- Flutter usa `SharedPreferences` para dados locais.
- Núcleo C++ pode salvar dados em arquivos ou sincronizar com UI.
- Telemetria de uso, eventos e padrões é registrada para IA.

#### Exemplo de persistência:
- Usuário ajusta rotina de iluminação.
- UI salva rotina em `SharedPreferences`.
- Bridge sincroniza com núcleo.

---

## 9. Workflows de Desenvolvimento

- **Build nativo:** `cd lib/core && ./build.sh`
- **Dependências Flutter:** `flutter pub get`
- **Rodar app:** `flutter run -d linux --target lib/ui/main.dart`
- **Testes e análise:** `flutter analyze`, `flutter test`
- **Treinamento IA:** `python3 lib/ai/models/train_and_export.py`

#### Dicas:
- Sempre rode `flutter analyze` antes de commit.
- Use o mock driver para testes sem hardware.
- Documente novos drivers e modelos.
- Utilize scripts de dataset para expandir vocabulário.
- Teste integração FFI após mudanças no núcleo.

---

## 10. Convenções, Padrões e Segurança

- Docblocks em todos os arquivos (`@file`, `@brief`, etc.).
- Nomes de enums e constantes respeitam os originais do núcleo.
- Não bypassar o Bridge para chamadas nativas.
- Campos de schema dos assets mantidos conforme original.
- Drivers isolados por protocolo.
- Interface FFI centralizada.
- Scripts Python podem ser atualizados sem recompilar o núcleo.
- UI modular e fácil de expandir.
- Controle de acesso e autenticação podem ser implementados via drivers ou UI.
- Uso de logs e telemetria para rastreabilidade.
- Testes unitários e de integração.

#### Exemplo de docblock:
```cpp
/**
 * @file transformer.hpp
 * @author Radmann
 * @brief Modelo transformer para IA.
 */
```

---

### 11. Referências dos Arquivos Críticos

- `lib/ui/bridge.dart`: Contrato FFI, orquestração de dispositivos e IA.
- `lib/core/include/core.h` e `lib/core/src/core.cpp`: API nativa do núcleo (registro de dispositivos, drivers, estado, eventos).
- `lib/ui/manage.dart`: Registro e descoberta de dispositivos.
- `lib/ui/assistant.dart`: UX do assistente e telemetria.
- `lib/ai/include/engine.hpp` e `lib/ai/src/engine.cpp`: Motor nativo de IA (ONNX) que fornece as APIs `ai_*` utilizadas pelo `Bridge`.
- `lib/ai/src/chat.py` e outros scripts Python em `lib/ai/src/` são scripts auxiliares/experimentais para desenvolvimento e treino.

---

## 12. Exemplos de Fluxo (Determinístico)

### 12.1. Registro de Dispositivo
```
Usuário → UI Flutter → Bridge.registerDevice() → Núcleo C++ → Driver → Dispositivo
```
1. Usuário seleciona template na UI.
2. UI chama `Bridge.registerDevice()`.
3. Núcleo C++ registra e retorna status.
4. UI exibe resultado.

### 12.2. Comando de Assistente
```
Usuário → UI Flutter → Bridge.aiExecuteCommandAsync() → Núcleo C++ → Script Python → IA → Resposta → UI
```
1. Usuário envia comando.
2. UI chama `Bridge.aiExecuteCommandAsync()`.
3. Núcleo C++ aciona script Python.
4. Resultado é retornado e exibido.

### 12.3. Aprendizado de Padrão
```
Usuário → UI Flutter → Bridge.aiRecordPattern() → Núcleo C++ → Persistência
```
1. Usuário executa rotina.
2. UI registra padrão.
3. Núcleo C++ salva padrão.

---

## 13. FAQ Técnico

**Como adicionar um novo protocolo?**
- Crie um driver em `lib/core/drivers/`.
- Implemente interface em `core.h`.
- Exporte via Bridge.

**Como treinar um novo modelo de IA?**
- Adicione dados em `lib/ai/data/`.
- Use scripts de treinamento em `lib/ai/models/`.
- Atualize o runtime conforme necessário.

**Como expandir a UI?**
- Crie novos widgets em `lib/ui/widgets/`.
- Adicione páginas e conecte via Bridge.

**Como testar sem hardware?**
- Use o mock driver em `lib/core/drivers/mock.cpp`.
- Simule eventos e comandos.

**Como garantir compatibilidade FFI?**
- Sempre sincronize enums e structs entre Dart e C++.
- Rode testes de integração.

**Como documentar um novo módulo?**
- Use docblocks.
- Explique propósito, parâmetros, retorno e exemplos.

---

## 14. Casos de Uso e Exemplos

### 14.1. Automação de Rotina
- Usuário define rotina de iluminação para 18h.
- UI salva rotina.
- Núcleo executa rotina automaticamente.

### 14.2. Controle por Voz
- Usuário diz: "Tranque a porta da frente".
- Assistente interpreta, aciona driver de fechadura.

### 14.3. Integração com Dispositivo Novo
- Desenvolvedor implementa driver para sensor de presença.
- Registra driver no núcleo.
- UI exibe status do sensor.

---

## 15. APIs, Contratos e Integrações

### 15.1. API FFI
- Contratos em `bridge.dart` e `core.h`.
- Métodos: registro, comando, consulta, telemetria.

### 15.2. API de Driver
- Interface padrão para drivers.
- Métodos: connect, send, receive, disconnect.

### 15.3. API de IA
- Tokenizer, inferência, treinamento.
- Scripts Python e C++.

---

## 16. Dicas Avançadas e Boas Práticas

- Use logs para rastrear eventos.
- Implemente testes unitários para drivers e modelos.
- Documente cada novo recurso.
- Utilize mocks para testes sem hardware.
- Expanda vocabulário da IA conforme novos dispositivos.
- Use temas visuais para personalização da UI.
- Garanta segurança em drivers de rede.
- Utilize telemetria para melhorar IA.

---

## 17. Contribuição, Contato e Comunidade

- Documentação e exemplos em `docs/`.
- Siga os padrões de docblock e arquitetura.
- Pull requests e sugestões são bem-vindos.
- Sempre documente novos módulos, drivers e modelos.
- Use comentários claros e explicativos.
- Teste todas as integrações antes de subir para produção.
- Participe da comunidade EaSync.

---

## 18. Referências, Links e Recursos

- [Flutter](https://flutter.dev/)
- [C++](https://isocpp.org/)
- [MQTT](https://mqtt.org/)
- [Zigbee](https://zigbeealliance.org/)
- [Python](https://python.org/)
- [SharedPreferences Flutter](https://pub.dev/packages/shared_preferences)

---

## 19. Apêndice: Exemplos de Código, Diagramas e Fluxos

### Exemplo de Tokenizer (C++)
```cpp
#include "tokenizer.hpp"
Tokenizer tokenizer("vocab.txt");
std::vector<int> ids = tokenizer.encode("ligar luz");
std::string texto = tokenizer.decode(ids);
```

### Exemplo de Driver BLE
```cpp
#include "ble.hpp"
BLEDriver ble;
ble.connect("AA:BB:CC:DD:EE:FF");
ble.send({0x01, 0x02});
std::vector<uint8_t> resp = ble.receive();
ble.disconnect();
```

### Exemplo de Bridge FFI (Dart)
```dart
final result = await Bridge.registerDevice(template);
if (result.success) {
  print("Dispositivo registrado!");
}
```

### Diagrama de Fluxo Completo
```
[Usuário] → [UI Flutter] → [Bridge] → [Núcleo C++] → [Driver] → [Dispositivo]
           ↘︎ [IA C++/Python] ↙︎
           ↘︎ [Persistência Local] ↙︎
```

### Exemplo de Docblock
```cpp
/**
 * @file feedForward.hpp
 * @author Radmann
 * @brief Camada feedforward para modelo transformer.
 */
```

### Exemplo de Telemetria
```cpp
void logEvent(const std::string& event) {
    std::ofstream log("telemetry.log", std::ios::app);
    log << event << std::endl;
}
```

### Exemplo de Teste Unitário
```cpp
#include "gtest/gtest.h"
TEST(DriverTest, ConnectTest) {
    Driver d;
    ASSERT_TRUE(d.connect("127.0.0.1"));
}
```

---

# Fim da Documentação
