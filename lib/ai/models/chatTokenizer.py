from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

SPECIAL_TOKENS = ["<PAD>", "<UNK>", "<BOS>", "<EOS>"]
PAD, UNK, BOS, EOS = SPECIAL_TOKENS


class ChatTokenizer:
    def __init__(self, tokenToIndex: dict[str, int]):
        self.tokenToIndex = tokenToIndex
        self.indexToToken = {v: k for k, v in tokenToIndex.items()}

    @staticmethod
    def tokenize(text: str) -> list[str]:
        return re.findall(r"[\w#:+./-]+|[!?.,;:]", text.lower(), flags=re.UNICODE)

    @classmethod
    def build(cls, texts: list[str], maxVocab: int = 90000, minFreq: int = 2) -> "ChatTokenizer":
        counter: Counter[str] = Counter()
        for text in texts:
            counter.update(cls.tokenize(text))

        vocab = list(SPECIAL_TOKENS)
        for token, freq in counter.most_common():
            if freq < minFreq:
                continue
            if token in SPECIAL_TOKENS:
                continue
            vocab.append(token)
            if len(vocab) >= maxVocab:
                break

        tokenToIndex = {token: idx for idx, token in enumerate(vocab)}
        return cls(tokenToIndex)

    def encode(self, text: str, maxLen: int, addBosEos: bool = False) -> list[int]:
        ids = [self.tokenToIndex.get(t, self.tokenToIndex[UNK]) for t in self.tokenize(text)]
        if addBosEos:
            ids = [self.tokenToIndex[BOS]] + ids + [self.tokenToIndex[EOS]]

        if len(ids) < maxLen:
            ids += [self.tokenToIndex[PAD]] * (maxLen - len(ids))
        return ids[:maxLen]

    def decode(self, ids: list[int]) -> str:
        tokens: list[str] = []
        for idx in ids:
            token = self.indexToToken.get(int(idx), UNK)
            if token in {PAD, BOS, EOS}:
                continue
            tokens.append(token)
        text = " ".join(tokens)
        text = re.sub(r"\s+([!?.,;:])", r"\1", text)
        return text.strip()

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8") as f:
            json.dump(self.tokenToIndex, f, ensure_ascii=False, indent=2)

    @classmethod
    def load(cls, path: Path) -> "ChatTokenizer":
        with path.open("r", encoding="utf-8") as f:
            tokenToIndex = json.load(f)
        return cls({str(k): int(v) for k, v in tokenToIndex.items()})
