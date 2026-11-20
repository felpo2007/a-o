--!strict
-- Explosões grandes do ataque aéreo (D-198; prompt de jogabilidade, item 17): efeito, dano e empurrão
-- independentes, superfície, variação, detalhe e limites, tremor ajustável, som e as amarras no código.
-- Uso: lune run tests/luau/explosao.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local ExplosaoEfeito = require(S .. "ExplosaoEfeito") :: any
local Explosive = require(S .. "Explosive") :: any
local Corpos = require(S .. "Corpos") :: any
local InputMap = require(S .. "InputMap") :: any

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

test("todo explosivo tem efeito; bomba e tiro naval são os pesados, a bomba a maior", function()
	for id in Explosive.TYPES do
		if not Explosive.TYPES[id].burn then
			assert(ExplosaoEfeito.TIPOS[id], "sem efeito: " .. id)
		end
	end
	assert(ExplosaoEfeito.de("bomb_250lb").classe == "pesada" and ExplosaoEfeito.de("naval_5in").classe == "pesada")
	for id, t in ExplosaoEfeito.TIPOS do
		if id ~= "bomb_250lb" then
			assert(t.escala < ExplosaoEfeito.TIPOS.bomb_250lb.escala, id)
		end
		if t.classe ~= "pesada" then
			assert(t.detritos == nil, id .. ": detritos só nas pesadas")
		end
	end
	assert(ExplosaoEfeito.de("desconhecido").classe == "media", "padrão")
end)

test("efeito, dano e empurrão independentes: a bomba enorme não empurra o mapa todo", function()
	local b = Explosive.TYPES.bomb_250lb
	assert(b.impulsoM and b.impulsoM < b.casualtyM, "empurrão menor que o raio de baixas")
	-- o raio de dano não mudou com o efeito (os números da D-36)
	assert(b.lethalM == 20 and b.casualtyM == 70)
	-- além do raio do empurrão, o estilhaço que matou empurra como bala
	local p1, u1 = Corpos.impulso("explosao", 40, b.impulsoM)
	assert(p1 == Corpos.IMPULSO.bala and u1 == 0, "longe: como bala")
	local p2, u2 = Corpos.impulso("explosao", 5, b.impulsoM)
	assert(p2 > Corpos.IMPULSO.bala and u2 > 0, "perto: o sopro")
	-- sem impulsoM (granada): o de antes, pelo casualtyM
	local g = Explosive.TYPES.grenade_us
	assert(g.impulsoM == nil)
	local p3 = Corpos.impulso("explosao", g.casualtyM * 0.9, g.casualtyM)
	assert(p3 > Corpos.IMPULSO.bala, "granada como antes")
end)

test("superfície: água, estrutura, vegetação e terra", function()
	assert(ExplosaoEfeito.superficie("Water", true) == "agua")
	assert(ExplosaoEfeito.superficie("Plastic", false, "PaddyWater") == "agua", "lâmina do arrozal")
	assert(ExplosaoEfeito.superficie("Wood", false, "Parede") == "estrutura")
	assert(ExplosaoEfeito.superficie("Grass", false, "Folhas_2") == "vegetacao", "folhagem")
	assert(
		ExplosaoEfeito.superficie("LeafyGrass", true) == "vegetacao"
			and ExplosaoEfeito.superficie("Grass", true) == "vegetacao"
	)
	assert(ExplosaoEfeito.superficie("Mud", true) == "terra" and ExplosaoEfeito.superficie("Ground", true) == "terra")
	for _, sup in { "agua", "estrutura", "vegetacao", "terra" } do
		assert(ExplosaoEfeito.CORES[sup], sup)
	end
end)

test("variação discreta: a mesma semente repete, sementes diferentes variam pouco", function()
	local a, b = ExplosaoEfeito.variacao(12345), ExplosaoEfeito.variacao(12345)
	assert(a.lobos == b.lobos and a.giro == b.giro and a.tamanhoK == b.tamanhoK, "repete")
	local lobos, tamanhos = {}, {}
	for seed = 1, 200 do
		local v = ExplosaoEfeito.variacao(seed * 7919)
		assert(v.lobos >= 3 and v.lobos <= 5)
		assert(v.tamanhoK >= 0.88 and v.tamanhoK <= 1.12, "±12%")
		assert(v.tempoK >= 0.85 and v.tempoK <= 1.15, "±15%")
		assert(math.abs(v.inclina) <= 0.12)
		lobos[v.lobos] = true
		tamanhos[string.format("%.2f", v.tamanhoK)] = true
	end
	assert(lobos[3] and lobos[4] and lobos[5], "as três formas aparecem")
	local n = 0
	for _ in tamanhos do
		n += 1
	end
	assert(n > 10, "tamanhos variados")
end)

test("detalhe pela distância e qualidade, com piso; limites ao mesmo tempo", function()
	near(ExplosaoEfeito.detalhe(50, 10), 1, 1e-9, "perto e qualidade alta")
	assert(ExplosaoEfeito.detalhe(500, 10) < 1 and ExplosaoEfeito.detalhe(2000, 10) >= 0.25)
	assert(ExplosaoEfeito.detalhe(50, 1) < ExplosaoEfeito.detalhe(50, 10), "qualidade baixa reduz")
	near(ExplosaoEfeito.detalhe(3000, 1), 0.25, 1e-9, "piso: segue reconhecível")
	local L = ExplosaoEfeito.LIMITES
	assert(L.grandes >= 1 and L.luzes >= 1 and L.detritos >= ExplosaoEfeito.TIPOS.bomb_250lb.detritos)
end)

test("tremor pela distância, vezes o ajuste do jogador (0 desliga)", function()
	local s = ExplosaoEfeito.TIPOS.bomb_250lb.escala
	local perto = ExplosaoEfeito.tremor(10, s, 1)
	local longe = ExplosaoEfeito.tremor(150, s, 1)
	assert(perto > longe and longe > 0, "cai com a distância")
	assert(ExplosaoEfeito.tremor(45 * s + 1, s, 1) == 0, "fora do alcance")
	assert(ExplosaoEfeito.tremor(10, s, 0) == 0, "ajuste 0")
	-- a 80 m (abaixo do teto de 1,5) o ajuste de 50% dá a metade
	near(ExplosaoEfeito.tremor(80, s, 0.5), ExplosaoEfeito.tremor(80, s, 1) * 0.5, 1e-9, "metade")
	assert(perto <= 1.5, "teto")
	assert(InputMap.DEFAULTS.cameraShake == 1, "padrão")
	local v = InputMap.validate({ cameraShake = 3 })
	assert(v.cameraShake <= 1, "validado no limite")
	near(ExplosaoEfeito.atrasoSom(343), 1, 1e-9, "o som pela velocidade do som")
end)

test("imagem, som e configurações ligados", function()
	local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
	local fx = fs.readFile(C .. "ExplosionFx.client.luau")
	for _, t in
		{
			'if ExplosaoEfeito.de(id).classe == "pesada" then',
			"local sup = superficieEm(pos)",
			"ExplosaoEfeito.detalhe(dM, qualidade())",
			"if ativos.luzes < LIM.luzes then",
			"LIM.detritos - ativos.detritos",
			"ExplosaoEfeito.tremor(dM, s, ajusteTremor())",
		}
	do
		assert(string.find(fx, t, 1, true), "ExplosionFx: " .. t)
	end
	assert(not string.find(fx, "local SCALE", 1, true), "a escala saiu do ExplosionFx")
	-- a smoke_main some com cor escura (Studio): fumaça escura só pela textura escura, com cor clara
	assert(string.find(fx, 'escura = "rbxasset://textures/particles/explosion01_smoke_main.dds"', 1, true))
	assert(string.find(fx, "Texture = if agua then TEX.dust else TEX.escura,", 1, true), "coluna da bomba")
	local vd = fs.readFile(C .. "VeiculoDano.client.luau")
	assert(string.find(vd, "w.smoke.Texture = TEX.escura", 1, true), "fumaça do destroço")
	for c in string.gmatch(fx .. vd, "Texture = TEX%.dust,%s*Color = ColorSequence%.new%(Color3%.fromRGB%((%d+)") do
		assert(tonumber(c) >= 100, "smoke_main com cor escura some: " .. c)
	end
	local au = fs.readFile(C .. "AudioController.client.luau")
	assert(string.find(au, 'play("explosion", pos, k * 0.55, 8000 / M, d + 0.22, 0.42, true)', 1, true), "cauda")
	local gm = fs.readFile(C .. "GameMenu.client.luau")
	assert(string.find(gm, 'numberRow("Tremor das explosões", "cameraShake", 0.1, "%d%%", 100)', 1, true))
	local ex = fs.readFile("src/ServerScriptService/Modules/ExplosionService.luau")
	assert(string.find(ex, 'e.model:SetAttribute("VT65GolpeRaioM", t.impulsoM or t.casualtyM)', 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
