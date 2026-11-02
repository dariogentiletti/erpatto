# Er Patto: draws the addon's own art (the stone tile and the close button) as TGA files.
# Usage: python3 tools/gen_media.py Media /tmp/preview
import numpy as np, sys, os
from PIL import Image

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
PREV = sys.argv[2]; os.makedirs(PREV, exist_ok=True)
rng = np.random.default_rng(1987)

def save(arr, name):
    a = np.clip(arr, 0, 255).astype(np.uint8)
    mode = "RGBA" if a.shape[2] == 4 else "RGB"
    Image.fromarray(a, mode).save(os.path.join(OUT, name + ".tga"))
    Image.fromarray(a, mode).save(os.path.join(PREV, name + ".png"))

# ---------------------------------------------------------------- stone: seamless cloudy dark grey
def fractal(n, beta, seed):
    r = np.random.default_rng(seed)
    w = r.standard_normal((n, n))
    F = np.fft.fft2(w)
    fx = np.fft.fftfreq(n)[:, None]; fy = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy); f[0, 0] = 1
    F = F / f ** (beta / 2)
    F[0, 0] = 0
    out = np.real(np.fft.ifft2(F))
    return (out - out.mean()) / out.std()

N = 512
clouds = fractal(N, 2.2, 11)            # big soft blotches
mid = fractal(N, 1.4, 12)               # mottling
grain = rng.standard_normal((N, N))     # fine speckle
# a few darker pits, like the vanilla stone
pits = np.clip(-fractal(N, 2.8, 13) - 1.3, 0, None) * 1.6
lum = clouds * 0.7 + mid * 0.45 + grain * 0.3 - pits
lum = (lum - lum.mean()) / lum.std()
L = 30 + lum * 6.5                       # light version (inner boxes); the window darkens it with vertex colour
stone = np.stack([L * 1.0, L * 0.97, L * 0.92], 2)
save(stone, "bg")

def grey(v):
    return (v, v * 0.96, v * 0.9)

# ---------------------------------------------------------------- close button (32x32, square 20x20 in the middle)
def close_button(pressed, name):
    S = 32; img = np.zeros((S, S, 4)); ss = 4
    o = 6 + (1 if pressed else 0)
    for y in range(S):
        for x in range(S):
            acc = np.zeros(4)
            for sy in range(ss):
                for sx in range(ss):
                    u = x + (sx + .5) / ss - o; v = y + (sy + .5) / ss - o
                    if not (0 <= u < 20 and 0 <= v < 20):
                        continue
                    e = min(u, v, 20 - u, 20 - v)
                    if e < 1: c = (14, 10, 8)
                    elif e < 2.2: c = grey(120) if (u + v) < 20 else grey(55)
                    else:
                        t = v / 20
                        k = 0.7 if pressed else 1
                        c = ((170 - 70 * t) * k, (28 - 12 * t) * k, (20 - 10 * t) * k)
                        # the X
                        a = abs((u - 10) - (v - 10)) / 1.414; b = abs((u - 10) + (v - 10)) / 1.414
                        if 4.5 < u < 15.5 and 4.5 < v < 15.5 and min(a, b) < 1.5:
                            c = (236, 214, 150) if not pressed else (190, 170, 120)
                    acc += np.array([c[0], c[1], c[2], 255])
            acc /= ss * ss
            if acc[3] > 0: img[y, x, :3] = acc[:3] * 255 / acc[3]
            img[y, x, 3] = acc[3]
    save(img, name)

close_button(False, "close-up")
close_button(True, "close-down")
hl = np.zeros((32, 32, 4))
yy, xx = np.mgrid[0:32, 0:32]
d = np.maximum(abs(xx - 15.5), abs(yy - 15.5))
hl[..., 0] = 255; hl[..., 1] = 200; hl[..., 2] = 120
hl[..., 3] = np.clip((11 - d) / 4, 0, 1) * 110
save(hl, "close-hl")

