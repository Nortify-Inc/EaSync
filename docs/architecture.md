# Arquitetura do Projeto EaSync

## Visão Geral
EaSync é uma plataforma modular para automação residencial, combinando uma interface Flutter com um núcleo nativo em C++ e integração de IA. O projeto foi desenhado para ser extensível, seguro e eficiente, permitindo controle de dispositivos, aprendizado de padrões e assistente inteligente.

---

## Estrutura de Pastas

- **assets/**: Contém templates de dispositivos, imagens e arquivos de configuração.
- **lib/**: Código-fonte principal.
  - **ai/**: Módulos de IA, modelos, utilitários e scripts de treinamento.
    - **include/**: Headers C++ para módulos de IA.
    - **models/**: Implementações de modelos, tokenização, inferência e treinamento.
    - **utils/**: Scripts utilitários para manipulação de dados e vocabulário.
    - **data/**: Dados de comandos, interações e informações.
    - **src/**: Implementação do motor de IA.
  - **core/**: Núcleo nativo C++.
    - **include/**: Headers do núcleo.
    - **src/**: Implementação do núcleo.
    - **drivers/**: Drivers de protocolos (BLE, WiFi, Zigbee, MQTT, Mock).
    - **build/**: Artefatos de build.
  - **ui/**: Interface Flutter.
    - **widgets/**: Componentes reutilizáveis.
    - Arquivos de páginas: dashboard, manage, assistant, profiles, etc.
- **docs/**: Documentação do projeto.
- **android/**, **ios/**, **linux/**, **macos/**, **windows/**, **web/**: Plataformas suportadas.

---

## Fluxo de Dados

### 1. Templates e Descoberta
- Templates de dispositivos são carregados de `assets/*.json`.
- O usuário pode registrar/discover dispositivos via UI (`manage.dart`).
- O registro chama `Bridge.registerDevice()` (Dart), que aciona o núcleo C++.

### 2. Comunicação com Dispositivos
- Drivers nativos implementam protocolos (BLE, WiFi, Zigbee, MQTT).
- O núcleo C++ gerencia conexões, eventos e comandos.
- Eventos são propagados para o Flutter via FFI (`bridge.dart`).

### 3. Assistente e IA
- Comandos do usuário são enviados pelo UI (`assistant.dart`) para `Bridge.aiExecuteCommandAsync()`.
- O núcleo C++ pode acionar scripts Python para inferência (`chatInferenceCli.py`).
- Resultados são retornados ao Flutter e exibidos ao usuário.

### 4. Aprendizado de Padrões
- Padrões de uso são salvos no Flutter (`SharedPreferences`) e sincronizados com o núcleo.
- Funções como `Bridge.aiRecordPattern()` e `Bridge.aiObserveProfileApply()` garantem persistência e telemetria.

---

## Principais Componentes

### Flutter UI (`lib/ui`)
- **main.dart**: Entrypoint, inicializa o Bridge.
- **bridge.dart**: Interface FFI, conecta Dart ao núcleo C++.
- **dashboard.dart, manage.dart, profiles.dart, assistant.dart**: Páginas principais.
- **handler.dart**: Exporta módulos compartilhados.
- **widgets/**: Componentes visuais reutilizáveis.

### Núcleo C++ (`lib/core`)
- **core.h / core.cpp**: API nativa, gerenciamento de dispositivos e eventos.
- **drivers/**: Implementação de protocolos.
- **CMakeLists.txt**: Configuração de build.

### IA (`lib/ai`)
- **chatModelRuntime.cpp**: Motor de inferência.
- **models/**: Tokenizer, attention, feedforward, MoE, etc.
- **train_and_export.py**: Treinamento e exportação de modelos.
- **chatInferenceCli.py**: Script Python para inferência.
- **data/**: Vocabulário, comandos, interações.

---

## Detalhes Técnicos

### FFI (Dart ↔ C++)
- O `Bridge` centraliza todas as chamadas entre Dart e C++.
- Assinaturas FFI são mantidas em `bridge.dart` e `core.h`.
- Eventos, comandos e respostas são serializados/deserializados.

### Drivers
- Cada protocolo tem um driver dedicado (BLE, WiFi, Zigbee, MQTT).
- Drivers implementam descoberta, conexão, envio/recebimento de dados.
- Mock driver permite testes sem hardware.

### IA
- Modelos são implementados em C++ e Python.
- Tokenizer, Attention, FeedForward, MoE, Transformer, etc.
- Scripts Python para treinamento e inferência.
- Dados de vocabulário e comandos em `data/`.

### Persistência
- Flutter usa `SharedPreferences` para dados locais.
- Núcleo C++ pode salvar dados em arquivos ou sincronizar com UI.

---

## Workflows de Desenvolvimento

- **Build nativo:** `cd lib/core && ./build.sh`
- **Dependências Flutter:** `flutter pub get`
- **Rodar app:** `flutter run -d linux --target lib/ui/main.dart`
- **Testes e análise:** `flutter analyze`, `flutter test`
- **Treinamento IA:** `python3 lib/ai/models/train_and_export.py`

---

## Convenções e Padrões

- Docblocks em todos os arquivos (`@file`, `@brief`, etc.).
- Nomes de enums e constantes respeitam os originais do núcleo.
- Não bypassar o Bridge para chamadas nativas.
- Campos de schema dos assets mantidos conforme original.

---

## Segurança e Extensibilidade

- Drivers isolados por protocolo.
- Interface FFI centralizada.
- Scripts Python podem ser atualizados sem recompilar o núcleo.
- UI modular e fácil de expandir.

---

## Referências dos Arquivos Críticos

- `lib/ui/bridge.dart`: Contrato FFI, orquestração de dispositivos e IA.
- `lib/core/include/core.h` e `lib/core/src/core.cpp`: API nativa.
- `lib/ui/manage.dart`: Registro e descoberta de dispositivos.
- `lib/ui/assistant.dart`: UX do assistente e telemetria.
- `lib/ai/src/chatModelRuntime.cpp` e `lib/ai/models/chatInferenceCli.py`: Fronteira de inferência Python.

---

## Exemplos de Fluxo

### Registro de Dispositivo
1. Usuário seleciona template na UI.
2. UI chama `Bridge.registerDevice()`.
3. Núcleo C++ registra e retorna status.
4. UI exibe resultado.

### Comando de Assistente
1. Usuário envia comando.
2. UI chama `Bridge.aiExecuteCommandAsync()`.
3. Núcleo C++ aciona script Python.
4. Resultado é retornado e exibido.

---

## FAQ Técnico

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

---

## Contato e Contribuição

- Documentação e exemplos em `docs/`.
- Siga os padrões de docblock e arquitetura.
- Pull requests e sugestões são bem-vindos.

---

_EaSync: Automação residencial inteligente, modular e extensível._
