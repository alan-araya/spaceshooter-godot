"""Pipeline de arte: folhas geradas por IA (fundo magenta) -> sprites do jogo (contrato do GDD §7).

Uso:  python -I tools/process_art.py            (processa tudo o que existir em art_src/codex)
      python -I tools/process_art.py soldier    (só um asset)

Passos por sprite: chroma key do magenta (com remoção de franja), recorte por grade ou por caixas,
alinhamento comum entre frames, redução com filtro de área (alfa pré-multiplicado), alfa binário,
contorno escuro de 1 px e quantização de paleta (pixel nítido, sem dithering).
Texturas: redução + "offset blend" para ficarem sem emenda.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art_src" / "codex"
OUT = ROOT / "assets" / "sprites"


# ----------------------------------------------------------------------------- utilidades

def load_rgba(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0


def chroma_key(a: np.ndarray) -> np.ndarray:
    """Remove o fundo magenta (#FF00FF) CONECTADO às bordas da imagem (flood fill).
    Rosa/roxo dentro dos sprites (olhos, veias, pétalas, brilhos) fica intacto.
    Na borda do sprite, a franja rosada vira transparência parcial + despill."""
    from PIL import ImageDraw
    h, w = a.shape[:2]
    img = Image.fromarray((a[..., :3] * 255).astype(np.uint8), "RGB")
    sentinel = (0, 255, 0)
    rgb8 = (a[..., :3] * 255).astype(np.int32)

    def is_bg(x, y):
        r, g, b = rgb8[y, x]
        return r > 200 and b > 200 and g < 70

    step = 4
    seeds = [(x, 0) for x in range(0, w, step)] + [(x, h - 1) for x in range(0, w, step)]
    seeds += [(0, y) for y in range(0, h, step)] + [(w - 1, y) for y in range(0, h, step)]
    px = img.load()
    for (x, y) in seeds:
        if is_bg(x, y) and px[x, y] != sentinel:
            ImageDraw.floodfill(img, (x, y), sentinel, thresh=110)
    filled = np.asarray(img).astype(np.int32)
    bg = (filled[..., 0] == 0) & (filled[..., 1] == 255) & (filled[..., 2] == 0)
    # ilhas de magenta puro (ex.: vão entre perna e corpo) também são fundo
    pure = (rgb8[..., 0] > 235) & (rgb8[..., 2] > 235) & (rgb8[..., 1] < 30)
    bg |= pure
    # faixa de 2 px junto ao fundo: alfa pela "magentice", com despill
    near = bg.copy()
    for _ in range(2):
        p = np.pad(near, 1)
        near = near | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    edge = near & ~bg
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mag = np.clip((np.minimum(r, b) - g) * 1.8, 0.0, 1.0)
    out = a.copy()
    alpha = np.ones((h, w), np.float32)
    alpha[bg] = 0.0
    alpha[edge] = 1.0 - mag[edge]
    spill = np.clip(np.minimum(r, b) - g, 0.0, 1.0) * edge
    out[..., 0] = np.clip(r - spill * 0.9, 0, 1)
    out[..., 2] = np.clip(b - spill * 0.9, 0, 1)
    out[..., 3] = alpha
    return out


def bbox(alpha: np.ndarray, thr: float = 0.5):
    ys, xs = np.where(alpha > thr)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def downscale(rgba: np.ndarray, size) -> np.ndarray:
    """Redução com alfa pré-multiplicado (sem halo) e filtro de caixa."""
    pm = rgba.copy()
    pm[..., :3] *= pm[..., 3:4]
    img = Image.fromarray((pm * 255).astype(np.uint8), "RGBA")
    img = img.resize(size, Image.Resampling.BOX)
    a = np.asarray(img).astype(np.float32) / 255.0
    al = a[..., 3:4]
    rgb = np.where(al > 0.001, a[..., :3] / np.maximum(al, 0.001), 0)
    return np.concatenate([np.clip(rgb, 0, 1), al], axis=-1)


def crisp(rgba: np.ndarray, outline=True, colors=48, alpha_thr=0.45) -> np.ndarray:
    a = rgba.copy()
    a[..., 3] = (a[..., 3] > alpha_thr).astype(np.float32)
    if outline:
        solid = a[..., 3] > 0.5
        pad = np.pad(solid, 1)
        neigh = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
        edge = neigh & ~solid
        a[edge] = [0.09, 0.06, 0.07, 1.0]
    # quantiza só os pixels opacos
    img = Image.fromarray((a * 255).astype(np.uint8), "RGBA")
    rgb = img.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = np.asarray(rgb).astype(np.float32) / 255.0
    return np.concatenate([out, a[..., 3:4]], axis=-1)


def fit(crop: np.ndarray, frame, pad=1, anchor="center", scale=None):
    """Reduz `crop` para caber no frame (fw, fh) e posiciona. Retorna (frame_rgba, escala usada)."""
    fw, fh = frame
    h, w = crop.shape[:2]
    if scale is None:
        scale = min((fw - pad * 2) / w, (fh - pad * 2) / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    small = downscale(crop, (nw, nh))
    canvas = np.zeros((fh, fw, 4), np.float32)
    x = (fw - nw) // 2
    y = (fh - nh) // 2 if anchor == "center" else fh - nh - pad
    x0, y0 = max(0, x), max(0, y)
    sx, sy = x0 - x, y0 - y
    cw, ch = min(nw - sx, fw - x0), min(nh - sy, fh - y0)
    canvas[y0:y0 + ch, x0:x0 + cw] = small[sy:sy + ch, sx:sx + cw]
    return canvas, scale


def save(arr: np.ndarray, name: str):
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT / f"{name}.png")
    print(f"  -> assets/sprites/{name}.png {arr.shape[1]}x{arr.shape[0]}")


def sheet(frames, cols):
    rows = (len(frames) + cols - 1) // cols
    fh, fw = frames[0].shape[:2]
    out = np.zeros((rows * fh, cols * fw, 4), np.float32)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        out[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = f
    return out


# ----------------------------------------------------------------------------- recorte

def grid_cells(a, cols, rows):
    H, W = a.shape[:2]
    cw, ch = W / cols, H / rows
    cells = []
    for r in range(rows):
        for c in range(cols):
            cells.append(a[int(r * ch):int((r + 1) * ch), int(c * cw):int((c + 1) * cw)])
    return cells


def union_crop(cells):
    """Recorta todos os frames com a mesma caixa (união das caixas, coords locais): alinhamento estável."""
    boxes = [bbox(c[..., 3]) for c in cells]
    boxes = [b for b in boxes if b]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    return [c[y0:y1, x0:x1] for c in cells]


def region_frames(a, boxes):
    """Frames a partir de caixas aproximadas: recorta pelo conteúdo e centraliza num tamanho comum."""
    crops = []
    for (x0, y0, x1, y1) in boxes:
        sub = a[y0:y1, x0:x1]
        b = bbox(sub[..., 3])
        crops.append(sub[b[1]:b[3], b[0]:b[2]])
    W = max(c.shape[1] for c in crops)
    H = max(c.shape[0] for c in crops)
    out = []
    for c in crops:
        canvas = np.zeros((H, W, 4), np.float32)
        y = H - c.shape[0]  # alinha pela base (bom para pulsar sem "pular")
        x = (W - c.shape[1]) // 2
        canvas[y:y + c.shape[0], x:x + c.shape[1]] = c
        out.append(canvas)
    return out


def build_frames(crops, frame, anchor="center", colors=48, outline=True, scale_from=None):
    # escala única para a folha inteira (todos os frames do mesmo tamanho relativo)
    ref = scale_from if scale_from is not None else crops[0]
    _, scale = fit(ref, frame, anchor=anchor)
    out = []
    for c in crops:
        f, _ = fit(c, frame, anchor=anchor, scale=scale)
        out.append(crisp(f, outline=outline, colors=colors))
    return out


# ----------------------------------------------------------------------------- texturas

def seamless(arr: np.ndarray) -> np.ndarray:
    """Offset blend: mistura a textura com ela mesma deslocada meia volta (bordas casam)."""
    h, w = arr.shape[:2]
    rolled = np.roll(np.roll(arr, h // 2, axis=0), w // 2, axis=1)
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.abs(xx - (w - 1) / 2) / (w / 2)
    dy = np.abs(yy - (h - 1) / 2) / (h / 2)
    wgt = np.clip(1.0 - np.maximum(dx, dy), 0, 1)
    wgt = np.clip(wgt * 2.2, 0, 1)[..., None]
    return arr * wgt + rolled * (1 - wgt)


def seamless_x(arr: np.ndarray) -> np.ndarray:
    h, w = arr.shape[:2]
    rolled = np.roll(arr, w // 2, axis=1)
    xx = np.arange(w)
    dx = np.abs(xx - (w - 1) / 2) / (w / 2)
    wgt = np.clip((1.0 - dx) * 2.2, 0, 1)[None, :, None]
    return arr * wgt + rolled * (1 - wgt)


def quant_tex(arr: np.ndarray, colors=40) -> np.ndarray:
    img = Image.fromarray((np.clip(arr[..., :3], 0, 1) * 255).astype(np.uint8), "RGB")
    q = img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb = np.asarray(q).astype(np.float32) / 255.0
    return np.concatenate([rgb, np.ones(rgb.shape[:2] + (1,), np.float32)], axis=-1)


def tex_resize(arr, size):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA").resize(size, Image.Resampling.BOX)
    return np.asarray(img).astype(np.float32) / 255.0


# ----------------------------------------------------------------------------- assets

def do_soldier():
    a = chroma_key(load_rgba(SRC / "soldier" / "soldier_sheet.png"))
    cells = union_crop(grid_cells(a, 5, 4))
    frames = build_frames(cells, (32, 40), anchor="bottom", colors=40)
    save(sheet(frames, 5), "soldier")


def do_bug():
    a = chroma_key(load_rgba(SRC / "bug" / "bug_sheet.png"))
    cells = union_crop(grid_cells(a, 4, 2))
    frames = build_frames(cells, (42, 42), colors=32)
    save(sheet(frames, 4), "bug")


def do_mother():
    a = chroma_key(load_rgba(SRC / "mother" / "mother_sheet.png"))
    m = region_frames(a, [(10, 280, 470, 720), (470, 270, 990, 730)])
    save(sheet(build_frames(m, (72, 72), colors=40, scale_from=m[1]), 2), "mother")
    l = region_frames(a, [(1050, 290, 1250, 460), (1280, 290, 1480, 460)])
    save(sheet(build_frames(l, (20, 20), colors=16), 2), "larva")
    f = region_frames(a, [(1030, 490, 1260, 750), (1260, 490, 1520, 750)])
    save(sheet(build_frames(f, (20, 20), colors=20, scale_from=f[1]), 2), "flower")


def do_nest():
    a = chroma_key(load_rgba(SRC / "nest" / "nest_sheet.png"))
    n = region_frames(a, [(180, 50, 600, 380), (920, 50, 1360, 380)])
    save(sheet(build_frames(n, (56, 48), colors=40, scale_from=n[1]), 2), "nest")
    h = region_frames(a, [(30, 440, 740, 980), (780, 440, 1530, 980)])
    save(sheet(build_frames(h, (96, 80), colors=48, scale_from=h[1]), 2), "heart")


def do_terrain():
    a = load_rgba(SRC / "terrain" / "terrain_sheet.png")
    H, W = a.shape[:2]
    hw, hh = W // 2, H // 2
    q = {
        "ground_sand": a[0:hh, 0:hw], "rock_top": a[0:hh, hw:W],
        "cliff": a[hh:H, 0:hw], "creep_ground": a[hh:H, hw:W],
    }
    for name in ("ground_sand", "rock_top", "creep_ground"):
        t = tex_resize(q[name], (256, 256))
        t = quant_tex(seamless(t), 48)
        save(t, name)
    # paredão: largura 128 sem emenda na horizontal, faixa do topo (borda arredondada das escamas)
    c = tex_resize(q["cliff"], (192, 192))
    c = seamless_x(c)[0:40, 0:192]
    c = tex_resize(c, (128, 32))  # achata um pouco: paredão baixo, escamas legíveis
    save(quant_tex(c, 32), "cliff")
    # mancha de território alienígena (alfa radial com ruído) para misturar em volta dos ninhos
    creep = tex_resize(q["creep_ground"], (256, 256))
    rng = np.random.default_rng(3)
    yy, xx = np.mgrid[0:256, 0:256]
    d = np.hypot(xx - 127.5, yy - 127.5) / 128.0
    ang = np.arctan2(yy - 127.5, xx - 127.5)
    wobble = 0.12 * np.sin(ang * 5 + 1.3) + 0.08 * np.sin(ang * 9 + 0.4)
    noise = rng.random((32, 32))
    noise = np.asarray(Image.fromarray((noise * 255).astype(np.uint8)).resize((256, 256), Image.Resampling.BICUBIC)) / 255.0
    alpha = np.clip((1.0 - d + wobble) * 2.2 - 0.6 + (noise - 0.5) * 0.5, 0, 1)
    blob = quant_tex(creep, 40)
    blob[..., 3] = (alpha > 0.5).astype(np.float32) * np.clip(alpha * 1.2, 0, 1)
    save(blob, "creep_blob")


def do_support():
    a = chroma_key(load_rgba(SRC / "support" / "support_sheet.png"))
    import json
    boxes_file = SRC / "support" / "boxes.json"
    if not boxes_file.exists():
        print("  (support: defina art_src/codex/support/boxes.json com as caixas)")
        return
    bx = json.loads(boxes_file.read_text())
    icons = region_frames(a, bx["pickups"])
    icons = [i[bbox(i[..., 3])[1]:, :] for i in icons]
    frames = []
    for ic in icons:
        f, _ = fit(ic, (37, 37), pad=2)
        frames.append(crisp(f, colors=24))
    save(sheet(frames, 6), "pickups")
    for name, size in (("buggy", (64, 40)), ("dropship", (112, 72))):
        fr = region_frames(a, [bx[name]])
        save(build_frames(fr, size, colors=32)[0], name)
    # robô: base e torre com a MESMA escala; a torre é centrada no corpo (pivô da rotação)
    def content(box):
        x0, y0, x1, y1 = box
        sub = a[y0:y1, x0:x1]
        b = bbox(sub[..., 3])
        return sub[b[1]:b[3], b[0]:b[2]], x0 + b[0]
    base_c, _ = content(bx["robot_base"])
    tur_c, tx0 = content(bx["robot_turret"])
    body_cx = bx["robot_turret_center_x"] - tx0
    right = tur_c.shape[1] - body_cx
    pad_left = max(0, int(right - body_cx))
    tur_c = np.pad(tur_c, ((0, 0), (pad_left, 0), (0, 0)))
    _, scale = fit(base_c, (48, 48), pad=2)
    tscale = scale * 1.0
    base_f, _ = fit(base_c, (48, 48), scale=scale)
    tur_f, _ = fit(tur_c, (48, 48), scale=tscale)
    save(sheet([crisp(base_f, colors=24), crisp(tur_f, colors=24)], 2), "robot")


def do_title():
    src = SRC / "title" / "title_bg.png"
    img = Image.open(src).convert("RGB")
    w, h = img.size
    th = int(w * 9 / 16)
    top = max(0, (h - th) // 2)
    img = img.crop((0, top, w, top + th)).resize((1280, 720), Image.Resampling.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "title_bg.png")
    print("  -> assets/sprites/title_bg.png 1280x720")


def do_tutorial():
    """Ilustrações do manual de campo: recorte 16:9 e redução para 800x450 (assets/ui/)."""
    out = OUT.parent / "ui"
    out.mkdir(parents=True, exist_ok=True)
    for name in ("tutorial_welcome", "tutorial_coop"):
        img = Image.open(SRC / "tutorial" / (name + ".png")).convert("RGB")
        w, h = img.size
        th = int(w * 9 / 16)
        top = max(0, (h - th) // 2)
        img = img.crop((0, top, w, top + th)).resize((800, 450), Image.Resampling.LANCZOS)
        img.save(out / (name + ".png"))
        print("  -> assets/ui/%s.png 800x450" % name)


def do_icon():
    """Ícone do jogo (janela, projeto e .exe): icon.png 256x256 e icon.ico 16..256 na raiz do projeto."""
    a = chroma_key(load_rgba(SRC / "icon" / "icon.png"))
    x0, y0, x1, y1 = bbox(a[..., 3])
    side = max(x1 - x0, y1 - y0)
    sq = np.zeros((side, side, 4), np.float32)
    ox, oy = (side - (x1 - x0)) // 2, (side - (y1 - y0)) // 2
    sq[oy:oy + y1 - y0, ox:ox + x1 - x0] = a[y0:y1, x0:x1]
    img = Image.fromarray((sq * 255).astype(np.uint8), "RGBA").resize((256, 256), Image.Resampling.LANCZOS)
    root = OUT.parent.parent
    img.save(root / "icon.png")
    img.save(root / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("  -> icon.png 256x256, icon.ico 16..256")


TASKS = {
    "soldier": do_soldier, "bug": do_bug, "mother": do_mother, "nest": do_nest,
    "terrain": do_terrain, "support": do_support, "title": do_title, "tutorial": do_tutorial,
    "icon": do_icon,
}

if __name__ == "__main__":
    which = sys.argv[1:] or list(TASKS)
    for name in which:
        src_dir = SRC / name
        if not src_dir.exists() or not any(src_dir.glob("*.png")):
            print(f"[{name}] sem imagem-fonte, pulando")
            continue
        print(f"[{name}]")
        TASKS[name]()
