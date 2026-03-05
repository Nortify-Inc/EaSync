from __future__ import annotations

import math

import torch
import torch.nn as nn


class HybridChatModel(nn.Module):
    def __init__(
        self,
        vocabSize: int,
        intentClasses: int,
        styleClasses: int,
        capabilityClasses: int,
        operationClasses: int,
        dModel: int = 256,
        nHead: int = 8,
        encoderLayers: int = 4,
        ffDim: int = 768,
        lstmHidden: int = 320,
        maxLen: int = 96,
        dropout: float = 0.2,
    ):
        super().__init__()
        self.maxLen = maxLen
        self.dModel = dModel
        self.lstmHidden = lstmHidden

        self.tokenEmbedding = nn.Embedding(vocabSize, dModel, padding_idx=0)
        self.positionEmbedding = nn.Embedding(maxLen, dModel)
        self.embeddingDropout = nn.Dropout(dropout)

        encoderLayer = nn.TransformerEncoderLayer(
            d_model=dModel,
            nhead=nHead,
            dim_feedforward=ffDim,
            dropout=dropout,
            activation="gelu",
            batch_first=True,
        )
        self.transformerEncoder = nn.TransformerEncoder(encoderLayer, num_layers=encoderLayers)

        self.sharedHead = nn.Sequential(
            nn.LayerNorm(dModel),
            nn.Linear(dModel, dModel),
            nn.GELU(),
            nn.Dropout(dropout),
        )

        self.intentHead = nn.Linear(dModel, intentClasses)
        self.styleHead = nn.Linear(dModel, styleClasses)
        self.capabilityHead = nn.Linear(dModel, capabilityClasses)
        self.operationHead = nn.Linear(dModel, operationClasses)

        self.decoderEmbedding = nn.Embedding(vocabSize, dModel, padding_idx=0)
        self.decoderLstm = nn.LSTM(dModel + dModel, lstmHidden, num_layers=2, batch_first=True, dropout=dropout)
        self.initH = nn.Linear(dModel, lstmHidden * 2)
        self.initC = nn.Linear(dModel, lstmHidden * 2)
        self.queryProjection = nn.Linear(lstmHidden, dModel)
        self.outputProjection = nn.Linear(lstmHidden + dModel, vocabSize)

    def encode(self, x: torch.Tensor, lengths: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        batchSize, seqLen = x.size()
        positions = torch.arange(seqLen, device=x.device).unsqueeze(0).expand(batchSize, seqLen)

        h = self.tokenEmbedding(x) * math.sqrt(self.dModel)
        h = h + self.positionEmbedding(positions)
        h = self.embeddingDropout(h)

        padMask = x.eq(0)
        memory = self.transformerEncoder(h, src_key_padding_mask=padMask)

        validMask = (~padMask).unsqueeze(-1)
        pooled = (memory * validMask).sum(dim=1) / lengths.clamp_min(1).unsqueeze(1).to(memory.dtype)
        shared = self.sharedHead(pooled)

        return memory, shared, padMask

    def attend(self, queryHidden: torch.Tensor, memory: torch.Tensor, padMask: torch.Tensor) -> torch.Tensor:
        query = self.queryProjection(queryHidden).unsqueeze(1)
        scores = torch.bmm(query, memory.transpose(1, 2)).squeeze(1)
        scores = scores.masked_fill(padMask, -1e9)
        weights = torch.softmax(scores, dim=1)
        context = torch.bmm(weights.unsqueeze(1), memory).squeeze(1)
        return context

    def decodeTeacher(
        self,
        memory: torch.Tensor,
        shared: torch.Tensor,
        responseInput: torch.Tensor,
        padMask: torch.Tensor,
    ) -> torch.Tensor:
        batchSize, steps = responseInput.size()
        embedded = self.decoderEmbedding(responseInput)

        h0 = torch.tanh(self.initH(shared)).view(batchSize, 2, self.lstmHidden).transpose(0, 1).contiguous()
        c0 = torch.tanh(self.initC(shared)).view(batchSize, 2, self.lstmHidden).transpose(0, 1).contiguous()
        state = (h0, c0)

        outputs = []
        previousContext = torch.zeros(batchSize, self.dModel, device=memory.device)

        for t in range(steps):
            stepInput = torch.cat([embedded[:, t, :], previousContext], dim=1).unsqueeze(1)
            stepOutput, state = self.decoderLstm(stepInput, state)
            decoderHidden = stepOutput[:, 0, :]
            context = self.attend(decoderHidden, memory, padMask)
            logits = self.outputProjection(torch.cat([decoderHidden, context], dim=1))
            outputs.append(logits)
            previousContext = context

        return torch.stack(outputs, dim=1)

    def forward(self, x: torch.Tensor, lengths: torch.Tensor, responseInput: torch.Tensor | None = None):
        memory, shared, padMask = self.encode(x, lengths)

        out = {
            "intent": self.intentHead(shared),
            "style": self.styleHead(shared),
            "capability": self.capabilityHead(shared),
            "operation": self.operationHead(shared),
            "shared": shared,
            "memory": memory,
            "padMask": padMask,
        }

        if responseInput is not None:
            out["responseLogits"] = self.decodeTeacher(memory, shared, responseInput, padMask)

        return out
