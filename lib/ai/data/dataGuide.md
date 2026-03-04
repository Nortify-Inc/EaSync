# AI Data Guide

Current canonical dataset files (camelCase):

- `chatUnderstandingDataset.jsonl` (NLU + command composition + humanized replies)
- `behaviorPatternDataset.jsonl` (usage sequence/pattern inference)

Generator:

- `generateAiDatasets.py`

Model training scripts (hardcoded, no pretrained):

- `../models/chatModel.py`
- `../models/patternsModel.py`

## Dataset scope

### 1) chatUnderstandingDataset.jsonl

Focus:

- intent detection (`greeting`, `gratitude`, `smalltalk`, `farewell`, `listDevices`, `listOnline`, `queryStatus`, `controlDevice`, `applyProfile`, `ambiguous`)
- entity extraction (`deviceHint`, `capability`, `value`)
- canonical action plan (`canonicalActions`)
- mixed language support (EN + PT)
- robust chat variants (typos, colloquial phrases, short forms, multi-action commands)

### 2) behaviorPatternDataset.jsonl

Focus:

- temporal behavior learning from event sequences
- next likely routine/action prediction
- preference targets (temperature, brightness, curtain position, color temperature)
- context-aware patterns (day/hour/weather/occupancy/holiday)

## Regenerate datasets

Run:

`/usr/bin/python lib/ai/data/generateAiDatasets.py`

Default sizes in generator:

- chatUnderstandingDataset: 50,000
- behaviorPatternDataset: 70,000

You can increase sizes by editing `target_size` defaults in the generator.

## Train models

Chat model:

`/usr/bin/python lib/ai/models/chatModel.py`

Patterns model:

`/usr/bin/python lib/ai/models/patternsModel.py`
