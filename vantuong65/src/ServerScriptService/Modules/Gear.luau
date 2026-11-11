--!strict
-- Uniforme e equipamento do soldado (D-30, v3). Chamado por Characters.describe/dress.
--
-- Parte PURA (sem `game`, `Enum`, `CFrame` no topo: carrega no Lune, tests/luau/uniformes.luau):
--   Gear.uniform    qual molde (v3, senão v2) e onde a cor do corpo tem de ser pele;
--   Gear.items      lista do equipamento por facção, papel e cosmético "extra";
--   Gear.layout     peças (tamanho/posição em studs) no espaço da peça do corpo;
--   Gear.headgearFit / Gear.vestFit  ajuste de capacete/chapéu e colete do ForgeGUI ao corpo.
-- Parte do ROBLOX: Gear.build cria as Parts (Fabric/Leather/Metal/Wood), soldadas ao corpo, sem
-- colisão, sem consulta de raio (o tiro passa para o corpo) e sem massa.
--
-- Fidelidade (agosto de 1965):
-- - USMC: cinto M1961 com porta-carregadores M1961 de UM carregador de M14 cada (o equipamento
--   próprio dos fuzileiros; o M1956 de 2 carregadores é do Exército), suspensório e mochila
--   M1941 ("haversack") com a pá M1943 na capa presa na mochila, cantis M1910 e estojo de
--   curativo. Fonte: vietnamgear.com (M1961 Cartridge Belt, "typically worn in conjunction with the
--   M1941 suspenders and pack"). A "butt pack" (M1961/M1956) era do Exército: não entra.
--   Com o colete M1955, o suspensório fica POR BAIXO do colete (legenda de 1965 citada nas fontes),
--   então só as alças da mochila aparecem por cima dos ombros.
-- - VC/Força Principal: cinto de lona, porta-carregador de peito chinês (10 células de pente para
--   o SKS; 3 carregadores + 2 bolsinhos para o Tipo 56), cantil de alumínio pintado, granadas de
--   cabo enfiadas no cinto, bolsa de tambor do RPD, coldre do Tipo 54. Tubo de arroz a tiracolo
--   só com o cosmético `vc_rice_tube` (Commerce).
local Gear = {}

Gear.STUD_M = 0.28 -- 1 stud = 0,28 m (Units)
Gear.SMALL = 1.1 -- peças pequenas 10% maiores para lerem à distância
Gear.MAX_PIECES = 20 -- teto de peças por soldado (60 soldados × 20 = 1.200 Parts no pior caso)
-- Fração dos bots VC vestidos de guerrilha local (pijama preto). Os jogadores só usam o preto
-- com o cosmético "vc_black" (ainda não existe no Commerce). 0 desliga.
Gear.GUERRILLA_SHARE = 0.2
-- Frente dos modelos do ForgeGUI no Roblox. Nos GLB o colete e os capacetes olham para +X (a
-- jugular aparece de frente quando se olha ao longo de X); o importador troca o sinal de x e z
-- (D-58), então no Roblox a frente fica em −X, como nos veículos (ART_YAW = −90°). CONFERIR NO
-- STUDIO: se o zíper do colete aparecer nas costas, troque para math.pi / 2.
Gear.ART_YAW = -math.pi / 2

export type Vec = { x: number, y: number, z: number }
export type Piece = {
	name: string,
	attach: string, -- "UpperTorso" | "LowerTorso" | "Head"
	shape: string, -- "Block" | "Cylinder" (o eixo do cilindro é o X da peça)
	size: Vec, -- studs
	pos: Vec, -- centro, no espaço da peça do corpo (−Z é a frente)
	rot: Vec, -- graus, CFrame.Angles(x, y, z)
	material: string, -- "Fabric" | "Leather" | "Metal" | "Wood" | "SmoothPlastic"
	color: { number }, -- RGB 0..255
	shadow: boolean,
	group: string?, -- "belt": recipientes pendurados no cinto (não podem se sobrepor)
}
export type Fit = {
	size: Vec, -- tamanho da caixa do modelo no espaço DO MODELO (x, y, z nativos)
	body: Vec, -- o mesmo no espaço do corpo (x = largura, y = altura, z = profundidade)
	offsetY: number, -- centro da caixa acima do centro da peça do corpo
	brimY: number?, -- capacete: altura da aba (espaço da cabeça)
	topY: number?, -- capacete: topo
	squash: number?, -- capacete: fator vertical aplicado (1 = proporção do modelo)
}
export type Env = {
	lower: Vec, -- LowerTorso.Size
	upper: Vec, -- UpperTorso.Size
	head: Vec?,
	shell: Vec, -- casca do tronco de cima: o colete ajustado, se houver; senão o próprio tronco
	shellLift: number, -- centro da casca acima do centro do UpperTorso
	hasVest: boolean,
	helmet: Fit?,
}
export type Uniform = {
	variant: string, -- US: "down" | "rolled"; VC: "khaki" | "green" | "black"
	colors: string, -- chave de Gear.COLORS (cor do corpo sem molde)
	shirt: string?, -- chave de AssetIds.Clothing (nil: nenhum molde publicado)
	pants: string?,
	shirtV3: boolean,
	pantsV3: boolean,
	skinTorso: boolean, -- o molde deixa a pele à mostra (decote do VC)
	skinArms: boolean, -- mãos (e antebraço arregaçado)
	skinLegs: boolean, -- canela e pé do VC (calça arregaçada, sandália)
	shirtRgb: { number }, -- cor do corpo por baixo da camisa (Gear.COLORS ou a da skin)
	pantsRgb: { number },
}
-- Skin de uniforme (Shared/Skins): molde novo na frente da lista e a cor do corpo sem molde. Sem
-- o molde da skin publicado, cai no molde normal do lado.
export type UniformSkin = {
	id: string,
	shirt: string?,
	pants: string?,
	rgb: { shirt: { number }, pants: { number } }?,
}

-- Cor do corpo por baixo do molde (e do soldado inteiro quando não há molde publicado).
Gear.COLORS = {
	US = { shirt = { 88, 92, 62 }, pants = { 80, 84, 58 } }, -- OG-107
	VC_khaki = { shirt = { 150, 132, 96 }, pants = { 140, 124, 90 } },
	VC_green = { shirt = { 76, 90, 64 }, pants = { 70, 82, 60 } },
	VC_black = { shirt = { 44, 44, 46 }, pants = { 40, 40, 42 } },
} :: { [string]: { shirt: { number }, pants: { number } } }

-- ------------------------------------------------------------------------------------------
-- Uniforme (molde)
-- ------------------------------------------------------------------------------------------
local function firstPublished(ids: { [string]: any }, keys: { string }): string?
	for _, k in keys do
		local id = ids[k]
		if type(id) == "number" and id ~= 0 then
			return k
		end
	end
	return nil
end

local function isV3(key: string?): boolean
	return key ~= nil and string.sub(key, -3) == "_v3"
end

-- Bot VC de guerrilha local? Determinístico pelo número do bot.
function Gear.isGuerrilla(seed: number): boolean
	local h = (math.floor(math.abs(seed)) * 7919 + 13) % 100
	return h < Gear.GUERRILLA_SHARE * 100
end

-- ids = AssetIds.Clothing. guerrilla: só para bots (BotService não passa cosmético). skin: skin de
-- uniforme com molde próprio (a do pijama preto vem como equipped.uniform = "vc_black").
function Gear.uniform(
	faction: string,
	equipped: { [string]: string }?,
	ids: { [string]: any },
	guerrilla: boolean?,
	skin: UniformSkin?
): Uniform
	local eq: { [string]: string } = equipped or {}
	local variant: string, colors: string, shirts: { string }, pants: { string }
	if faction == "US" then
		-- mangas arregaçadas só com o cosmético pago (Commerce: us_utility_rolled)
		variant = if eq.uniform == "us_utility_rolled" then "rolled" else "down"
		colors = "US"
		shirts = if variant == "rolled"
			then { "us_shirt_rolled_v3", "us_shirt_v3", "us_shirt" }
			else { "us_shirt_v3", "us_shirt" }
		pants = { "us_pants_v3", "us_pants" }
	else
		variant = if eq.uniform == "vc_green"
			then "green"
			elseif eq.uniform == "vc_black" or guerrilla then "black"
			else "khaki"
		colors = "VC_" .. variant
		-- reserva: a v2 não tem o preto; o verde cai no verde v2, o resto no cáqui
		local v2 = if variant == "green" then "green" else "khaki"
		shirts = { "vc_" .. variant .. "_shirt_v3", "vc_" .. v2 .. "_shirt_v3", "vc_" .. v2 .. "_shirt" }
		pants = { "vc_" .. variant .. "_pants_v3", "vc_" .. v2 .. "_pants_v3", "vc_" .. v2 .. "_pants" }
	end
	local col = Gear.COLORS[colors] or Gear.COLORS.US
	local shirtRgb, pantsRgb = col.shirt, col.pants
	if skin then
		variant = skin.id
		if skin.shirt then
			table.insert(shirts, 1, skin.shirt)
		end
		if skin.pants then
			table.insert(pants, 1, skin.pants)
		end
		if skin.rgb then
			shirtRgb, pantsRgb = skin.rgb.shirt, skin.rgb.pants
		end
	end
	local s = firstPublished(ids, shirts)
	local p = firstPublished(ids, pants)
	local s3, p3 = isV3(s), isV3(p)
	return {
		variant = variant,
		colors = colors,
		shirt = s,
		pants = p,
		shirtV3 = s3,
		pantsV3 = p3,
		skinTorso = s3 and faction ~= "US",
		skinArms = s3,
		skinLegs = p3 and faction ~= "US",
		shirtRgb = shirtRgb,
		pantsRgb = pantsRgb,
	}
end

-- ------------------------------------------------------------------------------------------
-- Ajuste de capacete/chapéu e colete (modelos do ForgeGUI)
-- ------------------------------------------------------------------------------------------
-- Medidas tiradas dos GLB (fatias de vértices, 2026-11-11):
--   crown: fração da largura lateral da caixa ocupada pela copa (o resto é aba/jugular);
--   brim: altura da aba (fatia mais larga) em fração da altura da caixa (embaixo fica a jugular).
-- Escolhas de visual (conferir no Studio):
--   side: largura da copa / largura da cabeça; brimAt: aba acima do centro da cabeça (× altura);
--   gap: folga do topo acima da cabeça (× altura). A cabeça do Roblox é um cubo grande: com a
--   proporção do modelo a aba cairia nos olhos, então a altura é achatada (squash, 0,6 a 1,2).
Gear.HEADGEAR = {
	us_m1_helmet = { side = 1.06, crown = 0.9, brim = 0.42, brimAt = 0.04, gap = 0.06 },
	vc_pith_helmet = { side = 1.04, crown = 0.62, brim = 0.52, brimAt = 0.1, gap = 0.16 },
	vc_jungle_hat = { side = 1.03, crown = 0.5, brim = 0.56, brimAt = 0.1, gap = 0.06 },
} :: { [string]: { side: number, crown: number, brim: number, brimAt: number, gap: number } }

-- Colete M1955 sobre o UpperTorso: largura, profundidade e altura relativas ao tronco.
Gear.VEST = { width = 1.08, depth = 1.3, height = 1.06, lift = 0.03 }

local function vec(x: number, y: number, z: number): Vec
	return { x = x, y = y, z = z }
end
Gear.vec = vec

local function clamp(x: number, a: number, b: number): number
	return if x < a then a elseif x > b then b else x
end

-- native: caixa do modelo no espaço do modelo (x = frente-trás, z = lado, como no GLB).
function Gear.headgearFit(key: string, head: Vec, native: Vec): Fit?
	local c = Gear.HEADGEAR[key]
	if not c or native.x <= 0 or native.y <= 0 or native.z <= 0 then
		return nil
	end
	local k = c.side * head.x / (native.z * c.crown)
	local brimY = c.brimAt * head.y
	local wantTop = head.y / 2 + c.gap * head.y
	local squash = clamp((wantTop - brimY) / ((1 - c.brim) * native.y * k), 0.6, 1.2)
	local sy = native.y * k * squash
	local sz = native.z * k
	local sx = math.max(native.x * k, head.z * 1.04) -- cobre a cabeça de frente a trás
	local offsetY = brimY + (0.5 - c.brim) * sy
	return {
		size = vec(sx, sy, sz),
		body = vec(sz, sy, sx), -- com o giro de 90° (ART_YAW) o lado do modelo vira a largura
		offsetY = offsetY,
		brimY = brimY,
		topY = offsetY + sy / 2,
		squash = squash,
	}
end

function Gear.vestFit(torso: Vec): Fit
	local c = Gear.VEST
	local w, h, d = torso.x * c.width, torso.y * c.height, torso.z * c.depth
	return { size = vec(d, h, w), body = vec(w, h, d), offsetY = torso.y * c.lift }
end

function Gear.env(lower: Vec, upper: Vec, head: Vec?, vest: Fit?, helmet: Fit?): Env
	local shell = upper
	if vest then
		shell = vec(math.max(vest.body.x, upper.x), vest.body.y, math.max(vest.body.z, upper.z))
	end
	return {
		lower = lower,
		upper = upper,
		head = head,
		shell = shell,
		shellLift = if vest then vest.offsetY else 0,
		hasVest = vest ~= nil,
		helmet = helmet,
	}
end

-- ------------------------------------------------------------------------------------------
-- Equipamento por facção e papel
-- ------------------------------------------------------------------------------------------
local KIT_BY_ROLE = {
	US = {
		rifleman = "rifle",
		squad_leader = "leader",
		engineer = "rifle",
		observer = "leader",
		sniper = "rifle",
		radio_operator = "radio",
		grenadier = "pistol",
		machine_gunner = "pistol",
		anti_tank = "pistol",
		medic = "medic",
		commander = "officer",
		tank_crew = "crew",
		pilot = "crew",
		door_gunner = "crew",
		mortar = "crew",
	},
	VC = {
		rifleman = "sks",
		engineer = "sks",
		sniper = "sks",
		grenadier = "grenadier",
		squad_leader = "ak",
		observer = "ak",
		machine_gunner = "rpd",
		commander = "pistol",
		anti_tank = "pistol",
		mortar = "pistol",
		medic = "medic",
		radio_operator = "radio",
		sapper = "sapper",
	},
} :: { [string]: { [string]: string } }

local KITS = {
	US = {
		-- fuzileiro com M14: 4 porta-carregadores M1961, 2 cantis, curativo, mochila M1941 e pá
		rifle = { "belt", "buckle", "m14_pouches", "first_aid", "canteen_l", "canteen_r", "haversack" },
		leader = { "belt", "buckle", "m14_pouches", "first_aid", "canteen_l", "canteen_r", "haversack", "binoculars" },
		-- rádio PRC-10 no lugar da mochila
		radio = { "belt", "buckle", "m14_pouches", "first_aid", "canteen_l", "canteen_r", "radio" },
		-- M60/M79/bazuca: pistola no coldre e 2 bolsas
		pistol = { "belt", "buckle", "pouches2", "holster", "first_aid", "canteen_l", "canteen_r", "haversack" },
		-- corpsman: bolsa médica atrás à esquerda
		medic = { "belt", "buckle", "holster", "first_aid", "canteen_r", "medic_bag", "haversack" },
		officer = { "belt", "buckle", "pouches2", "holster", "first_aid", "canteen_l", "canteen_r", "binoculars" },
		-- tripulações: só o cinto com coldre, curativo e um cantil
		crew = { "belt", "buckle", "holster", "first_aid", "canteen_r" },
	},
	VC = {
		sks = { "belt", "buckle", "canteen", "sks_rig", "grenades2" },
		grenadier = { "belt", "buckle", "canteen", "sks_rig", "grenades4" },
		ak = { "belt", "buckle", "canteen", "ak_rig", "grenades2" },
		rpd = { "belt", "buckle", "canteen", "drum_pouch", "grenades2" },
		pistol = { "belt", "buckle", "canteen", "holster", "grenades2" },
		medic = { "belt", "buckle", "canteen", "sks_rig", "medic_bag" },
		radio = { "belt", "buckle", "canteen", "sks_rig", "frog_pack" },
		sapper = { "belt", "buckle", "canteen", "grenades4" },
	},
} :: { [string]: { [string]: { string } } }
Gear.KITS = KITS
Gear.KIT_BY_ROLE = KIT_BY_ROLE

function Gear.items(faction: string, role: string?, equipped: { [string]: string }?): { string }
	local eq: { [string]: string } = equipped or {}
	local fac = if faction == "US" then "US" else "VC"
	local byRole = KIT_BY_ROLE[fac]
	local kit = byRole[role or "rifleman"] or byRole.rifleman
	local list = table.clone(KITS[fac][kit])
	-- D-94: todo soldado leva a faca no cinto (Ka-Bar do USMC; facão do VC)
	table.insert(list, "knife")
	if fac == "US" then
		if eq.extra == "us_towel" then
			table.insert(list, "towel")
		elseif eq.extra == "us_repellent_band" then
			table.insert(list, "repellent")
		end
	elseif eq.extra == "vc_rice_tube" then
		table.insert(list, "rice_tube")
	end
	return list
end

-- ------------------------------------------------------------------------------------------
-- Peças
-- ------------------------------------------------------------------------------------------
local C = {
	-- USMC
	od_web = { 86, 84, 58 }, -- M1961 (verde-oliva, mais novo)
	khaki_web = { 139, 124, 88 }, -- M1941 (cáqui desbotado, Coreia/2ª Guerra)
	od_canvas = { 80, 82, 58 },
	od_metal = { 74, 72, 56 },
	russet = { 92, 58, 36 }, -- coldre M1916 de couro
	wood = { 118, 86, 54 },
	radio = { 82, 86, 62 },
	black = { 30, 30, 30 },
	towel = { 72, 80, 54 },
	bottle = { 176, 170, 150 },
	-- VC
	vc_belt = { 112, 84, 52 }, -- lona marrom (D-30)
	vc_rig = { 118, 112, 78 }, -- lona cáqui-oliva chinesa
	vc_metal = { 128, 126, 118 },
	vc_canteen = { 80, 92, 66 }, -- alumínio pintado de verde
	iron = { 58, 58, 54 },
	vc_wood = { 130, 98, 62 },
	vc_leather = { 96, 64, 40 },
	rice = { 150, 140, 112 },
}

-- metros reais -> studs (k: fator de leitura; 1 para as peças grandes)
local function m(meters: number, k: number?): number
	return meters / Gear.STUD_M * (k or Gear.SMALL)
end

function Gear.layout(faction: string, items: { string }, env: Env): { Piece }
	local out: { Piece } = {}
	local function add(
		name: string,
		attach: string,
		shape: string,
		size: Vec,
		pos: Vec,
		material: string,
		color: { number },
		rot: Vec?,
		shadow: boolean?,
		group: string?
	)
		table.insert(out, {
			name = name,
			attach = attach,
			shape = shape,
			size = size,
			pos = pos,
			rot = rot or vec(0, 0, 0),
			material = material,
			color = color,
			shadow = shadow == true,
			group = group,
		})
	end
	local VERT = vec(0, 0, 90) -- cilindro em pé
	local us = faction == "US"
	local L, U, S = env.lower, env.upper, env.shell
	local lx, ly, lz = L.x / 2, L.y / 2, L.z / 2
	local ux, uy = U.x / 2, U.y / 2
	local sz = S.z / 2
	local T = 0.03 -- espessura do cinto
	local beltH = m(if us then 0.057 else 0.05)
	local beltY = ly - beltH / 2 - 0.02 -- na cintura (alto do LowerTorso)
	local beltTop = beltY + beltH / 2
	local fz, bz, sx = -(lz + T), lz + T, lx + T -- superfícies do cinto: frente, costas, lado
	local buckleW = m(if us then 0.065 else 0.05)

	-- alças por cima dos ombros (mochila, rádio, bolsa VC)
	local function shoulderStraps(color: { number })
		local y = uy + 0.035 + (if env.hasVest then 0.05 else 0)
		for i, sgn in { -1, 1 } do
			add(
				"strap_" .. i,
				"UpperTorso",
				"Block",
				vec(m(0.055), 0.06, S.z + 0.06),
				vec(sgn * 0.45 * ux, y, 0),
				"Fabric",
				color
			)
		end
	end
	-- pacote nas costas do tronco de cima (mochila, rádio): devolve centro e tamanho
	local function backpack(
		name: string,
		w: number,
		h: number,
		d: number,
		top: number,
		material: string,
		color: { number }
	): (number, number)
		local y = uy - top - h / 2
		local z = sz + d / 2 - 0.03 -- encostado na casca (colete ou tronco)
		add(name, "UpperTorso", "Block", vec(w, h, d), vec(0, y, z), material, color, nil, true)
		return y, z
	end
	-- porta-carregador de peito VC: corpo + 2 tiras na frente + tira nas costas
	local function chestStraps(rigTop: number, rigY: number)
		local len = math.max(0.1, uy - rigTop)
		for i, sgn in { -1, 1 } do
			add(
				"rig_strap_" .. i,
				"UpperTorso",
				"Block",
				vec(m(0.03), len, 0.04),
				vec(sgn * 0.5 * ux, rigTop + len / 2, -(sz + 0.02)),
				"Fabric",
				C.vc_rig
			)
		end
		add(
			"rig_strap_back",
			"UpperTorso",
			"Block",
			vec(U.x * 0.92, m(0.03), 0.04),
			vec(0, rigY, sz + 0.02),
			"Fabric",
			C.vc_rig
		)
	end
	local function grenades(xs: { number })
		local hl, hd = m(0.09), m(0.05)
		local gl, gd = m(0.15), m(0.03)
		for i, x in xs do
			add(
				"grenade_" .. i,
				"LowerTorso",
				"Cylinder",
				vec(hl, hd, hd),
				vec(x, beltTop + hl / 2 - 0.03, fz - 0.07),
				"Metal",
				C.iron,
				VERT,
				false,
				"belt"
			)
			add(
				"grenade_handle_" .. i,
				"LowerTorso",
				"Cylinder",
				vec(gl, gd, gd),
				vec(x, beltTop - 0.03 - gl / 2, fz - 0.04),
				"Wood",
				C.vc_wood,
				VERT
			)
		end
	end

	local wantKnife = false
	for _, item in items do
		if item == "knife" then
			wantKnife = true -- depois de tudo: vai no primeiro lugar livre do cinto
		elseif item == "belt" then
			add(
				"belt",
				"LowerTorso",
				"Block",
				vec(L.x + 2 * T, beltH, L.z + 2 * T),
				vec(0, beltY, 0),
				"Fabric",
				if us then C.od_web else C.vc_belt
			)
		elseif item == "buckle" then
			add(
				"buckle",
				"LowerTorso",
				"Block",
				vec(buckleW, beltH * 0.85, 0.05),
				vec(0, beltY, fz - 0.025),
				"Metal",
				if us then C.od_metal else C.vc_metal
			)
		elseif item == "m14_pouches" or item == "pouches2" then
			-- M1961: um carregador de 20 em pé por bolsa, dos dois lados da fivela
			local pw, ph, pd = m(0.075), m(0.15), m(0.045)
			local inner = buckleW / 2 + 0.04 + pw / 2
			local outer = inner + pw + 0.04
			local xs: { number } = if item == "m14_pouches" then { -outer, -inner, inner, outer } else { -inner, inner }
			for i, x in xs do
				add(
					"pouch_" .. i,
					"LowerTorso",
					"Block",
					vec(pw, ph, pd),
					vec(x, beltTop + 0.04 - ph / 2, fz - pd / 2),
					"Fabric",
					C.od_web,
					nil,
					false,
					"belt"
				)
			end
		elseif item == "first_aid" then
			local d, h, w = m(0.04), m(0.11), m(0.10)
			add(
				"first_aid",
				"LowerTorso",
				"Block",
				vec(d, h, w),
				vec(-(sx + d / 2), beltTop + 0.03 - h / 2, -0.22 * L.z),
				"Fabric",
				C.od_web,
				nil,
				false,
				"belt"
			)
		elseif item == "binoculars" then
			local d, h, w = m(0.05), m(0.13), m(0.10)
			add(
				"binoculars",
				"LowerTorso",
				"Block",
				vec(d, h, w),
				vec(-(sx + d / 2), beltTop + 0.02 - h / 2, 0.22 * L.z),
				"Fabric",
				C.od_canvas,
				nil,
				false,
				"belt"
			)
		elseif item == "canteen_l" or item == "canteen_r" then
			-- M1910 na capa, atrás dos quadris
			local w, h, d = m(0.14), m(0.19), m(0.075)
			local sgn = if item == "canteen_l" then -1 else 1
			add(
				item,
				"LowerTorso",
				"Block",
				vec(w, h, d),
				vec(sgn * 0.55 * lx, beltTop + 0.02 - h / 2, bz + d / 2),
				"Fabric",
				C.od_canvas,
				nil,
				false,
				"belt"
			)
		elseif item == "canteen" then
			local w, h, d = m(0.13), m(0.18), m(0.07)
			add(
				"canteen",
				"LowerTorso",
				"Block",
				vec(w, h, d),
				vec(0.55 * lx, beltTop + 0.02 - h / 2, bz + d / 2),
				"Metal",
				C.vc_canteen,
				nil,
				false,
				"belt"
			)
		elseif item == "holster" then
			local d, h, w = m(0.045), m(if us then 0.24 else 0.2), m(if us then 0.13 else 0.12)
			add(
				"holster",
				"LowerTorso",
				"Block",
				vec(d, h, w),
				vec(sx + d / 2, beltTop + 0.04 - h / 2, 0.05),
				"Leather",
				if us then C.russet else C.vc_leather,
				nil,
				false,
				"belt"
			)
		elseif item == "medic_bag" then
			if us then -- bolsa "Unit One" atrás, à esquerda
				local w, h, d = m(0.24), m(0.2), m(0.11)
				add(
					"medic_bag",
					"LowerTorso",
					"Block",
					vec(w, h, d),
					vec(-0.5 * lx, beltTop - 0.05 - h / 2, bz + d / 2),
					"Fabric",
					C.od_canvas,
					nil,
					true,
					"belt"
				)
			else
				local d, h, w = m(0.08), m(0.18), m(0.22)
				add(
					"medic_bag",
					"LowerTorso",
					"Block",
					vec(d, h, w),
					vec(-(sx + d / 2), beltY - 0.12, 0.05),
					"Fabric",
					C.vc_rig,
					nil,
					false,
					"belt"
				)
			end
		elseif item == "drum_pouch" then
			local d, h, w = m(0.11), m(0.17), m(0.2)
			add(
				"drum_pouch",
				"LowerTorso",
				"Block",
				vec(d, h, w),
				vec(sx + d / 2, beltY - 0.1, 0.05),
				"Fabric",
				C.vc_rig,
				nil,
				false,
				"belt"
			)
		elseif item == "grenades2" then
			grenades({ -0.42 * lx, -0.68 * lx })
		elseif item == "grenades4" then
			grenades({ -0.42 * lx, -0.68 * lx, 0.42 * lx, 0.68 * lx })
		elseif item == "haversack" then
			-- M1941: mochila alta nas costas, pá M1943 na capa por fora, cabo para baixo
			local w, h, d = m(0.3, 1), m(0.33, 1), m(0.1, 1)
			local y, z = backpack("haversack", w, h, d, 0.1, "Fabric", C.khaki_web)
			local cw, ch, cd = m(0.15), m(0.21), m(0.05)
			local cy, cz = y - 0.06, z + d / 2 + cd / 2 - 0.01
			add("etool", "UpperTorso", "Block", vec(cw, ch, cd), vec(0, cy, cz), "Fabric", C.od_canvas)
			local hl = m(0.16)
			add(
				"etool_handle",
				"UpperTorso",
				"Cylinder",
				vec(hl, m(0.035), m(0.035)),
				vec(0, cy - ch / 2 - hl / 2 + 0.08, cz),
				"Wood",
				C.wood,
				VERT
			)
			shoulderStraps(C.khaki_web)
		elseif item == "radio" then
			-- AN/PRC-10 nas costas, antena de chicote
			local w, h, d = m(0.29, 1), m(0.41, 1), m(0.11, 1)
			local y, z = backpack("radio", w, h, d, 0.05, "Metal", C.radio)
			local al = m(0.9, 1)
			add(
				"antenna",
				"UpperTorso",
				"Cylinder",
				vec(al, 0.06, 0.06),
				vec(w / 2 - 0.15, y + h / 2 + al / 2 - 0.05, z),
				"SmoothPlastic",
				C.black,
				vec(8, 0, 90)
			)
			shoulderStraps(C.khaki_web)
		elseif item == "frog_pack" then
			local w, h, d = m(0.28, 1), m(0.3, 1), m(0.12, 1)
			backpack("frog_pack", w, h, d, 0.15, "Fabric", C.vc_rig)
			shoulderStraps(C.vc_rig)
		elseif item == "sks_rig" then
			-- 10 células de pente de 10 tiros atravessando o peito
			local w, h, d = U.x * 0.9, m(0.12), m(0.045)
			local y = uy * 0.05
			add("sks_rig", "UpperTorso", "Block", vec(w, h, d), vec(0, y, -(sz + d / 2)), "Fabric", C.vc_rig, nil, true)
			chestStraps(y + h / 2, y)
		elseif item == "ak_rig" then
			-- 3 carregadores no meio e 2 bolsinhos (pentes/óleo) dos lados
			local mw, mh, md = m(0.21), m(0.2), m(0.06)
			local y = -uy * 0.15
			add(
				"ak_rig",
				"UpperTorso",
				"Block",
				vec(mw, mh, md),
				vec(0, y, -(sz + md / 2)),
				"Fabric",
				C.vc_rig,
				nil,
				true
			)
			local pw, ph, pd = m(0.08), m(0.12), m(0.045)
			for i, sgn in { -1, 1 } do
				add(
					"ak_side_" .. i,
					"UpperTorso",
					"Block",
					vec(pw, ph, pd),
					vec(sgn * (mw / 2 + pw / 2 + 0.03), y + 0.06, -(sz + pd / 2)),
					"Fabric",
					C.vc_rig
				)
			end
			chestStraps(y + mh / 2, y)
		elseif item == "rice_tube" then
			-- ống gạo: tubo de pano do ombro esquerdo ao quadril direito, frente e costas
			local dia = m(0.065)
			local x0, y0, x1, y1 = -0.8 * ux, uy * 0.92, 0.85 * ux, -uy * 0.95
			local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
			local ang = math.deg(math.atan2(y1 - y0, x1 - x0))
			local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
			add(
				"rice_front",
				"UpperTorso",
				"Cylinder",
				vec(len, dia, dia),
				vec(cx, cy, -(sz + dia / 2 + 0.05)),
				"Fabric",
				C.rice,
				vec(0, 0, ang)
			)
			add(
				"rice_back",
				"UpperTorso",
				"Cylinder",
				vec(len, dia, dia),
				vec(cx, cy, sz + dia / 2 - 0.02),
				"Fabric",
				C.rice,
				vec(0, 0, ang)
			)
		elseif item == "towel" then
			-- toalha verde no pescoço: dobra atrás da gola e duas pontas no peito
			local bw, bh, bd = m(0.34), m(0.1), m(0.035)
			add(
				"towel_back",
				"UpperTorso",
				"Block",
				vec(bw, bh, bd),
				vec(0, uy + bh / 2 - 0.02, sz * 0.55),
				"Fabric",
				C.towel
			)
			local tw, th, td = m(0.1), m(0.3), m(0.025)
			for i, sgn in { -1, 1 } do
				add(
					"towel_" .. i,
					"UpperTorso",
					"Block",
					vec(tw, th, td),
					vec(sgn * 0.3 * ux, uy - th / 2 + 0.06, -(sz + td / 2)),
					"Fabric",
					C.towel
				)
			end
		elseif item == "repellent" then
			-- frasco de repelente na tira do capacete, do lado esquerdo
			local hf = env.helmet
			if hf and hf.brimY and hf.topY then
				local bl, bd = m(0.09), m(0.032)
				local y = hf.brimY + 0.3 * (hf.topY - hf.brimY)
				add(
					"repellent",
					"Head",
					"Cylinder",
					vec(bl, bd, bd),
					vec(-(hf.body.x / 2 * 0.9 + bd / 2), y, 0.05),
					"SmoothPlastic",
					C.bottle,
					VERT
				)
			end
		end
	end
	if wantKnife then
		-- D-94: faca na bainha, pendurada no lado do cinto, cabo para cima (a arte publicada troca estas
		-- peças: Characters.knifeArt). Ka-Bar: bainha de couro de ~20 cm à vista; facão do VC: bainha
		-- de madeira de ~34 cm (PLACEHOLDER de medida, tools/faca). Primeiro lugar livre do cinto,
		-- sem encostar em bolsa, coldre, cantil ou granada.
		local d, w, h = m(if us then 0.03 else 0.035), m(if us then 0.055 else 0.075), m(if us then 0.2 else 0.34)
		local hl, hd = m(if us then 0.12 else 0.16), m(if us then 0.032 else 0.035)
		local top = beltTop + 0.02
		local slots = { { 1, 0.3 * L.z }, { 1, -0.32 * L.z }, { -1, 0 }, { -1, 0.36 * L.z }, { -1, -0.36 * L.z } }
		local belt: { Piece } = {}
		for _, p in out do
			if p.group == "belt" then
				table.insert(belt, p)
			end
		end
		for _, s in slots do
			local x = s[1] * (sx + d / 2)
			local sheath: Piece = {
				name = "knife_sheath",
				attach = "LowerTorso",
				shape = "Block",
				size = vec(d, h, w),
				pos = vec(x, top - h / 2, s[2]),
				rot = vec(0, 0, 0),
				material = if us then "Leather" else "Wood",
				color = if us then C.russet else C.vc_wood,
				shadow = false,
				group = "belt",
			}
			local handle: Piece = {
				name = "knife_handle",
				attach = "LowerTorso",
				shape = "Cylinder",
				size = vec(hl, hd, hd),
				pos = vec(x, top + hl / 2, s[2]),
				rot = VERT,
				material = if us then "Leather" else "Wood",
				color = if us then C.russet else C.vc_wood,
				shadow = false,
				group = "belt",
			}
			local free = true
			for _, mine in { sheath, handle } do
				local ea = Gear.extents(mine)
				for _, p in belt do
					local eb = Gear.extents(p)
					if
						math.abs(mine.pos.x - p.pos.x) < ea.x + eb.x + 0.01
						and math.abs(mine.pos.y - p.pos.y) < ea.y + eb.y + 0.01
						and math.abs(mine.pos.z - p.pos.z) < ea.z + eb.z + 0.01
					then
						free = false
					end
				end
			end
			if free then
				table.insert(out, sheath)
				table.insert(out, handle)
				break
			end
		end
	end
	return out
end

-- Meia-caixa (AABB) da peça girada, no espaço da peça do corpo. CFrame.Angles(x, y, z) = Rx·Ry·Rz.
function Gear.extents(p: Piece): Vec
	local rx, ry, rz = math.rad(p.rot.x), math.rad(p.rot.y), math.rad(p.rot.z)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	-- R = Rx * Ry * Rz
	local r = {
		{ cy * cz, -cy * sz, sy },
		{ cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
		{ sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
	}
	local h = { p.size.x / 2, p.size.y / 2, p.size.z / 2 }
	local e = {}
	for i = 1, 3 do
		e[i] = math.abs(r[i][1]) * h[1] + math.abs(r[i][2]) * h[2] + math.abs(r[i][3]) * h[3]
	end
	return vec(e[1], e[2], e[3])
end

-- ------------------------------------------------------------------------------------------
-- Roblox: cria as peças
-- ------------------------------------------------------------------------------------------
local function material(name: string): Enum.Material
	if name == "Leather" then
		return Enum.Material.Leather
	elseif name == "Metal" then
		return Enum.Material.Metal
	elseif name == "Wood" then
		return Enum.Material.Wood
	elseif name == "SmoothPlastic" then
		return Enum.Material.SmoothPlastic
	end
	return Enum.Material.Fabric
end

-- anchors: peça do corpo por nome ("UpperTorso", "LowerTorso", "Head"). As peças ficam numa
-- Folder (não Model): FindFirstAncestorWhichIsA("Model") de um acerto continua achando o soldado.
function Gear.build(model: Model, anchors: { [string]: BasePart? }, pieces: { Piece }): Folder
	local old = model:FindFirstChild("Equipamento")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Equipamento"
	for _, pc in pieces do
		local body = anchors[pc.attach]
		if body then
			local p = Instance.new("Part")
			p.Name = "Eq_" .. pc.name
			p.Shape = if pc.shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
			p.Size = Vector3.new(pc.size.x, pc.size.y, pc.size.z)
			p.Material = material(pc.material)
			p.Color = Color3.fromRGB(pc.color[1], pc.color[2], pc.color[3])
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CastShadow = pc.shadow
			p.CFrame = body.CFrame
				* CFrame.new(pc.pos.x, pc.pos.y, pc.pos.z)
				* CFrame.Angles(math.rad(pc.rot.x), math.rad(pc.rot.y), math.rad(pc.rot.z))
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
			p.Parent = folder
		end
	end
	folder.Parent = model
	return folder
end

return Gear
