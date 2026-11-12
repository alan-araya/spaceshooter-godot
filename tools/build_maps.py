"""Gera os mapas ASCII (40x20) das missões de defesa com muros em camadas.
Uso: python -I tools/build_maps.py  -> imprime os mapas prontos para colar em scripts/sim/missions.gd.
Desenhar por código evita erro de contagem de colunas e deixa as fortificações simétricas."""

W, H = 40, 20


class Map:
    def __init__(self, fill="."):
        self.g = [[fill] * W for _ in range(H)]

    def put(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.g[y][x] = c

    def hline(self, x0, x1, y, c="="):
        for x in range(x0, x1 + 1):
            self.put(x, y, c)

    def vline(self, x, y0, y1, c="="):
        for y in range(y0, y1 + 1):
            self.put(x, y, c)

    def rect(self, x0, y0, x1, y1, c="="):
        self.hline(x0, x1, y0, c)
        self.hline(x0, x1, y1, c)
        self.vline(x0, y0, y1, c)
        self.vline(x1, y0, y1, c)

    def fill(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def flowers(self, cx, cy):
        self.fill(cx - 1, cy - 1, cx + 1, cy + 1, "f")
        self.put(cx, cy, "F")

    def patch(self, x, y, w=3, h=2, c=","):
        self.fill(x, y, x + w - 1, y + h - 1, c)

    def rows(self):
        return ["".join(r) for r in self.g]


def posto_eco():
    """Missão 3 — o posto do MVP com um segundo anel de sacos de areia."""
    m = Map()
    for (x, y) in [(2, 1), (34, 1), (2, 18), (33, 18)]:
        m.put(x, y, "N")
    for (x, y) in [(23, 0), (24, 0), (4, 2), (5, 2), (34, 10), (35, 10), (35, 11), (4, 17), (5, 17), (5, 16)]:
        m.put(x, y, "^")
    m.flowers(6, 6)
    m.flowers(33, 6)
    m.flowers(6, 13)
    m.flowers(32, 15)
    m.patch(14, 1)
    m.patch(29, 3)
    m.patch(2, 9)
    m.patch(18, 17)
    # anel externo (sacos de areia) com portões no meio de cada lado
    m.rect(9, 3, 28, 15)
    for (x, y) in [(18, 3), (19, 3), (18, 15), (19, 15), (9, 9), (28, 9)]:
        m.put(x, y, "+")
    # posto interno
    m.fill(13, 6, 24, 12, "_")
    m.rect(13, 6, 24, 12)
    for (x, y) in [(16, 6), (21, 6), (16, 12), (21, 12), (13, 9), (24, 9)]:
        m.put(x, y, "+")
    # barricadas soltas entre os anéis (cobertura)
    for (x, y) in [(11, 5), (12, 5), (25, 5), (26, 5), (11, 13), (12, 13), (25, 13), (26, 13)]:
        m.put(x, y, "=")
    m.put(17, 9, "C")
    m.put(20, 9, "G")
    for (x, y) in [(16, 8), (21, 8), (16, 10), (21, 10)]:
        m.put(x, y, "s")
    m.put(26, 14, "6")
    return m.rows()


def trincheiras():
    """Missão 4 — linhas de trincheira de norte a sul, com metralhadoras de ponto atrás de cada linha."""
    m = Map()
    # ninhos e território alienígena ao norte
    for (x, y) in [(5, 1), (20, 1), (34, 2)]:
        m.put(x, y, "N")
    for (x, y) in [(11, 1), (12, 1), (12, 2), (27, 1), (28, 1), (27, 2)]:
        m.put(x, y, "^")
    m.flowers(9, 4)
    m.flowers(30, 4)
    m.patch(15, 3)
    m.patch(23, 4)
    # rochas laterais afunilam o avanço
    m.fill(0, 6, 1, 11, "#")
    m.fill(38, 6, 39, 11, "#")
    # 1ª linha (mais avançada)
    m.hline(2, 37, 7)
    for x in (6, 13, 20, 26, 33):
        m.put(x, 7, "+")
    for x in (12, 27):
        m.put(x, 8, "T")
    # 2ª linha
    m.hline(2, 37, 11)
    for x in (4, 12, 19, 27, 35):
        m.put(x, 11, "+")
    for x in (9, 30):
        m.put(x, 12, "T")
    m.patch(3, 13, 4, 2)
    m.patch(33, 14, 3, 2)
    # bunker do gerador
    m.fill(14, 15, 25, 19, "_")
    m.rect(14, 15, 25, 19)
    for (x, y) in [(17, 15), (22, 15), (14, 17), (25, 17)]:
        m.put(x, y, "+")
    m.put(16, 17, "C")
    m.put(20, 17, "G")
    m.put(19, 16, "T")
    for (x, y) in [(11, 9), (28, 9), (17, 13), (22, 13), (10, 14), (29, 14)]:
        m.put(x, y, "s")
    m.put(5, 16, "1")
    m.put(34, 17, "6")
    return m.rows()


def fortaleza():
    """Missão 5 — fortaleza concêntrica (muralha, pátio, muralha interna, torre do gerador)."""
    m = Map()
    # fosso de ácido em trechos (as entradas ficam nos portões)
    m.hline(4, 15, 0, "~")
    m.hline(24, 35, 0, "~")
    m.hline(4, 15, 19, "~")
    m.hline(24, 35, 19, "~")
    m.vline(0, 3, 7, "~")
    m.vline(0, 12, 16, "~")
    m.vline(39, 3, 7, "~")
    m.vline(39, 12, 16, "~")
    # muralha externa + torres de canto
    m.rect(2, 1, 37, 18)
    for (x, y) in [(3, 2), (36, 2), (3, 17), (36, 17)]:
        m.put(x, y, "=")
    for (x, y) in [(19, 1), (20, 1), (19, 18), (20, 18), (2, 9), (2, 10), (37, 9), (37, 10)]:
        m.put(x, y, "+")
    for (x, y) in [(5, 3), (34, 3), (5, 16), (34, 16)]:
        m.put(x, y, "T")
    # pátio: flores (perigo se os insetos entrarem)
    m.flowers(5, 9)
    m.flowers(34, 10)
    m.patch(11, 2, 4, 1)
    m.patch(25, 17, 4, 1)
    # muralha interna, portões desalinhados com os externos (caminho em zigue-zague)
    m.rect(8, 4, 31, 15)
    for (x, y) in [(14, 4), (25, 15), (8, 6), (31, 13)]:
        m.put(x, y, "+")
    for (x, y) in [(11, 9), (28, 10), (19, 6), (20, 13)]:
        m.put(x, y, "T")
    # torre (keep) com o gerador
    m.fill(14, 7, 25, 12, "_")
    m.rect(14, 7, 25, 12)
    for (x, y) in [(14, 10), (25, 9)]:
        m.put(x, y, "+")
    m.put(17, 10, "C")
    m.put(20, 9, "G")
    m.put(23, 11, "T")
    for (x, y) in [(10, 6), (29, 6), (10, 13), (29, 13), (16, 8), (22, 8)]:
        m.put(x, y, "s")
    m.put(16, 11, "6")
    m.put(33, 5, "1")
    return m.rows()


if __name__ == "__main__":
    for name, fn in (("posto_eco", posto_eco), ("trincheiras", trincheiras), ("fortaleza", fortaleza)):
        rows = fn()
        assert len(rows) == H and all(len(r) == W for r in rows)
        print(f"# {name}")
        for r in rows:
            print(f'\t\t\t"{r}",')
