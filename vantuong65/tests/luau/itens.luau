--!strict
-- Testes dos itens, das armas na mão e da granada de fumaça (2026-11-13, pedido do dono: "não consigo
-- puxar arma e selecionar os itens", "coloque arma secundária para todos", "copie a granada de fumaça
-- igual ao Front 44 e corrija seus defeitos", recarga automática). Uso: lune run tests/luau/itens.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local S = "../../src/ReplicatedStorage/Shared/"
local Equipar = require(S .. "Equipar") :: any
local InputMap = require(S .. "InputMap") :: any
local ItemAnim = require(S .. "ItemAnim") :: any
local Roles = require(S .. "Roles") :: any
local Smoke = require(S .. "Smoke") :: any
local Weapons = require(S .. "Weapons") :: any
local GrenadeArt = luau.load(fs.readFile("src/ReplicatedStorage/Shared/GrenadeArt.luau"), {
	debugName = "GrenadeArt",
	environment = {
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		Instance = roblox.Instance,
	},
})() :: any

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
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f (tol %.4f)", msg or "", a, b, tol))
end
local M = 0.28

-- ===== arma secundária para todos =====
test("todo papel dos dois lados leva a pistola de época (EUA M1911A1, VC Tipo 54)", function()
	assert(Weapons.get("m1911").name == "M1911A1" and Weapons.get("type54").kind == "pistol")
	for faction, byRole in Roles.loadout do
		local pistol = Equipar.PISTOL[faction]
		for role, list in byRole do
			assert(table.find(list, pistol), faction .. "/" .. role .. ": sem a pistola")
			for _, id in list do
				local wp = Weapons.get(id)
				assert(wp and wp.enabled and wp.faction == faction, faction .. "/" .. role .. ": " .. id)
			end
		end
	end
end)

test("vaga 2 = pistola (tecla 2, Y e ARMA trocam); só pistola: antitanque, tripulante e piloto", function()
	local onlyPistol = { anti_tank = true, tank_crew = true, pilot = true }
	for faction, byRole in Roles.loadout do
		for role, list in byRole do
			local slots = Equipar.weapons(list, role, nil)
			if onlyPistol[role] then
				assert(#list == 1 and list[1] == Equipar.PISTOL[faction], role .. ": a pistola é a arma de mão")
			else
				assert(#slots == 2, faction .. "/" .. role .. ": duas armas")
				assert(Weapons.get(slots[1]).kind ~= "pistol", role .. ": principal longa")
				assert(slots[2] == Equipar.PISTOL[faction], role .. ": pistola na vaga 2")
			end
		end
	end
	-- antitanque: pistola e o lançador; trocar sempre muda de arma (antes o ciclo de uma arma só parava)
	local at = Equipar.weapons(Roles.loadout.US.anti_tank, "anti_tank", nil)
	assert(at[1] == "m1911" and at[2] == "launcher")
	assert(Equipar.cycle(2, 1, 1) == 2 and Equipar.cycle(2, 2, 1) == 1 and Equipar.cycle(2, 1, -1) == 2)
	assert(Equipar.cycle(0, 1, 1) == 0, "sem arma")
	-- arma pega do chão no lugar da principal (como o servidor)
	local picked = Equipar.weapons({ "m14", "m1911" }, "rifleman", "type56")
	assert(picked[1] == "type56" and picked[2] == "m1911")
	assert(Equipar.handId("launcher", "VC") == "rpg2" and Equipar.handId("launcher", "US") == "launcher")
	assert(Equipar.handId("m14", "US") == "m14")
end)

-- ===== teclas =====
test("teclado: 1 a 0 escolhem a vaga, roda do mouse e Y trocam; sem conflito no teclado e no controle", function()
	local keys = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero" }
	for n = 1, 10 do
		local id = Equipar.actionOf(n)
		assert(Equipar.slotOfAction(id) == n, id)
		local found = false
		for _, a in InputMap.ACTIONS do
			if a.id == id then
				found = true
				assert(a.ctx == "infantry" and a.key == keys[n] and a.keyPress == "press", id .. ": tecla")
				assert(Equipar.SLOTS[n].key == keys[n], id .. ": a vaga e a tecla batem")
			elseif a.id == "swap_weapon" then
				assert(a.pad == "ButtonY" and a.padPress == "tap" and a.key == nil, "Y troca (a tecla 1 é a vaga 1)")
			end
		end
		assert(found, id .. " sem ação")
	end
	assert(#InputMap.keyConflicts(InputMap.DEFAULTS) == 0, table.concat(InputMap.keyConflicts(InputMap.DEFAULTS), "; "))
	assert(#InputMap.conflicts(InputMap.DEFAULTS) == 0, table.concat(InputMap.conflicts(InputMap.DEFAULTS), "; "))
	-- caído não troca de arma
	local st = InputMap.newState()
	InputMap.event(st, "downed")
	assert(not InputMap.allowed(st, "slot_2") and not InputMap.allowed(st, "swap_weapon"))
end)

test("recarga automática: opção ligada por padrão e saneada como booleana", function()
	assert(InputMap.DEFAULTS.autoReload == true)
	assert(InputMap.validate({ autoReload = false }).autoReload == false)
	assert(InputMap.validate({ autoReload = "sim" }).autoReload == true, "lixo volta ao padrão")
end)

-- ===== troca (tempos do Front 44) =====
test("troca: guardar = 40% do saque (0,15–0,3 s); pistola 0,3 s, fuzil 0,6 s, metralhadora 1 s", function()
	near(Equipar.drawS("m1911"), 0.3, 1e-9, "pistola")
	near(Equipar.drawS("m14"), 0.6, 1e-9, "M14")
	near(Equipar.drawS("rpd"), 1.0, 1e-9, "RPD")
	near(Equipar.drawS("nao_existe", "pistol"), 0.3, 1e-9, "pelo tipo")
	near(Equipar.holsterS("m1911"), 0.15, 1e-9, "mínimo")
	near(Equipar.holsterS("m60"), 0.3, 1e-9, "máximo")
	near(Equipar.holsterS("m14"), 0.24, 1e-9)
	for id, s in Equipar.DRAW_S do
		assert(s > 0 and s <= 1.0, id)
	end
	-- toda arma das vagas tem tempo de saque próprio
	for _, byRole in Roles.loadout do
		for _, list in byRole do
			for _, id in list do
				assert(Equipar.DRAW_S[id], id .. " sem saque")
			end
		end
	end
end)

test("itens das vagas: granada/fumaça só com estoque, construir e ferramenta pelo papel", function()
	local none = { frags = 0, smokes = 0 }
	local some = { frags = 2, smokes = 1 }
	assert(not Equipar.itemOk("frag", "rifleman", none, false) and Equipar.itemOk("frag", "rifleman", some, false))
	assert(not Equipar.itemOk("smoke", "rifleman", none, false) and Equipar.itemOk("smoke", "rifleman", some, false))
	assert(Equipar.itemOk("build", "engineer", none, true) and not Equipar.itemOk("build", "rifleman", none, false))
	assert(
		Equipar.itemOk("role_tool", "medic", none, false) and not Equipar.itemOk("role_tool", "rifleman", none, false)
	)
	assert(Equipar.itemOk("bandage", "rifleman", none, false) and Equipar.itemOk("shovel", nil, none, false))
	-- a vaga de cada item é a da roda de equipamento (mesmos ids)
	local ids = {}
	for _, s in Equipar.SLOTS do
		ids[s.id] = true
	end
	for _, id in { "bandage", "tourniquet", "frag", "smoke", "build", "binoculars", "shovel", "role_tool" } do
		assert(ids[id], id)
	end
end)

-- ===== granada na mão (gesto do Front 44) =====
local G = Equipar.GRENADE
test("granada: saca em 0,3 s, o pino sai em 0,24 s, arma em 0,3 s, lança ao soltar e acaba em 0,8 s", function()
	local h = Equipar.newHand("frag", 0)
	assert(Equipar.handStep(h, 0.1) == nil and h.phase == "saque")
	Equipar.handStep(h, G.drawS + 0.01)
	assert(h.phase == "pronta", h.phase)
	Equipar.press(h, 1)
	assert(h.phase == "armando")
	assert(Equipar.handStep(h, 1 + 0.1) == nil)
	assert(Equipar.handStep(h, 1 + G.pinS + 0.01) == "pin", "pino")
	Equipar.handStep(h, 1 + G.readyS + 0.01)
	assert(h.phase == "armada", h.phase)
	-- segurando: fica armada
	assert(Equipar.handStep(h, 5) == nil and h.phase == "armada")
	Equipar.release(h, false)
	assert(Equipar.handStep(h, 5.01) == "throw", "pedido ao servidor")
	assert(Equipar.handStep(h, 5.02) == nil, "uma vez só")
	assert(Equipar.handStep(h, 5.01 + G.throwS + 0.01) == "done")
	near(Equipar.throwPower(false), 1, 1e-9)
	near(Equipar.throwPower(true), 0.55, 1e-9, "por baixo (Front 44)")
	near(G.releaseS, 0.4, 1e-9, "sai da mão com o servidor (FieldService.RELEASE_S)")
end)

test("granada: soltar antes de armar lança assim que armar; apertar no saque arma ao chegar", function()
	local h = Equipar.newHand("smoke", 0)
	Equipar.press(h, 0.1) -- ainda no saque
	Equipar.release(h, true) -- e já soltou, mirando (por baixo)
	local events = {}
	local t = 0
	while t < 2 do
		t += 1 / 60
		local ev = Equipar.handStep(h, t)
		if ev then
			table.insert(events, { ev = ev, t = t })
		end
	end
	assert(#events == 3, "pino, lançamento, fim: " .. #events)
	assert(events[1].ev == "pin" and events[2].ev == "throw" and events[3].ev == "done")
	-- o movimento nunca pula: lança só depois de sacar e armar
	assert(events[2].t >= G.drawS + G.readyS - 1e-6, string.format("lançou cedo: %.3f", events[2].t))
	assert(h.under, "por baixo")
	-- soltar sem ter apertado não lança
	local h2 = Equipar.newHand("frag", 0)
	Equipar.release(h2, false)
	assert(Equipar.handStep(h2, 3) == nil and h2.phase == "pronta")
end)

test("granada na mão de 1ª pessoa: gesto em ordem, solta em 0,4 s e acaba em 0,8 s", function()
	local GA = ItemAnim.GRANADA
	for _, keys in { GA.throw, GA.under } do
		assert(keys[1].t == 0 and math.abs(keys[#keys].t - G.throwS) < 1e-9)
		local release = false
		for i = 2, #keys do
			assert(keys[i].t > keys[i - 1].t, "em ordem")
			if math.abs(keys[i].t - G.releaseS) < 1e-9 then
				release = true
			end
		end
		assert(release, "chave da soltura")
		-- começa no braço armado
		for j = 1, 3 do
			near(keys[1].r[j], GA.cock.r[j], 1e-9, "armado")
		end
	end
	-- por cima solta acima do por baixo
	assert(GA.throw[3].r[2] > GA.under[3].r[2])
end)

-- ===== granadas desenhadas (peças do Front 44) =====
test("granadas: M26 9,9 cm, M18 ~14 cm, cabo chinês; pino e alavanca saem na lançada", function()
	local function height(kind: string, faction: string?): number
		local list = GrenadeArt.specs(kind, faction)
		local lo, hi = math.huge, -math.huge
		for _, s in list do
			if not s.pin then
				local half = if s.shape == "cyl" then s.size.X / 2 else s.size.Y / 2
				lo = math.min(lo, s.cf.Position.Y - half)
				hi = math.max(hi, s.cf.Position.Y + half)
			end
		end
		return hi - lo
	end
	near(height("frag", "US"), 9.9, 0.3, "M26")
	near(height("smoke", "US"), 14.0, 0.8, "M18 com a espoleta")
	near(height("frag", "VC"), 25.2, 1.0, "cabo de 16 + cabeça de 9")
	for _, c in { { "frag", "US" }, { "smoke", "US" }, { "frag", "VC" }, { "smoke", "VC" } } do
		local list = GrenadeArt.specs(c[1], c[2])
		local pins, spoon = 0, 0
		for _, s in list do
			if s.pin then
				pins += 1
				assert(string.sub(s.name, 1, 4) == "Pino", s.name .. ": peça do pino sem o nome")
			end
			if s.spoon then
				spoon += 1
			end
		end
		assert(pins >= 3, c[1] .. "/" .. c[2] .. ": pino e argola")
		if c[2] == "US" or c[1] == "smoke" then
			assert(spoon == 1, "alavanca")
		end
	end
end)

-- ===== fumaça (Front 44, defeitos corrigidos) =====
test(
	"fumaça: abre em 1,5 s, cheia no meio, afina nos últimos 4 s e some no fim (antes ficava 12 s a mais)",
	function()
		local D = Smoke.DURATION_S
		assert(Smoke.factor(0, D) == 0, "não estoura de uma vez")
		near(Smoke.factor(0.75, D), 0.5, 1e-9, "meio da abertura")
		near(Smoke.factor(Smoke.GROW_S, D), 1, 1e-9)
		near(Smoke.factor(D / 2, D), 1, 1e-9)
		near(Smoke.factor(D - 2, D), 0.5, 1e-9, "afinando")
		assert(Smoke.factor(D + 0.01, D) == 0 and Smoke.factor(D + 12, D) == 0, "acabou")
		assert(Smoke.factor(-1, D) == 0)
		near(Smoke.FUSE_S, 1.4, 1e-9, "espoleta do Front 44")
		assert(Smoke.TAIL_S > Smoke.THIN_S, "as fontes param antes de a visão afinar")
	end
)

local R = Smoke.RADIUS_M / M
local function absolute(puffs: { any }): { any }
	local out = {}
	for _, p in puffs do
		table.insert(out, { x = p.x, y = p.y, z = p.z, r = p.r })
	end
	return out
end

test("fumaça: 7 sopros (Front 44) cobrem o raio útil; o soldado de 2 m some atrás", function()
	local puffs = Smoke.layout(R, {}, nil)
	assert(#puffs == 7)
	for i = 2, 7 do
		local p = puffs[i]
		near(math.sqrt(p.x * p.x + p.z * p.z) + p.r, R, 1e-6, "o anel chega ao raio")
	end
	local clouds = absolute(puffs)
	local h = Smoke.HEIGHT_M / M
	-- linha de visão a 1,7 m de altura atravessando a nuvem: tapada
	assert(Smoke.blocks(-3 * R, 1.7 / M, 0, 3 * R, 1.7 / M, 0, clouds))
	-- linha que passa 1,3 raio ao lado: livre
	assert(not Smoke.blocks(-3 * R, h, 1.3 * R, 3 * R, h, 1.3 * R, clouds))
	-- linha do joelho (0,5 m) ao pé do outro lado: tapada
	assert(Smoke.blocks(-3 * R, 0.5 / M, 0.5 * R, 3 * R, 0.5 / M, -0.5 * R, clouds))
	-- dentro: véu forte no miolo, nada fora
	assert(Smoke.density(0, h, 0, clouds) > 0.9 and Smoke.density(0, h, 3 * R, clouds) == 0)
end)

test("fumaça: a parede corta o sopro (não tapa a visão do outro lado); teto baixa a nuvem", function()
	-- parede reta a 1,5 m, de frente para +X: os raios de 0°, 60° e 300° batem nela (normal −X)
	local wall = 1.5 / M
	local walls = {}
	for i = 1, Smoke.RING do
		local dx = Smoke.ringDir(i)
		if dx > 0.1 and wall / dx <= R then
			walls[i] = { d = wall / dx, nx = -1, nz = 0 }
		end
	end
	assert(walls[1] and walls[2] and walls[6] and not walls[3], "raios que batem")
	local puffs = Smoke.layout(R, walls, nil)
	-- nenhum sopro do anel passa da parede (nem os de viés); o do meio escorre no máximo 0,35 R
	for i = 2, #puffs do
		assert(puffs[i].x + puffs[i].r <= wall + 1e-6, "o sopro " .. i .. " passa da parede")
	end
	assert(puffs[1].r >= R * 0.35 - 1e-6, "a fumaça escorre pela parede, não some")
	-- do outro lado da parede, uma linha paralela a ela (dentro da "casa"): livre
	local clouds = absolute(puffs)
	local x = wall + 0.8 / M
	assert(not Smoke.blocks(x, 1.5 / M, -2 * R, x, 1.5 / M, 2 * R, clouds), "tapou através da parede")
	-- sem parede, a mesma linha ficava tapada (o defeito antigo, de uma esfera só)
	assert(Smoke.blocks(x, 1.5 / M, -2 * R, x, 1.5 / M, 2 * R, absolute(Smoke.layout(R, {}, nil))))
	-- um raio só já vale para todos os sopros (a parede é um plano)
	for i, p in Smoke.layout(R, { walls[1] }, nil) do
		if i > 1 then
			assert(p.x + p.r <= wall + 1e-6, "plano de um raio só: sopro " .. i)
		end
	end
	-- do lado de cá, a nuvem continua cheia
	assert(Smoke.blocks(-3 * R, 1.5 / M, 0, 0, 1.5 / M, 0, clouds))
	-- teto a 2,4 m: nada passa do teto
	local roof = 2.4 / M
	for _, p in Smoke.layout(R, {}, roof) do
		assert(p.y + p.r <= roof + R * 0.25 + 1e-6, "atravessa o teto")
		assert(p.y <= roof, "acima do teto")
	end
end)

test("fumaça: as nuvens vêm do relógio (o formato antigo de peça com R ainda vale)", function()
	assert(#Smoke.clouds(nil) == 0)
	-- peça solta com "R" (bots e assistência antigos): o tamanho cheio
	local folder = roblox.Instance.new("Folder")
	local p = roblox.Instance.new("Part")
	p.CFrame = roblox.CFrame.new(1, 2, 3)
	p:SetAttribute("R", 10)
	p.Parent = folder
	local list = Smoke.clouds(folder, 0)
	assert(#list == 1 and list[1].r == 10 and list[1].y == 2)
	-- nuvem nova acabada (idade > duração): nenhuma esfera
	local m = roblox.Instance.new("Model")
	m:SetAttribute("T0", 0)
	m:SetAttribute("Dur", Smoke.DURATION_S)
	local c = roblox.Instance.new("Part")
	c.Name = "Centro"
	c.Parent = m
	m.Parent = folder
	assert(#Smoke.clouds(folder, Smoke.DURATION_S + 1) == 1, "só a peça antiga")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
