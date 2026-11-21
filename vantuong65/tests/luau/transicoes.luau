--!strict
-- D-215 (lote 100): as transições das telas. A cortina (ReplicatedFirst/CortinaCurva: cobre a tela
-- inteira em qualquer proporção, sai de fora e vai para fora) e as ligações (tela de entrada, fases do
-- fim de partida, a palavra da VITÓRIA, o desfoque da confirmação).
-- Uso, a partir de vantuong65/:  lune run tests/luau/transicoes.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local Curva = require("../../src/ReplicatedFirst/CortinaCurva") :: any

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
local function ler(p: string): string
	return (string.gsub(fs.readFile(p), "\r\n", "\n"))
end
local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"

local TELAS = {
	{ 1920, 1080 }, -- PC 16:9
	{ 1024, 768 }, -- 4:3
	{ 2560, 1080 }, -- 21:9
	{ 390, 844 }, -- celular em pé
	{ 844, 390 }, -- celular deitado
	{ 839, 656 }, -- a janela do Studio
}

test("cortina: no meio cobre os quatro cantos de qualquer tela; nas pontas, nada à vista", function()
	local ang = Curva.INCLINA
	for _, t in TELAS do
		local W, H = t[1], t[2]
		local lado, x0, xm, x1 = Curva.posicoes(W, H)
		for _, c in { { 0, 0 }, { W, 0 }, { 0, H }, { W, H }, { W / 2, H / 2 } } do
			assert(
				Curva.dentro(c[1], c[2], xm, H / 2, lado, ang),
				string.format("%dx%d: canto %d,%d de fora", W, H, c[1], c[2])
			)
		end
		local maxX0, minX1 = -math.huge, math.huge
		for _, k in Curva.cantos(x0, H / 2, lado, ang) do
			maxX0 = math.max(maxX0, k[1])
		end
		for _, k in Curva.cantos(x1, H / 2, lado, ang) do
			minX1 = math.min(minX1, k[1])
		end
		assert(maxX0 < 0, string.format("%dx%d: aparece antes de entrar (%.1f)", W, H, maxX0))
		assert(minX1 > W, string.format("%dx%d: ainda à vista no fim (%.1f)", W, H, minX1))
	end
end)

test("cortina: as curvas vão de 0 a 1 sem voltar; entra freando, sai puxando", function()
	local a, b = -1, -1
	for k = 0, 100 do
		local u = k / 100
		local e, s = Curva.entra(u), Curva.sai(u)
		assert(e >= a and s >= b, "volta")
		a, b = e, s
	end
	assert(Curva.entra(0) == 0 and Curva.entra(1) == 1 and Curva.sai(0) == 0 and Curva.sai(1) == 1)
	assert(Curva.entra(0.3) > 0.7, "entra rápido e assenta")
	assert(Curva.sai(0.3) < 0.05, "sai devagar e acelera")
end)

test("cortina: rápida (menos de 1 s) e mais curta com movimento reduzido", function()
	local T, K = Curva.TEMPO, Curva.TEMPO_CALMO
	local total = T.entra + T.segura + T.sai
	assert(total <= 1.0, string.format("%.2f s", total))
	assert(K.entra + K.segura + K.sai < total)
	local src = ler("src/ReplicatedFirst/Cortina.luau")
	assert(string.find(src, "Estilo.reduzMovimento()", 1, true), "movimento reduzido: esmaece no lugar")
	assert(string.find(src, "gui.DisplayOrder = 1000", 1, true), "acima da tela de entrada (100)")
	assert(string.find(src, "while ocupada do", 1, true), "uma de cada vez")
end)

test("ligações: tela de entrada, fases do fim, VITÓRIA e confirmação", function()
	local ls = ler("src/ReplicatedFirst/LoadingScreen.client.luau")
	local a = assert(string.find(ls, 'pcall(Cortina.cobrir, "STARLITE"', 1, true), "a entrada cobre")
	local b = assert(string.find(ls, 'gui:SetAttribute("Saindo", true)', a, true), "o lobby começa coberto")
	assert(string.find(ls, "pcall(Cortina.descobrir)", b, true), "e a cortina sai")
	-- a cortina falhando nunca prende a tela de entrada: volta o esmaecer de antes
	assert(string.find(ls, "Cortina.soltar()", a, true) and string.find(ls, "GroupTransparency = 1 }", b, true))
	local co = ler("src/ReplicatedFirst/Cortina.luau")
	assert(string.find(co, "local okC, errC = pcall(function()", 1, true), "a troca roda mesmo sem cortina")
	local fr = ler(C .. "FimDeRodada.client.luau")
	for _, t in { "Cortina.passar(function()", '"VOTAÇÃO DO MAPA"', '"PREPARANDO O CAMPO"', "onPhase(true)" } do
		assert(string.find(fr, t, 1, true), "FimDeRodada: " .. t)
	end
	local fh = ler(C .. "FrontHud.client.luau")
	assert(string.find(fh, 'u.Name = "Golpe"', 1, true) and string.find(fh, "UiEfeitos.faiscas(p.hold", 1, true))
	assert(string.find(fh, "UiEfeitos.tremer(p.hold", 1, true), "a derrota treme")
	local uk = ler(C .. "UiKit.luau")
	assert(string.find(uk, "desfoque(true)", 1, true) and string.find(uk, "desfoque(false)", 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
