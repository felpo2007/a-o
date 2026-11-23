--!strict
-- D-238: a corrida e o rastejo procedurais do soldado (Shared/Passada3P).
local Movement = require("../../src/ReplicatedStorage/Shared/Movement") :: any
local Passada3P = require("../../src/ReplicatedStorage/Shared/Passada3P") :: any
local Recarga = require("../../src/ReplicatedStorage/Shared/Recarga") :: any

local ok, fail = 0, 0
local function test(name: string, fn: () -> ())
	local good, err = pcall(fn)
	if good then
		ok += 1
	else
		fail += 1
		print("FALHOU: " .. name .. "\n  " .. tostring(err))
	end
end

local M = Movement.STUD_M
-- medidas lidas no boneco no Studio (studs)
local GEO = Passada3P.geo(1.174, 1.323, 0.36, 0)
local VELS = { Movement.JOG, (Movement.JOG + Movement.SPRINT) / 2, Movement.SPRINT }
local N = 240

test("cadência de gente correndo: cerca de 3 passos/s no trote e 3,6 na corrida", function()
	local j, s = Passada3P.passosPorSegundo(Movement.JOG), Passada3P.passosPorSegundo(Movement.SPRINT)
	assert(j > 2.8 and j < 3.3, "trote: " .. j)
	assert(s > 3.4 and s < 3.8, "corrida: " .. s)
end)

test("não saltita: a bacia sobe e desce de 3,5 a 7 cm", function()
	for _, v in VELS do
		local lo, hi = math.huge, -math.huge
		for i = 0, N - 1 do
			local y = Passada3P.pose(i / N, v, GEO).y * M
			lo, hi = math.min(lo, y), math.max(hi, y)
		end
		local cm = (hi - lo) * 100
		assert(cm >= 3.5 and cm <= 7, string.format("%.1f cm a %.2f m/s", cm, v))
	end
end)

test("pé apoiado não escorrega: anda para trás na velocidade do corpo", function()
	for _, v in VELS do
		local periodo = 1 / Passada3P.ciclos(v)
		local passoT = periodo / N
		local n = 0
		for i = 0, N - 2 do
			local a, b = Passada3P.pose(i / N, v, GEO).E, Passada3P.pose((i + 1) / N, v, GEO).E
			if a.apoio and b.apoio then
				n += 1
				local vel = -(b.x - a.x) / passoT * M
				assert(math.abs(vel - v) < 0.03 * v, string.format("%.2f contra %.2f m/s", vel, v))
			end
		end
		assert(n > 10, "sem apoio")
	end
end)

-- FK do plano: a perna chega onde o caminho do pé pede
local function tornozelo(p: any, pose: any): (number, number)
	local hx = -GEO.quadril * math.sin(pose.inclina)
	local hy = pose.y + GEO.altura - GEO.quadril * math.cos(pose.inclina)
	local coxa = p.quadril - pose.inclina
	local canela = coxa + p.joelho
	return hx + GEO.coxa * math.sin(coxa) + GEO.canela * math.sin(canela),
		hy - GEO.coxa * math.cos(coxa) - GEO.canela * math.cos(canela)
end

test("IK: o tornozelo chega ao caminho do pé e o joelho nunca dobra ao contrário", function()
	for _, v in VELS do
		local pior = 0
		for i = 0, N - 1 do
			local pose = Passada3P.pose(i / N, v, GEO)
			for _, p in { pose.E, pose.D } do
				assert(p.joelho <= 1e-6, "joelho ao contrário")
				local x, y = tornozelo(p, pose)
				pior = math.max(pior, math.sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2) * M)
			end
		end
		assert(pior < 0.035, string.format("erro de %.1f cm a %.2f m/s", pior * 100, v))
	end
end)

test("pé no chão no apoio e erguido no balanço; as duas pernas em oposição", function()
	for _, v in VELS do
		local maxY = 0
		for i = 0, N - 1 do
			local pose = Passada3P.pose(i / N, v, GEO)
			assert(not (pose.E.apoio and pose.D.apoio), "dois pés no chão correndo")
			if pose.E.apoio then
				assert(pose.E.y >= GEO.pe - 1e-6, "pé abaixo do chão")
			else
				maxY = math.max(maxY, pose.E.y - GEO.pe)
			end
		end
		assert(maxY * M > 0.15, "pé não levanta")
	end
end)

test("rastejo: um ciclo por segundo e joelho e cotovelo contrários", function()
	local c = Passada3P.ciclosRastejo(Movement.PRONE)
	assert(c > 0.9 and c < 1.2, "ciclos: " .. c)
	local a = Passada3P.rastejo(0.38) -- joelho esquerdo puxado
	local b = Passada3P.rastejo(0.88) -- joelho direito puxado
	assert(a.E.joelho < a.D.joelho - math.rad(40), "esquerdo dobrado")
	assert(b.D.joelho < b.E.joelho - math.rad(40), "direito dobrado")
	assert(a.E.abre < 0 and a.D.abre > 0, "abrem para fora")
	assert(a.braco * b.braco < 0, "os cotovelos alternam")
end)

test("recarga: começa e termina no guarda-mão, com o carregador na mão no caminho", function()
	for _, tipo in { "caixa", "tubo", "cinta" } do
		local a = Recarga.mao(tipo, 0)
		assert(a == "apoio", tipo .. ": começa no apoio")
		local _, b, e = Recarga.mao(tipo, 0.999)
		assert(b == "apoio" and e > 0.9, tipo .. ": termina no apoio")
		assert(Recarga.envelope(0) < 1e-6 and Recarga.envelope(1) < 1e-6, "entra e sai suave")
		assert(Recarga.envelope(0.5) > 0.99, "no meio, pose cheia")
		local comMag = false
		for i = 0, 100 do
			local _, _, _, m = Recarga.mao(tipo, i / 100)
			comMag = comMag or m
		end
		assert(comMag, tipo .. ": leva carregador ou cartucho")
	end
end)

test("recarga: o relógio do servidor dá o mesmo instante e o tipo sai da arma", function()
	assert(Recarga.progresso(100, 2, 101) == 0.5, "metade")
	assert(Recarga.progresso(100, 2, 103) == nil, "acabou")
	assert(Recarga.progresso(nil, 2, 101) == nil, "sem recarga")
	assert(Recarga.tipo("tube", "rifle") == "tubo")
	assert(Recarga.tipo(nil, "mg") == "cinta")
	assert(Recarga.tipo(nil, "rifle") == "caixa")
	local _, rola, sobe = Recarga.arma("caixa", 0.7)
	assert(rola > 10 and sobe > 0.05, "a arma gira e sente o tapa")
end)
print(string.format("passada: %d ok, %d falhas", ok, fail))
if fail > 0 then
	error("falhas")
end
