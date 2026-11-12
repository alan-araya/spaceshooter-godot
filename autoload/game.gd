extends Node
## Estado global entre telas: jogadores, dificuldade, missão atual, méritos e progresso salvo.

const SAVE_PATH := "user://enxame2199.cfg"

var players := 1
var difficulty := "normal"
var mission_index := 0
var merit_total := 0
var unlocked := 1
var completed := {}
## Qualidade gráfica: 2 = alto (tudo), 1 = médio (menos luzes), 0 = baixo (sem luzes dinâmicas nem brilho).
var gfx := 2

const GFX_LABELS := ["BAIXO", "MÉDIO", "ALTO"]
const GFX_KEYS := { baixo = 0, medio = 1, alto = 2 }


func _ready() -> void:
	load_save()


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


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "merit", merit_total)
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "completed", completed)
	cfg.set_value("options", "players", players)
	cfg.set_value("options", "difficulty", difficulty)
	cfg.set_value("options", "gfx", gfx)
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
