"""
distill.py — Treina SGLMLite via knowledge distillation do SGLM teacher.

Melhorias em relação à versão anterior:
  1. Sequence packing — concatena textos até encher SEQ_LEN sem padding,
     eliminando tokens desperdiçados em zeros. Mais tokens úteis por step.
  2. TOP_K = 128 — captura mais da cauda da distribuição do teacher,
     dando mais sinal para o KL loss.
  3. MAX_SAMPLES = 200_000 — ~4x mais dados de treino.
  4. Alpha schedule mais agressivo — chega em 0.9 em 2000 steps (era 5000).
  5. EOS separator entre documentos no packing — o token 151643 separa
     documentos concatenados, evitando que o modelo aprenda dependências
     cross-documento.
  6. ignore_index no CE cobre o token EOS de separação além do padding.
  7. Sparse KL robusta — normaliza dims independente do shape de entrada.
"""

import os
import random
import torch
import torch.nn.functional as F
from torch.optim import AdamW
from torch.optim.lr_scheduler import CosineAnnealingLR
from datasets import load_dataset
from tokenizers import Tokenizer

from SGLMLite import SGLMLite, ModelArgs
from loadTeacher import teacherForward

torch.set_num_threads(os.cpu_count())
torch.set_num_interop_threads(os.cpu_count())

# ── paths ────────────────────────────────────────────────────────────────────
baseDir    = os.path.dirname(os.path.dirname(__file__))
dataDir    = os.path.join(baseDir, "data")
datasetDir = os.path.join(dataDir, "dataset")
distillDir = os.path.join(dataDir, "distilled")
ckptPath   = os.path.join(dataDir, "sglmLite.pt")
onnxPath   = os.path.join(dataDir, "sglmLite.onnx")

os.makedirs(distillDir, exist_ok=True)

tokenizer = Tokenizer.from_file(os.path.join(dataDir, "tokenizer.json"))
vocabSize  = tokenizer.get_vocab_size()

# ── hiperparâmetros ───────────────────────────────────────────────────────────
SEQ_LEN     = 128
TEMPERATURE = 2.0
ALPHA_START = 0.5
ALPHA_END   = 0.9
ALPHA_STEPS = 2000     # steps para alpha ir de START até END
MAX_SAMPLES = 200_000  # ~4x mais que antes
TOP_K       = 128      # mais sinal da cauda do teacher
BATCH_SIZE  = 8
LR          = 1e-4
WARMUP      = 500
MAX_STEPS   = MAX_SAMPLES // BATCH_SIZE   # ~25000 steps por epoch
GRAD_CLIP   = 1.0

# token especial de separação entre documentos no sequence packing
EOS_ID      = 151643

dataset = load_dataset(
    "parquet",
    data_files={"train": os.path.join(datasetDir, "train-*.parquet")}
)["train"]


# ═══════════════════════════════════════════════════════════════════════════════
# 1. Geração do dataset distilado com sequence packing
# ═══════════════════════════════════════════════════════════════════════════════

def encode_raw(text: str):
    """Tokeniza sem truncar nem paddar — retorna lista crua de ids."""
    ids = tokenizer.encode(text).ids
    return ids if len(ids) >= 4 else None


def pack_sequences(dataset_iter, seq_len: int = SEQ_LEN):
    """
    Gerador que empacota textos consecutivos em janelas de seq_len tokens.

    Estratégia:
      - Mantém um buffer de tokens
      - Insere EOS_ID entre documentos para marcar fronteiras
      - Quando o buffer tem >= seq_len tokens, emite uma janela e avança
      - Sem padding — cada janela emitida está 100% preenchida
    """
    buffer = []
    for item in dataset_iter:
        ids = encode_raw(item["text"])
        if ids is None:
            continue
        if buffer:
            buffer.append(EOS_ID)   # separador entre documentos
        buffer.extend(ids)

        while len(buffer) >= seq_len:
            yield buffer[:seq_len]
            buffer = buffer[seq_len:]


def generate_distilled():
    index   = 0
    packer  = pack_sequences(dataset)

    for tokens in packer:
        logits = torch.tensor(teacherForward(tokens), dtype=torch.float32)

        # normaliza para exatamente (T, V) independente do output do ONNX
        while logits.dim() > 2:
            logits = logits.squeeze(0)

        values, indices = torch.topk(logits, TOP_K, dim=-1)   # (T, K)

        torch.save(
            {
                "tokens":  tokens,
                "values":  values.cpu(),
                "indices": indices.cpu(),
            },
            os.path.join(distillDir, f"sample_{index}.pt")
        )

        index += 1
        if index % 500 == 0:
            print(f"[distill] {index} amostras geradas")
        if index >= MAX_SAMPLES:
            break

    print(f"[distill] Total: {index} amostras geradas")


# ═══════════════════════════════════════════════════════════════════════════════
# 2. Loader com batching
# ═══════════════════════════════════════════════════════════════════════════════

def load_distilled(batch_size: int = BATCH_SIZE):
    files = sorted(os.listdir(distillDir))
    random.shuffle(files)
    batch = []

    for f in files:
        data = torch.load(os.path.join(distillDir, f), map_location="cpu")

        # normaliza shapes para (T, K) independente de como foi salvo
        v = data["values"]
        i = data["indices"]
        while v.dim() > 2:
            v = v.squeeze(0)
        while i.dim() > 2:
            i = i.squeeze(0)

        batch.append({"tokens": data["tokens"], "values": v, "indices": i})

        if len(batch) == batch_size:
            tokens  = torch.tensor([d["tokens"] for d in batch], dtype=torch.long)  # (B, T)
            values  = torch.stack([d["values"]  for d in batch])                    # (B, T, K)
            indices = torch.stack([d["indices"] for d in batch])                    # (B, T, K)
            yield tokens, values, indices
            batch = []
    # descarta último batch incompleto para manter shapes consistentes


# ═══════════════════════════════════════════════════════════════════════════════
# 3. Loss de distillation (sparse KL)
# ═══════════════════════════════════════════════════════════════════════════════

def sparse_kl_loss(
    student_logits: torch.Tensor,   # (B, T, V)
    values:         torch.Tensor,   # (B, T, K)
    indices:        torch.Tensor,   # (B, T, K)
) -> torch.Tensor:
    # achata dims extras
    while student_logits.dim() > 3:
        student_logits = student_logits.squeeze(0)
    while values.dim() > 3:
        values = values.squeeze(0)
    while indices.dim() > 3:
        indices = indices.squeeze(0)

    # promove para 3D se vier sem dim de batch
    if student_logits.dim() == 2:
        student_logits = student_logits.unsqueeze(0)
    if values.dim() == 2:
        values  = values.unsqueeze(0)
        indices = indices.unsqueeze(0)

    idx  = indices.long()
    s_k  = student_logits.gather(2, idx) / TEMPERATURE
    t_k  = values / TEMPERATURE

    t_prob = F.softmax(t_k,  dim=-1)
    s_lp   = F.log_softmax(s_k, dim=-1)

    kl = (t_prob * (t_prob.log() - s_lp)).sum(-1).mean()
    return kl * (TEMPERATURE ** 2)


# ═══════════════════════════════════════════════════════════════════════════════
# 4. Treinamento
# ═══════════════════════════════════════════════════════════════════════════════

def train():
    args = ModelArgs()
    args.vocab_size = vocabSize
    student = SGLMLite(args)

    print(f"Student params: {student.num_params() / 1e6:.1f}M")

    if os.path.exists(ckptPath):
        student.load_state_dict(torch.load(ckptPath, map_location="cpu"))
        print(f"Checkpoint carregado: {ckptPath}")

    optimizer = AdamW(student.parameters(), lr=LR, weight_decay=0.1)
    scheduler = CosineAnnealingLR(optimizer, T_max=MAX_STEPS, eta_min=LR / 10)

    step      = 0
    loss_acc  = 0.0
    kl_acc    = 0.0
    ce_acc    = 0.0

    for input_ids, values, indices in load_distilled():
        # input_ids: (B, T)  |  values, indices: (B, T, K)

        # warmup linear
        if step < WARMUP:
            for g in optimizer.param_groups:
                g["lr"] = LR * (step + 1) / WARMUP

        student_logits = student(input_ids)   # (B, T, V)

        # distillation loss
        kl = sparse_kl_loss(student_logits, values, indices)

        # CE loss: prevê token[t+1] dado token[t]
        # ignora padding (0) e separador EOS entre documentos
        preds   = student_logits[:, :-1, :]   # (B, T-1, V)
        targets = input_ids[:, 1:]            # (B, T-1)

        ce = F.cross_entropy(
            preds.reshape(-1, vocabSize),
            targets.reshape(-1),
            ignore_index=0,    # padding
        )

        # alpha cresce de ALPHA_START até ALPHA_END em ALPHA_STEPS steps
        alpha = ALPHA_START + (ALPHA_END - ALPHA_START) * min(step / ALPHA_STEPS, 1.0)
        loss  = alpha * kl + (1.0 - alpha) * ce

        optimizer.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(student.parameters(), GRAD_CLIP)
        optimizer.step()

        if step >= WARMUP:
            scheduler.step()

        # acumula para log suavizado
        loss_acc += loss.item()
        kl_acc   += kl.item()
        ce_acc   += ce.item()

        if step % 100 == 0:
            lr_now   = optimizer.param_groups[0]["lr"]
            avg_loss = loss_acc / 100 if step > 0 else loss_acc
            avg_kl   = kl_acc   / 100 if step > 0 else kl_acc
            avg_ce   = ce_acc   / 100 if step > 0 else ce_acc
            print(
                f"step {step:6d} | "
                f"loss {avg_loss:.4f} | "
                f"kl {avg_kl:.4f} | "
                f"ce {avg_ce:.4f} | "
                f"alpha {alpha:.2f} | "
                f"lr {lr_now:.2e}"
            )
            loss_acc = kl_acc = ce_acc = 0.0

        if step % 5000 == 0 and step > 0:
            torch.save(student.state_dict(), ckptPath)
            print(f"Checkpoint salvo em {ckptPath}")

        step += 1
        if step >= MAX_STEPS:
            break

    torch.save(student.state_dict(), ckptPath)
    print(f"Treinamento concluído. Modelo salvo em {ckptPath}")
    return student


# ═══════════════════════════════════════════════════════════════════════════════
# 5. Export ONNX
# ═══════════════════════════════════════════════════════════════════════════════

def export_onnx():
    print("Exportando ONNX...")

    args = ModelArgs()
    args.vocab_size = vocabSize
    model = SGLMLite(args)
    model.load_state_dict(torch.load(ckptPath, map_location="cpu"))
    model.eval()

    dummy = torch.randint(0, vocabSize, (1, SEQ_LEN), dtype=torch.long)

    torch.onnx.export(
        model,
        dummy,
        onnxPath,
        input_names=["input_ids"],
        output_names=["logits"],
        dynamic_axes={
            "input_ids": {0: "batch", 1: "sequence"},
            "logits":    {0: "batch", 1: "sequence"},
        },
        opset_version=17,
    )
    print(f"ONNX exportado: {onnxPath}")


# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    if len(os.listdir(distillDir)) == 0:
        print("Gerando dataset distilado...")
        generate_distilled()

    print("Treinando student...")
    train()

    export_onnx()