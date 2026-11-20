--!strict
-- Comemoração dos três melhores (D-202; prompt de jogabilidade, §21): os gestos procedurais do
-- Shared/Comemoracao (juntas dentro do limite, sem salto entre quadros, os três sem mexer igual), o
-- palco (1º no meio e mais alto, caixotes sem se encostar) e as amarras no código (cópia congelada no
-- fim, o rig de AnimationConstraint, empate sem vencedor, a cópia some na partida nova).
-- Uso: lune run tests/luau/comemoracao.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local Comemoracao = require("../../src/ReplicatedStorage/Shared/Comemoracao") :: any

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

local function tipo(junta: string): string
	for _, k in { "Shoulder", "Elbow", "Wrist", "Waist", "Neck", "Hip", "Knee", "Ankle" } do
		if string.find(junta, k, 1, true) then
			return k
		end
	end
	error("junta sem tipo: " .. junta)
end

local DT = 1 / 60
local T_MAX = 30

test("juntas dentro do limite, cotovelo só dobra para a frente e joelho para trás", function()
	for lugar = 1, 3 do
		local t = 0
		while t <= T_MAX do
			local p = Comemoracao.quadro(lugar, t)
			for _, j in Comemoracao.JUNTAS do
				local a = p.juntas[j]
				assert(a, string.format("lugar %d sem %s", lugar, j))
				local lim = Comemoracao.LIMITES[tipo(j)]
				for e = 1, 3 do
					assert(a[e] == a[e], "NaN")
					assert(math.abs(a[e]) <= lim + 1e-6, string.format("%s eixo %d = %.1f em t %.2f", j, e, a[e], t))
				end
				if tipo(j) == "Elbow" then
					assert(a[1] >= -1e-6, string.format("%s dobra para trás (%.1f)", j, a[1]))
				elseif tipo(j) == "Knee" then
					assert(a[1] <= 1e-6, string.format("%s dobra para a frente (%.1f)", j, a[1]))
				end
			end
			assert(p.sobe >= -0.5 and p.sobe <= 1.0, string.format("pulo de %.2f", p.sobe))
			t += DT
		end
	end
end)

test("sem salto entre quadros a 60 fps (nem na troca de gesto, nem na volta do laço)", function()
	local pior, onde = 0, ""
	for lugar = 1, 3 do
		local antes = Comemoracao.quadro(lugar, 0)
		local t = DT
		while t <= T_MAX do
			local p = Comemoracao.quadro(lugar, t)
			for _, j in Comemoracao.JUNTAS do
				for e = 1, 3 do
					local d = math.abs(p.juntas[j][e] - antes.juntas[j][e])
					if d > pior then
						pior, onde = d, string.format("lugar %d %s em t %.2f", lugar, j, t)
					end
				end
			end
			antes = p
			t += DT
		end
	end
	assert(pior <= 12, string.format("salto de %.1f° (%s)", pior, onde))
	print(string.format("       (maior passo entre dois quadros: %.1f°, %s)", pior, onde))
end)

test("os três não mexem igual: gestos diferentes e cada um troca de gesto na comemoração", function()
	local iguais, amostras = 0, 0
	local usados: { [number]: { [string]: boolean } } = { {}, {}, {} }
	local t = 0
	while t <= 12 do
		local g = {}
		for lugar = 1, 3 do
			local nome = Comemoracao.gestoEm(lugar, t)
			g[lugar] = nome
			usados[lugar][nome] = true
		end
		if g[1] == g[2] and g[2] == g[3] then
			iguais += 1
		end
		amostras += 1
		t += 0.1
	end
	assert(iguais == 0, string.format("%d de %d amostras com os três no mesmo gesto", iguais, amostras))
	for lugar = 1, 3 do
		local n = 0
		for _ in usados[lugar] do
			n += 1
		end
		assert(n >= 2, string.format("lugar %d com %d gesto(s) em 12 s", lugar, n))
	end
	-- e todo gesto das sequências existe
	for lugar, seq in Comemoracao.SEQ do
		for _, g in seq do
			assert(Comemoracao.GESTOS[g[1]], string.format("lugar %d: gesto %s", lugar, tostring(g[1])))
		end
	end
end)

test("palco: o 1º no meio e mais alto, o 2º acima do 3º, caixotes sem se encostar", function()
	local L = Comemoracao.LUGARES
	assert(L[1].x == 0 and L[1].alto > L[2].alto and L[2].alto > L[3].alto)
	assert(L[2].x < 0 and L[3].x > 0, "2º à esquerda, 3º à direita")
	assert(math.abs(L[2].x - L[1].x) >= Comemoracao.CAIXOTE.largura, "1º e 2º se encostam")
	assert(math.abs(L[3].x - L[1].x) >= Comemoracao.CAIXOTE.largura, "1º e 3º se encostam")
	-- os dos lados viram para o meio
	assert(L[2].giro > 0 and L[3].giro < 0)
end)

test("amarras: cópia congelada, rig de AnimationConstraint, empate sem vencedor", function()
	local rs = fs.readFile("src/ServerScriptService/Modules/RodadaService.luau")
	for _, t in
		{
			"pcall(congelarModelos, podio)",
			'f.Name = "VT65PodioModelos"',
			"pastaModelos():ClearAllChildren()",
		}
	do
		assert(string.find(rs, t, 1, true), "RodadaService: " .. t)
	end
	-- a cópia some antes da partida nova
	local a = string.find(rs, "pastaModelos():ClearAllChildren()", 1, true)
	local b = string.find(rs, "MatchService.newMatch()", 1, true)
	assert(a and b and a < b, "a cópia sai antes da partida nova")
	local cena = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/CenaComemoracao.luau")
	for _, t in
		{
			'd:IsA("AnimationConstraint")',
			"junta(d.Name, p0, p1, a0.CFrame, a1.CFrame)",
			'd:IsA("WeldConstraint")',
			"if juntas < 10 then",
			"function Cena.telaX(",
		}
	do
		assert(string.find(cena, t, 1, true), "CenaComemoracao: " .. t)
	end
	local tela = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/FimDeRodada.client.luau")
	for _, t in
		{
			'ReplicatedStorage:FindFirstChild("VT65PodioModelos")',
			"cena:bandeira({ V.US, V.VC })",
			"if not cena:por(i, modelFor(tostring(l.id), lado)) then",
			"cena:passo(dt)",
		}
	do
		assert(string.find(tela, t, 1, true), "FimDeRodada: " .. t)
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
