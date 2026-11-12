# ENXAME 2199 — Game Design Document (versão Godot)

> Documento-base do projeto Godot. Serve para quem programa, para quem desenha a arte
> e para as IAs que geram assets (Codex/GPT, FAL). Idioma do jogo: **pt-BR**.
> Engine: **Godot 4.8 (GDScript)**. Origem: MVP web em Three.js (`github.com/alan-araya/shootergame.mvp`).

---

## 1. Visão em uma frase

Ação tática retrô em **tela fixa, vista de cima em 3/4**: um **comandante** e o seu pelotão
contra **enxames de aracnídeos alienígenas** num planeta desértico. A contagem de tropas
é a sua vida. Até 4 jogadores no mesmo PC (teclado + controles).

### Inspiração e regras de IP (obrigatórias)
- Inspirado na **jogabilidade** de *Triumph! War 2099* (Darksun Games, 2001, freeware).
- **Pode replicar**: mecânicas, regras, loop de jogo, estrutura de missões, esquema de controle.
- **Não pode copiar**: sprites, sons, músicas, textos, mapas, logos, nomes ("Triumph", "Kratte"),
  nem *Starship Troopers*. Toda arte, nome e texto deste projeto é **original**.
- Não extrair assets do executável original. Referência visual = **estilo de época** (pixel art
  de RTS/ação de PC do fim dos anos 90), não os sprites de um jogo específico.
- Assets de terceiros só com licença compatível (preferir CC0) e registrados em `ASSETS_LICENSES.md`.

### Evolução planejada
1. **Fase 1 (agora)**: ~90% da jogabilidade do original, visual pixel art 2D original.
2. **Fase 2**: arte moderna (estilo Terraria: pixel art com luz dinâmica, partículas, parallax)
   e elementos 3D (unidades pré-renderizadas ou Node3D com câmera ortográfica).
3. **Fase 3**: ideias próprias (novas classes, progressão, mobile).

A arquitetura separa **simulação** (regras, IA, grade) de **visual** (sprites, FX) para que
a troca de arte 2D → 3D não toque na lógica (ver §8).

---

## 2. Tela e câmera

| Item | Valor |
|---|---|
| Resolução base | **1280×720** (16:9), `stretch_mode = canvas_items`, `aspect = keep` |
| Mundo jogável | **40×20 tiles de 32 px = 1280×640** |
| HUD superior | faixa de 48 px (y 0–48) |
| Barra inferior | 32 px (y 688–720): objetivo + mensagens |
| Câmera | fixa; o mapa inteiro sempre visível; *screen shake* em explosões |
| Filtro | `nearest` (pixels nítidos) |
| Perspectiva | 3/4 de cima (estilo RPG/RTS clássico). Unidades humanas têm sprites por direção; insetos são vistos de cima e giram |
| Ordenação | Y-sort (quem está mais abaixo na tela é desenhado por cima) |

---

## 3. Fluxo de telas

```
[Splash] → [Menu principal] ─┬─ Jogar ──→ [Seleção de missão] → [Briefing] → [Jogo] → [Resultado]
                              │                                        ↑          │ pausa
                              │                                        │      [Pausa]
                              ├─ Jogadores (1–4) / Dificuldade         │          │
                              ├─ Controles (lista de teclas)           └── Tentar de novo / Continuar (méritos)
                              └─ Sair
```

### 3.1 Menu principal
- Fundo: arte-chave (soldados contra o enxame num cânion ao entardecer), logotipo **ENXAME 2199**.
- Opções: **Jogar**, **Jogadores: 1–4**, **Dificuldade: Recruta / Soldado / Veterano**, **Controles**, **Sair**.
- Navegação por teclado (setas/WASD + Enter) e controle (D-pad + A).

### 3.2 Seleção de missão
- Lista das missões com nome, cenário e status (bloqueada / disponível / concluída).
- Mostra os **pontos de mérito** totais.

### 3.3 Briefing
- Painel com o nome da missão, 3–5 linhas de texto, o objetivo e as tropas iniciais.
- "Pressione FOGO para começar".

### 3.4 Jogo (HUD)
- **Topo esquerda**: retrato do soldado + **contagem de tropas** (número grande) + tempo de missão.
- **Topo centro**: 1 painel por jogador ativo (P1 cinza, P2 amarelo, P3 vermelho, P4 verde) com
  arma, munição, granadas e **ordem atual** (Normal / Atacar / Defender / Seguir).
- **Topo direita**: méritos da missão.
- **Rodapé**: texto do objetivo e progresso (ex.: "Ninhos 1/3 · Insetos 42").
- Mensagens (*toasts*) no centro: "REFORÇOS!", "MATRIARCA À VISTA!", "COMANDANTE ABATIDO — 10 s".
- Marcador colorido "P1..P4" acima de cada comandante.

### 3.5 Pausa
- Continuar, Reiniciar missão, Menu principal.

### 3.6 Resultado
- Vitória/derrota, motivo, estatísticas (abates, matriarcas, ninhos, flores, tropas perdidas, tempo),
  méritos ganhos. Na derrota: **Continuar (custa 150 méritos)**, Tentar de novo, Menu.

---

## 4. Regras do jogo

### 4.1 Tropas = vidas
- Contagem compartilhada pelos jogadores. Começa em 10 (Soldado).
- **−1** quando morre um soldado aliado ou um comandante.
- Comandante morto renasce em **10 s** na zona de pouso se a contagem for > 0 (com 2 s de invulnerabilidade
  e uma cápsula de pouso que esmaga insetos próximos).
- **Derrota**: contagem 0 e nenhum comandante vivo, ou falha do objetivo (ex.: gerador destruído).

### 4.2 Comandante (jogador)
- Mesmas stats de um soldado (um pouco mais de vida). Move em **8 direções**, atira para onde está virado.
- Segurar **Travar mira** mantém a direção do tiro enquanto anda (para recuar atirando).
- **Ordem**: cicla Normal → Atacar → Defender → Seguir (só afeta os soldados dele).
- **Granada**: arremesso em arco na direção do olhar.
- Só o comandante coleta pickups. Qualquer humano pisa e arranca flores.

### 4.3 Ordens dos soldados (IA)
| Ordem | Comportamento |
|---|---|
| Normal | patrulha perto de onde estava, atira no inimigo mais próximo, recua se encostarem |
| Atacar | avança pelo campo de fluxo até insetos e ninhos; para a ~1,5 tile e atira |
| Defender | volta ao ponto onde recebeu a ordem e segura a posição |
| Seguir | formação em anéis em volta do comandante (ângulo áureo) |

Melhorias de IA desta versão (o MVP tinha IA fraca):
- **Escolha de alvo por ameaça**: prioriza matriarca e insetos perto do comandante, depois o mais próximo.
- **Fogo distribuído**: soldados evitam focar todos no mesmo inseto já "condenado" (dano previsto).
- **Linha de tiro**: não atira se um aliado está na frente; reposiciona para o lado.
- **Kiting**: em Normal/Defender recuam um passo quando um inseto chega a < 1 tile.
- **Insetos com papéis**: corredores (cercam pelos flancos), cuspidores (mantêm distância),
  coletores (buscam flores). Flanqueio via deslocamento lateral no campo de fluxo.
- **Enxame coordenado**: insetos se agrupam antes de atacar (pequenos bandos) e evitam fila indiana.

### 4.4 Inimigos
| Inimigo | Papel |
|---|---|
| Aracnídeo (comum) | rápido, em bando, mordida corpo a corpo; 30% cospem ácido a distância |
| Filhote | pequeno e rápido, 1 PV; sai da matriarca |
| Matriarca | surge quando um aracnídeo toca uma **flor aberta**; lenta, muito resistente, pare um aracnídeo a cada 4 s e explode em 7 filhotes |
| Ninho | monte orgânico que gera aracnídeos sem parar, com taxa crescente por minuto |
| Coração da colmeia | ninho gigante da missão final; ao morrer libera o cristal |
| Flor | broto que abre em 7 s; se um aracnídeo tocar, vira matriarca. Humanos pisam para arrancar |
| Emboscada | após 75 s, grupos brotam do chão perto dos humanos (aviso de 1 s com poeira) |

### 4.5 Pickups
| Pickup | Efeito |
|---|---|
| Reforço terrestre | buggies entram pela borda, atropelam insetos e desembarcam 6 soldados (+6 tropas) |
| Ataque aéreo | nave solta 4 soldados na linha do comandante; 2ª passagem bombardeia a faixa com mais insetos |
| Apoio blindado | robô aliado autônomo com canhão (90 PV) |
| Lança-chamas | 260 de combustível; cone curto, atravessa |
| Canhão de plasma | 30 tiros perfurantes com explosão |
| Granadas | +3 granadas (máx. 9) |

### 4.6 Tipos de missão (data-driven)
`eliminate` (limpar ninhos e insetos), `nests` (destruir ninhos), `switches` (religar relés ficando
2 s parado em cima), `survive` (proteger o gerador até a evacuação; muros e portões destrutíveis),
`retrieve` (destruir o Coração, pegar o cristal, levar à extração).

### 4.7 Dificuldades
| | Recruta | Soldado | Veterano |
|---|---|---|---|
| Tropas iniciais | 14 | 10 | 8 |
| Velocidade dos insetos | ×0,9 | ×1,0 | ×1,1 |
| Taxa de spawn | ×0,7 | ×1,0 | ×1,3 |
| Vida dos insetos | ×1,0 | ×1,0 | ×1,25 |

---

## 5. Controles (remapeáveis via `InputMap`, ações `pN_*`)

| Jogador | Mover | Fogo | Ordem | Granada | Travar mira |
|---|---|---|---|---|---|
| P1 | W A S D | Espaço / J | Q / K | E / L | Shift esq. |
| P2 | Setas | Numpad 0 | Numpad 1 | Numpad 2 | Numpad 3 |
| P3 | Controle 1 | A / RT | X | B / LT | LB/RB |
| P4 | Controle 2 | A / RT | X | B / LT | LB/RB |

Com 1 jogador, o controle 1 também comanda o P1. Teclas 1–4 escolhem a ordem direto. Esc/Start pausa.

---

## 6. Direção de arte (Fase 1)

**Estilo**: pixel art de PC do fim dos anos 90, vista 3/4 de cima, cores quentes e saturadas,
contorno escuro de 1 px nas unidades, sombras projetadas para baixo-direita, sem anti-aliasing.

**Paleta-guia**
- Deserto: areia amarelo-alaranjada (#E8B860, #D9A24A, #C98C3A) com granulado pontilhado.
- Platôs: topo cinza-amarronzado (#8C7E6E, #A39582); paredão laranja-marrom em "escamas" (#B9773A, #8E5427).
- Território alienígena: veias e trepadeiras **roxas** (#6B3A8C, #8E4FB0), casulos **rosa-magenta** (#E05AC8).
- Humanos: farda **verde-oliva** (#4E6B2E, #6C8A3C), colete verde-escuro, botas cor de areia, pele variada.
- Aracnídeos: quitina **bege/areia** (#E8D2A6, #C9A97A, #8A6A44) com olhos e juntas rosa-magenta.
- Interface: metal cinza-azulado com rebites, texto branco/amarelo, faixas por jogador.

**Legibilidade**: o jogador acha o próprio comandante em menos de 1 s (marcador colorido + braçadeira).

---

## 7. Lista de assets (contrato com o código)

Todos os PNG com fundo **transparente** (a IA gera sobre magenta #FF00FF e o pipeline remove).
Tamanhos são o tamanho final no jogo (o pipeline reduz e quantiza a paleta).

| Arquivo | Conteúdo | Frames | Tamanho final por frame |
|---|---|---|---|
| `soldier.png` | soldado, 5 direções (S, SE, E, NE, N) × 4 passos de caminhada; W/SW/NW = espelho | 20 | 32×40 |
| `commander.png` | igual ao soldado + braçadeira/insígnia colorida (tingida por jogador) | 20 | 32×40 |
| `bug.png` | aracnídeo visto de cima, olhando para a **direita**, 4 frames de patas | 4 | 40×40 |
| `larva.png` | filhote, de cima, direita | 2 | 20×20 |
| `mother.png` | matriarca inchada, de cima, direita, pulsando | 2 | 72×72 |
| `nest.png` | ninho/monte orgânico, 3/4, pulsando | 2 | 56×48 |
| `heart.png` | coração da colmeia (ninho gigante) | 2 | 96×80 |
| `flower.png` | broto fechado + flor aberta (rosa/roxa) | 2 | 20×20 |
| `pickups.png` | reforço, ataque aéreo, blindado, lança-chamas, plasma, granadas | 6 | 32×32 |
| `buggy.png` | buggy militar aberto, de cima, direita | 1 | 64×40 |
| `dropship.png` | nave de transporte, de cima, direita | 1 | 112×72 |
| `robot.png` | robô/tanque de apoio, de cima: base + torre | 2 | 48×48 |
| `ground_sand.png` | textura de areia **sem emenda** | 1 | 256×256 |
| `rock_top.png` | topo de platô **sem emenda** | 1 | 128×128 |
| `cliff.png` | paredão de rocha em escamas, faixa horizontal sem emenda | 1 | 128×32 |
| `creep.png` | decalques de trepadeira roxa e casulos rosa | 4 | 64×64 |
| `title_bg.png` | arte-chave do menu, 16:9, sem texto | 1 | 1280×720 |

FX (tiros, faíscas, gosma, explosões, fumaça) e marcadores de UI ficam **procedurais** no código.

---

## 8. Arquitetura (Godot)

```
res://
  autoload/        Balance (números), Game (estado global), InputSetup (ações pN_*), Sfx (áudio), Art (atlas)
  scripts/sim/     Grid (tiles/colisão/linha de visão), FlowField (Dijkstra multi-fonte), SpatialHash, Missions (dados)
  scripts/world/   World (loop da missão), GroundRenderer (terreno 3/4), Fx (partículas/decalques), Projectiles
  scripts/actors/  Commander, Soldier, Robot, Bug (comum/filhote/matriarca), Nest, Flower, Pickup, Buggy, Dropship
  scripts/ui/      Main (máquina de estados), Menu, MissionSelect, Briefing, Hud, Pause, Result
  scenes/          main.tscn + cenas de UI
  assets/          sprites/, audio/, fonts/
  tools/           pipeline de sprites (Python), gerador de SFX
  tests/           testes headless da simulação
```

Princípios:
1. **Balanceamento só em `autoload/balance.gd`.** Nada de número mágico na lógica.
2. **Missões são dados** (`scripts/sim/missions.gd`, mapa ASCII 40×20). Nada de `if mission.id == ...`.
3. **Simulação sem física do Godot**: colisão círculo × grade e hash espacial (centenas de unidades a 60 Hz).
   Atores são `Node2D` leves; o `World` chama `tick(dt)` em ordem determinística.
4. **Visual desacoplado**: cada ator tem um nó `Visual` trocável (hoje `Sprite2D`; amanhã um `Node3D`
   num `SubViewport` ou sprite pré-renderizado), sem tocar na lógica.
5. **Arte por contrato de nomes** (§7). Sem o PNG, o jogo usa um placeholder procedural.

### Câmera
Tela fixa, como no original: o `GameRoot` fica em (0, 48) e mostra o mapa inteiro; o *screen shake* só desloca esse nó.
Para a Fase 2 (mapas maiores ou 3D), basta trocar por uma `Camera2D`/`Camera3D` ortográfica seguindo o centro dos
comandantes vivos — a simulação não depende da câmera.

---

## 9. Estado atual (2026-11-11) e próximos passos

**Feito**: 5 missões do MVP portadas (limpar, ninhos, relés, defesa do posto, coração + cristal); co-op local até 4
(teclado WASD, setas, 2 controles); 4 ordens; IA melhorada (§4.3); flor → matriarca, filhotes, emboscadas, bandos nos
ninhos; 6 pickups com buggies, nave e robô; muros/portões destrutíveis; méritos e *continue*; menu, seleção, briefing,
pausa e resultado; som sintetizado; arte original gerada pelo Codex e processada por `tools/process_art.py`.
Testes headless: 32 verificações. Simulação: 0,4–1,5 ms/frame por missão; ~11 ms/frame no estresse com
200 insetos vivos amontoados. Frame renderizado no pior caso (`--stress`): ~13 ms (física 8,9 + render 4,3).
Revisão externa do Codex (gpt-6-sol) aplicada: cuspe barrado por muros/portões, relé exige ficar parado,
Defender/Seguir contornam obstáculos por BFS, soldado não atira através de aliado, reforço não se perde no limite
de 50 em campo, percepção dos insetos escalonada, decalques em blocos, campos de fluxo sob demanda.
Pendente da revisão: desacoplar o visual (estado → adaptador 2D/3D) — entra na Fase 2.

**Próximos passos sugeridos**
1. Playtest com teclado e controle; ajustar `bal.gd` (missões 1 e 2 estão fáceis para bots com 2 jogadores).
2. Missões 6–9 no estilo do original: hangar interno, corredores com insetos de duto, caverna, câmara do cristal (proteger objeto).
3. Canhões fixos ocupáveis e cota de abates na defesa; terminais que abrem portas.
4. Animação de tiro do soldado e de morte (folhas novas no Codex), sombra de nave, partículas de areia.
5. Fonte pixel com acentos (ex.: Silkscreen, OFL) e vozes/efeitos gravados.
6. Fase 2: luz 2D (`PointLight2D` nos tiros e explosões), normal maps nos sprites, parallax; depois unidades 3D num
   `SubViewport` mantendo o mesmo `tick`/`sync_visual`.
