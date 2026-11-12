"""Gera as texturas dos muros e portões, com mapa de relevo: assets/sprites/walls.png e walls_n.png.

Uso: python -I tools/build_structures.py

Atlas 256×128 (regiões usadas por scripts/actors/props.gd):
  (0,0)    128×128 topo do muro, placas de concreto — repete nos dois eixos (amostrado pela posição no mundo)
  (128,0)  128×18  face frontal do muro, blocos — repete na horizontal (18 px = Prop.WALL_H)
  (128,24) 32×32   topo do portão (chapa de aço com faixa de aviso)
  (160,24) 32×18   face frontal do portão
Tudo procedural (sem arte de terceiros). Relevo no padrão do Godot 2D: G = para cima na tela.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites")
rng = np.random.default_rng(2199)

FACE = np.array([0.0, 0.85, 0.53])  # normal de uma face vertical voltada para a câmera (y = para baixo na tela)


def courses(total, lo, hi):
    """Larguras aleatórias entre lo e hi que somam `total`."""
    out = []
    left = total
    while left > 0:
        w = int(rng.integers(lo, hi + 1))
        if left - w < lo:
            w = left
        out.append(w)
        left -= w
    return out


def stone(w, h, row_heights, lo, hi, pillow):
    """Mapa de altura (0..1) e de tom (multiplicador) de um aparelho de pedra que repete nas bordas."""
    height = np.zeros((h, w))
    tone = np.ones((h, w))
    y = 0
    for rh in row_heights:
        off = int(rng.integers(0, lo))
        x = 0
        for bw in courses(w, lo, hi):
            jitter = 1.0 + rng.uniform(-0.09, 0.09)
            tilt = rng.uniform(-0.12, 0.12, size=2)
            for yy in range(rh):
                for xx in range(bw):
                    px = (x + xx + off) % w
                    py = (y + yy) % h
                    ex = min(xx, bw - 1 - xx)
                    ey = min(yy, rh - 1 - yy)
                    e = min(ex, ey)
                    if e == 0:
                        height[py, px] = 0.0  # junta
                        tone[py, px] = 0.55
                        continue
                    u = (xx + 0.5) / bw - 0.5
                    v = (yy + 0.5) / rh - 0.5
                    base = 0.72 if e == 1 else 1.0
                    if pillow:
                        base *= 1.0 - 0.9 * (u * u + v * v)
                    height[py, px] = base + tilt[0] * u + tilt[1] * v
                    tone[py, px] = jitter * (0.93 if e == 1 else 1.0)
            x += bw
        y += rh
    return height, tone


def weather(tone, amount):
    h, w = tone.shape
    tone = tone * (1.0 + rng.normal(0.0, 0.025, size=(h, w)))
    for _ in range(amount):  # lascas e manchas
        x, y = int(rng.integers(0, w)), int(rng.integers(0, h))
        tone[y, x] *= 0.72
        if rng.random() < 0.5:
            tone[y, (x + 1) % w] *= 0.82
    return tone


def colorize(tone, rgb):
    t = np.round(tone * 14.0) / 14.0  # poucos tons, cara de pixel art
    out = np.clip(t[..., None] * np.array(rgb)[None, None, :], 0, 255)
    return out


def normals(height, strength, wrap_x=True, wrap_y=True):
    hx = np.pad(height, ((0, 0), (1, 1)), mode="wrap" if wrap_x else "edge")
    hy = np.pad(height, ((1, 1), (0, 0)), mode="wrap" if wrap_y else "edge")
    gx = (hx[:, 2:] - hx[:, :-2]) * 0.5 * strength
    gy = (hy[2:, :] - hy[:-2, :]) * 0.5 * strength
    n = np.dstack([-gx, -gy, np.ones_like(height)])
    return n / np.linalg.norm(n, axis=2, keepdims=True)


def face_normals(n):
    """Relevo de detalhe aplicado sobre uma face vertical voltada para a câmera."""
    out = np.dstack([0.9 * n[..., 0], FACE[1] + 0.4 * n[..., 1], np.full(n.shape[:2], FACE[2])])
    return out / np.linalg.norm(out, axis=2, keepdims=True)


def encode(n):
    out = np.zeros(n.shape[:2] + (3,))
    out[..., 0] = 0.5 + 0.5 * n[..., 0]
    out[..., 1] = 0.5 - 0.5 * n[..., 1]
    out[..., 2] = 0.5 + 0.5 * n[..., 2]
    return np.clip(out * 255.0 + 0.5, 0, 255)


def wall_top():
    """Placas de concreto de 32 px com junta fina, manchas, trincas e parafusos."""
    w = h = 128
    height = np.ones((h, w))
    tone = np.ones((h, w))
    for py in range(0, h, 32):
        for px in range(0, w, 32):
            ys, xs = slice(py, py + 32), slice(px, px + 32)
            tone[ys, xs] *= 1.0 + rng.uniform(-0.05, 0.05)
            # junta escura em cima e à esquerda; chanfro claro logo depois, escuro do lado oposto
            height[py, xs] = 0.0
            height[ys, px] = 0.0
            tone[py + 1, px + 1:px + 32] *= 1.09
            tone[py + 1:py + 32, px + 1] *= 1.06
            tone[py + 31, px + 1:px + 32] *= 0.91
            tone[py + 1:py + 32, px + 31] *= 0.93
            tone[py, xs] = 0.60
            tone[ys, px] = 0.60
            if rng.random() < 0.75:
                for (bx, by) in [(4, 4), (27, 4), (4, 27), (27, 27)]:
                    height[py + by, px + bx] = 1.6
                    tone[py + by, px + bx] = 1.25
                    tone[py + by + 1, px + bx] *= 0.8
    yy, xx = np.mgrid[0:h, 0:w]
    for _ in range(18):  # manchas de umidade/óleo
        cx, cy, r = rng.integers(0, w), rng.integers(0, h), rng.uniform(4.0, 9.0)
        dx = np.minimum(np.abs(xx - cx), w - np.abs(xx - cx))
        dy = np.minimum(np.abs(yy - cy), h - np.abs(yy - cy))
        tone *= 1.0 - 0.13 * np.clip(1.0 - np.sqrt(dx * dx + dy * dy) / r, 0.0, 1.0)
    for _ in range(4):  # trincas
        x, y = int(rng.integers(0, w)), int(rng.integers(0, h))
        for _i in range(int(rng.integers(7, 15))):
            tone[y % h, x % w] = 0.58
            height[y % h, x % w] = 0.3
            x += int(rng.integers(-1, 2))
            y += 1 if rng.random() < 0.7 else 0
    tone = weather(tone, 120)
    col = colorize(tone, (134, 130, 124))
    sand = (height == 0.0) & (rng.random(height.shape) < 0.12)
    col[sand] = (140, 110, 78)
    return col, normals(height, 2.0)


def wall_front():
    w, h = 128, 18
    height = np.zeros((h, w))
    tone = np.ones((h, w))
    # beiral de 3 px no alto
    height[0:3, :] = 1.15
    tone[0, :] = 1.22
    tone[1, :] = 1.10
    tone[2, :] = 0.62  # sombra do beiral
    bh, bt = stone(w, 14, [7, 7], 15, 24, True)
    height[3:17, :] = bh
    tone[3:17, :] = bt
    tone[17, :] = 0.50
    tone = weather(tone, 40)
    # sujeira subindo do chão
    for y in range(12, 18):
        tone[y, :] *= 1.0 - 0.05 * (y - 11)
    col = colorize(tone, (112, 106, 98))
    n = face_normals(normals(height, 2.6, True, False))
    n[0:2, :] = (0.0, 0.25, 0.97)  # o beiral olha para cima
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return col, n


def gate_top():
    w = h = 32
    height = np.ones((h, w))
    tone = np.ones((h, w))
    col = np.zeros((h, w, 3))
    height[0, :] = height[-1, :] = 0.0
    height[:, 0] = height[:, -1] = 0.0
    height[:, 15:17] = 0.3  # emenda das duas folhas
    tone[height < 0.5] = 0.55
    tone = weather(tone, 10)
    col[:] = colorize(tone, (96, 104, 116))
    # faixa de aviso amarela e preta em diagonal
    for y in range(11, 21):
        for x in range(1, w - 1):
            stripe = ((x + y) // 4) % 2 == 0
            c = (214, 168, 48) if stripe else (38, 36, 34)
            col[y, x] = np.array(c) * min(1.0, tone[y, x] + 0.05)
    for (x, y) in [(3, 3), (28, 3), (3, 28), (28, 28), (12, 5), (19, 5), (12, 26), (19, 26)]:
        height[y, x] = 1.5  # rebites
        col[y, x] = (150, 158, 170)
    return col, normals(height, 2.0, False, False)


def gate_front():
    w, h = 32, 18
    height = np.ones((h, w))
    tone = np.ones((h, w))
    height[0:3, :] = 1.2
    tone[0, :] = 1.25
    tone[1, :] = 1.1
    tone[2, :] = 0.6
    for x in range(w):
        k = x % 8
        if k in (0, 7):
            height[3:, x] = 0.4
            tone[3:, x] = 0.62
        elif k in (1, 6):
            height[3:, x] = 0.8
            tone[3:, x] = 0.9 if k == 1 else 0.8
    tone[17, :] = 0.5
    tone = weather(tone, 8)
    col = colorize(tone, (82, 90, 102))
    for x in range(w):  # faixa amarela de aviso
        if x % 8 not in (0, 7):
            col[5:8, x] = np.array((222, 172, 52)) * min(1.0, tone[6, x])
    n = face_normals(normals(height, 2.4, True, False))
    n[0:2, :] = (0.0, 0.25, 0.97)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return col, n


def main():
    atlas = np.zeros((128, 256, 4), dtype=np.uint8)
    atlas_n = np.zeros((128, 256, 4), dtype=np.uint8)
    atlas_n[..., :3] = (128, 128, 255)
    atlas_n[..., 3] = 255
    for (col, n), (x, y) in [(wall_top(), (0, 0)), (wall_front(), (128, 0)), (gate_top(), (128, 24)), (gate_front(), (160, 24))]:
        h, w = col.shape[:2]
        atlas[y:y + h, x:x + w, :3] = col
        atlas[y:y + h, x:x + w, 3] = 255
        atlas_n[y:y + h, x:x + w, :3] = encode(n)
    Image.fromarray(atlas, "RGBA").save(os.path.join(ROOT, "walls.png"))
    Image.fromarray(atlas_n, "RGBA").save(os.path.join(ROOT, "walls_n.png"))
    print("walls.png e walls_n.png (256x128)")


if __name__ == "__main__":
    main()
