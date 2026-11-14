# Licenças dos assets

| Asset | Origem | Licença / observação |
|---|---|---|
| `assets/sprites/*.png` (soldado, aracnídeo, filhote, matriarca, flor, ninho, coração, pickups, buggy, nave, robô, terreno, arte do menu) | Gerados por IA (Codex / gpt-image) a partir de prompts originais em `docs/GDD.md` §7; imagens-fonte em `art_src/codex/`; reduzidos por `tools/process_art.py` | Criação própria do projeto. Nenhum asset do jogo original foi usado como entrada. |
| `icon.png`, `icon.ico` (ícone do jogo, da janela e do .exe) | Gerado por IA (Codex / gpt-image) a partir de prompt original; fonte em `art_src/codex/icon/`; recortado por `tools/process_art.py icon` | Criação própria do projeto. |
| `assets/sprites/*_n.png` (mapas de relevo) | Calculados dos próprios sprites por `tools/build_normals.py` | Criação própria. |
| `assets/sprites/walls*.png` (muros e portões) | Texturas procedurais geradas por `tools/build_structures.py` | Criação própria. |
| `assets/sprites/generator*.png`, `turret_base*.png`, `turret_gun*.png`, `relay*.png` | Modelados por código e renderizados no Blender por `tools/build_props.py` (cena em `tools/blender/props_scene.py`, renders em `art_src/blender/`) | Criação própria. Sem modelos de terceiros. |
| `assets/ui/tutorial_*.png` (ilustrações do manual de campo) | Gerados por IA (Codex / gpt-image) com os prompts em `art_src/codex/tutorial/`; reduzidos por `tools/process_art.py tutorial` | Criação própria do projeto. |
| Efeitos sonoros | Sintetizados em tempo de execução por `autoload/sfx.gd` | Criação própria. |
| Fonte da interface | Fonte padrão do Godot (embutida no motor) | Licença do Godot (MIT) / Open Sans e Noto (OFL). |

Regra: todo asset de terceiros que entrar precisa de licença compatível (preferir CC0) e de uma linha aqui.
