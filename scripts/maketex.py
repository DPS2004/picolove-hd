# adapted from https://stackoverflow.com/a/3753428/11126567

import sys
from PIL import Image
import numpy as np

im = Image.open(sys.argv[1])
im = im.convert('RGBA')

colors = [
    [29,43,83],
    [126,37,83],
    [0,135,81],
    [171,82,54],
    [95,87,79],
    [194,195,199],
    [255,241,232],
    [255,0,77],
    [255,163,0],
    [255,236,39],
    [0,228,54],
    [41,173,255],
    [131,118,156],
    [255,119,168],
    [255,204,170]
]

data = np.array(im)
i = 16
r, g, b, a = data.T 
for x in colors:
    replacearea = (r == x[0]) & (g == x[1]) & (b == x[2])
    data[..., :-1][replacearea.T] = (i, i, i)
    i = i + 16
im2 = Image.fromarray(data)
im2.save("tex.png")
