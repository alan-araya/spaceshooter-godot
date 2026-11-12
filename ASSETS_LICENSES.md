# Licenças dos assets

| Asset | Origem | Licença / observação |
|---|---|---|
| `assets/sprites/*.png` (soldado, aracnídeo, filhote, matriarca, flor, ninho, coração, pickups, buggy, nave, robô, terreno, arte do menu) | Gerados por IA (Codex / gpt-image) a partir de prompts originais em `docs/GDD.md` §7; imagens-fonte em `art_src/codex/`; reduzidos por `tools/process_art.py` | Criação própria do projeto. Nenhum asset do jogo original foi usado como entrada. |
| Efeitos sonoros | Sintetizados em tempo de execução por `autoload/sfx.gd` | Criação própria. |
| Fonte da interface | Fonte padrão do Godot (embutida no motor) | Licença do Godot (MIT) / Open Sans e Noto (OFL). |

Regra: todo asset de terceiros que entrar precisa de licença compatível (preferir CC0) e de uma linha aqui.
