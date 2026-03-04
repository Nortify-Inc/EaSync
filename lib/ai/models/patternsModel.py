#!/usr/bin/env python3
"""PyTorch behavior patterns model.

Dataset:
  lib/ai/data/behaviorPatternDataset.jsonl

Artifacts:
  lib/ai/models/artifacts/patterns/patternsModel.pt
  lib/ai/models/artifacts/patterns/patternMaps.json
"""

from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset


SEED = 73
random.seed(SEED)
torch.manual_seed(SEED)

ROOT = Path(__file__).resolve().parent
DATASET_PATH = ROOT.parent / "data" / "behaviorPatternDataset.jsonl"
ARTIFACT_DIR = ROOT / "artifacts" / "patterns"

MAX_HISTORY = 20
BATCH_SIZE = 128
EPOCHS = 36
EMBED_DIM = 96
HIDDEN_DIM = 160
LR = 8e-4

PAD = "<PAD>"
UNK = "<UNK>"

TARGET_KEYS = [
    "arrivalHour",
    "wakeHour",
    "sleepHour",
    "preferredTemperature",
    "preferredBrightness",
    "preferredCurtainPosition",
    "preferredColorTemperature",
]

TARGET_SCALES = {
    "arrivalHour": 23.0,
    "wakeHour": 23.0,
    "sleepHour": 23.0,
    "preferredTemperature": 35.0,
    "preferredBrightness": 100.0,
    "preferredCurtainPosition": 100.0,
    "preferredColorTemperature": 9000.0,
}


@dataclass
class PatternRow:
    context_day: str
    context_weather: str
    context_occupancy: str
    context_routine: str
    context_hour: float
    context_outside_temp: float
    context_is_holiday: float
    history_tokens: list[str]
    next_action: str
    targets: list[float]


def _event_to_token(ev: dict[str, Any]) -> str:
    return "|".join(
        [
            str(ev.get("device", "unknown")),
            str(ev.get("capability", "unknown")),
            str(ev.get("action", "unknown")),
        ]
    )


def load_rows(path: Path) -> list[PatternRow]:
    rows: list[PatternRow] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            raw = json.loads(line)
            context = raw.get("context") or {}
            hist = raw.get("history") or []
            label = raw.get("label") or {}
            ptargets = raw.get("patternTargets") or {}

            history_tokens = [_event_to_token(ev) for ev in hist][-MAX_HISTORY:]
            while len(history_tokens) < MAX_HISTORY:
                history_tokens.append(PAD)

            targets = [
                float(ptargets.get(k, 0.0)) / TARGET_SCALES[k]
                for k in TARGET_KEYS
            ]

            rows.append(
                PatternRow(
                    context_day=str(context.get("dayOfWeek", "unknown")),
                    context_weather=str(context.get("weather", "unknown")),
                    context_occupancy=str(context.get("occupancy", "unknown")),
                    context_routine=str(context.get("routineHint", "unknown")),
                    context_hour=float(context.get("hour", 0.0)),
                    context_outside_temp=float(context.get("outsideTemp", 0.0)),
                    context_is_holiday=1.0 if bool(context.get("isHoliday", False)) else 0.0,
                    history_tokens=history_tokens,
                    next_action=str(label.get("nextAction", "unknown")),
                    targets=targets,
                )
            )
    return rows


def _index_map(values: list[str]) -> tuple[dict[str, int], dict[int, str]]:
    uniq = sorted(set(values))
    to_idx = {v: i for i, v in enumerate(uniq)}
    from_idx = {i: v for v, i in to_idx.items()}
    return to_idx, from_idx


def _build_history_vocab(rows: list[PatternRow]) -> dict[str, int]:
    vocab = {PAD: 0, UNK: 1}
    for r in rows:
        for tok in r.history_tokens:
            if tok not in vocab:
                vocab[tok] = len(vocab)
    return vocab


class PatternDataset(Dataset):
    def __init__(
        self,
        rows: list[PatternRow],
        history_vocab: dict[str, int],
        day_map: dict[str, int],
        weather_map: dict[str, int],
        occupancy_map: dict[str, int],
        routine_map: dict[str, int],
        action_map: dict[str, int],
    ):
        self.hist = torch.tensor(
            [
                [history_vocab.get(tok, history_vocab[UNK]) for tok in r.history_tokens]
                for r in rows
            ],
            dtype=torch.long,
        )
        self.day = torch.tensor([day_map[r.context_day] for r in rows], dtype=torch.long)
        self.weather = torch.tensor([weather_map[r.context_weather] for r in rows], dtype=torch.long)
        self.occupancy = torch.tensor([occupancy_map[r.context_occupancy] for r in rows], dtype=torch.long)
        self.routine = torch.tensor([routine_map[r.context_routine] for r in rows], dtype=torch.long)
        self.numeric = torch.tensor(
            [[r.context_hour / 23.0, r.context_outside_temp / 50.0, r.context_is_holiday] for r in rows],
            dtype=torch.float32,
        )
        self.y_action = torch.tensor([action_map[r.next_action] for r in rows], dtype=torch.long)
        self.y_targets = torch.tensor([r.targets for r in rows], dtype=torch.float32)

    def __len__(self) -> int:
        return self.hist.size(0)

    def __getitem__(self, idx: int):
        return (
            self.hist[idx],
            self.day[idx],
            self.weather[idx],
            self.occupancy[idx],
            self.routine[idx],
            self.numeric[idx],
            self.y_action[idx],
            self.y_targets[idx],
        )


class PatternsModel(nn.Module):
    def __init__(
        self,
        history_vocab_size: int,
        day_classes: int,
        weather_classes: int,
        occupancy_classes: int,
        routine_classes: int,
        action_classes: int,
        target_dims: int,
    ):
        super().__init__()
        self.hist_embed = nn.Embedding(history_vocab_size, EMBED_DIM, padding_idx=0)
        self.hist_lstm = nn.LSTM(
            input_size=EMBED_DIM,
            hidden_size=HIDDEN_DIM,
            num_layers=1,
            batch_first=True,
            bidirectional=True,
        )

        self.day_embed = nn.Embedding(day_classes, 16)
        self.weather_embed = nn.Embedding(weather_classes, 16)
        self.occupancy_embed = nn.Embedding(occupancy_classes, 16)
        self.routine_embed = nn.Embedding(routine_classes, 16)

        fused_dim = (HIDDEN_DIM * 2) + 16 + 16 + 16 + 16 + 3
        self.shared = nn.Linear(fused_dim, 160)
        self.dropout = nn.Dropout(0.30)

        self.action_head = nn.Linear(160, action_classes)
        self.targets_head = nn.Linear(160, target_dims)

    def forward(
        self,
        hist: torch.Tensor,
        day: torch.Tensor,
        weather: torch.Tensor,
        occupancy: torch.Tensor,
        routine: torch.Tensor,
        numeric: torch.Tensor,
    ):
        h = self.hist_embed(hist)
        h, _ = self.hist_lstm(h)
        h_last = h[:, -1, :]

        d = self.day_embed(day)
        w = self.weather_embed(weather)
        o = self.occupancy_embed(occupancy)
        r = self.routine_embed(routine)

        fused = torch.cat([h_last, d, w, o, r, numeric], dim=1)
        x = self.dropout(torch.relu(self.shared(fused)))

        action_logits = self.action_head(x)
        target_values = self.targets_head(x)
        return action_logits, target_values


def _split(rows: list[PatternRow]) -> tuple[list[PatternRow], list[PatternRow]]:
    idx = list(range(len(rows)))
    random.shuffle(idx)
    cut = int(0.85 * len(idx))
    train_rows = [rows[i] for i in idx[:cut]]
    val_rows = [rows[i] for i in idx[cut:]]
    return train_rows, val_rows


def _acc(logits: torch.Tensor, y: torch.Tensor) -> float:
    pred = torch.argmax(logits, dim=1)
    return (pred == y).float().mean().item()


def train() -> None:
    rows = load_rows(DATASET_PATH)
    if not rows:
        raise RuntimeError(f"Dataset is empty: {DATASET_PATH}")

    train_rows, val_rows = _split(rows)

    history_vocab = _build_history_vocab(rows)
    day_map, idx_day = _index_map([r.context_day for r in rows])
    weather_map, idx_weather = _index_map([r.context_weather for r in rows])
    occupancy_map, idx_occupancy = _index_map([r.context_occupancy for r in rows])
    routine_map, idx_routine = _index_map([r.context_routine for r in rows])
    action_map, idx_action = _index_map([r.next_action for r in rows])

    train_ds = PatternDataset(
        train_rows,
        history_vocab,
        day_map,
        weather_map,
        occupancy_map,
        routine_map,
        action_map,
    )
    val_ds = PatternDataset(
        val_rows,
        history_vocab,
        day_map,
        weather_map,
        occupancy_map,
        routine_map,
        action_map,
    )

    train_dl = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True)
    val_dl = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False)

    device = torch.device("cpu")

    model = PatternsModel(
        history_vocab_size=len(history_vocab),
        day_classes=len(day_map),
        weather_classes=len(weather_map),
        occupancy_classes=len(occupancy_map),
        routine_classes=len(routine_map),
        action_classes=len(action_map),
        target_dims=len(TARGET_KEYS),
    ).to(device)

    opt = torch.optim.Adam(model.parameters(), lr=LR)

    best_val_action = 0.0
    best_state = None
    patience = 0

    for epoch in range(1, EPOCHS + 1):
        model.train()
        loss_sum = 0.0
        steps = 0
        for hist, day, weather, occupancy, routine, numeric, y_action, y_targets in train_dl:
            hist = hist.to(device)
            day = day.to(device)
            weather = weather.to(device)
            occupancy = occupancy.to(device)
            routine = routine.to(device)
            numeric = numeric.to(device)
            y_action = y_action.to(device)
            y_targets = y_targets.to(device)

            action_logits, target_values = model(hist, day, weather, occupancy, routine, numeric)
            loss_action = F.cross_entropy(action_logits, y_action)
            loss_targets = F.mse_loss(target_values, y_targets)
            loss = loss_action + 0.05 * loss_targets

            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()

            loss_sum += loss.item()
            steps += 1

        model.eval()
        val_action_acc = 0.0
        val_target_mse = 0.0
        n_batches = 0
        with torch.no_grad():
            for hist, day, weather, occupancy, routine, numeric, y_action, y_targets in val_dl:
                hist = hist.to(device)
                day = day.to(device)
                weather = weather.to(device)
                occupancy = occupancy.to(device)
                routine = routine.to(device)
                numeric = numeric.to(device)
                y_action = y_action.to(device)
                y_targets = y_targets.to(device)

                action_logits, target_values = model(hist, day, weather, occupancy, routine, numeric)
                val_action_acc += _acc(action_logits, y_action)
                val_target_mse += F.mse_loss(target_values, y_targets).item()
                n_batches += 1

        val_action_acc /= max(1, n_batches)
        val_target_mse /= max(1, n_batches)

        print(
            f"Epoch {epoch}/{EPOCHS} "
            f"loss={loss_sum/max(1, steps):.4f} "
            f"val(actionAcc/mse)={val_action_acc:.4f}/{val_target_mse:.4f}"
        )

        if val_action_acc > best_val_action:
            best_val_action = val_action_acc
            best_state = {k: v.detach().cpu() for k, v in model.state_dict().items()}
            patience = 0
        else:
            patience += 1
            if patience >= 8:
                print("Early stopping triggered.")
                break

    if best_state is not None:
        model.load_state_dict(best_state)

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), ARTIFACT_DIR / "patternsModel.pt")

    maps = {
        "historyVocab": history_vocab,
        "dayToIndex": day_map,
        "weatherToIndex": weather_map,
        "occupancyToIndex": occupancy_map,
        "routineToIndex": routine_map,
        "actionToIndex": action_map,
        "indexToAction": {str(k): v for k, v in idx_action.items()},
        "targetKeys": TARGET_KEYS,
        "targetScales": TARGET_SCALES,
        "maxHistory": MAX_HISTORY,
        "embedDim": EMBED_DIM,
        "hiddenDim": HIDDEN_DIM,
    }
    with (ARTIFACT_DIR / "patternMaps.json").open("w", encoding="utf-8") as f:
        json.dump(maps, f, ensure_ascii=False, indent=2)

    print(f"Saved patterns model artifacts to: {ARTIFACT_DIR}")


if __name__ == "__main__":
    train()
