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
			assert(p.sobe >= -0.5 and p.sobe <= 1.8, string.format("pulo de %.2f", p.sobe))
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
			"cena:bandeira({ V.US, V.VC }, ",
			"if not cena:por(i, modelFor(tostring(l.id), lado)) then",
			"cena:passo(dt)",
		}
	do
		assert(string.find(tela, t, 1, true), "FimDeRodada: " .. t)
	end
end)

-- ===== D-214: o melhor da partida e as comemorações =====
local function confere(p: any, onde: string)
	for _, j in Comemoracao.JUNTAS do
		local a = p.juntas[j]
		assert(a, onde .. " sem " .. j)
		local lim = Comemoracao.LIMITES[tipo(j)]
		for e = 1, 3 do
			assert(a[e] == a[e], "NaN")
			assert(math.abs(a[e]) <= lim + 1e-6, string.format("%s: %s eixo %d = %.1f", onde, j, e, a[e]))
		end
		if tipo(j) == "Elbow" then
			assert(a[1] >= -1e-6, string.format("%s: %s dobra para trás", onde, j))
		elseif tipo(j) == "Knee" then
			assert(a[1] <= 1e-6, string.format("%s: %s dobra para a frente", onde, j))
		end
	end
	assert(p.sobe >= -0.5 and p.sobe <= 1.8, string.format("%s: pulo de %.2f", onde, p.sobe))
end

local function maiorPasso(f: (t: number) -> any, t0: number, t1: number): (number, string)
	local pior, onde = 0, ""
	local antes = f(t0)
	local t = t0 + DT
	while t <= t1 do
		local p = f(t)
		for _, j in Comemoracao.JUNTAS do
			for e = 1, 3 do
				local d = math.abs(p.juntas[j][e] - antes.juntas[j][e])
				if d > pior then
					pior, onde = d, string.format("%s em t %.2f", j, t)
				end
			end
		end
		antes = p
		t += DT
	end
	return pior, onde
end

test("catálogo: ids únicos, a padrão grátis, grátis e EM BREVE, gestos que existem", function()
	local vistos, gratis, breve = {}, 0, 0
	for _, it in Comemoracao.CATALOGO do
		assert(not vistos[it.id], "id repetido: " .. it.id)
		vistos[it.id] = true
		assert(#it.nome > 0 and #it.desc > 0, it.id)
		for _, g in it.seq do
			assert(Comemoracao.GESTOS[g[1]], string.format("%s: gesto %s", it.id, tostring(g[1])))
		end
		if it.gratis then
			gratis += 1
		else
			breve += 1
		end
	end
	assert(Comemoracao.item(Comemoracao.PADRAO).gratis, "a padrão é grátis")
	assert(gratis >= 2 and breve >= 3, string.format("%d grátis, %d em breve", gratis, breve))
	assert(Comemoracao.valida("nao_existe") == Comemoracao.PADRAO and Comemoracao.valida(nil) == Comemoracao.PADRAO)
	assert(Comemoracao.tem("pulos", nil) == false and Comemoracao.tem("pulos", { pulos = true }))
	assert(Comemoracao.tem("padrao", nil) and not Comemoracao.tem("nao_existe", { nao_existe = true }))
end)

test("cada comemoração: juntas no limite e sem salto entre quadros (com a volta do laço)", function()
	local pior, onde = 0, ""
	for _, it in Comemoracao.CATALOGO do
		local t = 0
		while t <= 20 do
			confere(Comemoracao.celebracao(it.id, t), it.id)
			t += DT
		end
		local p, o = maiorPasso(function(tt: number): any
			return Comemoracao.celebracao(it.id, tt)
		end, 0, 20)
		if p > pior then
			pior, onde = p, it.id .. " " .. o
		end
	end
	assert(pior <= 12, string.format("salto de %.1f° (%s)", pior, onde))
	print(string.format("       (maior passo nas comemorações: %.1f°, %s)", pior, onde))
end)

test("pódio: o 1º passa à comemoração dele sem tranco; antes disso, os gestos de sempre", function()
	local P = Comemoracao.PODIO
	for _, it in Comemoracao.CATALOGO do
		local p, o = maiorPasso(function(t: number): any
			return Comemoracao.poseNoPodio(1, t, it.id)
		end, 0, 12)
		assert(p <= 12, string.format("%s: salto de %.1f° (%s)", it.id, p, o))
		local a, b = Comemoracao.poseNoPodio(1, P.mvp - 0.1, it.id), Comemoracao.quadro(1, P.mvp - 0.1)
		assert(a.juntas.RightShoulder[1] == b.juntas.RightShoulder[1], "antes do mvp, o gesto de sempre")
	end
	-- o 2º e o 3º não mudam
	local a, b = Comemoracao.poseNoPodio(2, 8, "pulos"), Comemoracao.quadro(2, 8)
	assert(a.juntas.LeftShoulder[3] == b.juntas.LeftShoulder[3])
end)

test("roteiro: 3º, 2º e 1º chegam nessa ordem; a câmera vai até o 1º depois que todos pousaram", function()
	local P = Comemoracao.PODIO
	assert(P.entrada[3] < P.entrada[2] and P.entrada[2] < P.entrada[1], "3º, 2º, 1º")
	for lugar = 1, 3 do
		local v = Comemoracao.entrada(lugar, P.entrada[lugar] - 0.01)
		assert(v == false, "fora de vista antes da vez")
		local v2, dy = Comemoracao.entrada(lugar, P.entrada[lugar] + 0.01)
		assert(v2 and dy > 6, "chega do alto")
		local _, dy3 = Comemoracao.entrada(lugar, P.entrada[lugar] + P.queda + 0.8)
		assert(dy3 < 0.01, "pousado")
	end
	assert(P.zoom > P.entrada[1] + P.queda + 2, "os três à vista antes da câmera ir")
	assert(P.mvp > P.zoom and P.mvp < P.perto and P.perto < 12 - 4, "o 1º comemora com tempo de sobra")
	-- câmera: começa como era (aberta), termina perto, sem pulo entre quadros
	local c0 = Comemoracao.camera(0)
	assert(c0.dist == 38 and c0.fov == 34 and c0.ay == 7.6)
	local c1 = Comemoracao.camera(P.perto + 0.5)
	assert(c1.dist == 20 and c1.fov == 30 and c1.dist < c0.dist / 1.8, "perto do 1º (quase o dobro de perto)")
	local antes = Comemoracao.camera(0)
	local t = DT
	while t <= 12 do
		local c = Comemoracao.camera(t)
		for _, k in { "ax", "ay", "az", "dist", "alto", "fov", "giro" } do
			assert(math.abs((c :: any)[k] - (antes :: any)[k]) < 0.5, string.format("%s pula em t %.2f", k, t))
		end
		antes = c
		t += DT
	end
	local s = Comemoracao.camera(3, true)
	-- D-221: o close do pódio recuou para 20 (tela cheia); a prévia segue enquadrando do pé à cabeça
	assert(s.dist >= 17 and s.ay < c1.ay, "a prévia mostra o corpo inteiro")
end)

test("amarras D-214: perfil, remote, servidor, pódio, tela e ARMÁRIO", function()
	local ps = fs.readFile("src/ServerScriptService/Modules/ProfileSchema.luau")
	assert(string.find(ps, 'comemoracao = "padrao",', 1, true) and string.find(ps, "comemoracoes = {},", 1, true))
	local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(net, '"Comemoracao_Equipar"', 1, true))
	local ts = fs.readFile("src/ServerScriptService/Modules/TeamService.luau")
	assert(string.find(ts, "if not Comemoracao.tem(id, p.comemoracoes) then", 1, true), "o servidor confere a posse")
	local rs = fs.readFile("src/ServerScriptService/Modules/RodadaService.luau")
	assert(string.find(rs, 'l.com = Comemoracao.valida(pl and pl:GetAttribute("Comemoracao"))', 1, true))
	local tela = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/FimDeRodada.client.luau")
	assert(string.find(tela, "cena:comemoracao(i,", 1, true) and string.find(tela, "MELHOR DA PARTIDA", 1, true))
	local cena = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/CenaComemoracao.luau")
	assert(string.find(cena, "Comemoracao.poseNoPodio(b.lugar, self.t, self.com[b.lugar])", 1, true))
	assert(string.find(cena, "Comemoracao.camera(", 1, true))
	-- campo com o nome de um método cai no método pelo metatable (no Studio, o pódio inteiro rodava no
	-- modo prévia): nenhum `self.<x>` pode ter o nome de uma `function Cena.<x>`
	for metodo in string.gmatch(cena, "function Cena%.([%w_]+)%(") do
		assert(not string.find(cena, "self." .. metodo .. " =", 1, true), "campo com o nome do método Cena." .. metodo)
	end
	local sc = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/ShopController.client.luau")
	assert(string.find(sc, '"COMEMORAÇÃO NO PÓDIO"', 1, true) and string.find(sc, '"🔒 EM BREVE"', 1, true))
	assert(string.find(sc, 'Net.event("Comemoracao_Equipar"):FireServer(it.id)', 1, true))
end)

test("D-221: o giro do corpo fecha a volta e o pouso dobra as pernas sem tranco", function()
	for _, it in Comemoracao.CATALOGO do
		local antes = Comemoracao.celebracao(it.id, 0).gira or 0
		local t = DT
		while t <= 20 do
			local g = Comemoracao.celebracao(it.id, t).gira or 0
			local d = math.abs(g - antes)
			d = math.min(d, 360 - d)
			assert(d <= 14, string.format("%s: o giro pula %.1f° em t %.2f", it.id, d, t))
			antes = g
			t += DT
		end
	end
	local P = Comemoracao.PODIO
	for lugar = 1, 3 do
		local pouso = P.entrada[lugar] + P.queda
		assert(Comemoracao.pouso(lugar, pouso) > 0.95, "dobra no pouso")
		assert(Comemoracao.pouso(lugar, pouso + 1.5) < 0.01, "volta a ficar de pé")
		assert(Comemoracao.pouso(lugar, P.entrada[lugar] - 0.01) == 0, "antes de chegar, nada")
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
