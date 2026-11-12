# CLAUDE.md — Enxame 2199 (Godot 4.8, GDScript)

Leia `docs/GDD.md` antes de mudar regras, telas ou assets.

## Comandos
- Godot: `D:\Godot Global\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe` (o MCP `godot` usa o mesmo).
- Depois de criar/renomear um script com `class_name`: `godot --headless --path . --import` (regera o cache de classes).
- Testes: `godot --headless --path . -- --test` (precisa terminar com `0 falhas`).
- Screenshot de uma missão: `godot --path . -- --mission=3 --autostart --shot=<png> --shot-after=6 --quit-after-shot`.
- Desempenho: os testes imprimem o perfil por seção do `World.update`; `-- --mission=1 --autostart --stress` mede um frame renderizado.
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
9. Geração de imagem no Codex: rode as chamadas em SEQUÊNCIA (em paralelo o WSL quebra). Fundo magenta; o
   `process_art.py` remove só o magenta ligado às bordas (sprites têm rosa/roxo por dentro).
