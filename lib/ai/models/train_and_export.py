import torch
import torch.nn as nn
import torch.optim as optim
import json

class Tokenizer:
    def __init__(self, vocab):
        self.stoi = {tok: i for i, tok in enumerate(vocab)}
        self.itos = {i: tok for tok, i in enumerate(vocab)}
    def encode(self, text):
        return [self.stoi.get(tok, 0) for tok in text.split()]
    def decode(self, ids):
        return ' '.join([self.itos.get(i, '<UNK>') for i in ids])

class ChatModel(nn.Module):
    def __init__(self, vocab_size, embed_dim=128, hidden_dim=256):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, embed_dim)
        self.gru = nn.GRU(embed_dim, hidden_dim, batch_first=True)
        self.fc = nn.Linear(hidden_dim, vocab_size)
    def forward(self, x, h=None):
        x = self.embedding(x)
        out, h = self.gru(x, h)
        out = self.fc(out)
        return out, h

def load_dataset(path):
    with open(path, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]

def build_vocab(dataset):
    tokens = set()
    for line in dataset:
        tokens.update(line.split())
    tokens = ['<PAD>', '<SOS>', '<EOS>'] + sorted(list(tokens))
    return tokens

def main():
    dataset = load_dataset('lib/ai/dataset.txt')
    vocab = build_vocab(dataset)
    tokenizer = Tokenizer(vocab)
    encoded = [[tokenizer.stoi['<SOS>']] + tokenizer.encode(line) + [tokenizer.stoi['<EOS>']] for line in dataset]
    model = ChatModel(len(vocab))
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    criterion = nn.CrossEntropyLoss()
    for epoch in range(5):
        for seq in encoded:
            inp = torch.tensor(seq[:-1]).unsqueeze(0)
            tgt = torch.tensor(seq[1:]).unsqueeze(0)
            out, _ = model(inp)
            loss = criterion(out.squeeze(0), tgt.squeeze(0))
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
    torch.jit.save(torch.jit.script(model), 'lib/ai/models/chat_model.pt')
    with open('lib/ai/data/vocab.json', 'w', encoding='utf-8') as f:
        json.dump(vocab, f)

if __name__ == '__main__':
    main()
