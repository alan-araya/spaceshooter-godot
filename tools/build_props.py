"""Estruturas em 3D → sprites com mapa de relevo e máscara de luz própria.

Uso: python -I tools/build_props.py [--skip-render]

1. Chama o Blender em segundo plano com tools/blender/props_scene.py, que modela as peças e
   grava três passes 4× maiores em art_src/blender/ (cor, normais da câmera, máscara de emissão).
2. Reduz para o tamanho do sprite, converte as normais para o padrão do jogo, limita a paleta,
   põe contorno escuro e grava em assets/sprites/: <nome>.png, <nome>_n.png e <nome>_e.png.

Blender: variável de ambiente BLENDER ou o caminho padrão abaixo.
Padrão das normais (Godot 2D): R = +x, G = para cima na tela (norte), B = para fora da tela.
"""
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.normpath(os.path.join(HERE, "..", "art_src", "blender"))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "sprites"))
SCENE = os.path.join(HERE, "blender", "props_scene.py")
BLENDER = os.environ.get("BLENDER", r"D:\Program Files\Blender_5_2\client\blender.exe")
SS = 4
THETA = math.atan(0.75)
# nome: (visto de cima, número de cores)
PIECES = {"generator": (False, 28), "turret_base": (False, 20), "turret_gun": (True, 18), "relay": (False, 22)}
INK = (20, 18, 22)
KEY = np.array([-0.45, 0.55, 0.70]) / np.linalg.norm([-0.45, 0.55, 0.70])  # luz fixa suave, de cima e da esquerda


def render():
    os.makedirs(RAW, exist_ok=True)
    cmd = [BLENDER, "--background", "--factory-startup", "--python", SCENE, "--", RAW]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if "PROPS ok" not in res.stdout:
        print(res.stdout[-3000:])
        print(res.stderr[-3000:])
        raise SystemExit("o Blender não terminou o render")


def load(name, suffix):
    return np.array(Image.open(os.path.join(RAW, "%s_%s.png" % (name, suffix))).convert("RGBA")).astype(np.float64) / 255.0


def blocks(a):
    """(H*SS, W*SS, C) -> (H, W, SS*SS, C)"""
    h, w = a.shape[0] // SS, a.shape[1] // SS
    return a.reshape(h, SS, w, SS, a.shape[2]).transpose(0, 2, 1, 3, 4).reshape(h, w, SS * SS, a.shape[2])


def process(name, top_down, colors):
    c, n, e = blocks(load(name, "c")), blocks(load(name, "n")), blocks(load(name, "e"))
    a_hi = c[..., 3:4]
    cover = a_hi.mean(axis=2)[..., 0]
    alpha = cover >= 0.5
    wsum = np.maximum(a_hi.sum(axis=2), 1e-6)
    rgb = (c[..., :3] * a_hi).sum(axis=2) / wsum

    # normais: média dos subpixels opacos, da câmera para o mundo, depois para o padrão do jogo
    nv = ((n[..., :3] * 2.0 - 1.0) * a_hi).sum(axis=2) / wsum
    if top_down:
        nx, ny, nz = nv[..., 0], nv[..., 1], nv[..., 2]
    else:
        ct, st = math.cos(THETA), math.sin(THETA)
        nx = nv[..., 0]
        ny = nv[..., 1] * ct - nv[..., 2] * st  # norte (para cima na tela)
        nz = nv[..., 1] * st + nv[..., 2] * ct  # altura (para fora da tela)
    nz = nz + 0.3  # faces verticais pegam um pouco da luz de cima, como as dos muros
    norm = np.dstack([nx, ny, nz])
    norm /= np.maximum(np.linalg.norm(norm, axis=2, keepdims=True), 1e-6)
    norm[~alpha] = (0.0, 0.0, 1.0)

    # um pouco de volume já na cor (o resto vem da luz do jogo)
    shade = 0.84 + 0.22 * np.clip((norm * KEY).sum(axis=2), 0.0, 1.0)
    rgb = np.clip(rgb * shade[..., None], 0.0, 1.0)

    # paleta curta, sem pontilhado
    img = Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8), "RGB")
    img = img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = np.zeros(alpha.shape + (4,), dtype=np.uint8)
    out[..., :3] = np.array(img)
    out[..., 3] = np.where(alpha, 255, 0)

    # contorno escuro de 1 px por fora da silhueta
    pad = np.pad(alpha, 1)
    grown = pad[1:-1, 1:-1] | pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    edge = grown & ~alpha
    out[edge] = INK + (255,)
    if alpha[0].any() or alpha[-1].any() or alpha[:, 0].any() or alpha[:, -1].any():
        print("  AVISO: %s encosta na borda do quadro" % name)

    enc = np.zeros(alpha.shape + (4,), dtype=np.uint8)
    enc[..., 0] = np.clip((0.5 + 0.5 * norm[..., 0]) * 255.0 + 0.5, 0, 255)
    enc[..., 1] = np.clip((0.5 + 0.5 * norm[..., 1]) * 255.0 + 0.5, 0, 255)
    enc[..., 2] = np.clip((0.5 + 0.5 * norm[..., 2]) * 255.0 + 0.5, 0, 255)
    enc[..., 3] = 255

    # luz própria: a cor das partes emissivas, para somar por cima no jogo
    mask = (e[..., 0:1] * a_hi).sum(axis=2)[..., 0] / (SS * SS) >= 0.5
    emit = np.zeros(alpha.shape + (4,), dtype=np.uint8)
    emit[..., :3] = np.where(mask[..., None], out[..., :3], 0)
    emit[..., 3] = np.where(mask, 255, 0)

    Image.fromarray(out, "RGBA").save(os.path.join(OUT, name + ".png"))
    Image.fromarray(enc, "RGBA").save(os.path.join(OUT, name + "_n.png"))
    Image.fromarray(emit, "RGBA").save(os.path.join(OUT, name + "_e.png"))
    ys, xs = np.nonzero(alpha)
    print("  %s  %dx%d  silhueta x %d..%d  y %d..%d  emissivos %d px" % (
        name, alpha.shape[1], alpha.shape[0], xs.min(), xs.max(), ys.min(), ys.max(), int(mask.sum())))


if __name__ == "__main__":
    if "--skip-render" not in sys.argv:
        render()
    for nm, (td, cols) in PIECES.items():
        process(nm, td, cols)
