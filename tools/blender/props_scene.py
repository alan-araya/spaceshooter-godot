"""Modela e renderiza as estruturas do jogo (gerador, metralhadora de ponto, relé) no Blender.

Não rode direto: use `python -I tools/build_props.py`, que chama o Blender em segundo plano
com este arquivo e depois transforma os renders em sprites.

Tudo é modelado aqui, por código, com formas simples (sem arquivos .blend nem modelos de
terceiros). Unidade: 1 = 1 pixel do jogo. Projeção: a mesma dos muros — o chão não encurta e
cada unidade de altura sobe 0,75 px na tela (câmera ortográfica inclinada + pixel alongado).
Cada peça sai em três passes, 4× maiores que o sprite final:
  *_c.png  cor chapada dos materiais, com vincos e quinas marcados (sem luz: a luz é do jogo)
  *_n.png  normais no espaço da câmera (matcap de normais)
  *_e.png  máscara das partes que emitem luz (branco) sobre preto
"""
import math
import os
import sys

import bpy

OUT = sys.argv[sys.argv.index("--") + 1]
SS = 4  # superamostragem
THETA = math.atan(0.75)  # inclinação da câmera: altura sobe 0,75 px por unidade


def srgb(r, g, b):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), 1.0)


MATS = {}


def mat(name, rgb, emit=False):
    m = bpy.data.materials.new(name)
    m.diffuse_color = srgb(*rgb)
    m["emit"] = emit
    MATS[name] = m
    return m


def setup_materials():
    mat("steel_dark", (58, 64, 74))
    mat("steel", (96, 105, 118))
    mat("steel_light", (138, 148, 162))
    mat("concrete", (134, 130, 124))
    mat("concrete_dark", (98, 94, 88))
    mat("hazard", (214, 168, 48))
    mat("rubber", (32, 32, 36))
    mat("brass", (176, 134, 62))
    mat("olive", (86, 96, 60))
    mat("olive_dark", (62, 70, 44))
    mat("bag", (170, 148, 112))
    mat("bag_dark", (146, 124, 92))
    mat("glass", (28, 46, 64))
    mat("cyan", (130, 240, 255), True)
    mat("green", (120, 255, 120), True)
    mat("white", (255, 255, 255), True)


def _finish(o, name, material, bevel):
    o.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        mod = o.modifiers.new("bevel", 'BEVEL')
        mod.width = bevel
        mod.segments = 1
    o.data.materials.append(MATS[material])
    return o


def box(group, name, size, pos, material, bevel=0.6, rot=(0.0, 0.0, 0.0)):
    """Caixa de tamanho `size`; `pos` = centro em x/y e BASE em z."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(pos[0], pos[1], pos[2] + size[2] * 0.5), rotation=rot)
    o = bpy.context.object
    o.scale = size
    group.append(_finish(o, name, material, bevel))
    return o


def cyl(group, name, r, h, pos, material, verts=12, bevel=0.4, rot=(0.0, 0.0, 0.0), r_top=None, centered=False):
    """Cilindro (ou tronco de cone com r_top); `pos` = centro em x/y e BASE em z (ou centro, se centered)."""
    z = pos[2] if centered else pos[2] + h * 0.5
    if r_top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=(pos[0], pos[1], z), rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r_top, depth=h, location=(pos[0], pos[1], z), rotation=rot)
    group.append(_finish(bpy.context.object, name, material, bevel))
    return bpy.context.object


def ball(group, name, r, pos, material, scale=(1.0, 1.0, 1.0), rot=(0.0, 0.0, 0.0), seg=10, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=pos, rotation=rot)
    o = bpy.context.object
    o.scale = scale
    group.append(_finish(o, name, material, 0.0))
    return o


# ----------------------------------------------------------------------------- peças

def generator():
    g = []
    box(g, "plinth", (54, 26, 4), (0, 0, 0), "concrete_dark", 1.0)
    box(g, "stripe", (48, 1.0, 2.0), (0, -13.1, 1.0), "hazard", 0.0)
    box(g, "housing", (44, 20, 15), (0, 0, 4), "steel", 1.5)
    box(g, "deck", (38, 15, 3), (0, 0, 19), "steel_light", 0.8)
    cyl(g, "core_base", 8.0, 6.0, (0, 0, 22), "steel_dark", 12, 0.6)
    cyl(g, "core_glow", 6.0, 5.0, (0, 0, 28), "cyan", 12, 0.0)
    ball(g, "core_dome", 6.0, (0, 0, 33), "cyan", (1.0, 1.0, 0.6))
    for i in range(4):
        a = math.pi * 0.25 + i * math.pi * 0.5
        box(g, "post%d" % i, (1.6, 1.6, 12.5), (math.cos(a) * 8.6, math.sin(a) * 8.6, 22), "steel_light", 0.3)
    for sx in (-1, 1):
        cyl(g, "tank", 5.6, 18.0, (sx * 21, 2, 4), "olive", 12, 0.8)
        cyl(g, "tank_cap", 4.0, 2.2, (sx * 21, 2, 22), "steel_dark", 10, 0.4)
        cyl(g, "tank_band", 5.9, 2.0, (sx * 21, 2, 11), "olive_dark", 12, 0.0)
        cyl(g, "pipe", 1.3, 13.0, (sx * 14, 2, 21.5), "brass", 8, 0.0, (0.0, math.pi * 0.5, 0.0), centered=True)
        box(g, "bolt", (2.2, 2.2, 1.2), (sx * 16, -7, 19), "steel_dark", 0.3)
        box(g, "bolt", (2.2, 2.2, 1.2), (sx * 16, 5, 19), "steel_dark", 0.3)
    # painel frontal: três luzes e respiros
    box(g, "panel", (20, 1.2, 8.4), (0, -10.4, 8.0), "steel_dark", 0.3)
    for x in (-6, 0, 6):
        box(g, "led", (3.2, 0.9, 2.2), (x, -11.2, 12.8), "green", 0.0)
    for x in (-7.5, -4.5, -1.5, 1.5, 4.5, 7.5):
        box(g, "vent", (1.8, 0.9, 2.6), (x, -11.2, 9.0), "rubber", 0.0)
    return g


def turret_base():
    g = []
    cyl(g, "pad", 16.0, 1.6, (0, 0, 0), "concrete_dark", 10, 0.5)
    n = 9
    for layer, (radius, z, off) in enumerate([(13.0, 1.6, 0.0), (12.4, 4.6, 0.5)]):
        for i in range(n):
            a = (i + off) / n * math.tau
            # abertura atrás (norte) na fiada de cima, por onde o operador entra
            if layer == 1 and abs(math.sin(a) - 1.0) < 0.12:
                continue
            ball(g, "bag", 1.0, (math.cos(a) * radius, math.sin(a) * radius, z + 1.7),
                 "bag" if (i + layer) % 2 == 0 else "bag_dark", (4.9, 2.9, 1.9), (0.0, 0.0, a + math.pi * 0.5), 8, 5)
    cyl(g, "pedestal", 3.4, 9.0, (0, 0, 1.6), "steel_dark", 8, 0.5)
    for i in range(3):
        a = math.pi * 0.5 + i * math.tau / 3.0
        box(g, "leg", (7.0, 1.6, 1.4), (math.cos(a) * 4.0, math.sin(a) * 4.0, 1.6), "steel", 0.2, (0.0, 0.0, a))
    return g


def turret_gun():
    """Visto de cima; cano no +X; gira em torno da origem."""
    g = []
    box(g, "receiver", (14.0, 5.5, 5.0), (1.0, 0.0, 0.0), "steel", 0.7)
    box(g, "cover", (8.0, 4.0, 1.2), (1.0, 0.0, 5.0), "steel_dark", 0.3)
    cyl(g, "jacket", 1.9, 7.0, (11.5, 0.0, 2.6), "steel_dark", 8, 0.0, (0.0, math.pi * 0.5, 0.0), centered=True)
    cyl(g, "barrel", 1.15, 14.0, (15.0, 0.0, 2.6), "steel_light", 8, 0.0, (0.0, math.pi * 0.5, 0.0), centered=True)
    cyl(g, "muzzle", 1.7, 2.4, (22.0, 0.0, 2.6), "rubber", 8, 0.0, (0.0, math.pi * 0.5, 0.0), centered=True)
    box(g, "shield", (1.6, 13.0, 6.5), (6.5, 0.0, 0.0), "steel_light", 0.4)
    box(g, "shield_slot", (1.8, 3.0, 2.0), (6.5, 0.0, 4.6), "rubber", 0.0)
    box(g, "ammo", (6.5, 5.0, 4.6), (0.5, 5.4, 0.0), "olive", 0.5)
    box(g, "ammo_lid", (5.5, 4.0, 0.8), (0.5, 5.4, 4.6), "olive_dark", 0.2)
    box(g, "belt", (3.0, 1.6, 1.0), (1.5, 2.6, 4.4), "brass", 0.0)
    for sy in (-1, 1):
        box(g, "grip", (3.4, 1.3, 2.2), (-7.4, sy * 2.2, 1.5), "rubber", 0.2)
    box(g, "back", (1.6, 6.0, 4.4), (-6.2, 0.0, 0.3), "steel_dark", 0.3)
    return g


def relay():
    g = []
    cyl(g, "plate", 13.0, 1.5, (0, 0, 0), "steel_dark", 12, 0.4)
    cyl(g, "ring", 11.0, 0.5, (0, 0, 1.5), "hazard", 12, 0.0)
    cyl(g, "inner", 9.4, 0.9, (0, 0, 1.5), "steel", 12, 0.2)
    box(g, "console", (9.0, 7.0, 9.0), (-5.0, -2.5, 2.2), "steel", 0.8)
    box(g, "console_top", (9.6, 7.6, 1.2), (-5.0, -2.5, 11.2), "steel_light", 0.3)
    box(g, "screen", (6.0, 0.8, 3.6), (-5.0, -6.2, 6.4), "glass", 0.0)
    box(g, "screen_led", (2.0, 0.9, 1.0), (-6.4, -6.3, 7.8), "green", 0.0)
    cyl(g, "mast_foot", 3.0, 3.0, (3.0, 1.0, 2.2), "steel_dark", 8, 0.4)
    cyl(g, "mast", 1.5, 34.0, (3.0, 1.0, 4.0), "steel_light", 8, 0.0)
    box(g, "brace", (1.2, 1.2, 12.0), (0.2, 1.0, 3.0), "steel", 0.0, (0.0, 0.32, 0.0))
    cyl(g, "dish", 6.0, 3.0, (3.0, -1.4, 29.0), "steel_light", 10, 0.0, (math.radians(62.0), 0.0, 0.0), r_top=1.2, centered=True)
    cyl(g, "lamp_socket", 2.2, 1.6, (3.0, 1.0, 38.0), "rubber", 8, 0.0)
    ball(g, "lamp", 3.2, (3.0, 1.0, 41.4), "white", (1.0, 1.0, 1.0))
    return g


# ----------------------------------------------------------------------------- render

def render_piece(name, objs, width, height, look_y, top_down=False):
    """Renderiza `objs` num quadro de width×height px finais; look_y = quanto o centro do quadro fica
    acima (norte) da origem da peça, em px."""
    sc = bpy.context.scene
    for o in sc.objects:
        if o.type == 'MESH':
            o.hide_render = o not in objs
    theta = 0.0 if top_down else THETA
    cam = sc.camera
    cam.data.ortho_scale = float(width)
    cam.rotation_euler = (theta, 0.0, 0.0)
    dist = 400.0
    cam.location = (0.0, look_y - dist * math.sin(theta), dist * math.cos(theta))
    r = sc.render
    r.resolution_x = width * SS
    r.resolution_y = height * SS
    r.pixel_aspect_x = 1.0 / math.cos(theta)
    r.pixel_aspect_y = 1.0
    sh = sc.display.shading
    # cor
    sh.light = 'FLAT'
    sh.color_type = 'MATERIAL'
    sh.show_cavity = True
    sh.cavity_type = 'BOTH'
    sh.cavity_ridge_factor = 1.6
    sh.cavity_valley_factor = 1.3
    sh.curvature_ridge_factor = 1.3
    sh.curvature_valley_factor = 1.1
    r.filepath = os.path.join(OUT, name + "_c.png")
    bpy.ops.render.render(write_still=True)
    # normais (espaço da câmera)
    sh.light = 'MATCAP'
    sh.studio_light = 'check_normal+y.exr'
    sh.color_type = 'SINGLE'
    sh.single_color = (1.0, 1.0, 1.0)
    sh.show_cavity = False
    r.filepath = os.path.join(OUT, name + "_n.png")
    bpy.ops.render.render(write_still=True)
    # máscara de emissão
    saved = {m.name: tuple(m.diffuse_color) for m in MATS.values()}
    for m in MATS.values():
        m.diffuse_color = (1.0, 1.0, 1.0, 1.0) if m["emit"] else (0.0, 0.0, 0.0, 1.0)
    sh.light = 'FLAT'
    sh.color_type = 'MATERIAL'
    r.filepath = os.path.join(OUT, name + "_e.png")
    bpy.ops.render.render(write_still=True)
    for m in MATS.values():
        m.diffuse_color = saved[m.name]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.render.film_transparent = True
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'
    sc.display.render_aa = 'OFF'
    sc.display.shading.show_shadows = False
    sc.display.shading.show_object_outline = False
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = 'ORTHO'
    cam_d.sensor_fit = 'HORIZONTAL'
    cam_d.clip_start = 1.0
    cam_d.clip_end = 2000.0
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    setup_materials()
    # nome, objetos, largura, altura, deslocamento do centro (px acima da origem), visto de cima
    render_piece("generator", generator(), 64, 60, 14.0)
    render_piece("turret_base", turret_base(), 44, 44, 4.0)
    render_piece("turret_gun", turret_gun(), 48, 20, 0.0, True)
    render_piece("relay", relay(), 40, 60, 16.0)
    print("PROPS ok")


main()
