extends Node
## Estado global entre telas: jogadores, dificuldade, missão atual, méritos e progresso salvo.

const SAVE_PATH := "user://enxame2199.cfg"

var players := 1
var difficulty := "normal"
var mission_index := 0
var merit_total := 0
var unlocked := 1
var completed := {}
var tutorial_seen := false # manual de campo já mostrado antes da primeira missão
var language := "" # código de LANGUAGES; vazio = ainda não escolhido (usa DEFAULT_LANGUAGE)
const DEFAULT_LANGUAGE := "en_US"

## Idiomas do jogo, na ordem do botão IDIOMA, com o nome no próprio idioma (não se traduz).
## Colunas de i18n/strings.csv. Frase sem tradução num idioma cai no pt-BR (locale/fallback).
const LANGUAGES := ["en_US", "pt_BR", "pt_PT", "es", "de", "ja", "zh_CN"]
const LANGUAGE_NAMES := {
	pt_BR = "Português (Brasil)", en_US = "English", es = "Español", pt_PT = "Português (Portugal)",
	de = "Deutsch", ja = "日本語", zh_CN = "简体中文",
}
## Qualidade gráfica: 2 = alto (tudo), 1 = médio (menos luzes), 0 = baixo (sem luzes dinâmicas nem brilho).
var gfx := 2

const GFX_LABELS := ["GFX_LOW", "GFX_MEDIUM", "GFX_HIGH"] # chaves de i18n
const GFX_KEYS := { baixo = 0, medio = 1, alto = 2 }


func _ready() -> void:
	load_save()
	set_language(language if language != "" else DEFAULT_LANGUAGE)


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	merit_total = cfg.get_value("progress", "merit", 0)
	unlocked = cfg.get_value("progress", "unlocked", 1)
	completed = cfg.get_value("progress", "completed", {})
	players = cfg.get_value("options", "players", 1)
	difficulty = cfg.get_value("options", "difficulty", "normal")
	gfx = clampi(cfg.get_value("options", "gfx", 2), 0, 2)
	tutorial_seen = cfg.get_value("progress", "tutorial_seen", false)
	language = cfg.get_value("options", "language", "")


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "merit", merit_total)
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "completed", completed)
	cfg.set_value("options", "players", players)
	cfg.set_value("options", "difficulty", difficulty)
	cfg.set_value("options", "gfx", gfx)
	cfg.set_value("progress", "tutorial_seen", tutorial_seen)
	cfg.set_value("options", "language", language)
	cfg.save(SAVE_PATH)


func mission_won(index: int, merit: int) -> void:
	merit_total += merit
	completed[index] = true
	unlocked = maxi(unlocked, mini(index + 2, Missions.count()))
	save()


func add_merit(merit: int) -> void:
	merit_total += merit
	save()


func spend_merit(amount: int) -> bool:
	if merit_total < amount:
		return false
	merit_total -= amount
	save()
	return true


## Idioma do sistema mapeado para um dos idiomas do jogo. Hoje a primeira execução abre em DEFAULT_LANGUAGE
## (inglês); fica aqui para um futuro "usar o idioma do sistema".
static func system_language() -> String:
	var loc := OS.get_locale() # ex.: "pt_BR", "pt_PT", "es_MX", "de_AT", "ja_JP", "zh_CN", "zh_TW"
	var lang := OS.get_locale_language()
	if loc == "pt_PT":
		return "pt_PT"
	match lang:
		"pt":
			return "pt_BR"
		"es":
			return "es"
		"de":
			return "de"
		"ja":
			return "ja"
		"zh":
			return "zh_CN"
		"en":
			return "en_US"
	return "en_US"


func set_language(code: String) -> void:
	if not LANGUAGES.has(code):
		code = DEFAULT_LANGUAGE
	language = code
	TranslationServer.set_locale(code)


func cycle_language() -> void:
	set_language(LANGUAGES[(LANGUAGES.find(language) + 1) % LANGUAGES.size()])
	save()
