import torch
import torch.nn.functional as F
from tokenizers import Tokenizer

from SGLMLite import SGLMLite, ModelArgs

modelPath = "sglmLite.pt"
tokenizerPath = "../data/tokenizer.json"

tokenizer = Tokenizer.from_file(tokenizerPath)
vocabSize = tokenizer.get_vocab_size()

args = ModelArgs()
args.vocab_size = vocabSize
args.dim = 512

model = SGLMLite(args)
model.load_state_dict(torch.load(modelPath, map_location="cpu"))
model.eval()

seqLen = 128
temperature = 0.9
topP = 0.9
maxNewTokens = 60


def sample(logits):

    logits = logits / temperature
    probs = torch.softmax(logits, dim=-1)

    sortedProbs, sortedIdx = torch.sort(probs, descending=True)

    cumulative = torch.cumsum(sortedProbs, dim=-1)
    cutoff = cumulative > topP

    if cutoff.any():
        last = torch.where(cutoff)[0][0]
        sortedProbs = sortedProbs[:last+1]
        sortedIdx = sortedIdx[:last+1]

    sortedProbs = sortedProbs / sortedProbs.sum()

    token = sortedIdx[torch.multinomial(sortedProbs, 1)]

    return token.item()


def generate(prompt):

    tokens = tokenizer.encode(prompt).ids

    for _ in range(maxNewTokens):

        inputIds = tokens[-seqLen:]
        inputIds = torch.tensor([inputIds], dtype=torch.long)

        with torch.no_grad():
            logits = model(inputIds)

        nextLogits = logits[0, -1]

        top = torch.topk(nextLogits, 10)

        print([
            tokenizer.id_to_token(int(i))
            for i in top.indices
        ])
        
        nextToken = sample(nextLogits)

        tokens.append(nextToken)

    return tokenizer.decode(tokens, skip_special_tokens=True)

print("SGLM Chat Ready\n")

history = ""

print(tokenizer.get_vocab_size())
print(tokenizer.id_to_token(0))


while True:
    
    user = input("You: ")

    if user.lower() in ["exit", "quit"]:
        break

    history += "User: " + user + "\nAssistant: "

    output = generate(history)

    answer = output[len(history):]

    print("AI:", answer.strip())

    history += answer + "\n"