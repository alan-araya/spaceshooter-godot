# ENXAME 2199 (Godot 4.8)

Ação tática retrô em tela fixa: um comandante e o seu pelotão contra enxames de aracnídeos num
planeta desértico. Até 4 jogadores no mesmo PC. Mecânica inspirada em *Triumph! WAR 2099*
(2001, freeware), com **arte, nomes e textos originais**. Porte do MVP web
(`github.com/alan-araya/shootergame.mvp`).

Design completo, fluxo de telas e contrato de assets: [docs/GDD.md](docs/GDD.md).

## Rodar

Abra a pasta no Godot 4.8 (ou rode pelo MCP do Godot). Linha de comando:

```bash
godot --path .
```

Atalhos de depuração (argumentos depois de `--`):

```bash
godot --path . -- --mission=4 --autostart --players=2 --difficulty=dificil
```

- `--mission=N` vai direto ao briefing da missão N; com `--autostart` pula o briefing.
- `--unlockall` libera todas as missões na seleção.
- `--shot=arquivo.png --shot-after=5 --quit-after-shot` salva um screenshot e sai.
- F9 (build de depuração): destrói todos os ninhos.

## Testes

```bash
godot --headless --path . -- --test
```

Valida as missões, roda as 5 missões por 45 s com bots, testa cada pickup, flor → matriarca,
cristal/extração, respawn do comandante e um estresse de desempenho (200 insetos vivos).
Sai com código 1 se algo falhar.

## Controles

| Jogador | Mover | Fogo | Ordem | Granada | Travar mira |
|---|---|---|---|---|---|
| P1 | WASD | Espaço / J | Q / K | E / L | Shift |
| P2 | Setas | / ou Num0 | . ou Num1 | , ou Num2 | Ctrl ou Num3 |
| P3, P4 | Controle 1, 2 | A / RT | X | B / LT | LB / RB |

Com 1 jogador, qualquer teclado ou controle comanda o P1. Teclas 1–4: ordem direta. Esc/Start: pausa.

## Estrutura

```
autoload/      Game (progresso), InputSetup (ações por jogador), Art (sprites por contrato), Sfx (som sintetizado)
scripts/core/  Bal — TODOS os números de jogabilidade
scripts/sim/   Grid, FlowField, SpatialHash, Missions (dados)
scripts/world/ World (loop), GroundBuilder (terreno 3/4), Projectiles, Fx, camadas
scripts/actors/ Commander, Soldier, Robot, Bug, Nest, Prop, Vehicle
scripts/ui/    Main (telas), Hud, UiKit (tema)
assets/sprites/ sprites finais (gerados pelo pipeline)
art_src/       imagens-fonte geradas por IA (ignoradas pelo Godot)
tools/         process_art.py (fonte → sprites)
tests/         testes headless
```

## Arte

As imagens-fonte foram geradas com o Codex (gpt-image) a partir dos prompts do GDD §7 e ficam em
`art_src/codex/`. Para regerar os sprites do jogo:

```bash
python -I tools/process_art.py
```

Trocar qualquer sprite = substituir o PNG em `assets/sprites/` mantendo a grade de frames do contrato.
Se um PNG faltar, o jogo desenha um placeholder procedural.
