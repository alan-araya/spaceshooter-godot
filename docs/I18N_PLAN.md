# Plano de multi-idiomas — Enxame 2199

Idiomas: **português do Brasil (padrão)**, inglês (EUA), espanhol, português de Portugal, alemão, japonês e
chinês. Este documento é o plano; nada dele está implementado ainda.

## 1. Situação atual

- Todo o texto está escrito direto no código, em pt-BR: menus e telas (`scripts/ui/main.gd`), HUD
  (`scripts/ui/hud.gd`), manual de campo (`scripts/ui/field_manual.gd`), mensagens da partida
  (`world.toast(...)`, 22 chamadas) e briefings/objetivos das 6 missões (`scripts/sim/missions.gd`).
  Estimativa: **~350 frases**, ~4.500 palavras (o manual e os briefings são a maior parte).
- A fonte é a padrão do Godot, que **não tem ideogramas** japoneses nem chineses.
- Em rede, as mensagens vão do host para os clientes **como texto pronto** (`world.toast` grava o texto no
  evento). Um cliente em outro idioma veria as mensagens no idioma do host.
- As imagens não têm texto (regra do projeto), então não há arte para traduzir.

## 2. Como fazer (Godot 4)

**Tabela única de traduções**: `i18n/strings.csv`, uma linha por frase, uma coluna por idioma. O Godot
importa o CSV e gera um `.translation` por idioma; `tr("CHAVE")` devolve o texto do idioma ativo.

```
keys,pt_BR,en_US,es,pt_PT,de,ja,zh_CN
MENU_PLAY,JOGAR,PLAY,JUGAR,JOGAR,SPIELEN,プレイ,开始游戏
HUD_TROOPS,TROPAS,TROOPS,TROPAS,TROPAS,TRUPPEN,部隊,兵力
TOAST_WALL_BROKEN,MURO ROMPIDO!,WALL BREACHED!,¡MURO ROTO!,MURO ROMPIDO!,MAUER DURCHBROCHEN!,壁が破られた！,城墙被突破！
```

- **Chaves estáveis** (`MENU_PLAY`, `M5_BRIEF_2`), não a frase em português: corrigir um texto em pt-BR não
  quebra as outras línguas.
- Valores variáveis com nome, não posição: `"Volta em {s} s"` → `tr("HUD_RESPAWN").format({s = 7})`.
  A ordem das palavras muda entre idiomas (japonês e alemão invertem muito).
- Plural: chaves separadas quando precisar (`_ONE` / `_MANY`); são poucos casos.
- CSV (e não `.po`) porque são só ~350 frases, o arquivo é legível no GitHub e abre em planilha para
  revisores. Se um dia entrar uma plataforma de tradução (Crowdin, Weblate), ela importa o CSV.

**Idioma ativo**
- Novo `Game.language`, salvo no progresso. Na primeira execução, vem do sistema (`OS.get_locale()`):
  `pt_BR`/`pt` → pt-BR, `pt_PT` → pt-PT, `es*` → es, `de*` → de, `ja*` → ja, `zh*` → zh-CN,
  `en*` → en-US; qualquer outro → en-US. Sem nada, pt-BR.
- Botão **IDIOMA** no menu principal (mostra o nome no próprio idioma: Português (Brasil), English,
  Español, Português (Portugal), Deutsch, 日本語, 简体中文). Troca na hora e redesenha a tela.
- `-- --lang=xx` na linha de comando (screenshots e testes).

**Fontes**
- Latim (pt, en, es, de): continua a fonte atual.
- Japonês e chinês: **Noto Sans JP** e **Noto Sans SC** (licença OFL, livre) como fontes de reserva do tema:
  o Godot usa a primeira fonte que tem o caractere. Para não pesar ~20 MB no jogo, cortar as fontes só
  para os caracteres usados no CSV (subset gerado por script a cada mudança no texto).
- O HUD desenha texto com a fonte padrão do motor (`ThemeDB.fallback_font`); trocar pela fonte do tema.

**Rede**
- `world.toast()` passa a gravar **chave + valores** (`["TOAST_WALL_BROKEN", {}]`) em vez do texto pronto;
  cada máquina traduz no próprio idioma. Mesma coisa para o motivo do fim de missão (`outcome_reason`), que
  vai no snapshot. Muda o protocolo: host e cliente precisam da mesma versão (já é assim hoje).

**Layout**
- Alemão fica até ~35% mais comprido que o português: botões e cartões do manual precisam aceitar
  quebra de linha ou fonte menor automática; revisar as larguras fixas (`custom_minimum_size`).
- Japonês e chinês quebram linha sem espaços; o servidor de texto avançado do Godot (padrão no Windows)
  já faz isso, mas cada tela precisa de uma conferência visual.
- Textos em maiúsculas (estilo dos menus) não existem em japonês e chinês: manter como está escrito na
  tradução, sem `to_upper()` no código.

## 3. Etapas

| Etapa | O que | Resultado |
|---|---|---|
| 1. Extrair | Trocar todo texto do código por `tr("CHAVE")`; montar `strings.csv` só com a coluna pt-BR; toasts e motivo de fim de missão por chave (rede) | jogo idêntico, só que pronto para traduzir |
| 2. Sistema | `Game.language`, detecção do sistema, botão IDIOMA, `--lang`, fontes Noto com corte, HUD com a fonte do tema | troca de idioma funcionando (com pt-BR em todas) |
| 3. Traduzir | Rascunho das 6 línguas (eu traduzo, seguindo um glossário), depois revisão por falante nativo, principalmente ja, zh e de | `strings.csv` completo |
| 4. Conferir | Teste automático (toda chave tem texto nas 7 colunas, mesmos `{nomes}` em todas, nenhuma frase fora do CSV via pseudo-idioma do Godot) + screenshots de todas as telas em cada idioma | lista de telas com texto cortado ou quebrado, corrigida |

**Glossário** (decidir uma vez, antes da etapa 3): Enxame, aracnídeo, matriarca, ninho, flor, tropas,
comandante, pelotão, ordens (Normal/Atacar/Defender/Seguir), relé, gerador, mérito, Recruta/Soldado/Veterano.

## 4. Decisões que são suas

1. **Espanhol**: neutro latino-americano ou da Espanha? (Sugestão: neutro latino-americano, que serve
   melhor a maioria dos jogadores.)
2. **Chinês**: só simplificado (China continental) ou também tradicional (Taiwan, Hong Kong)? O pedido diz
   "chinês"; o plano assume **simplificado**.
3. **Nome do jogo**: manter "ENXAME 2199" em todos os idiomas ou traduzir (ex.: SWARM 2199, ENJAMBRE 2199)?
4. **Revisão nativa**: há alguém para revisar japonês, chinês e alemão? Sem revisão, essas três ficam
   marcadas como "tradução preliminar".
