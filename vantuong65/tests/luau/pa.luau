--!strict
-- Pá: uma pazada por acionamento e o buraco que cresce (D-195; prompt de jogabilidade, item 13):
-- cadência sem fila, a grade 4 x 4 (buraco, borda irregular, monte), a coluna de voxels que desce e
-- sobe, a histerese do gatilho analógico e as amarras no código. Uso: lune run tests/luau/pa.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local FieldWork = require(S .. "FieldWork") :: any
local ItemAnim = require(S .. "ItemAnim") :: any
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
local D = FieldWork.DIG

test("cadência: uma pazada por 1,4 s (folga de rede 0,3), sem fila no servidor", function()
	assert(FieldWork.podePazada(nil, 10), "a primeira")
	assert(not FieldWork.podePazada(10, 10.5), "no meio da pazada não")
	assert(not FieldWork.podePazada(10, 10 + D.pazadaS - D.folgaS - 0.01), "antes da folga não")
	assert(FieldWork.podePazada(10, 10 + D.pazadaS - D.folgaS + 1e-9), "com a folga da rede")
	-- 20 apertos em 2 s viram no máximo 2 pazadas
	local last, n = nil, 0
	for i = 0, 19 do
		local now = i * 0.1
		if FieldWork.podePazada(last, now) then
			last, n = now, n + 1
		end
	end
	assert(n == 2, "apertos rápidos: " .. n)
	-- o buraco inteiro leva as 6 pazadas (~8 s, como antes)
	near(D.pazadas * D.pazadaS, 8.4, 1e-9)
	near(D.pazadaS, ItemAnim.PA.periodo, 1e-9, "a pazada é a da animação e do som")
end)

test("grade 4 x 4: o buraco no meio, o monte do lado de quem cavou, borda no resto", function()
	local cont = { buraco = 0, monte = 0, borda = 0 }
	for ix = 1, 4 do
		for iz = 1, 4 do
			local t = FieldWork.coluna(ix, iz, 1, 0)
			cont[t] += 1
		end
	end
	assert(cont.buraco == 4 and cont.monte == 4 and cont.borda == 8, "contagem")
	assert(FieldWork.coluna(4, 1, 1, 0) == "monte" and FieldWork.coluna(1, 2, -1, 0) == "monte")
	assert(FieldWork.coluna(2, 4, 0, 1) == "monte" and FieldWork.coluna(3, 1, 0, -1) == "monte")
	assert(FieldWork.coluna(2, 3, 0, 1) == "buraco")
end)

test("progressão: o buraco desce por igual, a borda afunda no começo, o monte cresce", function()
	local fundo, folga = 1.8, 0.6
	local antes = 0
	for k = 1, D.pazadas do
		local h = FieldWork.alturaColuna("buraco", k, D.pazadas, fundo, 0.5, folga)
		assert(h < antes, "desce a cada pazada")
		antes = h
	end
	near(antes, -fundo, 1e-9, "no fim, o fundo inteiro")
	-- 1ª pazada: a folga da suavização (0,6 m) e mais um sexto (0,2 m): ~0,24 m visto no Studio
	near(FieldWork.alturaColuna("buraco", 1, 6, fundo, 0, folga), -0.8, 1e-9)
	assert(FieldWork.alturaColuna("buraco", 0, 6, fundo, 0, folga) == 0, "nada antes da 1ª")
	near(FieldWork.alturaColuna("buraco", 1, 6, fundo, 0), -0.3, 1e-9, "sem folga")
	assert(FieldWork.alturaColuna("borda", 1, 6, fundo, 1) < 0, "borda desce na 1ª")
	near(FieldWork.alturaColuna("borda", 2, 6, fundo, 1), -D.bordaM, 1e-9, "borda inteira na 2ª")
	near(FieldWork.alturaColuna("borda", 6, 6, fundo, 1), -D.bordaM, 1e-9, "e para")
	near(FieldWork.alturaColuna("monte", 6, 6, fundo, 1), D.monteM, 1e-9, "monte no fim")
	assert(FieldWork.alturaColuna("monte", 0, 6, fundo, 1) == 0, "nada antes da 1ª")
	-- bordas irregulares, mas iguais a cada pazada (a mesma coluna dá o mesmo número)
	local vistos = {}
	for ix = 1, 4 do
		for iz = 1, 4 do
			local j = FieldWork.jitter(-160, -2064, ix, iz)
			assert(j >= 0 and j <= 1)
			assert(j == FieldWork.jitter(-160, -2064, ix, iz), "fixo")
			vistos[string.format("%.3f", j)] = true
		end
	end
	local n = 0
	for _ in vistos do
		n += 1
	end
	assert(n >= 10, "as colunas variam: " .. n)
end)

test("coluna de voxels: desce sem buraco no meio, a terra mexida no lugar do capim; sobe por cima", function()
	local V = 4
	-- 4 voxels de 4 studs a partir de y0 = 0: cheio, cheio, meio (topo em 10), ar
	local mats = { "Rock", "Ground", "Grass", "Air" }
	local occs = { 1, 1, 0.5, 0 }
	near(FieldWork.topoColuna(occs, 0, V), 10, 1e-9, "topo")
	local troca = { Grass = true, LeafyGrass = true }
	-- desce para 5: o 3º vira ar, o 2º fica com 1/4 e a terra mexida
	local nm, no = FieldWork.colunaVoxels(mats, occs, 0, V, 5, "Ground", "Air", troca)
	assert(nm[3] == "Air" and no[3] == 0 and nm[4] == "Air", "acima vira ar")
	near(no[2], 0.25, 1e-9, "fundo proporcional")
	assert(nm[1] == "Rock" and no[1] == 1, "embaixo não mexe")
	near(FieldWork.topoColuna(no, 0, V), 5, 1e-9, "topo novo")
	-- só baixa o topo do capim: a terra aparece
	local m2, o2 = FieldWork.colunaVoxels(mats, occs, 0, V, 9, "Ground", "Air", troca)
	assert(m2[3] == "Ground", "capim vira terra")
	near(o2[3], 0.25, 1e-9)
	-- sobe para 13: o 3º enche e o 4º fica com 1/4 de terra
	local m3, o3 = FieldWork.colunaVoxels(mats, occs, 0, V, 13, "Ground", "Air", troca)
	assert(o3[3] == 1 and m3[3] == "Ground", "o voxel do topo enche")
	near(o3[4], 0.25, 1e-9)
	assert(m3[4] == "Ground" and m3[1] == "Rock", "terra solta por cima")
	near(FieldWork.topoColuna(o3, 0, V), 13, 1e-9, "topo do monte")
	-- o original não muda (cada pazada parte do terreno de antes)
	assert(mats[3] == "Grass" and occs[3] == 0.5)
	-- a mesma pazada duas vezes dá o mesmo chão (vários jogadores no mesmo buraco)
	local a1, b1 = FieldWork.colunaVoxels(mats, occs, 0, V, 5, "Ground", "Air", troca)
	for y = 1, 4 do
		assert(a1[y] == nm[y] and b1[y] == no[y], "determinístico")
	end
end)

test("animação: a pá segurada sobe ao pronto, faz uma pazada e para no pronto", function()
	local P = ItemAnim.PA
	near(ItemAnim.paTime(0.3, nil), 0.3, 1e-9, "subindo")
	near(ItemAnim.paTime(5, nil), P.t0, 1e-9, "parada no pronto")
	near(ItemAnim.paTime(5, 0.35), P.t0 + 0.35, 1e-9, "a lâmina crava")
	near(ItemAnim.paTime(5, P.periodo + 0.1), P.t0, 1e-9, "acabou a pazada")
	assert(ItemAnim.ANIMS.shovel.held, "segurada")
	local get = function(k: string): any
		return ({ VT65Item = "shovel", VT65ItemT = 10 } :: any)[k]
	end
	local n, t, Dd = ItemAnim.current(get, 500)
	assert(n == "shovel" and t == 490 and Dd == nil, "na mão até guardar")
	near(ItemAnim.itemTime("shovel", ItemAnim.ANIMS.shovel, 490, nil, 0.65), P.t0 + 0.65, 1e-9, "alavanca")
	near(D.contatoS, 0.35, 1e-9, "a terra sai quando a lâmina crava (chave e som)")
end)

test("gatilho analógico: aperta acima do limiar e só solta abaixo dele menos a folga", function()
	local th = 0.15
	assert(not InputMap.triggerDown(false, 0.15, th) and InputMap.triggerDown(false, 0.16, th), "aperta")
	assert(InputMap.triggerDown(true, 0.1, th), "tremida perto do limiar segue apertado")
	assert(not InputMap.triggerDown(true, th - InputMap.TRIGGER_HYS, th), "solta abaixo da folga")
	-- o dedo parado tremendo em volta do limiar: um aperto só
	local was, presses = false, 0
	for i = 0, 40 do
		local z = 0.15 + 0.03 * math.sin(i)
		local d = InputMap.triggerDown(was, z, th)
		if d and not was then
			presses += 1
		end
		was = d
	end
	assert(presses == 1, "apertos com a tremida: " .. presses)
end)

test("servidor: pá na mão, pazada validada no contato, obra pelo terreno de antes e restauração", function()
	local fw = fs.readFile("src/ServerScriptService/Modules/FieldWorkService.luau")
	for _, t in
		{
			'if not (char and hum and root) or char:GetAttribute("VT65Item") ~= "shovel" then',
			"if not FieldWork.podePazada(lastStroke[p], now) then",
			"task.delay(C.contatoS, function()",
			'toast(p, "Pá: pazada perdida (você se moveu)")',
			"or longe > C.alcanceM then",
			"if obras[o.key] ~= o or o.k >= o.n then",
			"b.mats, b.occs = workspace.Terrain:ReadVoxels(region, VOXEL)",
			"workspace.Terrain:WriteVoxels(b.region, VOXEL, outM, outO)",
			"table.clear(obras) -- D-195",
			'char:SetAttribute("VT65PazadaT", workspace:GetServerTimeNow())',
			'local op = if type(req) == "table" then req.op else nil',
		}
	do
		assert(string.find(fw, t, 1, true), "FieldWorkService: " .. t)
	end
	assert(not string.find(fw, "local function excavate", 1, true), "o buraco de uma vez saiu")
end)

test("cliente: o gatilho dá a pazada, a troca guarda a pá e o toque pega a pá", function()
	local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
	local wc = fs.readFile(C .. "WeaponController.client.luau")
	assert(string.find(wc, "if ItemView.paNaMao() and not seated() then\n\t\tItemView.pazada()", 1, true), "gatilho")
	assert(string.find(wc, "ItemView.guardarPa()\n\t\tfromHand = true", 1, true), "troca de arma guarda")
	local iv = fs.readFile(C .. "ItemView.luau")
	for _, t in
		{
			'Net.event("Dig_Request"):FireServer({ op = "pazada" })',
			"elseif subindo or since >= P * 0.6 then",
			'Bus.on("pa_alternar", function()',
		}
	do
		assert(string.find(iv, t, 1, true), "ItemView: " .. t)
	end
	local ic = fs.readFile(C .. "InfantryController.client.luau")
	assert(string.find(ic, 'Bus.fire("pa_alternar")', 1, true), "vaga 8 e roda")
	local ot = fs.readFile(C .. "ObraToque.client.luau")
	assert(string.find(ot, 'Bus.fire("pa_pegar")', 1, true), "toque")
	local input = fs.readFile(C .. "Input.luau")
	assert(string.find(input, "InputMap.triggerDown(was,", 1, true), "histerese no gatilho")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
