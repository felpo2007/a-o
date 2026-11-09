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

-- intervalo mínimo entre tiros (s), usado na validação do servidor
function Weapons.minInterval(wp: Weapon): number
	return 60 / wp.rpm
end

return Weapons
