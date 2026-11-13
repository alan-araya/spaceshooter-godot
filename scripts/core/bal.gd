class_name Bal
extends RefCounted
## BALANÇO — todos os números de jogabilidade num lugar só.
## Porte do MVP (src/config/balance.js) com escala ×2: 1 tile = 32 px.
## Unidades: distâncias em px do mundo, tempo em segundos. Nada de números mágicos na lógica.

const TILE := 32
const COLS := 40
const ROWS := 20
const WORLD_W := 1280
const WORLD_H := 640
const HUD_TOP := 48
const HUD_BOTTOM := 32
const MAX_PLAYERS := 4

const TROOPS := {
	max_in_field = 50, # máximo de soldados aliados em campo
	commander_respawn = 10.0, # segundos até o comandante renascer
	respawn_invuln = 2.0, # invulnerabilidade após renascer
	pod_clear_radius = 56.0, # cápsula de pouso esmaga insetos neste raio
}

const COMMANDER := {
	hp = 6.0, speed = 144.0, radius = 10.0, hit_invuln = 0.6,
	start_grenades = 3, max_grenades = 9, carry_slow = 0.8,
}

const SOLDIER := {
	hp = 4.0, speed = 124.0, radius = 10.0, reach = 280.0, fire_interval = 0.42, spread = 0.10,
	retarget = 0.25, patrol_radius = 72.0, chase_radius = 180.0,
	kite_dist = 44.0, # recua quando um inseto chega mais perto que isso
	attack_hold = 150.0, # em Atacar, para de avançar a esta distância do alvo
	follow_back = 34.0, follow_row = 22.0, follow_spread = 24.0, # formação atrás do comandante
}

const WEAPONS := {
	mg = { label = "WEAPON_MG", interval = 0.11, speed = 660.0, reach = 350.0, damage = 1.0, spread = 0.05, ammo = -1, pierce = 0, splash = 0.0 },
	flame = { label = "WEAPON_FLAME", interval = 0.03, speed = 300.0, reach = 144.0, damage = 0.35, spread = 0.32, ammo = 260, pierce = 99, splash = 0.0 },
	plasma = { label = "WEAPON_PLASMA", interval = 0.42, speed = 520.0, reach = 520.0, damage = 7.0, spread = 0.0, ammo = 30, pierce = 6, splash = 36.0 },
	rifle = { label = "WEAPON_RIFLE", interval = 0.42, speed = 600.0, reach = 300.0, damage = 1.0, spread = 0.1, ammo = -1, pierce = 0, splash = 0.0 },
	cannon = { label = "WEAPON_CANNON", interval = 0.22, speed = 600.0, reach = 340.0, damage = 2.0, spread = 0.04, ammo = -1, pierce = 0, splash = 0.0 },
	turret = { label = "WEAPON_TURRET", interval = 0.14, speed = 720.0, reach = 380.0, damage = 1.0, spread = 0.06, ammo = -1, pierce = 0, splash = 0.0 },
}

## Metralhadora de ponto montada (tile 'T'): atira sozinha quando alguém a opera.
const TURRET := {
	man_radius = 16.0, # distância para operar
	claim_radius = 260.0, # soldados em Normal/Defender a esta distância vão operar
	radius = 14.0,
}

## Hordas pelas bordas do mapa (configuradas por missão em settings.hordes).
const HORDES := {
	warn_time = 1.2, min_interval = 2.5, growth_per_min = 0.18,
}

const GRENADE := {
	throw_dist = 192.0, flight_time = 0.55, radius = 76.0, damage = 12.0, cooldown = 0.45,
}

const BUG := {
	hp = 2.0, speed = 160.0, radius = 9.0, damage = 1.0, bite_interval = 0.7,
	forager_chance = 0.12, forager_range = 12.0, # coletores buscam flores a até N tiles
	wall_damage = 1.0,
	spitter_chance = 0.3, spit_min = 72.0, spit_max = 220.0, spit_hold = 130.0,
	spit_cd_min = 3.5, spit_cd_max = 7.0, spit_speed = 230.0, spit_damage = 1.0,
	flank = 0.55, # força do desvio lateral (cerco em vez de fila indiana)
	lunge_dist = 52.0, lunge_boost = 1.55, lunge_time = 0.35, lunge_cd = 1.6,
	sense = 112.0, # distância em que o inseto vê um humano e parte direto para ele
	dodge_chance = 0.5, # fração "esperta" que foge do ponto de queda de granadas (× agressividade)
}

const LARVA := { hp = 1.0, speed = 192.0, radius = 6.0, damage = 1.0 }

const MOTHER := {
	hp = 40.0, speed = 44.0, radius = 22.0, damage = 2.0, birth_interval = 4.0, death_larvae = 7,
	threat_birth = 0.65, # pare mais rápido quando há humanos perto
	brood_burst = 3, # filhotes soltos ao perder 1/3 e 2/3 da vida
	keep_dist = 150.0, # mantém esta distância dos humanos (fica atrás da ninhada)
	charge_dist = 58.0, charge_boost = 2.6, charge_time = 0.35, charge_cd = 2.6, knockback = 46.0,
	retreat_hp = 0.35, # abaixo disso recua para o ninho
	mortar_cd = 6.0, mortar_min = 90.0, mortar_range = 360.0, mortar_flight = 1.1,
	mortar_radius = 40.0, mortar_damage = 2.0,
	pool_time = 3.5, pool_radius = 34.0, pool_tick = 0.8, pool_damage = 1.0,
	aura_radius = 140.0, aura_speed = 1.12, aura_bite = 0.85, # frenesi dos aracnídeos próximos
	max_alive = 3, # flor tocada com 3 matriarcas vivas é só comida
}

const NEST := {
	hp = 70.0, radius = 24.0, spawn_interval = 3.2, min_interval = 0.6,
	pickup_drop_chance = 0.6,
	gather_time = 3.5, pack_size = 4, gather_radius = 56.0, # bandos: juntam-se antes de atacar
}

const HEART := { hp = 320.0, radius = 40.0, spawn_interval = 2.2 }

const FLOWER := { max_on_map = 6, respawn_interval = 12.0, radius = 12.0, bloom_time = 7.0, initial_bloom = 14.0 }

const AMBUSH := {
	start_after = 75.0, base_interval = 22.0, min_interval = 9.0, size_min = 3, size_max = 6,
	warn_time = 1.0, min_dist = 80.0, max_dist = 240.0,
}

const PICKUPS := {
	spawn_min = 16.0, spawn_max = 26.0, lifetime = 22.0, radius = 18.0,
	reinforce_soldiers = 6, reinforce_buggies = 3, airstrike_soldiers = 4,
	bomb_spacing = 44.0, bomb_radius = 60.0, bomb_damage = 14.0, grenade_pack = 3,
	weights = { reinforce = 3.0, airstrike = 2.0, robot = 1.2, flame = 1.5, plasma = 1.5, grenades = 2.0 },
}

const VEHICLES := {
	buggy_speed = 300.0, buggy_radius = 18.0, dropship_speed = 420.0,
	robot_hp = 90.0, robot_speed = 76.0, robot_radius = 18.0,
}

const STRUCTURES := { wall_hp = 40.0, gate_hp = 32.0, generator_hp = 160.0, switch_time = 2.0 }

const MERIT := {
	bug = 1, larva = 1, mother = 12, nest = 30, heart = 120, flower = 5,
	objective = 100, per_surviving_troop = 10, continue_cost = 150, switch = 25,
}

const LIMITS := { max_bugs = 200, flowfield_interval = 0.2, max_decals = 450 }

## aggro: agressividade da IA (cuspe, bote, investida, morteiro, esquiva).
## Recruta = o antigo Soldado ~7% mais fácil; Soldado = mais pressão; Veterano mantido.
const DIFFICULTY := {
	facil = { label = "DIFF_FACIL", troops = 11, bug_speed = 0.95, spawn = 0.93, bug_hp = 1.0, escalation = 0.11, ambush = 1.08, aggro = 0.9 },
	normal = { label = "DIFF_NORMAL", troops = 9, bug_speed = 1.05, spawn = 1.15, bug_hp = 1.0, escalation = 0.14, ambush = 0.88, aggro = 1.1 },
	dificil = { label = "DIFF_DIFICIL", troops = 8, bug_speed = 1.1, spawn = 1.3, bug_hp = 1.25, escalation = 0.16, ambush = 0.75, aggro = 1.25 },
}
const DIFFICULTY_ORDER := ["facil", "normal", "dificil"]

const ORDERS := ["normal", "atacar", "defender", "seguir"]
## Rótulos = chaves de i18n/strings.csv (traduzir com L.t).
const ORDER_LABELS := { normal = "ORDER_NORMAL", atacar = "ORDER_ATACAR", defender = "ORDER_DEFENDER", seguir = "ORDER_SEGUIR" }

const PLAYER_COLORS := [Color("59c6ff"), Color("ffd23f"), Color("ff5a5a"), Color("7dff6b")]
