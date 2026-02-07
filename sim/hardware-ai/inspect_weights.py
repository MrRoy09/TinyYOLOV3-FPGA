import numpy as np

data = np.load("sim/hardware-ai/folded_weights.npz", allow_pickle=True)
keys = sorted(list(data.keys()), key=lambda x: int(x.split('_')[1]))

for k in keys:
    l = data[k].item()
    s = l.get('stride', 'N/A')
    t = l.get('type', 'N/A')
    print(f"{k}: Type={t}, Stride={s}")
