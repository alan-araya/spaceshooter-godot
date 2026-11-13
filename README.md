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
- `--gfx=alto|medio|baixo` escolhe a qualidade gráfica só nesta execução; `--seed=N` fixa a semente da missão.
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
| P3, P4 | Controle 1, 2 | A / RT | LB (ou X) | RB (ou B) | LT |

Com 1 jogador, qualquer teclado ou controle comanda o P1. Teclas 1–4: ordem direta. Esc/Start: pausa.

## Jogar em rede (LAN)

1. Um jogador escolhe **JOGAR EM REDE → HOSPEDAR PARTIDA**. O lobby mostra o IP dele (porta UDP 24565).
   Na primeira vez o Windows pede permissão no firewall: libere em **redes privadas**.
2. Os outros digitam esse IP e escolhem **ENTRAR** (até 4 jogadores, um por PC).
3. O host troca missão e dificuldade no lobby e aperta **COMEÇAR**.

Pela internet sem servidor: todos instalam uma rede virtual (ex.: Tailscale) e usam o IP dela.
Em rede a partida não pausa (Esc abre um menu por cima).

Teste automático com duas instâncias no mesmo PC:

```bash
godot --headless --path . -- --net-host --mission=3 --net-start-when=2 --net-log --quit-after=30
```

```bash
godot --path . -- --net-join=127.0.0.1 --net-bot --net-log --quit-after=24
```

Sem rede, `-- --loopback --mission=3 --autostart` joga localmente desenhando tudo pelo mesmo caminho
do cliente (snapshots + eventos), útil para achar o que não está sendo replicado.

## Gráficos

Luz dinâmica 2D com mapas de relevo, sombras projetadas pelo sol, brilho e correção de cor; cada missão tem
um clima (hora do dia). O nível de qualidade fica no menu principal (**GRÁFICOS: ALTO / MÉDIO / BAIXO**).
Detalhes em [docs/GDD.md](docs/GDD.md) §10; comparação antes/depois em `docs/shots/`.

Para medir FPS, grave a saída num arquivo (pelo pipe do terminal o número sai distorcido):

```bash
godot --path . --disable-vsync --print-fps -- --mission=5 --autostart --seed=11 --quit-after=40 > fps.txt 2>&1
```

## Estrutura

```
autoload/      Game (progresso), InputSetup (ações por jogador), Art (sprites por contrato), Sfx (som sintetizado), Net (ENet/lobby/RPCs)
scripts/core/  Bal — TODOS os números de jogabilidade
scripts/sim/   Grid, FlowField, SpatialHash, Missions (dados)
scripts/world/ World (loop), GroundBuilder (terreno 3/4), Projectiles, Fx, camadas,
               Stage (palco + pós), Lighting (luzes), Shadows (sombras), Ambience (clima por missão),
               Atmosphere (nuvens, névoa, partículas no ar)
shaders/       composição final, desfoque do brilho, ácido, silhueta de sombra, relevo plano, nuvens, névoa
scripts/actors/ Commander, Soldier, Robot, Bug, Nest, Prop, Vehicle
scripts/net/   CmdInput (comandos), Snapshot (estado binário), Replica (cliente: interpolação + eventos)
scripts/ui/    Main (telas, lobby, laço host/cliente), Hud, UiKit (tema)
assets/sprites/ sprites finais (gerados pelo pipeline)
art_src/       imagens-fonte geradas por IA (ignoradas pelo Godot)
tools/         process_art.py (fonte → sprites), build_normals.py (mapas de relevo), build_structures.py (muros),
               build_props.py + blender/props_scene.py (gerador, metralhadora e relé modelados no Blender)
tests/         testes headless
```

## Arte

As imagens-fonte foram geradas com o Codex (gpt-image) a partir dos prompts do GDD §7 e ficam em
`art_src/codex/`. Para regerar os sprites do jogo:

```bash
python -I tools/process_art.py
```

Depois de trocar um sprite, regere o mapa de relevo dele (`<nome>_n.png`) e reimporte:

```bash
python -I tools/build_normals.py
```

Trocar qualquer sprite = substituir o PNG em `assets/sprites/` mantendo a grade de frames do contrato.
Se um PNG faltar, o jogo desenha um placeholder procedural.
