# CLAUDE.md — Enxame 2199 (Godot 4.8, GDScript)

Leia `docs/GDD.md` antes de mudar regras, telas ou assets.

## Comandos
- Godot: `D:\Godot Global\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe` (o MCP `godot` usa o mesmo).
- Depois de criar/renomear um script com `class_name`: `godot --headless --path . --import` (regera o cache de classes).
- Testes: `godot --headless --path . -- --test` (precisa terminar com `0 falhas`).
- Screenshot de uma missão: `godot --path . -- --mission=3 --autostart --shot=<png> --shot-after=6 --quit-after-shot`.
- Desempenho: os testes imprimem o perfil por seção do `World.update`; `-- --mission=1 --autostart --stress` mede um frame renderizado.
- Balanceamento das defesas: `-- --test --probe` (bot parado no gerador, 1 jogador, Soldado) e
  `-- --test --timeline=m3` (estado da missão segundo a segundo).
- Mapas das defesas em camadas: `python -I tools/build_maps.py` (imprime os mapas para colar em missions.gd).
- Rede com 2 instâncias: host `-- --net-host --mission=3 --net-start-when=2 --net-log --quit-after=30` (pode ser
  `--headless`) e cliente `-- --net-join=127.0.0.1 --net-bot --net-log --quit-after=24`. `-- --loopback` = réplica sem rede.
- Visual: `-- --gfx=alto|medio|baixo`, `-- --seed=N` (screenshot repetível), `-- --shot-all=PASTA --shot-after=8`
  (as seis missões numa janela só). `-- --fx-demo=SEG` dispara uma explosão ao lado do P1 e
  `-- --hurt-demo=SEG` o aviso de dano, para screenshot (só visual). Relevo dos sprites:
  `python -I tools/build_normals.py` (rode depois de mudar um sprite). Muros: `python -I tools/build_structures.py`.
  Estruturas 3D (gerador, metralhadora, relé): `python -I tools/build_props.py` (roda o Blender sem janela;
  caminho na variável BLENDER). Depois de gerar PNG novo: `godot --headless --path . --import`.
  FPS: `godot --path . --disable-vsync --print-fps -- --mission=5 --autostart --seed=11 --quit-after=40 > fps.txt 2>&1`
  (sempre para arquivo: pelo pipe o número sai errado).
- Arte: `python -I tools/process_art.py [soldier|bug|mother|nest|terrain|support|title]`.

## Regras do projeto
1. **IP**: mecânicas do Triumph! WAR 2099 podem ser replicadas; sprites, sons, mapas, textos e nomes não.
   Nunca extrair nem traçar assets de `D:\Program Files\WAR2099v23`. Arte nova sai do Codex (prompts no GDD §7) ou de código.
2. **Balanceamento só em `scripts/core/bal.gd`.** Missões só em `scripts/sim/missions.gd` (dados + `validate`).
3. **Simulação sem física do Godot**: `Grid.move_circle`, `SpatialHash`, `FlowField`. Atores são `Node2D` com `tick(dt)`
   chamado pelo `World` e `sync_visual()` no fim do frame. Lógica não lê o visual.
4. Referências entre unidades podem apontar para nós já liberados: sempre `Unit.ok(x)` antes de usar.
5. GDScript: não use `:=` com valores Variant (dicionários `Bal.*`, elementos de Array, parâmetros sem tipo) — dá erro de
   inferência. Declare o tipo (`var x: float = Bal.BUG.speed`).
6. Mudou mecânica? Acrescente um caso em `tests/sim_tests.gd`. Mudou visual? Tire screenshot e olhe.
7. Texto de UI em pt-BR.
8. Campos de fluxo (Dijkstra em GDScript) são o custo dominante: um campo a cada 4 quadros, pulando os sem uso.
   Não volte a recalcular todo frame.
10. Rede: a simulação só produz efeitos via `world.sfx()`, `world.fx.*`, `world.decal_layer.*`, `world.toast()`,
   `world.shake()` (gravam eventos para os clientes). Entidade nova com estado visível = campo novo em
   `Snapshot.encode/decode` + `Replica._create/_apply_ent`, senão o cliente não vê. O teste de loopback pega isso.
11. Visual (GDD §10): luz, sombra, partículas e pós só LEEM o estado — nunca escrevem na simulação nem usam
   `world.rng` (`Fx` tem o próprio `rnd`; os testes `_test_visuals` e `_test_effects_keep_sim` comparam a simulação
   com e sem a parte visual). Emissivo = `Art.unshaded()` +
   `visibility_layer = Stage.LAYER_BOTH` no nó e nos pais. Desenho sem mapa de relevo = `Art.flat_material()`,
   senão fica mais claro que o chão. Máximo de 16 luzes por item: clarão novo passa por `world.lights.flash()`.
   Clima de missão só em `scripts/world/ambience.gd`.
9. Geração de imagem no Codex: rode as chamadas em SEQUÊNCIA (em paralelo o WSL quebra). Fundo magenta; o
   `process_art.py` remove só o magenta ligado às bordas (sprites têm rosa/roxo por dentro).
