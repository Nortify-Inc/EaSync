# EaSync — Documentação de Arquitetura (Completa, Didática e Profunda)

---

## 1. Visão Geral

EaSync é uma plataforma de automação residencial inteligente, modular e multiplataforma. O projeto une uma interface Flutter moderna, um núcleo nativo C++ robusto e módulos de IA para controle, automação, aprendizado de padrões e assistente virtual. O foco é flexibilidade, segurança, extensibilidade e facilidade de integração.

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
- **lib/ai/**: IA, modelos, scripts de treinamento, vocabulário.
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
- Núcleo C++ pode acionar scripts Python para inferência (`chatInferenceCli.py`).
- Resultados são retornados ao Flutter e exibidos ao usuário.

#### Exemplo de comando:
> "Acenda a luz da sala e ajuste para 50% de brilho"

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
- **chatModelRuntime.cpp**: Motor de inferência.
- **models/**: Tokenizer, attention, feedforward, MoE, transformer, etc.
- **train_and_export.py**: Treinamento e exportação de modelos.
- **chatInferenceCli.py**: Script Python para inferência.
- **data/**: Vocabulário, comandos, interações.

#### Exemplo de fluxo IA:
1. Usuário envia comando de voz.
2. UI chama Bridge → núcleo C++ → script Python.
3. Script Python processa, retorna resposta.
4. UI exibe resultado.

#### Modelos:
- **tokenizer.cpp/hpp**: Tokenização de texto.
- **attention.cpp/hpp**: Mecanismo de atenção.
- **feedForward.cpp/hpp**: Camada feedforward.
- **moe.cpp/hpp**: Mixture of Experts.
- **transformer.cpp/hpp**: Modelo transformer.

#### Scripts:
- **train_and_export.py**: Treinamento de modelos.
- **datasetCleaner.cpp**: Limpeza de datasets.
- **buildVocab.cpp**: Construção de vocabulário.

---

## 5. FFI (Dart ↔ C++)

- O `Bridge` centraliza todas as chamadas entre Dart e C++.
- Assinaturas FFI são mantidas em `bridge.dart` e `core.h`.
- Eventos, comandos e respostas são serializados/deserializados.
- Compatibilidade garantida por enums, structs e contratos.

#### Exemplo de assinatura FFI:
- `Bridge.registerDevice()` → C++: `core_register_device()`
- `Bridge.aiExecuteCommandAsync()` → C++: `core_ai_execute_command_async()`

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

## 11. Referências dos Arquivos Críticos

- `lib/ui/bridge.dart`: Contrato FFI, orquestração de dispositivos e IA.
- `lib/core/include/core.h` e `lib/core/src/core.cpp`: API nativa.
- `lib/ui/manage.dart`: Registro e descoberta de dispositivos.
- `lib/ui/assistant.dart`: UX do assistente e telemetria.
- `lib/ai/src/chatModelRuntime.cpp` e `lib/ai/models/chatInferenceCli.py`: Fronteira de inferência Python.

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
