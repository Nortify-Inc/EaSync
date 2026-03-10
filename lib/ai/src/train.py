import json
import random
import os
from collections import defaultdict

import sentencepiece as spm
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from torch.optim import AdamW

from SGLM import SGLM


datasetPath = "../data/interactions.json"
corpusPath = "../data/corpus.txt"
tokenizerPrefix = "../data/tokenizer"

vocabSize = 2658
seqLen = 64
generatedConversations = 10000

batchSize = 32
epochs = 20

import os
if os.environ.get("TRAIN_EPOCHS"):
    try:
        epochs = int(os.environ.get("TRAIN_EPOCHS"))
    except Exception:
        pass
lr = 3e-4


def loadDataset(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def filterDataset(dataset, min_user_len=3, dedup=True):
    """Filter out trivial or duplicate entries and normalize spacing.

    - remove pairs where user text is too short (e.g. single-word greetings)
    - deduplicate exact pairs
    - normalize whitespace
    """
    seen = set()
    out = []
    for rec in dataset:
        u = rec.get("user", "").strip()
        a = rec.get("agent", "").strip()
        # normalize spaces
        u = " ".join(u.split())
        a = " ".join(a.split())
        if len(u) < min_user_len:
            continue
        # filter trivial one-word greetings
        low = u.lower()
        if low in ("hi", "hello", "hey", "bye", "thanks", "morning", "evening", "goodbye"):
            continue
        key = (u, a)
        if dedup and key in seen:
            continue
        seen.add(key)
        out.append({"user": u, "agent": a})
    return out


def detectTopic(text):

    t = text.lower()

    if "hello" in t or "hi" in t:
        return "greeting"

    if "how are" in t:
        return "smalltalk"

    if "joke" in t:
        return "humor"

    return "other"


def groupByTopic(dataset):

    topics = defaultdict(list)

    for s in dataset:
        topic = detectTopic(s["user"])
        topics[topic].append(s)

    return topics


def maybeParaphrase(text):

    variants = {
        "hello": ["hello", "hi", "hey"],
        "how are you": ["how are you", "how are you doing", "how are things"]
    }

    if random.random() > 0.3:
        return text

    t = text.lower()

    for k in variants:
        if k in t:
            return random.choice(variants[k])

    return text


def buildMultiTurn(topicGroup, maxTurns=3):

    turns = random.randint(2, maxTurns)

    samples = random.sample(topicGroup, min(turns, len(topicGroup)))

    conversation = []

    for s in samples:

        user = maybeParaphrase(s["user"].strip())
        agent = maybeParaphrase(s["agent"].strip())

        conversation.append(f"user: {user}")
        conversation.append(f"assistant: {agent}")

    return conversation


def formatConversation(conversation):

    text = "<bos>"

    for i, turn in enumerate(conversation):

        if i > 0:
            text += "<sep>"

        text += turn

    text += "<eos>"

    return text


def generateCorpus(dataset, samples):
    topics = groupByTopic(dataset)
    topicKeys = list(topics.keys())

    texts = []

    # ensure at least some variety: sample across topics with weighted sampling
    weights = {}
    for k in topicKeys:
        # favor less-represented topics slightly to improve coverage
        weights[k] = 1.0 / max(1, len(topics[k]))
    total_w = sum(weights.values())
    for k in weights:
        weights[k] /= total_w

    for _ in range(samples):
        topic = random.choices(topicKeys, weights=[weights[k] for k in topicKeys], k=1)[0]
        conv = buildMultiTurn(topics[topic], maxTurns=4)

        # occasionally inject a short clarification or follow-up to increase dialogue depth
        if random.random() < 0.15:
            conv.append(f"user: Could you clarify that?")
            conv.append(f"assistant: Sure — what would you like me to explain?")

        # format and add
        formatted = formatConversation(conv)
        texts.append(formatted)

    return texts


def saveCorpus(texts, path):

    os.makedirs(os.path.dirname(path), exist_ok=True)

    with open(path, "w", encoding="utf-8") as f:
        for t in texts:
            f.write(t + "\n")


def trainTokenizer():

    os.makedirs(os.path.dirname(tokenizerPrefix), exist_ok=True)

    spm.SentencePieceTrainer.train(
        input=corpusPath,
        model_prefix=tokenizerPrefix,
        vocab_size=vocabSize,
        model_type="unigram",
        character_coverage=1.0,
        hard_vocab_limit=False,
        unk_id=0,
        bos_id=1,
        eos_id=2,
        pad_id=3,
        user_defined_symbols=["<bos>", "<sep>", "<eos>"]
    )


def loadTokenizer():

    modelPath = os.path.abspath(tokenizerPrefix + ".model")

    if not os.path.exists(modelPath):
        raise FileNotFoundError(f"Tokenizer model not found: {modelPath}")

    tokenizer = spm.SentencePieceProcessor()

    ok = tokenizer.load(modelPath)

    if not ok:
        raise RuntimeError("Failed to load tokenizer")

    return tokenizer


class ChatDataset(Dataset):

    def __init__(self, texts, tokenizer, seqLen):

        self.samples = []

        padId = tokenizer.pad_id()

        for text in texts:

            tokens = tokenizer.encode(text)

            if len(tokens) < seqLen + 1:
                tokens = tokens + [padId] * (seqLen + 1 - len(tokens))

            for i in range(0, len(tokens) - seqLen):

                x = tokens[i:i + seqLen]
                y = tokens[i + 1:i + seqLen + 1]

                self.samples.append(
                    (
                        torch.tensor(x, dtype=torch.long),
                        torch.tensor(y, dtype=torch.long)
                    )
                )

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        return self.samples[idx]


def trainModel(loader, tokenizer):

    device = torch.device("cpu")

    model = SGLM(
        vocabSize=vocabSize,
        dim=256,
        layers=6,
        heads=8,
        kvHeads=2,
    ).to(device)

    optimizer = AdamW(model.parameters(), lr=lr, weight_decay=0.01)

    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer,
        T_max=epochs
    )

    padId = tokenizer.pad_id()

    criterion = nn.CrossEntropyLoss(ignore_index=padId)

    for epoch in range(epochs):

        model.train()
        totalLoss = 0

        for x, y in loader:

            x = x.to(device)
            y = y.to(device)

            optimizer.zero_grad()

            logits = model(x)

            loss = criterion(
                logits.view(-1, logits.size(-1)),
                y.view(-1)
            )

            loss.backward()

            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)

            optimizer.step()

            totalLoss += loss.item()

        scheduler.step()

        avgLoss = totalLoss / len(loader)

        print(f"epoch {epoch+1} loss {avgLoss:.4f}")

        torch.save(model.state_dict(), "../data/sglm_model.pt")


def fineTuneModel(loader, tokenizer, checkpoint_path="../data/sglm_model.pt", finetune_epochs=2, finetune_lr=5e-5, save_path="../data/sglm_finetuned.pt", label_smoothing=0.1):

    device = torch.device("cpu")

    model = SGLM(
        vocabSize=vocabSize,
        dim=256,
        layers=6,
        heads=8,
        kvHeads=2,
    ).to(device)

    # try to load existing checkpoint and adapt embeddings if vocab differs
    if os.path.exists(checkpoint_path):
        try:
            ck = torch.load(checkpoint_path, map_location=device)
            if isinstance(ck, dict) and not any(k.startswith('tokenEmb') for k in ck.keys()):
                # some checkpoints stored as nested dicts
                for k in ('model_state', 'state_dict', 'model', 'model_state_dict'):
                    if k in ck:
                        ck = ck[k]
                        break
            model_state = model.state_dict()
            new_state = {}
            for kk, vv in (ck.items() if isinstance(ck, dict) else []):
                if kk in model_state:
                    if vv.shape == model_state[kk].shape:
                        new_state[kk] = vv
                    else:
                        # prefix-copy embeddings/heads
                        if kk in ("tokenEmb.weight", "head.weight") and vv.dim() >= 2:
                            min0 = min(vv.shape[0], model_state[kk].shape[0])
                            tmp = model_state[kk].clone()
                            tmp[:min0] = vv[:min0]
                            new_state[kk] = tmp
                        else:
                            # skip incompatible
                            pass
            for kk in model_state:
                if kk not in new_state:
                    new_state[kk] = model_state[kk]
            model.load_state_dict(new_state)
            print("Loaded and adapted checkpoint for fine-tune.")
        except Exception as e:
            print("Failed to load checkpoint for fine-tune, training from scratch:", e)

    optimizer = AdamW(model.parameters(), lr=finetune_lr, weight_decay=0.01)

    criterion = nn.CrossEntropyLoss(ignore_index=tokenizer.pad_id(), label_smoothing=label_smoothing)

    for epoch in range(finetune_epochs):
        model.train()
        totalLoss = 0.0
        for x, y in loader:
            x = x.to(device)
            y = y.to(device)
            optimizer.zero_grad()
            logits = model(x)
            loss = criterion(logits.view(-1, logits.size(-1)), y.view(-1))
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            totalLoss += loss.item()
        avg = totalLoss / max(1, len(loader))
        print(f"finetune epoch {epoch+1}/{finetune_epochs} loss {avg:.4f}")
        torch.save(model.state_dict(), save_path)



def main():

    print("loading dataset")
    dataset = loadDataset(datasetPath)
    print("filtering dataset")
    dataset = filterDataset(dataset)

    print("generating conversations")
    texts = generateCorpus(dataset, generatedConversations)

    print("saving corpus")
    saveCorpus(texts, corpusPath)

    if not os.path.exists(tokenizerPrefix + ".model"):
        print("training tokenizer")
        trainTokenizer()

    print("loading tokenizer")
    tokenizer = loadTokenizer()

    print("building torch dataset")
    torchDataset = ChatDataset(texts, tokenizer, seqLen)

    loader = DataLoader(torchDataset, batch_size=batchSize, shuffle=True)

    print("dataset size:", len(torchDataset))

    trainModel(loader, tokenizer)

if __name__ == "__main__":
    main()