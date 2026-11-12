class_name Unit
extends Node2D
## Base de toda unidade da simulação (humanos, insetos, ninhos).
## A lógica fica em tick(dt), chamada pelo World em ordem determinística.
## O visual fica no nó filho "Visual" (hoje Sprite2D; pode virar 3D sem tocar na lógica).

var world: World
var uid := 0
var kind := ""
var r := 10.0
var hp := 1.0
var max_hp := 1.0
var dead := false
var flash := 0.0
var face := 0.0 # ângulo para onde está virado (radianos, 0 = direita)
var walk_t := 0.0
var moving := false
var pending := 0.0 # dano previsto de projéteis a caminho (evita desperdício de tiro)
var emerge := 0.0 # saindo do chão / do ovo (não age, não toma tiro)
var drop_t := 0.0 # caindo do céu (soldados de reforço)
var is_human := false
var visual: Sprite2D


func _init() -> void:
	visual = Sprite2D.new()
	visual.name = "Visual"
	add_child(visual)


func tick(_dt: float) -> void:
	pass


func sync_visual() -> void:
	pass


## Retorna true se a referência ainda aponta para uma unidade viva.
static func ok(u) -> bool:
	return u != null and is_instance_valid(u) and not u.dead


func apply_flash() -> void:
	visual.self_modulate = Color(2.6, 2.6, 2.6) if flash > 0.0 else Color.WHITE


## Índice de direção (0..7) a partir do ângulo: 0=L, 1=SE, 2=S, 3=SO, 4=O, 5=NO, 6=N, 7=NE.
static func dir8(a: float) -> int:
	return posmod(roundi(a / (PI / 4.0)), 8)
