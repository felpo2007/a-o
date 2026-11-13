--!strict
-- Testes das skins (Lune): catálogo, preços em $ e em Robux, posse e escolha, perfil, moldes de
-- uniforme, a malha da camuflagem de mato e a vantagem contra os bots.
-- Uso: lune run tests/luau/skins.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Skins = require(S .. "Skins") :: any
local Progression = require(S .. "Progression") :: any
local Commerce = require(S .. "Commerce") :: any
local Weapons = require(S .. "Weapons") :: any
local BotBrain = require(S .. "BotBrain") :: any
local AssetIds = require(S .. "AssetIds") :: any
local ProfileSchema = require("../../src/ServerScriptService/Modules/ProfileSchema") :: any
local Gear = require("../../src/ServerScriptService/Modules/Gear") :: any

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

local function near(a: number, b: number, tol: number, msg: string?)
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f", msg or "", a, b))
end

-- Moeda ---------------------------------------------------------------------------------------
test("dinheiro do jogo com $ e milhar com ponto", function()
	assert(Progression.CUR == "$")
	assert(Progression.money(0) == "$ 0", Progression.money(0))
	assert(Progression.money(999) == "$ 999")
	assert(Progression.money(1250) == "$ 1.250", Progression.money(1250))
	assert(Progression.money(1234567) == "$ 1.234.567", Progression.money(1234567))
	assert(Progression.money(30000) == "$ 30.000")
	assert(Progression.money(-50) == "-$ 50", Progression.money(-50))
	assert(Progression.money(12.6) == "$ 13")
	local _, why = Progression.canBuyGear("us_vest", "US", 5, {}, {}, 100)
	assert(why == "faltam $ 800", tostring(why))
end)

-- Catálogo ------------------------------------------------------------------------------------
test("catálogo: ids únicos, tipos, lados, armas de verdade e chaves de Robux", function()
	local seen = {}
	local kinds = { weapon = 0, uniform = 0, camo = 0 }
	for _, s in Skins.CATALOG do
		assert(not seen[s.id], "id repetido " .. s.id)
		seen[s.id] = true
		assert(kinds[s.kind] ~= nil, s.id .. ": tipo " .. tostring(s.kind))
		kinds[s.kind] += 1
		assert(s.side == "US" or s.side == "VC" or s.side == "both", s.id)
		assert(#s.name > 0 and #s.desc > 0, s.id .. ": nome e descrição")
		assert(Skins.get(s.id) == s)
		assert(Skins.IDS[s.robuxKey] ~= nil, s.id .. ": chave fora de Skins.IDS")
		assert(type(Skins.IDS[s.robuxKey]) == "number")
		assert(#s.swatch > 0, s.id .. ": sem cores de prévia")
		if s.kind == "weapon" then
			local wp = Weapons.get(s.weapon)
			assert(wp, s.id .. ": arma " .. tostring(s.weapon))
			assert(wp.faction == s.side, s.id .. ": skin do lado errado da arma")
			assert(s.finish and (s.finish.wood or s.finish.metal or s.finish.handguard), s.id .. ": sem acabamento")
			assert(s.robuxKind == "product", s.id .. ": arma em Robux é Developer Product")
		else
			assert(s.robuxKind == "pass", s.id .. ": uniforme e camuflagem são Game Pass")
		end
		if s.kind == "uniform" then
			assert(s.gearUniform or (s.shirt and s.pants), s.id .. ": sem molde")
			for _, key in { s.shirt, s.pants } do
				assert(AssetIds.Clothing[key] ~= nil, s.id .. ": chave " .. key .. " fora de AssetIds.Clothing")
				assert(string.sub(key, -3) == "_v3", key .. ": molde com mãos de pele termina em _v3")
			end
		end
		if s.kind == "camo" then
			assert(s.side == "both", s.id)
			assert(BotBrain.CAMO.fit[s.camo], s.id .. ": tipo de camuflagem " .. tostring(s.camo))
			assert(AssetIds.Images[s.texture] ~= nil, s.id .. ": textura fora de AssetIds.Images")
		end
	end
	assert(kinds.weapon >= 9 and kinds.uniform >= 4 and kinds.camo == 3)
	assert(AssetIds.Accessories.ghillie ~= nil, "malha da camuflagem em AssetIds.Accessories")
	-- toda chave de Robux tem uma skin (nada sobra para o dono criar à toa)
	local used = {}
	for _, s in Skins.CATALOG do
		assert(not used[s.robuxKey], "chave repetida " .. s.robuxKey)
		used[s.robuxKey] = true
	end
	for key in Skins.IDS do
		assert(used[key], "chave sem skin: " .. key)
	end
end)

test("realismo de 1965: os acabamentos e uniformes pedidos, sem duplicar o Commerce", function()
	local names = {}
	for _, s in Skins.CATALOG do
		table.insert(names, string.lower(s.name .. " " .. s.desc))
	end
	local all = table.concat(names, " | ")
	for _, word in { "bétula", "nogueira", "azul", "gast", "verde-oliva", "fita" } do
		assert(string.find(all, word, 1, true), "falta o acabamento: " .. word)
	end
	for _, id in { "skin_us_faded", "skin_us_tiger", "skin_us_duck", "skin_vc_black" } do
		assert(Skins.get(id) and Skins.get(id).kind == "uniform", id)
	end
	for _, kind in { "rice", "jungle", "bamboo" } do
		local found = false
		for _, s in Skins.list("camo") do
			found = found or s.camo == kind
		end
		assert(found, "camuflagem " .. kind)
	end
	-- o cáqui, o verde e o OG-107 (padrão e arregaçado) já estão no Commerce
	for _, s in Skins.list("uniform") do
		assert(not Commerce.find(s.gearUniform or ""), s.id .. ": duplica um uniforme do Commerce")
		for _, c in Commerce.Cosmetics do
			assert(c.name ~= s.name, s.id .. ": mesmo nome de " .. c.id)
		end
	end
	-- e cada arma tem pelo menos uma skin. Fora da conta: os fuzis de precisão do Blender
	-- (2026-11-12, M70 Unertl e Mosin PU), ainda sem acabamento escolhido pelo dono nem Developer
	-- Product criado; a loja (Progresso.client) só lista arma que tem skin, então eles não aparecem lá.
	-- D-108: a espingarda Winchester 12 também (modelo da frente de Blender ainda a subir).
	local SEM_SKIN = { m70 = true, mosin = true, win12 = true }
	for _, wp in Weapons.list do
		if SEM_SKIN[wp.id] then
			continue
		end
		local n = 0
		for _, s in Skins.list("weapon", wp.faction) do
			if s.weapon == wp.id then
				n += 1
			end
		end
		assert(n >= 1, wp.id .. " sem skin")
	end
end)

-- Preços --------------------------------------------------------------------------------------
test("preço: dezenas de partidas em $, camuflagem a mais cara, Robux barato e proporcional", function()
	local maxWeapon, minUniform, maxUniform, minCamo = 0, math.huge, 0, math.huge
	local ratios = {}
	for _, s in Skins.CATALOG do
		local t = Skins.TIERS[s.tier]
		assert(t, s.id .. ": nível " .. tostring(s.tier))
		assert(s.price == t.matches * Skins.MONEY_PER_MATCH, s.id)
		assert(s.price >= 20 * Skins.MONEY_PER_MATCH, s.id .. ": menos de 20 partidas")
		assert(s.robux == t.robux and s.robux <= 200, s.id .. ": Robux caro demais")
		table.insert(ratios, s.robux / t.matches)
		if s.kind == "weapon" then
			maxWeapon = math.max(maxWeapon, s.price)
		elseif s.kind == "uniform" then
			minUniform, maxUniform = math.min(minUniform, s.price), math.max(maxUniform, s.price)
		else
			minCamo = math.min(minCamo, s.price)
		end
	end
	assert(maxWeapon < minUniform and maxUniform < minCamo, "camuflagem > uniforme > arma")
	local mean = 0
	for _, r in ratios do
		mean += r / #ratios
	end
	for _, r in ratios do
		near(r, mean, mean * 0.1, "R$ por partida igual em todos os níveis")
	end
	-- a skin de arma mais barata pede dezenas de partidas, a camuflagem 100
	assert(Skins.tierPrice("weapon") == 7500 and Skins.tierPrice("camo") == 30000)
	assert(Progression.money(Skins.tierPrice("camo")) == "$ 30.000")
end)

test("Robux: ID 0 esconde; produto e passe acham a skin pelo ID", function()
	local m14 = Skins.get("skin_m14_birch")
	-- os itens já existem no Roblox (IDs reais em Skins.IDS): o teste zera e põe IDs de mentira
	local oldP, oldC = Skins.IDS.PRODUCT_SKIN_M14_BIRCH, Skins.IDS.PASS_CAMO_RICE
	Skins.IDS.PRODUCT_SKIN_M14_BIRCH = 0
	local hidden = Skins.robuxId(m14) == 0 and Skins.skinByProductId(0) == nil and Skins.skinByPassId(0) == nil
	Skins.IDS.PRODUCT_SKIN_M14_BIRCH = oldP
	assert(hidden, "ID 0 esconde o botão de Robux")
	Skins.IDS.PRODUCT_SKIN_M14_BIRCH = 123456
	Skins.IDS.PASS_CAMO_RICE = 654321
	local ok, err = pcall(function()
		assert(Skins.skinByProductId(123456) == "skin_m14_birch")
		assert(Skins.skinByPassId(123456) == nil, "produto não é passe")
		assert(Skins.skinByPassId(654321) == "camo_rice")
		assert(Skins.passKeyById(654321) == "PASS_CAMO_RICE")
		assert(Skins.skinByProductId(654321) == nil, "passe não é produto")
		assert(table.find(Skins.passKeys(), "PASS_CAMO_RICE"))
		assert(not table.find(Skins.passKeys(), "PRODUCT_SKIN_M14_BIRCH"))
		-- o produto de skin nunca cai no catálogo do Commerce (o recibo dele não é tip nem respawn)
		assert(Commerce.productKeyById(123456) == nil)
	end)
	Skins.IDS.PRODUCT_SKIN_M14_BIRCH, Skins.IDS.PASS_CAMO_RICE = oldP, oldC
	assert(ok, err)
end)

-- Posse e escolha -----------------------------------------------------------------------------
test("compra com $: falta dinheiro, já é sua, pode comprar", function()
	local ok, why = Skins.canBuy("skin_m14_birch", {}, {}, 1000)
	assert(not ok and why == "faltam $ 6.500", tostring(why))
	ok, why = Skins.canBuy("skin_m14_birch", { skin_m14_birch = true }, {}, 99999)
	assert(not ok and why == "já é sua")
	ok, why = Skins.canBuy("camo_jungle", {}, { PASS_CAMO_JUNGLE = true }, 99999)
	assert(not ok and why == "já é sua", "passe conta como posse")
	assert(Skins.canBuy("skin_m14_birch", {}, {}, 7500))
	assert(not Skins.canBuy("nao_existe", {}, {}, 1e9))
end)

test("equipar: posse, lado e encaixe; o que vale de fato", function()
	local owned = { skin_m14_birch = true, skin_sks_walnut = true }
	local passes = { PASS_CAMO_RICE = true }
	assert(Skins.canEquip("skin_m14_birch", "US", owned, passes))
	local ok, why = Skins.canEquip("skin_m14_birch", "VC", owned, passes)
	assert(not ok and why == "skin do outro lado")
	ok, why = Skins.canEquip("skin_m14_worn", "US", owned, passes)
	assert(not ok and why == "skin não é sua")
	ok, why = Skins.canEquip("camo_rice", nil, owned, passes)
	assert(not ok and why == "escolha um lado primeiro")
	assert(Skins.canEquip("camo_rice", "VC", owned, passes) and Skins.canEquip("camo_rice", "US", owned, passes))
	assert(Skins.factionFor(Skins.get("camo_rice"), "VC") == "VC")
	assert(Skins.factionFor(Skins.get("skin_m14_birch"), "VC") == "US", "skin de um lado só vale no lado dela")
	assert(Skins.slotOf(Skins.get("skin_m14_birch")) == "m14" and Skins.slotOf(Skins.get("camo_rice")) == "camo")
	-- escolha gravada com lixo, outro encaixe e passe perdido: só o válido passa
	local on = { m14 = "skin_m14_birch", sks = "skin_sks_walnut", uniform = "skin_m14_birch", camo = "camo_jungle" }
	local eq = Skins.equipped(on, "US", owned, passes)
	assert(eq.m14 == "skin_m14_birch" and eq.sks == nil and eq.uniform == nil and eq.camo == nil)
	eq = Skins.equipped({ camo = "camo_rice" }, "US", owned, {})
	assert(eq.camo == nil, "passe reembolsado: não veste")
end)

test("skins de arma num texto (atributo WeaponSkins) ida e volta", function()
	local text = Skins.encodeWeapons({ m14 = "skin_m14_birch", m60 = "skin_m60_od", camo = "camo_rice" })
	assert(text == "m14=skin_m14_birch;m60=skin_m60_od", text)
	local back = Skins.decodeWeapons(text)
	assert(back.m14 == "skin_m14_birch" and back.m60 == "skin_m60_od")
	assert(Skins.weaponSkinFrom(text, "m60") == "skin_m60_od" and Skins.weaponSkinFrom(text, "sks") == nil)
	assert(Skins.weaponSkinFrom(nil, "m14") == nil and Skins.weaponSkinFrom(42, "m14") == nil)
	-- texto adulterado: skin no encaixe errado é ignorada
	assert(Skins.decodeWeapons("sks=skin_m14_birch").sks == nil)
end)

test("pintura: peças com nome (arte nova e provisória) e o guarda-mão segue a madeira", function()
	assert(Skins.partClass("Madeira0_0") == "wood" and Skins.partClass("GuardaMao") == "handguard")
	assert(Skins.partClass("Metal_1") == "metal" and Skins.partClass("Receiver") == "metal")
	assert(Skins.partClass("Stock") == "wood" and Skins.partClass("Handguard") == "handguard")
	assert(Skins.partClass("m14_studs_parker") == nil, "malha inteira sem máscara: não pinta")
	local birch = Skins.get("skin_m14_birch")
	local rgb = Skins.paintFor(birch, "handguard")
	assert(rgb == birch.finish.wood, "guarda-mão sem cor própria segue a madeira")
	assert(Skins.paintFor(birch, "metal") == nil, "bétula não mexe no aço")
	local tape = Skins.get("skin_m14_tape")
	local trgb, mat = Skins.paintFor(tape, "handguard")
	assert(trgb == tape.finish.handguard and mat == "Fabric")
	assert(Skins.paintFor(nil, "wood") == nil)
end)

test("lista por tipo e lado: o de ambos entra nos dois", function()
	for _, s in Skins.list("weapon", "US") do
		assert(s.side == "US" and s.kind == "weapon")
	end
	assert(#Skins.list("camo", "US") == 3 and #Skins.list("camo", "VC") == 3)
	assert(#Skins.list("uniform", "VC") == 1 and Skins.list("uniform", "VC")[1].id == "skin_vc_black")
end)

-- Perfil --------------------------------------------------------------------------------------
test("perfil: perfil sem skins migra vazio; lixo é saneado", function()
	local p = ProfileSchema.migrate({ schema = 3, xp = 10, credits = 50 })
	assert(next(p.skins.owned) == nil and next(p.skins.on.US) == nil and next(p.skins.on.VC) == nil)
	assert(p.credits == 50)
	p = ProfileSchema.migrate({
		skins = {
			owned = { skin_m14_birch = true, skin_antiga = true, [5] = true, ruim = "sim" },
			on = {
				US = { m14 = "skin_m14_birch", sks = "skin_sks_walnut", uniform = "skin_vc_black", camo = "camo_rice" },
				VC = { m14 = "skin_m14_birch", camo = "camo_bamboo" },
				XX = { camo = "camo_rice" },
			},
		},
	})
	-- posse: guarda até skin que saiu do catálogo (foi paga); recusa o que não é id
	assert(p.skins.owned.skin_m14_birch and p.skins.owned.skin_antiga)
	assert(p.skins.owned.ruim == nil and p.skins.owned[5 :: any] == nil)
	-- escolha: só skin conhecida, do lado e no encaixe dela
	assert(p.skins.on.US.m14 == "skin_m14_birch" and p.skins.on.US.camo == "camo_rice")
	assert(p.skins.on.US.sks == nil and p.skins.on.US.uniform == nil)
	assert(p.skins.on.VC.m14 == nil and p.skins.on.VC.camo == "camo_bamboo")
	assert(p.skins.on.XX == nil)
	assert(ProfileSchema.migrate({ skins = "lixo" }).skins.on.US ~= nil)
end)

test("perfil: posse é união entre servidores; a escolha é a da sessão", function()
	local stored = ProfileSchema.migrate({ skins = { owned = { camo_rice = true } }, credits = 100000 })
	local base = { xp = 0, credits = 100000, respawnCredits = 0 }
	local mem = ProfileSchema.migrate({
		credits = 92500,
		skins = { owned = { skin_m14_birch = true }, on = { US = { m14 = "skin_m14_birch" } } },
	})
	local rec = table.clone(stored)
	local wrote = ProfileSchema.applySession(rec, stored, mem, base)
	assert(wrote.credits == 92500, "a compra de $ 7.500 desconta pelo delta")
	assert(rec.skins.owned.camo_rice and rec.skins.owned.skin_m14_birch, "união")
	assert(rec.skins.on.US.m14 == "skin_m14_birch")
	assert(rec.skins ~= mem.skins and rec.skins.owned ~= mem.skins.owned, "não divide tabela com a memória")
	-- recibo gravado direto no DataStore entra na memória pela união
	local m2 = ProfileSchema.migrate({})
	ProfileSchema.mergeSkins(m2.skins, rec.skins)
	assert(m2.skins.owned.camo_rice and m2.skins.owned.skin_m14_birch)
	-- recibo idempotente: o mesmo PurchaseId não entrega duas vezes
	local p = ProfileSchema.migrate({})
	assert(ProfileSchema.applyReceipt(p, "abc", 1, function(x)
		x.skins.owned.skin_sks_worn = true
	end))
	assert(not ProfileSchema.applyReceipt(p, "abc", 2, function(_x)
		error("entregou duas vezes")
	end))
	assert(p.skins.owned.skin_sks_worn)
end)

-- Uniforme ------------------------------------------------------------------------------------
test("uniforme da skin: molde próprio primeiro, reserva no molde normal, cor do corpo", function()
	local s = Skins.get("skin_us_tiger")
	local skin = { id = s.id, shirt = s.shirt, pants = s.pants, rgb = s.rgb }
	local ids = { us_shirt_v3 = 1, us_pants_v3 = 2, us_tiger_shirt_v3 = 3, us_tiger_pants_v3 = 4 }
	local u = Gear.uniform("US", nil, ids, false, skin)
	assert(u.shirt == "us_tiger_shirt_v3" and u.pants == "us_tiger_pants_v3" and u.variant == "skin_us_tiger")
	assert(u.skinArms and not u.skinLegs, "mãos de pele como na v3")
	assert(u.shirtRgb == s.rgb.shirt)
	local semSkin = Gear.uniform("US", nil, { us_shirt_v3 = 1, us_pants_v3 = 2 }, false, skin)
	assert(semSkin.shirt == "us_shirt_v3", "molde da skin não publicado: cai no normal")
	local padrao = Gear.uniform("US", nil, ids, false)
	assert(padrao.shirt == "us_shirt_v3" and padrao.shirtRgb == Gear.COLORS.US.shirt)
	-- pijama preto: a variante que o Gear já veste (molde publicado)
	local black = Skins.get("skin_vc_black")
	local v = Gear.uniform("VC", { uniform = black.gearUniform }, AssetIds.Clothing, false)
	assert(v.variant == "black" and v.shirt == "vc_black_shirt_v3")
end)

-- Camuflagem de mato --------------------------------------------------------------------------
test("malha da camuflagem: partes R15, até 3 mil triângulos, pouco na cabeça e nos braços", function()
	local G = Skins.GHILLIE
	local R15 = {
		Head = true,
		UpperTorso = true,
		LowerTorso = true,
		LeftUpperArm = true,
		LeftLowerArm = true,
		RightUpperArm = true,
		RightLowerArm = true,
		LeftUpperLeg = true,
		LeftLowerLeg = true,
		RightUpperLeg = true,
		RightLowerLeg = true,
	}
	local total, n = 0, 0
	for name, pc in G.parts do
		assert(R15[name], "parte desconhecida " .. name)
		local ref = G.ref[name]
		assert(ref and #ref == 3 and #pc.size == 3 and #pc.offset == 3, name)
		for i = 1, 3 do
			assert(pc.size[i] > 0 and ref[i] > 0, name)
		end
		total += pc.tris
		n += 1
	end
	assert(n == 11, "11 peças (cabeça, tronco, braços e pernas)")
	assert(total == G.tris and total > 0 and total <= 3000, "triângulos: " .. total)
	local arms = G.parts.LeftUpperArm.tris
		+ G.parts.RightUpperArm.tris
		+ G.parts.LeftLowerArm.tris
		+ G.parts.RightLowerArm.tris
	assert(G.parts.Head.tris <= 0.05 * total, "cabeça leve")
	assert(arms <= 0.15 * total, "braços leves")
	-- nada na frente do rosto: a caixa da cabeça não passa da face da frente (−z)
	local h = G.parts.Head
	assert(h.offset[3] - h.size[3] / 2 > -G.ref.Head[3] / 2, "folha na frente do rosto")
	assert(Skins.GHILLIE_TRANSPARENCY > 0, "recorte pelo alfa pede Transparency > 0")
end)

test("vantagem: bots veem o camuflado de mais perto só na vegetação do tipo", function()
	local D = BotBrain.DIFFICULTY.medium
	local C = BotBrain.CAMO
	-- sem camuflagem: o de sempre
	assert(BotBrain.spotFactor(D, "stand", false) == 1)
	assert(BotBrain.spotFactor(D, "stand", false, nil, "rice") == 1)
	-- arrozal no arrozal: ~60%; deitado, menos ainda (e menos que o deitado sem camuflagem)
	near(BotBrain.spotFactor(D, "stand", false, "rice", "rice"), C.match, 1e-9, "em pé no arrozal")
	local proneCamo = BotBrain.spotFactor(D, "prone", false, "rice", "rice")
	near(proneCamo, D.spotStance.prone * C.match * C.prone, 1e-9, "deitado no arrozal")
	assert(proneCamo < BotBrain.spotFactor(D, "prone", false) * C.match)
	-- vegetação errada: nada; parecida: metade
	assert(BotBrain.spotFactor(D, "stand", false, "rice", "jungle") == 1)
	assert(BotBrain.spotFactor(D, "stand", false, "jungle", "open") == 1)
	local half = BotBrain.camoFactor("bamboo", "jungle", "stand")
	assert(half > C.match and half < 1)
	-- alvo já seguido não some
	assert(BotBrain.spotFactor(D, "prone", true, "jungle", "jungle") == 1)
	-- PLACEHOLDER pedido: ~60%
	near(C.match, 0.6, 0.05, "fração da distância")
end)

test("vegetação do lugar: arrozal, bambu, mata, capim e aberto", function()
	local function n(j: number, b: number, g: number, r: number)
		return { jungle = j, bamboo = b, grass = g, rice = r }
	end
	assert(BotBrain.vegetation("paddy", n(5, 0, 0, 0)) == "rice", "lâmina d'água é arrozal")
	assert(BotBrain.vegetation("ground", n(0, 0, 0, 1)) == "rice", "canteiro de arroz")
	assert(BotBrain.vegetation("ground", n(2, 3, 0, 0)) == "bamboo")
	assert(BotBrain.vegetation("ground", n(8, 2, 0, 0)) == "jungle", "bambu solto na mata é mata")
	assert(BotBrain.vegetation("ground", n(0, 0, 3, 0)) == "grass")
	assert(BotBrain.vegetation("ground", n(1, 1, 1, 0)) == "open")
	assert(BotBrain.plantKind("ph_island_tree_01") == "jungle" and BotBrain.plantKind("bamboo_clump") == "bamboo")
	assert(BotBrain.plantKind("elephant_grass") == "grass" and BotBrain.plantKind("hut_thatch") == nil)
end)

test("balanço ao vento: pequeno, cresce com o vento e tem limite", function()
	local function amp(wind: number): number
		local m = 0
		for i = 0, 400 do
			local ax, az = Skins.swayAngles(i * 0.05, 0.3, wind)
			m = math.max(m, math.abs(ax), math.abs(az))
		end
		return m
	end
	local calm, gale = amp(0), amp(1000)
	assert(calm > 0 and calm < math.rad(1.5), "parado: quase nada")
	assert(gale > calm and gale <= math.rad(Skins.SWAY.baseDeg + Skins.SWAY.windDeg) + 1e-9, "teto")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
