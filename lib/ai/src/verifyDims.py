import torch

sd = torch.load("sglmLite.pt", map_location="cpu")

for k,v in sd.items():
    print(k, v.shape)
    break