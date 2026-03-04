#!/usr/bin/env python3
"""PyTorch chat model training.

Dataset:
  lib/ai/data/chatUnderstandingDataset.jsonl

Artifacts:
  lib/ai/models/artifacts/chat/chatModel.pt
  lib/ai/models/artifacts/chat/vocab.json
  lib/ai/models/artifacts/chat/labelMaps.json
"""

from __future__ import annotations

import json
import random
import re
import hashlib
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
DATASET_PATH = ROOT.parent / "data" / "chatUnderstandingDataset.jsonl"
ARTIFACT_DIR = ROOT / "artifacts" / "chat"

MAX_LEN = 40
MAX_RESP_LEN = 36
BATCH_SIZE = 96
EPOCHS = 14
EMBED_DIM = 128
HIDDEN_DIM = 160
LR = 9e-4

PAD = "<PAD>"
UNK = "<UNK>"
BOS = "<BOS>"
EOS = "<EOS>"


@dataclass
class ChatRow:
    text: str
    intent: str
    response_style: str
    action_capability: str
    action_operation: str
    target_response: str


def _tokenize(text: str) -> list[str]:
    return re.findall(r"[a-zA-Z0-9_#:+-]+", text.lower())


def _safe_action_fields(row: dict[str, Any]) -> tuple[str, str]:
    actions = row.get("canonicalActions") or []
    if not actions:
        return "none", "none"
    a0 = actions[0] if isinstance(actions[0], dict) else {}
    capability = str(a0.get("capability") or "none")
    operation = str(a0.get("operation") or "none")
    return capability, operation


def load_rows(path: Path) -> list[ChatRow]:
    rows: list[ChatRow] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            raw = json.loads(line)
            cap, op = _safe_action_fields(raw)
            rows.append(
                ChatRow(
                    text=str(raw.get("text", "")).strip(),
                    intent=str(raw.get("intent", "unknown")),
                    response_style=str(raw.get("responseStyle", "helpful")),
                    action_capability=cap,
                    action_operation=op,
                    target_response=str(raw.get("targetResponse", "")).strip(),
                )
            )
    return rows


def build_vocab(texts: list[str], min_freq: int = 1) -> dict[str, int]:
    freq: dict[str, int] = {}
    for t in texts:
        for tok in _tokenize(t):
            freq[tok] = freq.get(tok, 0) + 1

    vocab = {PAD: 0, UNK: 1, BOS: 2, EOS: 3}
    for tok, c in sorted(freq.items()):
        if c >= min_freq:
            if tok not in vocab:
                vocab[tok] = len(vocab)
    return vocab


def encode_text(text: str, vocab: dict[str, int]) -> list[int]:
    ids = [vocab.get(tok, vocab[UNK]) for tok in _tokenize(text)]
    if len(ids) < MAX_LEN:
        ids.extend([vocab[PAD]] * (MAX_LEN - len(ids)))
    return ids[:MAX_LEN]


def encode_response_inputs(text: str, vocab: dict[str, int]) -> tuple[list[int], list[int], int]:
    tokens = [BOS] + _tokenize(text) + [EOS]
    ids = [vocab.get(tok, vocab[UNK]) for tok in tokens]
    if len(ids) < 2:
        ids = [vocab[BOS], vocab[EOS]]

    inp = ids[:-1]
    out = ids[1:]
    length = max(1, min(MAX_RESP_LEN, len(inp)))
    inp = inp[:MAX_RESP_LEN]
    out = out[:MAX_RESP_LEN]

    if len(inp) < MAX_RESP_LEN:
        pad_n = MAX_RESP_LEN - len(inp)
        inp.extend([vocab[PAD]] * pad_n)
        out.extend([vocab[PAD]] * pad_n)

    return inp, out, length


def build_label_map(values: list[str]) -> tuple[dict[str, int], dict[int, str]]:
    uniq = sorted(set(values))
    to_idx = {v: i for i, v in enumerate(uniq)}
    from_idx = {i: v for v, i in to_idx.items()}
    return to_idx, from_idx


class ChatDataset(Dataset):
    def __init__(
        self,
        rows: list[ChatRow],
        vocab: dict[str, int],
        intent_map: dict[str, int],
        style_map: dict[str, int],
        cap_map: dict[str, int],
        op_map: dict[str, int],
        is_train: bool = False,
    ):
        self.vocab = vocab
        self.is_train = is_train
        encoded = [encode_text(r.text, vocab) for r in rows]
        self.x = torch.tensor(encoded, dtype=torch.long)
        self.lengths = torch.tensor(
            [max(1, min(MAX_LEN, len(_tokenize(r.text)))) for r in rows],
            dtype=torch.long,
        )
        self.y_intent = torch.tensor([intent_map[r.intent] for r in rows], dtype=torch.long)
        self.y_style = torch.tensor([style_map[r.response_style] for r in rows], dtype=torch.long)
        self.y_cap = torch.tensor([cap_map[r.action_capability] for r in rows], dtype=torch.long)
        self.y_op = torch.tensor([op_map[r.action_operation] for r in rows], dtype=torch.long)
        resp = [encode_response_inputs(r.target_response, vocab) for r in rows]
        self.y_resp_in = torch.tensor([x[0] for x in resp], dtype=torch.long)
        self.y_resp_out = torch.tensor([x[1] for x in resp], dtype=torch.long)
        self.y_resp_len = torch.tensor([x[2] for x in resp], dtype=torch.long)

    def __len__(self) -> int:
        return self.x.size(0)

    def __getitem__(self, idx: int):
        x = self.x[idx].clone()
        if self.is_train:
            # Mild token-level noise to improve robustness.
            for i in range(x.size(0)):
                tok = int(x[i].item())
                if tok == self.vocab[PAD]:
                    break
                r = random.random()
                if r < 0.03:
                    x[i] = self.vocab[UNK]
                elif r < 0.04 and i + 1 < x.size(0) and int(x[i + 1].item()) != self.vocab[PAD]:
                    tmp = x[i].item()
                    x[i] = x[i + 1]
                    x[i + 1] = tmp

        return (
            x,
            self.lengths[idx],
            self.y_intent[idx],
            self.y_style[idx],
            self.y_cap[idx],
            self.y_op[idx],
            self.y_resp_in[idx],
            self.y_resp_out[idx],
            self.y_resp_len[idx],
        )


class MambaLiteBlock(nn.Module):
    def __init__(self, dim: int, state_dim: int = 64, conv_kernel: int = 3):
        super().__init__()
        self.norm = nn.LayerNorm(dim)
        self.in_proj = nn.Linear(dim, dim * 2)
        self.dw_conv = nn.Conv1d(
            in_channels=dim,
            out_channels=dim,
            kernel_size=conv_kernel,
            groups=dim,
            padding=conv_kernel // 2,
        )
        self.dt_proj = nn.Linear(dim, state_dim)
        self.b_proj = nn.Linear(dim, state_dim)
        self.c_proj = nn.Linear(dim, state_dim)
        self.a_log = nn.Parameter(torch.randn(state_dim) * 0.02)
        self.d = nn.Parameter(torch.ones(dim))
        self.out_proj = nn.Linear(dim + state_dim, dim)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: [B, T, D]
        residual = x
        x = self.norm(x)
        x_proj, z = self.in_proj(x).chunk(2, dim=-1)
        x_conv = self.dw_conv(x_proj.transpose(1, 2)).transpose(1, 2)
        x_conv = torch.tanh(x_conv)

        bsz, tlen, _ = x_conv.shape
        state_dim = self.a_log.shape[0]
        state = torch.zeros(bsz, state_dim, device=x.device, dtype=x.dtype)
        a = -torch.exp(self.a_log).unsqueeze(0)

        ys: list[torch.Tensor] = []
        for t in range(tlen):
            z_t = z[:, t, :]
            dt_t = F.softplus(self.dt_proj(z_t)) + 1e-4
            b_t = torch.tanh(self.b_proj(z_t))
            c_t = torch.tanh(self.c_proj(z_t))
            state = state * torch.exp(a * dt_t) + b_t
            y_t = c_t * state
            mix = torch.cat([x_conv[:, t, :] * self.d, y_t], dim=-1)
            ys.append(self.out_proj(mix))

        y = torch.stack(ys, dim=1)
        return residual + y


class ChatModel(nn.Module):
    def __init__(
        self,
        vocab_size: int,
        intent_classes: int,
        style_classes: int,
        cap_classes: int,
        op_classes: int,
    ):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, EMBED_DIM, padding_idx=0)
        self.embed_dropout = nn.Dropout(0.18)
        self.mamba1 = MambaLiteBlock(EMBED_DIM, state_dim=64)
        self.mamba2 = MambaLiteBlock(EMBED_DIM, state_dim=64)
        self.pool_norm = nn.LayerNorm(EMBED_DIM)
        self.dropout = nn.Dropout(0.28)
        self.shared = nn.Linear(EMBED_DIM, 128)

        self.intent_head = nn.Linear(128, intent_classes)
        self.style_head = nn.Linear(128, style_classes)
        self.cap_head = nn.Linear(128, cap_classes)
        self.op_head = nn.Linear(128, op_classes)

        self.decoder_embedding = nn.Embedding(vocab_size, EMBED_DIM, padding_idx=0)
        self.decoder_init = nn.Linear(128, HIDDEN_DIM)
        self.decoder = nn.GRU(
            input_size=EMBED_DIM,
            hidden_size=HIDDEN_DIM,
            num_layers=1,
            batch_first=True,
        )
        self.decoder_out = nn.Linear(HIDDEN_DIM, vocab_size)

    def forward(self, x: torch.Tensor, lengths: torch.Tensor, resp_in: torch.Tensor | None = None):
        emb = self.embed_dropout(self.embedding(x))
        h_seq = self.mamba1(emb)
        h_seq = self.mamba2(h_seq)

        max_len = h_seq.size(1)
        mask = (torch.arange(max_len, device=x.device).unsqueeze(0) < lengths.unsqueeze(1)).unsqueeze(-1)
        masked = h_seq * mask
        denom = lengths.clamp_min(1).unsqueeze(1).to(h_seq.dtype)
        pooled = masked.sum(dim=1) / denom

        h = self.pool_norm(pooled)
        h = self.dropout(torch.relu(self.shared(h)))
        out = {
            "intent": self.intent_head(h),
            "style": self.style_head(h),
            "capability": self.cap_head(h),
            "operation": self.op_head(h),
        }
        if resp_in is not None:
            dec_in = self.decoder_embedding(resp_in)
            h0 = torch.tanh(self.decoder_init(h)).unsqueeze(0)
            dec_out, _ = self.decoder(dec_in, h0)
            out["response_logits"] = self.decoder_out(dec_out)
        out["shared"] = h
        return out


def _generalization_key(text: str) -> str:
    q = text.lower().strip()
    q = re.sub(r"\b([01]?\d|2[0-3]):[0-5]\d\b", " <TIME> ", q)
    q = re.sub(r"#([0-9a-f]{6})\b", " <HEX> ", q)
    q = re.sub(r"\b-?\d+(?:\.\d+)?\b", " <NUM> ", q)
    q = re.sub(r"\s+", " ", q)
    return q


def _split(rows: list[ChatRow]) -> tuple[list[ChatRow], list[ChatRow]]:
    groups: dict[str, list[ChatRow]] = {}
    for r in rows:
        k = _generalization_key(r.text)
        groups.setdefault(k, []).append(r)

    keys = list(groups.keys())
    random.shuffle(keys)

    train_rows: list[ChatRow] = []
    val_rows: list[ChatRow] = []
    for k in keys:
        digest = hashlib.md5(k.encode("utf-8")).hexdigest()
        bucket = int(digest[:8], 16) % 100
        if bucket < 85:
            train_rows.extend(groups[k])
        else:
            val_rows.extend(groups[k])

    if not val_rows:
        cut = int(len(train_rows) * 0.1)
        val_rows = train_rows[:cut]
        train_rows = train_rows[cut:]

    return train_rows, val_rows


def _acc(logits: torch.Tensor, y: torch.Tensor) -> float:
    pred = torch.argmax(logits, dim=1)
    return (pred == y).float().mean().item()


def train() -> None:
    rows = load_rows(DATASET_PATH)
    if not rows:
        raise RuntimeError(f"Dataset is empty: {DATASET_PATH}")

    train_rows, val_rows = _split(rows)

    vocab = build_vocab([r.text for r in rows] + [r.target_response for r in rows])
    intent_map, idx_intent = build_label_map([r.intent for r in rows])
    style_map, idx_style = build_label_map([r.response_style for r in rows])
    cap_map, idx_cap = build_label_map([r.action_capability for r in rows])
    op_map, idx_op = build_label_map([r.action_operation for r in rows])

    train_ds = ChatDataset(train_rows, vocab, intent_map, style_map, cap_map, op_map, is_train=True)
    val_ds = ChatDataset(val_rows, vocab, intent_map, style_map, cap_map, op_map, is_train=False)

    train_dl = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True)
    val_dl = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False)

    device = torch.device("cpu")

    model = ChatModel(
        vocab_size=len(vocab),
        intent_classes=len(intent_map),
        style_classes=len(style_map),
        cap_classes=len(cap_map),
        op_classes=len(op_map),
    ).to(device)

    opt = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=2e-4)
    total_steps = max(1, EPOCHS * max(1, len(train_dl)))
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=total_steps, eta_min=LR * 0.2)

    best_score = 0.0
    best_state = None
    patience = 0

    for epoch in range(1, EPOCHS + 1):
        model.train()
        loss_sum = 0.0
        steps = 0
        for x, lengths, y_intent, y_style, y_cap, y_op, y_resp_in, y_resp_out, y_resp_len in train_dl:
            x = x.to(device)
            lengths = lengths.to(device)
            y_intent = y_intent.to(device)
            y_style = y_style.to(device)
            y_cap = y_cap.to(device)
            y_op = y_op.to(device)
            y_resp_in = y_resp_in.to(device)
            y_resp_out = y_resp_out.to(device)

            out = model(x, lengths, y_resp_in)
            resp_logits = out["response_logits"].reshape(-1, out["response_logits"].size(-1))
            resp_targets = y_resp_out.reshape(-1)
            loss = (
                F.cross_entropy(out["intent"], y_intent, label_smoothing=0.05)
                + F.cross_entropy(out["style"], y_style, label_smoothing=0.03)
                + F.cross_entropy(out["capability"], y_cap, label_smoothing=0.03)
                + F.cross_entropy(out["operation"], y_op, label_smoothing=0.03)
                + 0.45 * F.cross_entropy(resp_logits, resp_targets, ignore_index=vocab[PAD])
            )

            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            scheduler.step()

            loss_sum += loss.item()
            steps += 1

        model.eval()
        val_intent = 0.0
        val_style = 0.0
        val_cap = 0.0
        val_op = 0.0
        val_resp = 0.0
        n_batches = 0
        with torch.no_grad():
            for x, lengths, y_intent, y_style, y_cap, y_op, y_resp_in, y_resp_out, y_resp_len in val_dl:
                x = x.to(device)
                lengths = lengths.to(device)
                y_intent = y_intent.to(device)
                y_style = y_style.to(device)
                y_cap = y_cap.to(device)
                y_op = y_op.to(device)
                y_resp_in = y_resp_in.to(device)
                y_resp_out = y_resp_out.to(device)
                out = model(x, lengths, y_resp_in)

                val_intent += _acc(out["intent"], y_intent)
                val_style += _acc(out["style"], y_style)
                val_cap += _acc(out["capability"], y_cap)
                val_op += _acc(out["operation"], y_op)
                pred_resp = torch.argmax(out["response_logits"], dim=-1)
                mask = y_resp_out != vocab[PAD]
                if mask.any():
                    val_resp += (pred_resp[mask] == y_resp_out[mask]).float().mean().item()
                n_batches += 1

        val_intent /= max(1, n_batches)
        val_style /= max(1, n_batches)
        val_cap /= max(1, n_batches)
        val_op /= max(1, n_batches)
        val_resp /= max(1, n_batches)

        print(
            f"Epoch {epoch}/{EPOCHS} "
            f"loss={loss_sum/max(1, steps):.4f} "
            f"val(intent/style/cap/op/respTok)={val_intent:.4f}/{val_style:.4f}/{val_cap:.4f}/{val_op:.4f}/{val_resp:.4f}"
        )

        score = (0.38 * val_intent) + (0.22 * val_cap) + (0.18 * val_op) + (0.12 * val_style) + (0.10 * val_resp)
        if score > (best_score + 1e-4):
            best_score = score
            best_state = {k: v.detach().cpu() for k, v in model.state_dict().items()}
            patience = 0
        else:
            patience += 1
            if patience >= 4:
                print("Early stopping triggered.")
                break

    if best_state is not None:
        model.load_state_dict(best_state)

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), ARTIFACT_DIR / "chatModel.pt")

    with (ARTIFACT_DIR / "vocab.json").open("w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=2)

    label_maps = {
        "intentToIndex": intent_map,
        "styleToIndex": style_map,
        "capabilityToIndex": cap_map,
        "operationToIndex": op_map,
        "indexToIntent": {str(k): v for k, v in idx_intent.items()},
        "indexToStyle": {str(k): v for k, v in idx_style.items()},
        "indexToCapability": {str(k): v for k, v in idx_cap.items()},
        "indexToOperation": {str(k): v for k, v in idx_op.items()},
        "maxLen": MAX_LEN,
        "maxRespLen": MAX_RESP_LEN,
        "embedDim": EMBED_DIM,
        "hiddenDim": HIDDEN_DIM,
        "modelType": "mamba-lite-gru",
    }
    with (ARTIFACT_DIR / "labelMaps.json").open("w", encoding="utf-8") as f:
        json.dump(label_maps, f, ensure_ascii=False, indent=2)

    print(f"Saved chat model artifacts to: {ARTIFACT_DIR}")


def _extract_entities(text: str) -> dict[str, Any]:
    q = text.lower()
    entities: dict[str, Any] = {}

    m_num = re.search(r"-?\d{1,5}", q)
    if m_num:
        entities["numericValue"] = int(m_num.group(0))

    m_time = re.search(r"\b([01]?\d|2[0-3]):[0-5]\d\b", q)
    if m_time:
        entities["time"] = m_time.group(0)

    m_hex = re.search(r"#([0-9a-f]{6})\b", q)
    if m_hex:
        entities["hexColor"] = "#" + m_hex.group(1)

    return entities


def _load_for_inference():
    vocab_path = ARTIFACT_DIR / "vocab.json"
    maps_path = ARTIFACT_DIR / "labelMaps.json"
    weights_path = ARTIFACT_DIR / "chatModel.pt"

    if not vocab_path.exists():
        vocab_path = ROOT / "chatModelVocab.json"
    if not maps_path.exists():
        maps_path = ROOT / "chatModelLabelMaps.json"
    if not weights_path.exists():
        weights_path = ROOT / "chatModel.pth"

    with vocab_path.open("r", encoding="utf-8") as f:
        vocab = json.load(f)
    with maps_path.open("r", encoding="utf-8") as f:
        maps = json.load(f)

    model = ChatModel(
        vocab_size=len(vocab),
        intent_classes=len(maps["intentToIndex"]),
        style_classes=len(maps["styleToIndex"]),
        cap_classes=len(maps["capabilityToIndex"]),
        op_classes=len(maps["operationToIndex"]),
    )
    state = torch.load(weights_path, map_location="cpu")
    model.load_state_dict(state)
    model.eval()
    return model, vocab, maps


def predict_message(text: str) -> dict[str, Any]:
    model, vocab, maps = _load_for_inference()
    inv_vocab = {int(v): k for k, v in vocab.items()}
    x = torch.tensor([encode_text(text, vocab)], dtype=torch.long)
    lengths = torch.tensor([max(1, min(MAX_LEN, len(_tokenize(text))))], dtype=torch.long)
    with torch.no_grad():
        out = model(x, lengths)

    def pick(logits: torch.Tensor, index_to: dict[str, str]) -> str:
        i = int(torch.argmax(logits, dim=1).item())
        return index_to[str(i)]

    def confidence(logits: torch.Tensor) -> float:
        probs = torch.softmax(logits, dim=1)
        return float(torch.max(probs, dim=1).values.item())

    intent = pick(out["intent"], maps["indexToIntent"])
    style = pick(out["style"], maps["indexToStyle"])
    capability = pick(out["capability"], maps["indexToCapability"])
    operation = pick(out["operation"], maps["indexToOperation"])
    intent_conf = confidence(out["intent"])
    entities = _extract_entities(text)
    q = text.lower().strip()

    smart_markers = [
        "device", "devices", "smart", "home", "ac", "air", "lamp", "light", "curtain", "blind",
        "lock", "fridge", "freezer", "temperature", "brightness", "color", "mode", "status",
        "dispositivo", "dispositivos", "luz", "cortina", "fechadura", "geladeira", "congelador",
        "temperatura", "brilho", "cor", "modo", "estado",
    ]
    ood_markers = [
        "poem", "conto", "capital", "stock", "invest", "investir", "derivative", "cálculo",
        "world cup", "restaurant", "filme", "física", "quantica", "quântica",
    ]

    if any(k in q for k in ood_markers) and not any(k in q for k in smart_markers):
        intent = "outOfDomain"

    if ("list" in q or "listar" in q or "quais dispositivos" in q or "what devices" in q or
        "show online devices" in q or "online devices" in q):
        intent = "listOnline" if "online" in q else "listDevices"

    status_like = any(k in q for k in ["what is", "check", "status", "estado", "is ", "qual", "como está", "show "])
    hard_action_like = any(k in q for k in ["set", "change", "adjust", "defina", "ajusta", "mude", "turn on", "turn off", "liga", "desliga"])
    open_close_action_like = (
        q.startswith("open ") or q.startswith("close ") or q.startswith("abrir ") or q.startswith("fechar ") or
        " can you open" in q or " can you close" in q or " please open" in q or " please close" in q or
        " pode abrir" in q or " pode fechar" in q
    )
    action_like = hard_action_like or open_close_action_like

    if action_like:
        intent = "controlDevice"
    elif status_like and intent not in {"listDevices", "listOnline", "outOfDomain"}:
        intent = "queryStatus"

    if capability == "none":
        if any(k in q for k in ["curtain", "curtains", "blind", "blinds", "shade", "cortina", "persiana"]):
            capability = "position"
        elif any(k in q for k in ["brightness", "brilho", "light level", "luminosidade"]):
            capability = "brightness"
        elif any(k in q for k in ["temperature", "temperatura", "temp", "thermo"]):
            capability = "temperature"
        elif any(k in q for k in ["lock", "unlock", "fechadura", "tranca"]):
            capability = "lock"
        elif any(k in q for k in ["color temperature", "temperatura de cor", "kelvin"]):
            capability = "colorTemperature"
        elif any(k in q for k in ["color", "colour", "cor"]):
            capability = "color"

    if operation == "none":
        if any(k in q for k in ["set", "change", "adjust", "defina", "ajusta", "mude", "turn on", "turn off", "liga", "desliga", "open", "close", "abrir", "fechar"]):
            operation = "set"

    def decode_response() -> str:
        with torch.no_grad():
            shared = out["shared"]
            h = torch.tanh(model.decoder_init(shared)).unsqueeze(0)
            token = torch.tensor([[vocab[BOS]]], dtype=torch.long)
            generated: list[str] = []
            for _ in range(MAX_RESP_LEN):
                emb = model.decoder_embedding(token)
                dec_out, h = model.decoder(emb, h)
                logits = model.decoder_out(dec_out[:, -1, :])
                next_id = int(torch.argmax(logits, dim=1).item())
                if next_id == vocab[EOS] or next_id == vocab[PAD]:
                    break
                tok = inv_vocab.get(next_id, UNK)
                if tok not in {BOS, EOS, PAD}:
                    generated.append(tok)
                token = torch.tensor([[next_id]], dtype=torch.long)
        text_out = " ".join(generated).strip()
        text_out = re.sub(r"\s+", " ", text_out)
        return text_out

    def compose_response() -> tuple[str, bool]:
        if intent in {"ambiguous", "unknown"} or intent_conf < 0.48:
            return (
                "I could not fully understand the request yet. Please provide the device name, the capability to change, and a target value when relevant.",
                True,
            )

        if intent == "greeting":
            return (
                "Hello. I am online and ready to interpret commands, check device status, and explain any missing context.",
                False,
            )
        if intent == "gratitude":
            return (
                "You are welcome. If you want, I can continue with another command or verify device state now.",
                False,
            )
        if intent == "farewell":
            return ("See you soon. I will remain ready for your next request.", False)
        if intent == "smalltalk":
            return (
                "I am operating normally and ready. You can ask me to execute a command, check status, or list available devices.",
                False,
            )
        if intent == "listDevices":
            return ("I can list all registered devices. If needed, I can also filter only online devices.", False)
        if intent == "listOnline":
            return ("I can check which devices are online right now and report them clearly.", False)
        if intent == "outOfDomain":
            return (
                "This topic is outside my smart-device scope. I can help with devices, automations, and status checks. For this question, please use a specialized source.",
                True,
            )
        if intent == "queryStatus":
            if capability != "none":
                return (
                    f"I understood a status query for {capability}. If you provide a device name, I can return a precise value.",
                    False,
                )
            return (
                "I understood a status request. Please mention the device name for a precise answer.",
                True,
            )
        if intent in {"controlDevice", "applyProfile"}:
            has_num = entities.get("numericValue") is not None
            if capability in {"position", "brightness", "temperature", "temperatureFridge", "temperatureFreezer", "colorTemperature", "mode"} and not has_num and "open" not in q and "close" not in q and "abr" not in q and "fech" not in q:
                return (
                    f"I understood a command for {capability}, but I still need a target value to execute it safely.",
                    True,
                )
            return (
                f"I understood a device-control request with capability {capability} and operation {operation}.",
                False,
            )

        return (
            "I interpreted your message, but I still need more context to proceed with confidence.",
            True,
        )

    generated_response = decode_response()
    fallback_response, fallback_clarify = compose_response()
    if len(generated_response.split()) < 6:
        generated_response = fallback_response
        needs_clarify = fallback_clarify
    else:
        needs_clarify = fallback_clarify and intent_conf < 0.55

    return {
        "intent": intent,
        "responseStyle": style,
        "predictedCapability": capability,
        "predictedOperation": operation,
        "generatedResponse": generated_response,
        "needsClarification": needs_clarify,
        "intentConfidence": round(intent_conf, 5),
        "entities": entities,
    }


if __name__ == "__main__":
    train()
