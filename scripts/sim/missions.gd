class_name Missions
extends RefCounted
## MISSÕES — 100% data-driven. Nova missão = novo dicionário aqui + validate() sem erros.
## Mapa: 40 colunas × 20 linhas (1 caractere = 1 tile de 32 px).
## Mapas de defesa com muros em camadas são gerados por tools/build_maps.py.
##
## TILES                        ENTIDADES (o tile embaixo vira o chão da missão)
##  .  chão                      C  zona de pouso (comandantes nascem aqui)
##  ,  chão variante             s  soldado aliado      b  aracnídeo
##  :  trilha                    M  matriarca
##  _  piso metálico             N  ninho               H  coração da colmeia
##  f  solo fértil (flores)      F  flor (vira solo fértil)
##  x  escombros                 S  relé/interruptor    G  gerador (defender)
##  #  rocha / platô             E  ponto de extração   T  metralhadora de ponto
##  ^  formação alienígena       1 reforço  2 ataque aéreo  3 blindado
##  ~  ácido (tiros passam)      4 lança-chamas  5 plasma  6 granadas
##  =  muro destrutível
##  +  portão (humanos passam, insetos derrubam)
##
## OBJETIVOS: eliminate | nests | switches | survive (tempo) | hold (cota de abates) | retrieve
## settings.hordes = { start, interval, size_min, size_max, edges = "nsew", mother_chance }: hordas pelas bordas
##   (depois de 60 s, mother_chance é a chance de uma matriarca vir junto).
##   Em defesas (survive/hold) vêm até o fim; nas outras, enquanto houver ninhos.
## name, briefing e objective.text são CHAVES de i18n/strings.csv (o texto fica lá, por idioma).
## ambience: clima visual (hora do dia), chave de Ambience.PRESETS; padrão "day". Não muda a simulação.
## settings.nest_rate: multiplicador da taxa dos ninhos da missão.
## settings.troops_bonus: tropas extras na contagem inicial. settings.hordes.growth: crescimento por minuto
##   (padrão Bal.HORDES.growth_per_min). settings.hordes.min_interval: menor intervalo entre hordas
##   (padrão Bal.HORDES.min_interval).

const LIST := [
	{
		id = "m1", name = "M1_NAME", theme = "desert", ambience = "dawn",
		briefing = [
			"M1_BRIEF_1",
			"M1_BRIEF_2",
			"M1_BRIEF_3",
			"M1_BRIEF_4",
		],
		objective = { type = "eliminate", text = "M1_OBJ" },
		settings = { max_flowers = 3, ambush = false, pickup_interval = 1.0, nest_rate = 1.25,
			hordes = { start = 30.0, interval = 14.0, size_min = 3, size_max = 5, edges = "ne" } },
		map = [
			"........,,,..........##.................",
			"..##.....,,.........###.........,,,.....",
			"..###.........................,,,,......",
			"...#.................,,,........ff......",
			"..........,,,........,,.........fFf..N..",
			".........,,,,...................ff......",
			"....................##..................",
			".............s..b..###..........,,......",
			"..........s.....b...#...................",
			"..C..........s..b.........1.............",
			"..........s......b.........,,,..........",
			".............s......#...................",
			"....##.............###..................",
			"...###..................ff..........,,..",
			"....#......,,,.........fFf..............",
			"..........,,,,..........ff..........N...",
			"...................,,...................",
			"..,,.........##...........###...........",
			".,,,........###............#............",
			".............#..........................",
		],
	},
	{
		id = "m2", name = "M2_NAME", theme = "canyon", ambience = "noon",
		briefing = [
			"M2_BRIEF_1",
			"M2_BRIEF_2",
			"M2_BRIEF_3",
			"M2_BRIEF_4",
		],
		objective = { type = "switches", text = "M2_OBJ" },
		settings = { max_flowers = 3, ambush = true, pickup_interval = 0.9, nest_rate = 1.3,
			hordes = { start = 25.0, interval = 12.0, size_min = 4, size_max = 6, edges = "nsew" } },
		map = [
			"######.............#####..........######",
			"#####......:.......####.....S.....######",
			"###........:........##...........N..####",
			"##.........:...............#.........###",
			"#....S.....:..............###.........##",
			"#..........::::............#...........#",
			"##............:.....N..................#",
			"###...........:..............ff........#",
			"####..........:.....###.....fFf..##.....",
			"####..C.s.....:....#####.....ff####.....",
			"###...s.s.....:.....###.........##......",
			"##............:.........................",
			"#.............::::::........4...........",
			"#...................:..........N........",
			"##...####...........:..........,,.......",
			"###..####...........:...................",
			"####................:..........#####....",
			"#####..........S....:.........#######...",
			"######..............:..........#####..##",
			"#######.............:................###",
		],
	},
	{
		id = "m3", name = "M3_NAME", theme = "desert", ambience = "afternoon",
		briefing = [
			"M3_BRIEF_1",
			"M3_BRIEF_2",
			"M3_BRIEF_3",
			"M3_BRIEF_4",
		],
		objective = { type = "survive", time = 210.0, text = "M3_OBJ" },
		settings = { max_flowers = 2, ambush = true, pickup_interval = 0.8,
			hordes = { start = 40.0, interval = 13.0, size_min = 3, size_max = 5, edges = "nsew" } },
		map = [
			".......................^^...............",
			"..N...........,,,.................N.....",
			"....^^........,,,.......................",
			".........=========++=========,,,........",
			".........=..................=,,,........",
			".....fff.=.==............==.=...fff.....",
			".....fFf.=...===+====+===...=...fFf.....",
			".....fff.=...=__________=...=...fff.....",
			".........=...=__s____s__=...=...........",
			"..,,,....+...+___C__G___+...+...........",
			"..,,,....=...=__s____s__=...=.....^^....",
			".........=...=__________=...=......^....",
			".....fff.=...===+====+===...=...........",
			".....fFf.=.==............==.=...........",
			".....fff.=................6.=..fff......",
			".........=========++=========..fFf......",
			".....^.........................fff......",
			"....^^............,,,...................",
			"..N...............,,,............N......",
			"........................................",
		],
	},
	{
		id = "m4", name = "M4_NAME", theme = "desert", ambience = "storm",
		briefing = [
			"M4_BRIEF_1",
			"M4_BRIEF_2",
			"M4_BRIEF_3",
			"M4_BRIEF_4",
			"M4_BRIEF_5",
		],
		objective = { type = "hold", kills = 400, text = "M4_OBJ" },
		settings = { max_flowers = 3, ambush = false, pickup_interval = 0.8,
			hordes = { start = 12.0, interval = 5.0, size_min = 6, size_max = 9, edges = "nwe", mother_chance = 0.2 } },
		map = [
			"........................................",
			".....N.....^^.......N......^^...........",
			"............^..............^......N.....",
			"........fff....,,,...........fff........",
			"........fFf....,,,.....,,,...fFf........",
			"........fff............,,,...fff........",
			"##....................................##",
			"##====+======+======+=====+======+====##",
			"##..........T..............T..........##",
			"##.........s................s.........##",
			"##....................................##",
			"##==+=======+======+=======+=======+==##",
			".........T....................T.........",
			"...,,,,..........s....s.................",
			"...,,,,...s..................s...,,,....",
			"..............===+====+===.......,,,....",
			".....1........=____T_____=..............",
			"..............+_C___G____+........6.....",
			"..............=__________=..............",
			"..............============..............",
		],
	},
	{
		id = "m5", name = "M5_NAME", theme = "desert", ambience = "dusk",
		briefing = [
			"M5_BRIEF_1",
			"M5_BRIEF_2",
			"M5_BRIEF_3",
			"M5_BRIEF_4",
			"M5_BRIEF_5",
		],
		objective = { type = "survive", time = 240.0, text = "M5_OBJ" },
		settings = { max_flowers = 3, ambush = false, pickup_interval = 0.7, troops_bonus = 4,
			# enxame quase contínuo: grupos pequenos a cada ~2 s, que crescem e ficam mais frequentes com o tempo
			hordes = { start = 20.0, interval = 2.0, min_interval = 0.7, size_min = 2, size_max = 3, edges = "nsew",
				mother_chance = 0.04, growth = 0.42 } },
		map = [
			"....~~~~~~~~~~~~........~~~~~~~~~~~~....",
			"....===============++===============....",
			"....==.....,,,,...................==....",
			"~...=..T........................T..=...~",
			"~...=....=====+================....=...~",
			"~...=....=..........s.........=.f1f=...~",
			"~...=....+s........T.........s=.fFf=...~",
			"~...=....=....============....=.fff=...~",
			"....=....=....=_s_____s__=....=....=....",
			"....+....=.T..=_____G____+...s=....+....",
			"....+....=s...+__C_______=..T.=....+....",
			"....=....=....=_6______T_=....=....=....",
			"~...=fff.=....============....=....=...~",
			"~...=fFf.=s.........T........s+....=...~",
			"~...=fff.=.........s..........=....=...~",
			"~...=....================+=====....=...~",
			"~...=..T........................T..=...~",
			"....==...................,,,,.....==....",
			"....===============++===============....",
			"....~~~~~~~~~~~~........~~~~~~~~~~~~....",
		],
	},
	{
		id = "m6", name = "M6_NAME", theme = "hive", ambience = "hive",
		briefing = [
			"M6_BRIEF_1",
			"M6_BRIEF_2",
			"M6_BRIEF_3",
			"M6_BRIEF_4",
		],
		objective = { type = "retrieve", text = "M6_OBJ" },
		settings = { max_flowers = 4, ambush = true, pickup_interval = 0.8, nest_rate = 1.2 },
		map = [
			"########################################",
			"#______#____,,,,______#______,,,,,_____#",
			"#______#____,,,_______#_____,,,,,,_____#",
			"#___E__#______________#_____,,N,,______#",
			"#______####_#####_____#______,,,,______#",
			"#______________,,_____##########_#######",
			"#__s___________,,,______________,,,,___#",
			"#_____________________________,,,,,,,__#",
			"___C____~~~~__________________,,,H,,,__#",
			"___s____~~~~____N_____________,,,,,,,__#",
			"________~~~~______3___________,,,,,,,__#",
			"#__s__________________##_#######,,,,___#",
			"#_______________,,____#_________,,_____#",
			"#####_######____,,,___#____N____,,_____#",
			"#______#____________________,,,________#",
			"#__,,__#___________###__________#______#",
			"#_,,,,______ff_____###______________ff_#",
			"#__,,__#__fFf_______________,,,,#__fFf_#",
			"#______#___ff_______________,,,,#___ff_#",
			"########################################",
		],
	},
]


static func count() -> int:
	return LIST.size()


static func get_mission(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]


## Valida dimensões e caracteres. Retorna lista de erros (vazia = ok).
static func validate(m: Dictionary) -> Array:
	var errors := []
	var amb: String = m.get("ambience", "day")
	if not Ambience.PRESETS.has(amb):
		errors.append("%s: ambience desconhecido '%s'" % [m.id, amb])
	var allowed := ".,:_fx#^~=+CsbMNHFSGET123456"
	var map: Array = m.map
	if map.size() != Bal.ROWS:
		errors.append("%s: %d linhas (esperado %d)" % [m.id, map.size(), Bal.ROWS])
	var joined := ""
	for y in map.size():
		var row: String = map[y]
		if row.length() != Bal.COLS:
			errors.append("%s: linha %d tem %d colunas (esperado %d)" % [m.id, y, row.length(), Bal.COLS])
		for ch in row:
			if allowed.find(ch) < 0:
				errors.append("%s: caractere inválido '%s' na linha %d" % [m.id, ch, y])
		joined += row
	var t: String = m.objective.type
	if joined.count("C") != 1:
		errors.append("%s: precisa de exatamente 1 'C'" % m.id)
	if (t == "eliminate" or t == "nests") and joined.count("N") == 0:
		errors.append("%s: objetivo '%s' sem ninhos" % [m.id, t])
	if t == "switches" and joined.count("S") == 0:
		errors.append("%s: objetivo 'switches' sem relés" % m.id)
	if (t == "survive" or t == "hold") and joined.count("G") != 1:
		errors.append("%s: objetivo '%s' precisa de 1 'G'" % [m.id, t])
	if t == "hold" and int(m.objective.get("kills", 0)) <= 0:
		errors.append("%s: objetivo 'hold' precisa de 'kills' > 0" % m.id)
	if t == "retrieve" and (joined.count("H") != 1 or joined.count("E") != 1):
		errors.append("%s: objetivo 'retrieve' precisa de 1 'H' e 1 'E'" % m.id)
	var s: Dictionary = m.get("settings", {})
	if s.has("hordes"):
		var hz: Dictionary = s.hordes
		for k in ["start", "interval", "size_min", "size_max", "edges"]:
			if not hz.has(k):
				errors.append("%s: settings.hordes sem '%s'" % [m.id, k])
	return errors
