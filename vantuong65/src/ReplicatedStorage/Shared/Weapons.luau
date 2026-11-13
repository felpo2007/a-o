--!strict
-- Ficha técnica das armas (Parte 10.6). Cada número tem fonte registrada em `src`.
-- "wiki:<página>" = infobox da Wikipedia em inglês consultada em 2026-11-09
--   (research/armas/wikipedia_infobox_2026-11-09.json): FONTE SECUNDÁRIA, a conferir no FM/TM.
-- "PLACEHOLDER" = sem fonte ainda; valor de jogo provisório, não tratar como histórico.
--
-- Armas (2026-11-12, pedido do dono: "as armas não estão automáticas", "algumas armas não estão
-- atirando", "faça sniper"): modo padrão primeiro em `modes` (Tipo 56 sai no automático, como o
-- seletor do AK depois da trava); o automático da M14 só para o fuzileiro automático (`roleModes`);
-- o semi tem limite próprio de gatilho (`triggerS`), separado da cadência prática (`rpm` da SKS e das
-- pistolas era a prática, com recarga: a SKS só aceitava um tiro a cada 1,5 s); ferrolho com ciclo
-- (`boltS`) e luneta (`scope`) nos fuzis de precisão. A regra do disparo fica em Shared/Gatilho.
local Weapons = {}

-- Luneta (fuzis de precisão). fov = FOV da câmera com a luneta, pela regra do binóculo do jogo
-- (7x ≈ 10°, WeaponController): 70 / aumento. O campo real (trueFovDeg) fica registrado; na tela o
-- círculo da luneta mostra mais que ele (compromisso de jogo: com o campo real a Unertl teria 2,4° de
-- FOV e o analógico giraria 25 telas por segundo).
export type Scope = {
	name: string,
	mag: number, -- aumento
	fov: number, -- FOV vertical da câmera (graus)
	reticle: string, -- "unertl" (cruz fina com ponto) | "pu" (poste com barras laterais)
	eyeReliefM: number, -- olho até a ocular (m)
	trueFovDeg: number?, -- campo real (graus), quando há fonte
	src: { [string]: string },
}

export type Weapon = {
	id: string,
	name: string,
	faction: string,
	kind: string, -- "rifle" | "mg" | "pistol" | "launcher"
	cartridge: string,
	muzzleVelocity: number, -- m/s
	rpm: number, -- cadência cíclica (tiros/min); arma sem automático: cadência prática (bots)
	magazine: number,
	massLoadedKg: number,
	bulletMassG: number,
	bcG1: number, -- coeficiente balístico G1 (lb/in²)
	modes: { string }, -- "semi" | "auto" | "single" | "bolt"; o 1º é o padrão
	dispersionMoa: number,
	boltHoldOpen: boolean,
	enabled: boolean, -- false: entra numa fase posterior
	src: { [string]: string },
	-- opcionais (2026-11-12)
	roleModes: { [string]: { string } }?, -- modo -> papéis que o têm (senão, todos)
	triggerS: number?, -- semi: intervalo mínimo entre puxadas de gatilho (s)
	boltS: number?, -- ferrolho: manobra entre tiros (s)
	reloadS: number?, -- recarga desta arma (s); senão a do tipo (RELOAD_S)
	zeros: { number }?, -- alça de mira (m); senão ZEROS
	adsEyeM: number?, -- olho até o ponto Sight mirando (m); senão o da arte (WeaponArt.eyeM)
	maxFlightS: number?, -- voo máximo simulado (s); senão 2,5
	armM: { number }?, -- lançador: distância de armar da espoleta (mín., máx.) em m
	explosive: string?, -- lançador: tipo em Shared/Explosive
	scope: Scope?,
	bipod: boolean?, -- bipé integral (M60, RPD)
	bipodRoles: { string }?, -- bipé só nestes papéis (M14: o bipé M2 do fuzileiro automático)
}

-- Limite do semi: o gatilho não sai mais rápido que isso (PLACEHOLDER: limite de jogo contra macro;
-- 10 puxadas por segundo, acima do que um atirador mira). A cadência cíclica vale se for maior.
Weapons.SEMI_MIN_S = 0.1
-- Alça padrão (m)
Weapons.ZEROS = { 100, 200, 300 }
-- Recarga por tipo (s), PLACEHOLDER (antes em CombatService.RELOAD e WeaponController.RELOAD_S)
Weapons.RELOAD_S = { rifle = 3.0, mg = 7.0, pistol = 2.5, launcher = 3.0 } :: { [string]: number }
-- Papel que leva a M14 com seletor e bipé (o fuzileiro automático da esquadra de tiro, Roles, só dos
-- EUA, um por squad). As outras M14 ficam no semi, como a maioria das M14 do USMC em 1965.
Weapons.AUTO_RIFLEMAN = "automatic_rifleman"
-- FOV mirando (fração do FOV base): fecha um pouco, sem lupa (pedido do dono). Era 55/70 = 0,786.
-- PLACEHOLDER de jogo.
Weapons.ADS_FOV_K = 0.72
-- Bipé: deitado ele fica armado no chão; de pé ou agachado, mirando com o guarda-mão sobre um
-- apoio (parapeito, tronco, saco de areia), a arma fica apoiada. Multiplica o coice por tiro e o
-- balanço da mira. PLACEHOLDER de jogo (sem medida de dispersão com e sem bipé).
Weapons.BIPOD = {
	prone = { kick = 0.5, sway = 0.4 },
	rested = { kick = 0.7, sway = 0.6 },
} :: { [string]: { kick: number, sway: number } }

local function w(t: Weapon): Weapon
	return t
end

Weapons.list = {
	w({
		id = "m14",
		name = "M14",
		faction = "US",
		kind = "rifle",
		cartridge = "7.62x51mm NATO",
		muzzleVelocity = 853, -- 2.800 ft/s
		rpm = 725, -- 700-750
		magazine = 20,
		massLoadedKg = 4.85, -- 10,7 lb com carregador cheio
		bulletMassG = 9.5,
		bcG1 = 0.39,
		modes = { "semi", "auto" },
		-- semi travado na maioria; seletor só no fuzileiro automático (FM 23-8, 1965: "When employed as
		-- an automatic rifle, the selector and bipod M2 must be installed")
		roleModes = { auto = { "automatic_rifleman" } },
		bipodRoles = { "automatic_rifleman" }, -- bipé M2 (FM 23-8, 1965, par. 3a)
		dispersionMoa = 3,
		boltHoldOpen = true,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:M14_rifle",
			rpm = "FM 23-8 (7/5/1965) par. 4: 700-750; wiki:M14_rifle",
			massLoadedKg = "wiki:M14_rifle",
			modes = "FM 23-8 (1965) par. 3a (Exército; o seletor e o bipé M2 só no fuzil automático); "
				.. "wiki:M14_rifle ('most M14s were permanently set to semiautomatic fire only'); fuzileiro "
				.. "em Chu Lai, 1965 (Small Arms Review): 3 em semi e 1 em automático por esquadra. "
				.. "Norma escrita do USMC: PLACEHOLDER (não achada)",
			magazine = "PLACEHOLDER (confirmar no FM 23-8)",
			bulletMassG = "PLACEHOLDER (M80 ball)",
			bcG1 = "PLACEHOLDER",
			dispersionMoa = "PLACEHOLDER",
		},
	}),
	w({
		id = "m60",
		name = "M60",
		faction = "US",
		kind = "mg",
		cartridge = "7.62x51mm NATO",
		muzzleVelocity = 853,
		rpm = 550, -- cíclica
		magazine = 100, -- fita
		massLoadedKg = 10.5,
		bulletMassG = 9.5,
		bcG1 = 0.39,
		modes = { "auto" }, -- só automático (sem seletor)
		bipod = true, -- bipé integral
		dispersionMoa = 6,
		boltHoldOpen = false,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:M60_machine_gun",
			rpm = "FM 23-67 (26/10/1964): cerca de 550 cíclica (wiki: 550-650; era 600)",
			massLoadedKg = "wiki:M60_machine_gun (sem munição)",
			magazine = "PLACEHOLDER (fita de 100)",
			bcG1 = "PLACEHOLDER",
		},
	}),
	w({
		id = "m1911",
		name = "M1911A1",
		faction = "US",
		kind = "pistol",
		cartridge = ".45 ACP",
		muzzleVelocity = 253, -- 830 ft/s
		rpm = 30, -- cadência prática (bots)
		magazine = 7,
		massLoadedKg = 1.1, -- 39 oz vazia com carregador
		bulletMassG = 14.9,
		bcG1 = 0.16,
		modes = { "semi" },
		dispersionMoa = 10,
		boltHoldOpen = true,
		enabled = true,
		adsEyeM = 0.38, -- braços estendidos, cotovelos pouco dobrados (era 0,45: pequena demais)
		src = {
			muzzleVelocity = "wiki:M1911_pistol",
			rpm = "PLACEHOLDER (FM 23-35, 1940: limitada pela destreza do atirador; era 120 = 0,5 s entre tiros)",
			magazine = "wiki:M1911_pistol (7 no padrão)",
			massLoadedKg = "wiki:M1911_pistol",
			bulletMassG = "PLACEHOLDER (230 gr)",
			bcG1 = "PLACEHOLDER",
			adsEyeM = "PLACEHOLDER (pedido do dono: pistola mais perto, braços estendidos)",
		},
	}),
	w({
		id = "m79",
		name = "M79",
		faction = "US",
		kind = "launcher",
		cartridge = "40x46mm (M406 HE)",
		muzzleVelocity = 76, -- 250 ft/s
		rpm = 6,
		magazine = 1,
		massLoadedKg = 2.93,
		bulletMassG = 230,
		bcG1 = 0.14, -- ajustado: alcance máximo de 401 m a 42° (tests/luau/armas.luau)
		modes = { "single" },
		dispersionMoa = 30,
		boltHoldOpen = false,
		enabled = true, -- 2026-11-12: atira (granada M406 simulada no CombatService)
		zeros = { 75, 100, 150, 200, 250, 300, 375 }, -- alça de escada: 75 a 375 m de 25 em 25
		maxFlightS = 12,
		armM = { 14, 27 },
		explosive = "grenade_us", -- PLACEHOLDER: 5 m de raio letal, como a M406 (FAS)
		src = {
			muzzleVelocity = "TM 43-0001-28 via inetres.com (250 ft/s); wiki:M79_grenade_launcher",
			massLoadedKg = "wiki:M79_grenade_launcher",
			armM = "man.fas.org/dod-101/sys/land/m406.htm ('arms between 14 and 27 meters')",
			explosive = "FAS M406: baixas num raio de 5 m (o raio de 130 m do TM é área de perigo); "
				.. "o efeito é o da granada de mão grenade_us (5 m letal), PLACEHOLDER",
			zeros = "wiki:M79_grenade_launcher (alça de 75 a 375 m, de 25 em 25)",
			bcG1 = "PLACEHOLDER derivado: alcance máximo de 400 m (wiki)",
		},
	}),
	w({
		id = "type56",
		name = "Type 56",
		faction = "VC",
		kind = "rifle",
		cartridge = "7.62x39mm",
		muzzleVelocity = 735,
		rpm = 650,
		magazine = 30,
		massLoadedKg = 3.8,
		bulletMassG = 7.9,
		bcG1 = 0.275,
		-- seletor do AK: trava em cima, automático no meio, semi embaixo (o 1º clique depois da trava é
		-- o automático); marcas chinesas 连 (contínuo) e 单 (simples)
		modes = { "auto", "semi" },
		dispersionMoa = 4,
		boltHoldOpen = false, -- sem trava do ferrolho no vazio (Parte 10.6)
		enabled = true,
		src = {
			muzzleVelocity = "wiki:Type_56_assault_rifle",
			rpm = "wiki:Type_56_assault_rifle (zh-wiki: 600)",
			modes = "wiki:AK-47 ('safe (up), full-auto (center), and semi-auto (down)'); manual do "
				.. "Exército dos EUA do AK-47 (203d MI Bn); zh-wiki 56式自动步枪 (连/单)",
			magazine = "wiki:Type_56_assault_rifle (20/30/40)",
			massLoadedKg = "wiki:Type_56_assault_rifle (3,8 kg; vazia?)",
			bulletMassG = "PLACEHOLDER (M43)",
			bcG1 = "PLACEHOLDER",
		},
	}),
	w({
		id = "sks",
		name = "SKS",
		faction = "VC",
		kind = "rifle",
		cartridge = "7.62x39mm",
		muzzleVelocity = 735,
		rpm = 40, -- cadência prática 35-40 (com recarga): só os bots usam; o gatilho usa triggerS
		magazine = 10,
		massLoadedKg = 3.85,
		bulletMassG = 7.9,
		bcG1 = 0.275,
		modes = { "semi" },
		dispersionMoa = 3.5,
		boltHoldOpen = true,
		enabled = true,
		-- olho 6 cm mais à frente na coronha (era 0,319 m da alça tangente: a arma parecia longe)
		adsEyeM = 0.26,
		src = {
			muzzleVelocity = "wiki:SKS",
			rpm = "wiki:SKS (prática 35-40; ru-wiki: 40 de combate)",
			magazine = "wiki:SKS (fixo, clipe)",
			massLoadedKg = "wiki:SKS",
			bcG1 = "PLACEHOLDER",
			adsEyeM = "PLACEHOLDER (pedido do dono: arma mais perto ao mirar)",
		},
	}),
	w({
		id = "rpd",
		name = "RPD",
		faction = "VC",
		kind = "mg",
		cartridge = "7.62x39mm",
		muzzleVelocity = 735,
		rpm = 700, -- 650-750
		magazine = 100,
		massLoadedKg = 7.4,
		bulletMassG = 7.9,
		bcG1 = 0.275,
		modes = { "auto" }, -- só automático (sem seletor)
		bipod = true, -- bipé integral
		dispersionMoa = 6,
		boltHoldOpen = false,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:RPD_machine_gun",
			rpm = "wiki:RPD_machine_gun (650-750)",
			magazine = "wiki:RPD_machine_gun (fita de 100 no tambor)",
			massLoadedKg = "wiki:RPD_machine_gun (vazia)",
			bcG1 = "PLACEHOLDER",
		},
	}),
	w({
		id = "type54",
		name = "Type 54",
		faction = "VC",
		kind = "pistol",
		cartridge = "7.62x25mm",
		muzzleVelocity = 420,
		rpm = 28, -- cadência prática (bots)
		magazine = 8,
		massLoadedKg = 0.89,
		bulletMassG = 5.5,
		bcG1 = 0.13,
		modes = { "semi" },
		dispersionMoa = 10,
		boltHoldOpen = true,
		enabled = true,
		adsEyeM = 0.38,
		src = {
			muzzleVelocity = "wiki:Type_54_pistol",
			rpm = "Museu da Grande Guerra Patriótica (Google Arts & Culture, TT-33): 25-30 utilizável",
			magazine = "wiki:Type_54_pistol",
			massLoadedKg = "wiki:Type_54_pistol",
			bulletMassG = "PLACEHOLDER",
			bcG1 = "PLACEHOLDER",
			adsEyeM = "PLACEHOLDER (pedido do dono: pistola mais perto, braços estendidos)",
		},
	}),
	w({
		id = "rpg2",
		name = "RPG-2",
		faction = "VC",
		kind = "launcher",
		cartridge = "PG-2 HEAT",
		muzzleVelocity = 0,
		rpm = 4,
		magazine = 1,
		massLoadedKg = 4.67,
		bulletMassG = 1840,
		bcG1 = 0.05,
		modes = { "single" },
		dispersionMoa = 40,
		boltHoldOpen = false,
		-- fora daqui de propósito: o RPG-2 atira pelo slot "launcher" do antitanque (VehicleService, PG-2)
		enabled = false,
		src = { massLoadedKg = "wiki:RPG-2 (pronto para disparo)", muzzleVelocity = "PENDENTE" },
	}),
	-- ===== fuzis de precisão (2026-11-12, "faça sniper"); modelos do Blender em assets/blender/arma_* =====
	w({
		id = "m70",
		name = "Winchester M70 (Unertl 8x)",
		faction = "US",
		kind = "rifle",
		cartridge = ".30-06 Springfield (M72 Match)",
		muzzleVelocity = 805, -- 2.640 ft/s medidos a 78 pés da boca
		rpm = 12, -- tiros mirados por minuto (bots)
		magazine = 5,
		massLoadedKg = 5.9,
		bulletMassG = 11.2, -- 173 gr
		bcG1 = 0.49,
		modes = { "bolt" },
		dispersionMoa = 1.0,
		boltHoldOpen = true,
		enabled = true,
		boltS = 1.1, -- manobra do ferrolho e a Unertl puxada de volta (corre para a frente no coice)
		reloadS = 6.0,
		zeros = { 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000 },
		maxFlightS = 3.5,
		scope = {
			name = "Unertl 8x",
			mag = 8,
			fov = 70 / 8,
			reticle = "unertl",
			eyeReliefM = 0.075,
			trueFovDeg = 2.1,
			src = {
				mag = "American Rifleman (M1903A1 Unertl): aumento real 7,8x, marcada 'J. UNERTL / USMC-SNIPER'",
				reticle = "anúncios de leilão (Rock Island, CT Firearms): cruz média com ponto pequeno no centro",
				eyeReliefM = "PLACEHOLDER",
				trueFovDeg = "PLACEHOLDER (réplica Hi-Lux: 11 pés a 100 jardas)",
				recuo = "American Rifleman: a luneta corria para a frente nas montagens e era puxada de volta",
			},
		},
		src = {
			uso = "usmcweaponry.com: 3ª Divisão de Fuzileiros chegou em meados de 1965 com 12 Winchester "
				.. "M70 de cano pesado; depois 53 M70 e 59 Unertl 8x para as duas divisões (e M1D)",
			muzzleVelocity = "TM 43-0001-27 via inetres.com (M72 Match: 2.640 ft/s a 78 pés)",
			bulletMassG = "TM 43-0001-27 via inetres.com (M72: 173 gr)",
			bcG1 = "PLACEHOLDER (wiki:.30-06_Springfield: M1 Ball 173 gr ~0,494; o M72 é a versão de competição)",
			magazine = "wiki:Winchester_Model_70 (5 nos calibres padrão)",
			massLoadedKg = "PLACEHOLDER (~13 lb com luneta e montagens; sem fonte firme)",
			rpm = "PLACEHOLDER (FM 23-10, 1940, no M1903: 10 a 15 tiros mirados por minuto)",
			dispersionMoa = "PLACEHOLDER (fuzil de competição com M72)",
			boltS = "PLACEHOLDER",
			reloadS = "PLACEHOLDER (cartucho a cartucho: a Unertl fica sobre a caixa da culatra)",
		},
	}),
	w({
		id = "mosin",
		name = "Mosin-Nagant 91/30 PU",
		faction = "VC",
		kind = "rifle",
		cartridge = "7.62x54mmR (leve, tipo L)",
		muzzleVelocity = 865,
		rpm = 10, -- tiros por minuto (bots)
		magazine = 5,
		massLoadedKg = 4.6,
		bulletMassG = 9.6,
		bcG1 = 0.338,
		modes = { "bolt" },
		dispersionMoa = 1.5,
		boltHoldOpen = true,
		enabled = true,
		boltS = 1.2,
		reloadS = 6.0,
		zeros = { 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300 },
		maxFlightS = 3.5,
		scope = {
			name = "PU 3,5x",
			mag = 3.5,
			fov = 70 / 3.5,
			reticle = "pu",
			eyeReliefM = 0.072,
			trueFovDeg = 4.5,
			src = {
				mag = "wiki:PU_scope (3,5x21)",
				trueFovDeg = "wiki:PU_scope (4°30')",
				eyeReliefM = "wiki:PU_scope (72 mm)",
				reticle = "Firearms News ('heavy post reticle'); vendedor de peças: poste embaixo com "
					.. "traços laterais (confiança média)",
				zeros = "wiki:PU_scope (tambor de elevação de 0 a 1.300 m, de 100 em 100)",
			},
		},
		src = {
			uso = "Guns & Ammo ('Early Vietnam sniper rifles'): o ENV tinha muitos 91/30 PU; Firearms "
				.. "News: serviu no Vietnã",
			muzzleVelocity = "wiki:Mosin–Nagant (infobox: 865 m/s); ru-wiki: 865 m/s com a bala leve de 1908",
			bulletMassG = "wiki:7.62x54mmR (L de 1908: 9,61 g; LPS 9,6 g)",
			bcG1 = "wiki:7.62x54mmR (L: G1 ~0,338)",
			magazine = "snipercentral.com e wiki (5)",
			massLoadedKg = "PLACEHOLDER (fontes de 8,7 a 11,3 lb com luneta)",
			rpm = "ru-wiki Винтовка Мосина (10 tiros/min)",
			dispersionMoa = "PLACEHOLDER",
			boltS = "PLACEHOLDER",
			reloadS = "PLACEHOLDER (cartucho a cartucho com a PU montada: a confirmar)",
		},
	}),
} :: { Weapon }

Weapons.byId = {} :: { [string]: Weapon }
for _, wp in Weapons.list do
	Weapons.byId[wp.id] = wp
end

function Weapons.get(id: string): Weapon?
	return Weapons.byId[id]
end

-- ===== modos, cadência, recarga e alça (2026-11-12) =====

-- O papel tem este modo? (M14: automático só para o fuzileiro automático)
function Weapons.modeAllowed(wp: Weapon, mode: string, role: string?): boolean
	if not table.find(wp.modes, mode) then
		return false
	end
	local need = wp.roleModes and wp.roleModes[mode]
	return need == nil or (role ~= nil and table.find(need, role) ~= nil)
end

-- Modos do seletor que este papel tem, na ordem do seletor (o 1º é o padrão)
function Weapons.modesFor(wp: Weapon, role: string?): { string }
	local out = {}
	for _, m in wp.modes do
		if Weapons.modeAllowed(wp, m, role) then
			table.insert(out, m)
		end
	end
	if #out == 0 then
		table.insert(out, wp.modes[1])
	end
	return out
end

-- Intervalo mínimo entre tiros (s) no modo: automático = cadência cíclica; ferrolho = manobra;
-- semi e tiro único = limite do gatilho (e a cíclica, se a arma tiver automático).
function Weapons.interval(wp: Weapon, mode: string): number
	if mode == "auto" then
		return 60 / wp.rpm
	elseif mode == "bolt" then
		return wp.boltS or 1.2
	end
	local t = wp.triggerS or Weapons.SEMI_MIN_S
	if table.find(wp.modes, "auto") then
		t = math.max(t, 60 / wp.rpm)
	end
	return t
end

-- menor intervalo entre os modos da arma (compatibilidade)
function Weapons.minInterval(wp: Weapon): number
	local best = math.huge
	for _, m in wp.modes do
		best = math.min(best, Weapons.interval(wp, m))
	end
	return best
end

-- A arma tem bipé neste papel?
function Weapons.hasBipod(wp: Weapon, role: string?): boolean
	if wp.bipod then
		return true
	end
	local roles = wp.bipodRoles
	return roles ~= nil and role ~= nil and table.find(roles, role) ~= nil
end

-- Recarga (s). mult: vantagem "reload" (Shared/Vantagens.mult(player, "reload"); 1 sem o passe),
-- a mesma no cliente (animação) e no servidor (o gatilho só volta depois dela).
function Weapons.reloadTime(wp: Weapon, mult: number?): number
	return (wp.reloadS or Weapons.RELOAD_S[wp.kind] or 3) * (mult or 1)
end

-- Dotação por vida (PLACEHOLDER; antes em CombatService.MAGS, igual a Kit.DEFAULT_MAGS)
Weapons.MAGS = { rifle = 6, mg = 2, pistol = 3, launcher = 6 } :: { [string]: number }

-- Carregadores da arma principal ao nascer: os do kit (Kit_Set) ou a dotação, + equipamento liberado
-- (D-72, GearMags) + vantagem "mags" (Vantagens.extra; 0 sem o passe).
function Weapons.magsFor(wp: Weapon, kitMags: number?, gearMags: number?, perk: number?): number
	return (kitMags or Weapons.MAGS[wp.kind] or 3) + (gearMags or 0) + (perk or 0)
end

-- Granadas de mão por vida: kit (padrão 2, PLACEHOLDER) + equipamento liberado + vantagem "grenades"
function Weapons.grenadesFor(kitFrags: number?, gearFrags: number?, perk: number?): number
	return (kitFrags or 2) + (gearFrags or 0) + (perk or 0)
end

-- Prender a respiração mirando (s), PLACEHOLDER. Na luneta, vezes a vantagem "breath" (1,6 com o
-- passe); segurar mais que BREATH_TIRED_K desse tempo deixa o fôlego curto.
Weapons.BREATH_S = 4
Weapons.BREATH_TIRED_K = 0.75
function Weapons.breathTime(scoped: boolean, mult: number?): number
	return Weapons.BREATH_S * (if scoped then mult or 1 else 1)
end

function Weapons.zeros(wp: Weapon): { number }
	return wp.zeros or Weapons.ZEROS
end

-- olho até a alça mirando (m), se a ficha corrige a arte
function Weapons.adsEye(id: string?): number?
	local wp = if id then Weapons.byId[id] else nil
	if not wp then
		return nil
	end
	return if wp.scope then wp.scope.eyeReliefM else wp.adsEyeM
end

-- ===== Facas e baionetas (D-94) =====
-- Fora de Weapons.list (lista das armas de fogo: tela de equipamento, skins e testes). Modelos
-- feitos no Blender (tools/faca, assets/facas/<chave>.glb), chave do asset em AssetIds.Models.
-- Pontos medidos na malha (assets/facas/pontos.json), em studs no referencial local da MeshPart
-- publicada: ponta em −Z, fio em −Y (o importador gira o GLB 180° em Y e centra a peça na caixa).
-- grip = onde a mão fecha; guard = junção lâmina/guarda; ring = anel de boca (M6); base = articulação
-- que encosta na boca do fuzil (Tipo 56). Bainha: mouth = boca, loop = presilha do cinto (a malha da
-- bainha já traz o cabo da faca embainhada).
export type Knife = {
	id: string,
	name: string,
	faction: string,
	kind: string, -- "knife" | "bayonet"
	art: string, -- chave em AssetIds.Models
	lengthM: number,
	bladeM: number,
	size: { number },
	grip: { number },
	guard: { number },
	tip: { number },
	ring: { number }?,
	base: { number }?,
	sheath: { size: { number }, mouth: { number }, loop: { number }, tip: { number } }?,
	src: { [string]: string },
}

-- stylua: ignore
Weapons.knives = {
	kabar = {
		id = "kabar", name = "Ka-Bar USMC", faction = "US", kind = "knife", art = "faca_kabar",
		lengthM = 0.3014, bladeM = 0.1778,
		size = { 0.0886, 0.2232, 1.0764 }, grip = { 0, 0.0027, 0.3018 }, guard = { 0, 0.0009, 0.0968 },
		tip = { 0, 0.017, -0.5382 },
		sheath = { size = { 0.1638, 0.2232, 1.17 }, mouth = { -0.0134, 0.0027, 0.1421 },
			loop = { 0.0627, -0.0009, 0.3489 }, tip = { -0.0134, -0.0116, -0.585 } },
		src = { lengthM = "PLACEHOLDER (1219C2: 11 7/8 pol., lâmina 7 pol., de memória)" },
	},
	m6 = {
		id = "m6", name = "Baioneta M6", faction = "US", kind = "bayonet", art = "faca_m6",
		lengthM = 0.2921, bladeM = 0.1714,
		size = { 0.1036, 0.2232, 1.0432 }, grip = { 0, -0.0316, 0.2729 }, guard = { 0, -0.0357, 0.0907 },
		tip = { 0, -0.0348, -0.5216 }, ring = { 0, 0.0598, 0.1014 },
		sheath = { size = { 0.1289, 0.2232, 1.1666 }, mouth = { -0.0127, -0.0357, 0.1471 },
			loop = { 0.048, -0.033, 0.4976 }, tip = { -0.0127, -0.0384, -0.5833 } },
		src = { lengthM = "PLACEHOLDER (lâmina 6 3/4 pol., de memória)" },
	},
	type56 = {
		id = "type56", name = "Baioneta de espigão Tipo 56", faction = "VC", kind = "bayonet", art = "faca_type56",
		lengthM = 0.2886, bladeM = 0.223,
		size = { 0.0536, 0.0571, 1.0307 }, grip = { 0, 0, 0.3793 }, guard = { 0, 0, 0.2811 },
		tip = { 0, 0, -0.5154 }, base = { 0, 0, 0.4882 },
		src = { lengthM = "PLACEHOLDER (espigão rebatível, 22–24 cm)" },
	},
	dao = {
		id = "dao", name = "Facão (dao)", faction = "VC", kind = "knife", art = "faca_dao",
		lengthM = 0.5085, bladeM = 0.33,
		size = { 0.1116, 0.2261, 1.8161 }, grip = { 0, 0.0512, 0.6277 }, guard = { 0, 0.0441, 0.2705 },
		tip = { 0, 0.0584, -0.908 },
		sheath = { size = { 0.1234, 0.2614, 1.9018 }, mouth = { -0.0059, 0, 0.3062 },
			loop = { 0.0377, 0, 0.0455 }, tip = { -0.0059, 0.0161, -0.9509 } },
		src = { lengthM = "PLACEHOLDER (facão de mato, lâmina 30–35 cm)" },
	},
} :: { [string]: Knife }

function Weapons.knife(id: string?): Knife?
	return if id then Weapons.knives[id] else nil
end

return Weapons
