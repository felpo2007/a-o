--!strict
-- Testes do uniforme e do equipamento 3D (Lune): Modules/Gear (parte pura).
-- Uso, a partir de vantuong65/:  lune run tests/luau/uniformes.luau
local process = require("@lune/process")

local Gear = require("../../src/ServerScriptService/Modules/Gear") :: any
local Roles = require("../../src/ReplicatedStorage/Shared/Roles") :: any
local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds") :: any

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FALHA " .. name .. ": " .. tostring(err))
	end
end

local v = Gear.vec
-- R15 em bloco com HeightScale 1,2 (D-30) e um corpo de outras medidas (o "Man" não foi medido
-- fora do Studio: o layout tem de se ajustar a qualquer caixa). D-98: ampliados por Gear.BODY_K
-- (soldado de 2,0 m), como no jogo; o corpo "Man" pequeno de cabeça fica no terceiro.
local K = Gear.BODY_K
local function vk(x: number, y: number, z: number): any
	return v(x * K, y * K, z * K)
end
local BODIES = {
	bloco = { lower = vk(2, 0.48, 1), upper = vk(2, 1.92, 1), head = vk(1.2, 1.2, 1.2) },
	outro = { lower = vk(1.7, 0.55, 0.9), upper = vk(1.8, 1.9, 0.95), head = vk(1.05, 1.25, 1.1) },
	cabeca_pequena = { lower = vk(1.67, 0.6, 1.04), upper = vk(1.84, 1.75, 1.07), head = vk(0.8, 1.0, 0.85) },
}
-- caixas dos modelos do ForgeGUI em studs (espaço do modelo; x = frente-trás, z = lado), dos GLB
local NATIVE = {
	us_m1_helmet = v(1.02, 0.98, 0.88),
	vc_pith_helmet = v(1.14, 0.95, 0.96),
	vc_jungle_hat = v(1.13, 0.95, 1.21),
}

local ALL_V3: { [string]: number } = {}
for _, k in
	{
		"us_shirt_v3",
		"us_shirt_rolled_v3",
		"us_pants_v3",
		"vc_khaki_shirt_v3",
		"vc_khaki_pants_v3",
		"vc_green_shirt_v3",
		"vc_green_pants_v3",
		"vc_black_shirt_v3",
		"vc_black_pants_v3",
		"us_shirt",
		"us_pants",
		"vc_khaki_shirt",
		"vc_khaki_pants",
		"vc_green_shirt",
		"vc_green_pants",
	}
do
	ALL_V3[k] = 1
end
local ONLY_V2: { [string]: number } = {}
for k, id in AssetIds.Clothing do
	if string.sub(k, -3) ~= "_v3" then
		ONLY_V2[k] = id
	end
end

local function envFor(faction: string, b: any, helmetKey: string?): any
	local vest = if faction == "US" then Gear.vestFit(b.upper) else nil
	local helmet = if helmetKey then Gear.headgearFit(helmetKey, b.head, NATIVE[helmetKey]) else nil
	return Gear.env(b.lower, b.upper, b.head, vest, helmet)
end

-- caixa da peça do corpo onde a peça se apoia (centro, meia-caixa)
local function anchorBox(env: any, attach: string): (any, any)
	if attach == "LowerTorso" then
		return v(0, 0, 0), v(env.lower.x / 2, env.lower.y / 2, env.lower.z / 2)
	elseif attach == "UpperTorso" then
		return v(0, 0, 0), v(env.shell.x / 2, env.upper.y / 2, env.shell.z / 2)
	end
	local h = env.head
	local hf = env.helmet
	if hf then
		return v(0, hf.offsetY, 0), v(hf.body.x / 2, hf.body.y / 2, hf.body.z / 2)
	end
	return v(0, 0, 0), v(h.x / 2, h.y / 2, h.z / 2)
end

local function combos(): { { faction: string, role: string, extra: string?, body: string } }
	local out = {}
	for faction, byRole in Roles.loadout do
		local extras = if faction == "US"
			then { "us_none", "us_towel", "us_repellent_band" }
			else { "vc_none", "vc_rice_tube" }
		for role in byRole do
			for _, extra in extras do
				for bodyName in BODIES do
					table.insert(out, { faction = faction, role = role, extra = extra, body = bodyName })
				end
			end
		end
	end
	return out
end

local function piecesFor(c: any): (any, { any })
	local b = BODIES[c.body]
	local helmet = if c.faction == "US" then "us_m1_helmet" else nil
	local env = envFor(c.faction, b, helmet)
	local items = Gear.items(c.faction, c.role, { extra = c.extra })
	return env, Gear.layout(c.faction, items, env)
end

test("uniforme: v3 quando publicado; sem v3 cai na v2; sem nada, sem molde", function()
	local u = Gear.uniform("US", nil, ALL_V3, false)
	assert(u.shirt == "us_shirt_v3" and u.pants == "us_pants_v3", "US v3")
	assert(u.skinArms and not u.skinTorso and not u.skinLegs, "US v3: só mãos na pele")
	local u2 = Gear.uniform("US", nil, ONLY_V2, false)
	assert(u2.shirt == "us_shirt" and u2.pants == "us_pants", "US cai na v2: " .. tostring(u2.shirt))
	assert(not u2.skinArms, "v2 é opaca: braço na cor do uniforme")
	local u3 = Gear.uniform("US", nil, {}, false)
	assert(u3.shirt == nil and u3.pants == nil, "sem molde")
end)

test("uniforme: mangas arregaçadas só com o cosmético us_utility_rolled", function()
	assert(Gear.uniform("US", nil, ALL_V3).shirt == "us_shirt_v3")
	assert(Gear.uniform("US", { uniform = "us_utility_down" }, ALL_V3).shirt == "us_shirt_v3")
	assert(Gear.uniform("US", { uniform = "us_utility_rolled" }, ALL_V3).shirt == "us_shirt_rolled_v3")
	local semRolo = table.clone(ALL_V3)
	semRolo.us_shirt_rolled_v3 = 0
	assert(Gear.uniform("US", { uniform = "us_utility_rolled" }, semRolo).shirt == "us_shirt_v3", "reserva")
end)

test("uniforme VC: cáqui padrão, verde com cosmético, preto da guerrilha; reservas", function()
	local k = Gear.uniform("VC", nil, ALL_V3, false)
	assert(k.variant == "khaki" and k.shirt == "vc_khaki_shirt_v3", "cáqui padrão")
	assert(k.skinTorso and k.skinArms and k.skinLegs, "VC v3: decote, mãos e canelas na pele")
	assert(Gear.uniform("VC", { uniform = "vc_green" }, ALL_V3).shirt == "vc_green_shirt_v3", "verde")
	assert(Gear.uniform("VC", nil, ALL_V3, true).pants == "vc_black_pants_v3", "guerrilha")
	assert(Gear.uniform("VC", { uniform = "vc_black" }, ALL_V3).shirt == "vc_black_shirt_v3", "cosmético preto")
	-- o verde é pago: nunca sai para quem não equipou
	for seed = 1, 50 do
		assert(Gear.uniform("VC", nil, ALL_V3, Gear.isGuerrilla(seed)).variant ~= "green", "verde de graça")
	end
	local semPreto = table.clone(ALL_V3)
	semPreto.vc_black_shirt_v3 = 0
	assert(Gear.uniform("VC", nil, semPreto, true).shirt == "vc_khaki_shirt_v3", "preto cai no cáqui v3")
	local v2 = Gear.uniform("VC", { uniform = "vc_green" }, ONLY_V2)
	assert(v2.shirt == "vc_green_shirt" and not v2.skinLegs, "verde v2")
	assert(Gear.uniform("VC", nil, ONLY_V2, true).shirt == "vc_khaki_shirt", "preto sem v3 cai no cáqui v2")
end)

test("guerrilha: fração dos bots igual a GUERRILLA_SHARE e determinística", function()
	local n = 0
	for seed = 1, 100 do
		if Gear.isGuerrilla(seed) then
			n += 1
		end
		assert(Gear.isGuerrilla(seed) == Gear.isGuerrilla(seed))
	end
	assert(n == math.floor(Gear.GUERRILLA_SHARE * 100 + 0.5), "guerrilheiros em 100 bots: " .. n)
end)

test("todo papel das duas facções tem kit; 5 a MAX_PIECES peças, com e sem extra", function()
	for _, c in combos() do
		local _, pieces = piecesFor(c)
		local tag = c.faction .. "/" .. c.role .. "/" .. tostring(c.extra) .. "/" .. c.body
		assert(#pieces >= 5, tag .. ": só " .. #pieces .. " peças")
		assert(#pieces <= Gear.MAX_PIECES, tag .. ": " .. #pieces .. " peças")
	end
end)

test("peças válidas: tamanho, material, cor, forma, anexo e nomes únicos", function()
	local MAT = { Fabric = true, Leather = true, Metal = true, Wood = true, SmoothPlastic = true }
	local ATT = { UpperTorso = true, LowerTorso = true, Head = true }
	for _, c in combos() do
		local _, pieces = piecesFor(c)
		local names = {}
		for _, p in pieces do
			assert(not names[p.name], "nome repetido " .. p.name)
			names[p.name] = true
			assert(p.size.x > 0.01 and p.size.y > 0.01 and p.size.z > 0.01, p.name .. ": tamanho")
			for _, a in { p.pos.x, p.pos.y, p.pos.z } do
				assert(a == a and math.abs(a) < 10, p.name .. ": posição")
			end
			assert(MAT[p.material], p.name .. ": material " .. p.material)
			assert(ATT[p.attach], p.name .. ": anexo " .. p.attach)
			assert(p.shape == "Block" or p.shape == "Cylinder", p.name .. ": forma")
			assert(#p.color == 3, p.name .. ": cor")
			for _, ch in p.color do
				assert(ch >= 0 and ch <= 255 and ch == math.floor(ch), p.name .. ": cor fora de 0..255")
			end
		end
	end
end)

test("peças aparecem (saem da caixa do corpo/colete) e ficam presas (nada solto longe)", function()
	for _, c in combos() do
		local env, pieces = piecesFor(c)
		for _, p in pieces do
			local ctr, half = anchorBox(env, p.attach)
			local e = Gear.extents(p)
			local lo = v(p.pos.x - e.x - ctr.x, p.pos.y - e.y - ctr.y, p.pos.z - e.z - ctr.z)
			local hi = v(p.pos.x + e.x - ctr.x, p.pos.y + e.y - ctr.y, p.pos.z + e.z - ctr.z)
			local tag = c.faction .. "/" .. c.role .. "/" .. c.body .. " " .. p.name
			-- aparece: algum lado passa da caixa
			local out = hi.x > half.x + 1e-3
				or lo.x < -half.x - 1e-3
				or hi.y > half.y + 1e-3
				or lo.y < -half.y - 1e-3
				or hi.z > half.z + 1e-3
				or lo.z < -half.z - 1e-3
			assert(out, tag .. ": escondida dentro do corpo")
			-- presa: encosta na caixa crescida 0,5 stud (a pá fica sobre a mochila)
			local g = 0.5
			local touches = hi.x > -half.x - g
				and lo.x < half.x + g
				and hi.y > -half.y - g
				and lo.y < half.y + g
				and hi.z > -half.z - g
				and lo.z < half.z + g
			assert(touches, tag .. ": solta, longe do corpo")
			-- não vai longe (a antena do rádio sobe acima da cabeça)
			local reachY = if p.name == "antenna" then 3.8 else 1.2
			assert(hi.x < half.x + 1.2 and lo.x > -half.x - 1.2, tag .. ": longe em x")
			assert(hi.z < half.z + 1.2 and lo.z > -half.z - 1.2, tag .. ": longe em z")
			assert(hi.y < half.y + reachY and lo.y > -half.y - 1.2, tag .. ": longe em y")
		end
	end
end)

test("bolsas, cantis e granadas do cinto não se sobrepõem", function()
	for _, c in combos() do
		local _, pieces = piecesFor(c)
		local belt = {}
		for _, p in pieces do
			if p.group == "belt" then
				table.insert(belt, p)
			end
		end
		for i = 1, #belt do
			for j = i + 1, #belt do
				local a, b = belt[i], belt[j]
				local ea, eb = Gear.extents(a), Gear.extents(b)
				local tol = 0.005
				local overlap = math.abs(a.pos.x - b.pos.x) < ea.x + eb.x - tol
					and math.abs(a.pos.y - b.pos.y) < ea.y + eb.y - tol
					and math.abs(a.pos.z - b.pos.z) < ea.z + eb.z - tol
				assert(not overlap, c.faction .. "/" .. c.role .. "/" .. c.body .. ": " .. a.name .. " x " .. b.name)
			end
		end
	end
end)

test("USMC 1965: 4 porta-carregadores M1961 no fuzileiro, mochila M1941 e pá; sem butt pack", function()
	local items = Gear.items("US", "rifleman", nil)
	local pieces = Gear.layout("US", items, envFor("US", BODIES.bloco, "us_m1_helmet"))
	local pouches, names = 0, {}
	for _, p in pieces do
		names[p.name] = p
		if string.match(p.name, "^pouch_") then
			pouches += 1
			assert(p.pos.z < 0, "porta-carregador na frente")
		end
	end
	assert(pouches == 4, "porta-carregadores: " .. pouches)
	assert(names.haversack and names.etool and names.etool_handle, "mochila M1941 e pá M1943")
	assert(names.canteen_l and names.canteen_r and names.canteen_l.pos.z > 0, "cantis atrás")
	assert(not names.butt_pack, "butt pack é do Exército")
	-- a mochila fica por fora do colete
	local env = envFor("US", BODIES.bloco, "us_m1_helmet")
	local h = names.haversack
	assert(h.pos.z - h.size.z / 2 >= env.shell.z / 2 - 0.05, "mochila dentro do colete")
	-- rádio no lugar da mochila
	local radio = Gear.items("US", "radio_operator", nil)
	assert(table.find(radio, "radio") and not table.find(radio, "haversack"), "operador de rádio")
end)

test("VC: porta-carregador de peito pelo fuzil (SKS 10 células, Tipo 56 3+2), granadas de cabo", function()
	assert(table.find(Gear.items("VC", "rifleman", nil), "sks_rig"), "SKS")
	assert(table.find(Gear.items("VC", "squad_leader", nil), "ak_rig"), "Tipo 56")
	assert(table.find(Gear.items("VC", "machine_gunner", nil), "drum_pouch"), "RPD")
	assert(table.find(Gear.items("VC", "grenadier", nil), "grenades4"), "granadeiro")
	-- arma do papel bate com o kit (Roles.loadout)
	for role, list in Roles.loadout.VC do
		local items = Gear.items("VC", role, nil)
		if list[1] == "type56" then
			assert(table.find(items, "ak_rig"), role .. ": Tipo 56 sem o porta-carregador dele")
		elseif list[1] == "rpd" then
			assert(table.find(items, "drum_pouch"), role .. ": RPD sem bolsa de tambor")
		end
	end
	local pieces = Gear.layout("VC", Gear.items("VC", "rifleman", nil), envFor("VC", BODIES.bloco, nil))
	local heads = 0
	for _, p in pieces do
		if string.match(p.name, "^grenade_%d") then
			heads += 1
		end
	end
	assert(heads == 2, "granadas: " .. heads)
end)

test("extras só com o cosmético: tubo de arroz, toalha, repelente (só com capacete)", function()
	assert(not table.find(Gear.items("VC", "rifleman", nil), "rice_tube"))
	assert(table.find(Gear.items("VC", "rifleman", { extra = "vc_rice_tube" }), "rice_tube"))
	assert(not table.find(Gear.items("US", "rifleman", { extra = "us_none" }), "towel"))
	assert(table.find(Gear.items("US", "rifleman", { extra = "us_towel" }), "towel"))
	local items = Gear.items("US", "rifleman", { extra = "us_repellent_band" })
	local semCapacete = Gear.layout("US", items, envFor("US", BODIES.bloco, nil))
	for _, p in semCapacete do
		assert(p.name ~= "repellent", "repelente sem capacete")
	end
	local comCapacete = Gear.layout("US", items, envFor("US", BODIES.bloco, "us_m1_helmet"))
	local found = false
	for _, p in comCapacete do
		found = found or p.name == "repellent"
	end
	assert(found, "repelente na tira do capacete")
end)

test("capacete/chapéu: cobre a cabeça, aba acima do centro e abaixo do topo, achatamento limitado", function()
	for key, native in NATIVE do
		for bodyName, b in BODIES do
			local f = Gear.headgearFit(key, b.head, native)
			local tag = key .. "/" .. bodyName
			assert(f, tag .. ": sem ajuste")
			assert(f.body.x * Gear.HEADGEAR[key].crown >= b.head.x, tag .. ": copa mais estreita que a cabeça")
			assert(f.body.z >= b.head.z, tag .. ": mais curto que a cabeça")
			assert(f.brimY > 0 and f.brimY < b.head.y / 2, tag .. ": aba fora da testa")
			assert(f.topY > b.head.y / 2, tag .. ": topo dentro da cabeça")
			assert(f.squash >= 0.6 and f.squash <= 1.2, tag .. ": achatamento " .. f.squash)
			-- espaço do modelo x/z trocado com o do corpo (giro de 90°)
			assert(f.size.x == f.body.z and f.size.z == f.body.x, tag .. ": eixos")
			-- D-98: no mínimo o tamanho real do casco, na escala do corpo de 2 m
			local c = Gear.HEADGEAR[key]
			assert(f.body.x * Gear.STUD_M >= c.widthM * K - 1e-6, tag .. ": casco estreito demais")
			assert(f.body.z * Gear.STUD_M >= c.lengthM * K - 1e-6, tag .. ": casco curto demais")
		end
	end
	assert(Gear.headgearFit("nao_existe", BODIES.bloco.head, NATIVE.us_m1_helmet) == nil)
end)

test("colete M1955: mais largo e mais fundo que o tronco, eixos do modelo girados", function()
	for _, b in BODIES do
		local f = Gear.vestFit(b.upper)
		assert(f.body.x > b.upper.x and f.body.z > b.upper.z and f.body.y >= b.upper.y)
		assert(f.size.x == f.body.z and f.size.z == f.body.x)
	end
	assert(math.abs(Gear.ART_YAW) > 1.5 and math.abs(Gear.ART_YAW) < 1.6, "giro de 90° (D-58)")
end)

test("extents: cilindro em pé e caixa girada", function()
	local p = {
		size = v(2, 0.2, 0.2),
		rot = v(0, 0, 90),
		pos = v(0, 0, 0),
	}
	local e = Gear.extents(p)
	assert(math.abs(e.x - 0.1) < 1e-6 and math.abs(e.y - 1) < 1e-6 and math.abs(e.z - 0.1) < 1e-6)
	local q = { size = v(2, 1, 4), rot = v(0, 90, 0), pos = v(0, 0, 0) }
	local eq = Gear.extents(q)
	assert(math.abs(eq.x - 2) < 1e-6 and math.abs(eq.z - 1) < 1e-6)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
