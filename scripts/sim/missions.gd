class_name Missions
extends RefCounted
## MISSÕES — 100% data-driven. Nova missão = novo dicionário aqui + validate() sem erros.
## Mapa: 40 colunas × 20 linhas (1 caractere = 1 tile de 32 px).
##
## TILES                        ENTIDADES (o tile embaixo vira o chão da missão)
##  .  chão                      C  zona de pouso (comandantes nascem aqui)
##  ,  chão variante             s  soldado aliado      b  aracnídeo
##  :  trilha                    M  matriarca
##  _  piso metálico             N  ninho               H  coração da colmeia
##  f  solo fértil (flores)      F  flor (vira solo fértil)
##  x  escombros                 S  relé/interruptor    G  gerador (defender)
##  #  rocha / platô             E  ponto de extração
##  ^  formação alienígena       1 reforço  2 ataque aéreo  3 blindado
##  ~  ácido (tiros passam)      4 lança-chamas  5 plasma  6 granadas
##  =  muro destrutível
##  +  portão (humanos passam, insetos derrubam)

const LIST := [
	{
		id = "m1", name = "Queda Quente", theme = "desert",
		briefing = [
			"Comandante, seu módulo de pouso vai cair no meio de um combate.",
			"Um pelotão já está segurando a linha nas Planícies de Varga.",
			"Assuma o esquadrão, limpe a área e destrua os dois ninhos a leste.",
			"Use este combate para se acostumar com as ordens de tropa.",
		],
		objective = { type = "eliminate", text = "Destrua os ninhos e elimine todos os aracnídeos" },
		settings = { max_flowers = 3, ambush = false, pickup_interval = 1.0 },
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
		id = "m2", name = "Pântano de Esporos", theme = "swamp",
		briefing = [
			"O vale de Ixil está coberto de flores de esporo.",
			"Quando um aracnídeo toca uma flor, ele incha e vira uma MATRIARCA:",
			"resistente, pare aracnídeos sem parar e explode em filhotes ao morrer.",
			"Pise nas flores antes deles. Destrua os três ninhos.",
		],
		objective = { type = "nests", text = "Destrua os 3 ninhos" },
		settings = { max_flowers = 7, ambush = true, pickup_interval = 1.0 },
		map = [
			"....~~~~.........,,,..........~~~.......",
			"...~~~~~~....ff.......N.......~~~~......",
			"....~~~~....fFf...........M..~~~~.......",
			".............ff.....,,,.................",
			"..,,................,,,.......ff........",
			".,,,.......^^..............fFf..........",
			"...........^^^..............ff..........",
			"......ff.....^.......~~~................",
			".....fFf............~~~~~......,,.......",
			"......ff.............~~~~.....,,,.......",
			".....................~~~................",
			"...N,..........ff.............^^........",
			"..,,,.........fFf.............^^^.......",
			"...............ff.......,,.....^........",
			".....~~~..............,,,,..........ff..",
			"....~~~~~.......s.....,,...........fFf..",
			".....~~~......s.C.s.....2..........ff...",
			"...............s.........~~~............",
			"........................~~~~~......N....",
			".........................~~~............",
		],
	},
	{
		id = "m3", name = "Sinal Perdido", theme = "canyon",
		briefing = [
			"Os relés de comunicação do Cânion Rubro pararam de responder.",
			"Sem eles, não há reforço orbital no setor.",
			"Chegue a cada relé e fique parado sobre ele até religar.",
			"Os ninhos não param de gerar aracnídeos. Seja rápido.",
		],
		objective = { type = "switches", text = "Religue os 3 relés de comunicação" },
		settings = { max_flowers = 3, ambush = true, pickup_interval = 0.9 },
		map = [
			"######.............#####..........######",
			"#####......:.......####.....S.....######",
			"###........:........##..............####",
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
		id = "m4", name = "Posto Avançado Eco", theme = "desert",
		briefing = [
			"O Posto Eco guarda o gerador que mantém o escudo do vale ligado.",
			"Ondas de aracnídeos vão derrubar os muros pouco a pouco.",
			"Se o gerador cair, o setor inteiro cai junto.",
			"Resista até a nave de evacuação chegar. Os portões só deixam humanos passar.",
		],
		objective = { type = "survive", time = 210.0, text = "Proteja o gerador até a evacuação" },
		settings = { max_flowers = 2, ambush = true, pickup_interval = 0.8 },
		map = [
			"........................................",
			"..N.......,,,..........^^.........N.....",
			"..........,,,..........^^...............",
			"....^^..................................",
			"....^^^.......................,,........",
			".........ff..................,,,........",
			"........fFf..===+====+===...............",
			".........ff..=__________=......ff.......",
			".............=__s____s__=.....fFf.......",
			"..,,.........+___C__G___+......ff.......",
			".,,,.........=__s____s__=...............",
			".............=__________=........^^.....",
			"......ff.....===+====+===........^^^....",
			".....fFf................................",
			"......ff.........,,,....................",
			"...^^............,,,..........ff........",
			"...^^^.......................fFf........",
			"..............................ff........",
			"..N.............................N.......",
			"........................................",
		],
	},
	{
		id = "m5", name = "Coração da Colmeia", theme = "hive",
		briefing = [
			"A Estação Orbe-7 foi tomada. O Cristal Prisma do canhão de plasma",
			"está dentro do Coração da Colmeia, no fundo da instalação.",
			"Destrua o Coração, pegue o cristal e leve-o até a extração.",
			"Carregando o cristal você fica mais lento. Proteja-se com o esquadrão.",
		],
		objective = { type = "retrieve", text = "Destrua o Coração da Colmeia e recupere o cristal" },
		settings = { max_flowers = 4, ambush = true, pickup_interval = 0.8 },
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
	var allowed := ".,:_fx#^~=+CsbMNHFSGE123456"
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
	if t == "survive" and joined.count("G") != 1:
		errors.append("%s: objetivo 'survive' precisa de 1 'G'" % m.id)
	if t == "retrieve" and (joined.count("H") != 1 or joined.count("E") != 1):
		errors.append("%s: objetivo 'retrieve' precisa de 1 'H' e 1 'E'" % m.id)
	return errors
