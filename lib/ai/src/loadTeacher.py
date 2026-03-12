import os
import onnxruntime as ort
import numpy as np
from tokenizers import Tokenizer

baseDir = os.path.dirname(os.path.dirname(__file__))
dataDir = os.path.join(baseDir, "data")

modelPath = os.path.join(dataDir, "model.onnx")
tokenizerPath = os.path.join(dataDir, "tokenizer.json")

session = ort.InferenceSession(modelPath, providers=["CPUExecutionProvider"])
tokenizer = Tokenizer.from_file(tokenizerPath)

inputName = session.get_inputs()[0].name
outputName = session.get_outputs()[0].name

def encode(text):
    return tokenizer.encode(text).ids

def decode(tokens):
    return tokenizer.decode(tokens)

def teacherForward(inputIds):

    arr = np.array([inputIds], dtype=np.int64)

    outputs = session.run(
        [outputName],
        {inputName: arr}
    )

    return outputs[0]

def teacherNextToken(text):

    tokens = encode(text)

    logits = teacherForward(tokens)

    nextLogits = logits[0][-1]

    return nextLogits