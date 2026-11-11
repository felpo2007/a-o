--!strict
-- Ficha técnica das armas (Parte 10.6). Cada número tem fonte registrada em `src`.
-- "wiki:<página>" = infobox da Wikipedia em inglês consultada em 2026-11-09
--   (research/armas/wikipedia_infobox_2026-11-09.json): FONTE SECUNDÁRIA, a conferir no FM/TM.
-- "PLACEHOLDER" = sem fonte ainda; valor de jogo provisório, não tratar como histórico.
local Weapons = {}

export type Weapon = {
	id: string,
	name: string,
	faction: string,
	kind: string, -- "rifle" | "mg" | "pistol" | "launcher"
	cartridge: string,
	muzzleVelocity: number, -- m/s
	rpm: number, -- cadência cíclica (tiros/min); semi: cadência prática máxima
	magazine: number,
	massLoadedKg: number,
	bulletMassG: number,
	bcG1: number, -- coeficiente balístico G1 (lb/in²)
	modes: { string }, -- "semi" | "auto" | "single"
	dispersionMoa: number,
	boltHoldOpen: boolean,
	enabled: boolean, -- false: entra numa fase posterior (lançadores, F4)
	src: { [string]: string },
}

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
		modes = { "semi" }, -- seletor automático só no fuzileiro automático (Parte 10.3)
		dispersionMoa = 3,
		boltHoldOpen = true,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:M14_rifle",
			rpm = "wiki:M14_rifle",
			massLoadedKg = "wiki:M14_rifle",
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
		rpm = 600, -- 550-650
		magazine = 100, -- fita
		massLoadedKg = 10.5,
		bulletMassG = 9.5,
		bcG1 = 0.39,
		modes = { "auto" },
		dispersionMoa = 6,
		boltHoldOpen = false,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:M60_machine_gun",
			rpm = "wiki:M60_machine_gun",
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
		rpm = 120,
		magazine = 7,
		massLoadedKg = 1.1, -- 39 oz vazia com carregador
		bulletMassG = 14.9,
		bcG1 = 0.16,
		modes = { "semi" },
		dispersionMoa = 10,
		boltHoldOpen = true,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:M1911_pistol",
			magazine = "wiki:M1911_pistol (7 no padrão)",
			massLoadedKg = "wiki:M1911_pistol",
			bulletMassG = "PLACEHOLDER (230 gr)",
			bcG1 = "PLACEHOLDER",
		},
	}),
	w({
		id = "m79",
		name = "M79",
		faction = "US",
		kind = "launcher",
		cartridge = "40x46mm",
		muzzleVelocity = 76,
		rpm = 6,
		magazine = 1,
		massLoadedKg = 2.93,
		bulletMassG = 230,
		bcG1 = 0.05,
		modes = { "single" },
		dispersionMoa = 30,
		boltHoldOpen = false,
		enabled = false, -- explosivos e distância de armar entram na F4
		src = { muzzleVelocity = "wiki:M79_grenade_launcher", massLoadedKg = "wiki:M79_grenade_launcher" },
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
		modes = { "semi", "auto" }, -- ordem real do seletor a confirmar
		dispersionMoa = 4,
		boltHoldOpen = false, -- sem trava do ferrolho no vazio (Parte 10.6)
		enabled = true,
		src = {
			muzzleVelocity = "wiki:Type_56_assault_rifle",
			rpm = "wiki:Type_56_assault_rifle",
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
		rpm = 40, -- cadência prática 35-40
		magazine = 10,
		massLoadedKg = 3.85,
		bulletMassG = 7.9,
		bcG1 = 0.275,
		modes = { "semi" },
		dispersionMoa = 3.5,
		boltHoldOpen = true,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:SKS",
			rpm = "wiki:SKS",
			magazine = "wiki:SKS (fixo, clipe)",
			massLoadedKg = "wiki:SKS",
			bcG1 = "PLACEHOLDER",
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
		modes = { "auto" },
		dispersionMoa = 6,
		boltHoldOpen = false,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:RPD_machine_gun",
			rpm = "wiki:RPD_machine_gun",
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
		rpm = 120,
		magazine = 8,
		massLoadedKg = 0.89,
		bulletMassG = 5.5,
		bcG1 = 0.13,
		modes = { "semi" },
		dispersionMoa = 10,
		boltHoldOpen = true,
		enabled = true,
		src = {
			muzzleVelocity = "wiki:Type_54_pistol",
			magazine = "wiki:Type_54_pistol",
			massLoadedKg = "wiki:Type_54_pistol",
			bulletMassG = "PLACEHOLDER",
			bcG1 = "PLACEHOLDER",
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
		enabled = false, -- sem velocidade de boca com fonte ainda; F4
		src = { massLoadedKg = "wiki:RPG-2 (pronto para disparo)", muzzleVelocity = "PENDENTE" },
	}),
} :: { Weapon }

Weapons.byId = {} :: { [string]: Weapon }
for _, wp in Weapons.list do
	Weapons.byId[wp.id] = wp
end

function Weapons.get(id: string): Weapon?
	return Weapons.byId[id]
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

-- intervalo mínimo entre tiros (s), usado na validação do servidor
function Weapons.minInterval(wp: Weapon): number
	return 60 / wp.rpm
end

return Weapons
