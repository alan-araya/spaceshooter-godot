"""Gera os mapas de relevo (normal maps) dos sprites: assets/sprites/<nome>_n.png.

Uso: python -I tools/build_normals.py [nome ...]

Para cada quadro da folha: altura = "inflado" a partir da borda da silhueta (perfil de quarto
de círculo) + detalhe pelo brilho do pixel (contorno escuro vira sulco). Do gradiente da altura
sai a normal. Convenção do Godot 2D: R = +x (direita), G = +y para CIMA na tela, B = para fora.
O jogo carrega o arquivo por nome (Art.lit); sem ele o sprite fica com relevo plano.
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites")

# nome: (colunas, linhas, raio do inflado em px, força do detalhe em px)
SHEETS = {
    "soldier": (5, 4, 4.5, 2.6),
    "bug": (4, 2, 4.0, 3.0),
    "larva": (2, 1, 3.0, 2.0),
    "mother": (2, 1, 7.0, 3.5),
    "nest": (2, 1, 8.0, 3.5),
    "heart": (2, 1, 10.0, 4.0),
    "flower": (2, 1, 3.0, 2.0),
    "buggy": (1, 1, 5.0, 3.0),
    "dropship": (1, 1, 7.0, 3.0),
    "robot": (2, 1, 5.0, 3.0),
}


def edge_distance(mask):
    """Distância (px) de cada pixel opaco até o pixel transparente mais próximo (chamfer 3-4)."""
    h, w = mask.shape
    big = 10 ** 6
    d = np.where(mask, big, 0).astype(np.int64)
    d = np.pad(d, 1, constant_values=0)
    for y in range(1, h + 1):
        for x in range(1, w + 1):
            if d[y, x]:
                d[y, x] = min(d[y, x], d[y, x - 1] + 3, d[y - 1, x] + 3, d[y - 1, x - 1] + 4, d[y - 1, x + 1] + 4)
    for y in range(h, 0, -1):
        for x in range(w, 0, -1):
            if d[y, x]:
                d[y, x] = min(d[y, x], d[y, x + 1] + 3, d[y + 1, x] + 3, d[y + 1, x + 1] + 4, d[y + 1, x - 1] + 4)
    return d[1:-1, 1:-1] / 3.0


def blur(a, sigma):
    if sigma <= 0:
        return a
    r = max(1, int(sigma * 2.5))
    xs = np.arange(-r, r + 1)
    k = np.exp(-(xs ** 2) / (2 * sigma * sigma))
    k /= k.sum()
    # separável: horizontal e depois vertical
    p = np.pad(a, r, mode="edge")
    tmp = np.zeros_like(a, dtype=np.float64)
    for i, kv in enumerate(k):
        tmp += kv * p[r:r + a.shape[0], i:i + a.shape[1]]
    p2 = np.pad(tmp, r, mode="edge")
    out = np.zeros_like(a, dtype=np.float64)
    for i, kv in enumerate(k):
        out += kv * p2[i:i + a.shape[0], r:r + a.shape[1]]
    return out


def frame_normals(rgba, radius, detail):
    a = rgba[..., 3] > 127
    if not a.any():
        n = np.zeros(rgba.shape[:2] + (3,))
        n[..., 2] = 1.0
        return n
    d = edge_distance(a)
    t = np.clip(d / radius, 0.0, 1.0)
    bevel = radius * np.sqrt(1.0 - (1.0 - t) ** 2)
    lum = (0.299 * rgba[..., 0] + 0.587 * rgba[..., 1] + 0.114 * rgba[..., 2]) / 255.0
    lum = np.where(a, lum, 0.0)
    h = bevel + blur(lum, 0.7) * detail
    h = np.where(a, h, 0.0)
    h = blur(h, 0.6)
    gy, gx = np.gradient(h)
    n = np.dstack([-gx, -gy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    n[~a] = (0.0, 0.0, 1.0)
    return n


def encode(n):
    out = np.zeros(n.shape[:2] + (4,), dtype=np.uint8)
    out[..., 0] = np.clip((0.5 + 0.5 * n[..., 0]) * 255.0 + 0.5, 0, 255)
    out[..., 1] = np.clip((0.5 - 0.5 * n[..., 1]) * 255.0 + 0.5, 0, 255)  # y da imagem cresce para baixo
    out[..., 2] = np.clip((0.5 + 0.5 * n[..., 2]) * 255.0 + 0.5, 0, 255)
    out[..., 3] = 255
    return out


def build(name):
    cols, rows, radius, detail = SHEETS[name]
    src = os.path.join(ROOT, name + ".png")
    if not os.path.exists(src):
        print("  (sem %s.png)" % name)
        return
    img = np.array(Image.open(src).convert("RGBA")).astype(np.float64)
    H, W = img.shape[:2]
    fw, fh = W // cols, H // rows
    out = np.zeros((H, W, 3))
    out[..., 2] = 1.0
    for r in range(rows):
        for c in range(cols):
            ys, xs = slice(r * fh, (r + 1) * fh), slice(c * fw, (c + 1) * fw)
            out[ys, xs] = frame_normals(img[ys, xs], radius, detail)
    Image.fromarray(encode(out), "RGBA").save(os.path.join(ROOT, name + "_n.png"))
    print("  %s_n.png  %dx%d  (%dx%d quadros)" % (name, W, H, cols, rows))


if __name__ == "__main__":
    names = sys.argv[1:] or list(SHEETS)
    for nm in names:
        build(nm)
