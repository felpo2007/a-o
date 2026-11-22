--!nocheck
-- D-243: regras da Linha de Frente e do Comboio (prompt, seções 6, 7, 9, 10 e 16).
local MapasRet = require("../../src/ReplicatedStorage/Shared/MapasRet")
local LF = require("../../src/ReplicatedStorage/Shared/LinhaFrente")
local Trajeto = require("../../src/ReplicatedStorage/Shared/Trajeto")
local Comboio = require("../../src/ReplicatedStorage/Shared/Comboio")

local ok, falhas = 0, 0
local function test(nome, fn)
	local sucesso, erro = pcall(fn)
	if sucesso then
		ok += 1
	else
		falhas += 1
		print("  FALHA " .. nome .. ": " .. tostring(erro))
	end
end
local function perto(a, b, tol)
	return math.abs(a - b) <= (tol or 1e-6)
end
local function roda(s, segundos, o, l, dt)
	local passo = dt or 0.25
	for _ = 1, math.round(segundos / passo) do
		LF.passo(s, passo, o, l)
	end
end
local R = MapasRet.FRENTE.regras

-- ===== dados =====
test("dimensões, centros e índices dos nós", function()
	assert(MapasRet.FRENTE.compM == 700 and MapasRet.FRENTE.profM == 300)
	assert(MapasRet.COMBOIO.compM == 900 and MapasRet.COMBOIO.profM == 300)
	local esperado = { A = { 135, 150 }, B = { 245, 190 }, C = { 350, 150 }, D = { 455, 110 }, E = { 565, 150 } }
	for _, st in MapasRet.FRENTE.setores do
		assert(st.x == esperado[st.id][1] and st.y == esperado[st.id][2], st.id)
	end
	-- road_guide_index 2, 5, 6, 9 (base zero) = N3, N6, N7, N10
	local base0 = { 2, 5, 6, 9 }
	for i, cp in MapasRet.COMBOIO.checkpoints do
		assert(cp.no == base0[i] + 1, cp.id)
	end
	assert(MapasRet.COMBOIO.nos[6].x == 480 and MapasRet.COMBOIO.nos[7].x == 575)
end)

test("a polilinha plana mede 990,11 m e leva 292,56 s com as paradas", function()
	local L = Trajeto.polilinha(MapasRet.COMBOIO.nos)
	assert(perto(L, 990.11, 0.005), string.format("%.3f", L))
	local t = L / 3.8
	assert(perto(t, 260.56, 0.005), string.format("%.3f", t))
	assert(perto(t + 4 * 8, 292.56, 0.005))
	local cp23 = math.sqrt((575 - 480) ^ 2 + (200 - 105) ^ 2)
	assert(perto(cp23, 134.35, 0.005), "CP2-CP3")
end)

-- ===== Linha de Frente =====
test("começa em C, neutra", function()
	local s = LF.novo()
	assert(s.ativo == 3 and s.barra == 0 and s.fase == "disputa")
end)

for n, seg in { 50, 40, 35 } do
	test(string.format("%d jogador(es) capturam em %d s", n, seg), function()
		local s = LF.novo()
		roda(s, seg - 0.25, n, 0)
		assert(s.ativo == 3, "conquistou cedo")
		roda(s, 0.25, n, 0)
		assert(s.ativo == 4 and s.fase == "transicao" and s.barra == 0)
	end)
end

test("quatro jogadores não capturam mais rápido que três", function()
	local s = LF.novo()
	roda(s, 34.75, 4, 0)
	assert(s.ativo == 3)
end)

test("os dois times na área congelam a barra", function()
	local s = LF.novo()
	roda(s, 20, 1, 0)
	local b = s.barra
	roda(s, 30, 5, 1)
	assert(s.barra == b)
end)

test("área vazia: nada nos 10 s, depois volta devagar até o neutro", function()
	local s = LF.novo()
	roda(s, 25, 1, 0)
	local b = s.barra
	roda(s, 10, 0, 0)
	assert(perto(s.barra, b), "voltou antes dos 10 s")
	roda(s, 6, 0, 0)
	assert(perto(s.barra, b - 6 * R.retornoPorS, 1e-6))
	roda(s, 120, 0, 0)
	assert(s.barra == 0, "passou do neutro")
end)

test("adversário sozinho desfaz o progresso e depois avança para o lado dele", function()
	local s = LF.novo()
	roda(s, 25, 1, 0) -- +0,5
	roda(s, 25, 0, 1)
	assert(perto(s.barra, 0, 1e-6))
	roda(s, 25, 0, 1)
	assert(perto(s.barra, -0.5, 1e-6) and s.ativo == 3)
end)

test("a conquista muda o setor e bloqueia a captura por 15 s", function()
	local s = LF.novo()
	roda(s, 50, 1, 0)
	assert(s.ativo == 4 and s.fase == "transicao")
	roda(s, 14.75, 5, 0)
	assert(s.barra == 0 and s.fase == "transicao")
	roda(s, 0.25, 5, 0)
	assert(s.fase == "disputa")
end)

test("Oeste capturando E vence; Leste capturando A vence", function()
	local s = LF.novo()
	for _ = 1, 3 do
		roda(s, 35, 3, 0)
		if s.fase == "transicao" then
			roda(s, 15, 0, 0)
		end
	end
	assert(s.fase == "fim" and s.vencedor == "oeste" and s.motivo == "conquista", tostring(s.fase))
	local l = LF.novo()
	for _ = 1, 3 do
		roda(l, 35, 0, 3)
		if l.fase == "transicao" then
			roda(l, 15, 0, 0)
		end
	end
	assert(l.fase == "fim" and l.vencedor == "leste")
end)

-- leva a partida até perto do fim com o setor `ativo`
local function noFim(ativo, faltaS)
	local s = LF.novo()
	s.ativo = ativo
	s.t = R.duracaoS - faltaS
	return s
end

test("fim do relógio: D/E vitória do Oeste, A/B do Leste", function()
	for _, a in { 4, 5 } do
		local s = noFim(a, 1)
		roda(s, 1, 0, 0)
		assert(s.vencedor == "oeste" and s.motivo == "territorio")
	end
	for _, a in { 1, 2 } do
		local s = noFim(a, 1)
		roda(s, 1, 0, 0)
		assert(s.vencedor == "leste" and s.motivo == "territorio")
	end
end)

test("fim com C ativo: disputa final preserva a barra e a primeira conquista decide", function()
	local s = noFim(3, 1)
	s.barra = 0.6
	roda(s, 1, 0, 0)
	assert(s.fase == "final" and perto(s.barra, 0.6, 1e-6))
	roda(s, 20, 1, 0) -- 0,6 + 0,4
	assert(s.fase == "fim" and s.vencedor == "oeste" and s.motivo == "disputa_final")
end)

test("disputa final sem conquista empata em 90 s", function()
	local s = noFim(3, 1)
	roda(s, 1, 0, 0)
	roda(s, 89.75, 2, 2)
	assert(s.fase == "final")
	roda(s, 0.25, 2, 2)
	assert(s.fase == "fim" and s.vencedor == "empate")
end)

test("relógio termina na transição PARA C: acaba a transição e só então 90 s, barra neutra", function()
	local s = noFim(4, 5)
	s.barra = -0.999
	roda(s, 0.25, 0, 3)
	assert(s.ativo == 3 and s.fase == "transicao")
	local fim = s.transicaoAte
	roda(s, 6, 3, 0)
	assert(s.relogioEsgotado and s.fase == "transicao", "encerrou durante a transição")
	roda(s, fim - s.t, 0, 0)
	assert(s.fase == "final" and s.barra == 0)
	assert(perto(s.finalAte, fim + 90, 1e-6))
end)

test("relógio termina noutra transição: vale o novo índice já registrado", function()
	local s = noFim(3, 5)
	s.barra = 0.999
	roda(s, 0.25, 3, 0)
	assert(s.ativo == 4 and s.fase == "transicao")
	roda(s, 5, 0, 0)
	assert(s.fase == "fim" and s.vencedor == "oeste" and s.motivo == "territorio")
	local l = noFim(3, 5)
	l.barra = -0.999
	roda(l, 0.25, 0, 3)
	assert(l.ativo == 2)
	roda(l, 5, 0, 0)
	assert(l.vencedor == "leste")
end)

test("conquista terminal no mesmo passo do fim do relógio tem prioridade", function()
	local s = noFim(5, 0.25)
	s.barra = 0.999
	LF.passo(s, 0.25, 3, 0)
	assert(s.vencedor == "oeste" and s.motivo == "conquista")
	-- sem essa prioridade, A ativo daria vitória territorial do Leste; aqui é o mesmo lado, então
	-- o caso que distingue é Oeste segurando A até o fim
	local a = noFim(1, 0.25)
	a.barra = -0.999
	LF.passo(a, 0.25, 0, 3)
	assert(a.vencedor == "leste" and a.motivo == "conquista")
end)

test("conquista não terminal no último passo: o índice novo decide", function()
	local s = noFim(2, 0.25) -- B ativo daria vitória do Leste
	s.barra = 0.999
	LF.passo(s, 0.25, 3, 0)
	assert(s.ativo == 3, "o Oeste levou B e a frente volta a C")
	assert(s.fase == "transicao" and s.relogioEsgotado)
	roda(s, 15, 0, 0)
	assert(s.fase == "final", "transição para C vira disputa final")
end)

-- ===== trajetória =====
local nos = MapasRet.COMBOIO.nos
local T = Trajeto.novo(nos, MapasRet.COMBOIO.regras.extensaoM)

test("a curva passa pelos dez nós e reserva a extensão nos dois extremos", function()
	for i, n in nos do
		local x, y = Trajeto.pos(T, T.sNos[i])
		assert(perto(x, n.x, 1e-6) and perto(y, n.y, 1e-6), "N" .. i)
	end
	local x0, y0 = Trajeto.pos(T, -18)
	assert(perto(math.sqrt((x0 - 40) ^ 2 + (y0 - 120) ^ 2), 18, 0.2), "extensão inicial")
	local x1, y1 = Trajeto.pos(T, T.comprimento + 18)
	assert(perto(math.sqrt((x1 - 850) ^ 2 + (y1 - 150) ^ 2), 18, 0.2), "extensão final")
	assert(T.comprimento >= Trajeto.polilinha(nos), "a curva não pode ser mais curta que a guia")
end)

test("o comprimento inclui o relevo", function()
	local c = Trajeto.novo(nos, 18, function(x, _y)
		return math.sin(x / 15) * 3
	end)
	assert(c.comprimento > T.comprimento + 1)
end)

test("os caminhões ficam a 18 m ao longo do caminho em todo o percurso", function()
	for s = 0, math.floor(T.comprimento), 7 do
		local a, b = Comboio.centros(s)
		assert(perto(b - a, 18))
		local xa, ya = Trajeto.pos(T, a)
		local xb, yb = Trajeto.pos(T, b)
		local corda = math.sqrt((xb - xa) ^ 2 + (yb - ya) ^ 2)
		assert(corda <= 18 + 1e-6 and corda > 14, string.format("s=%d corda %.2f", s, corda))
	end
end)

-- ===== comboio =====
local function corrida()
	local cps = {}
	for i, cp in MapasRet.COMBOIO.checkpoints do
		cps[i] = T.sNos[cp.no]
	end
	return Comboio.nova(cps, T.comprimento)
end
local ESC = { escolta = 1, defesa = 0, reparadores = 0 }
local NADA = { escolta = 0, defesa = 0, reparadores = 0 }
local function anda(c, seg, e, dt)
	local p = dt or 0.25
	for _ = 1, math.round(seg / p) do
		Comboio.passo(c, p, e)
	end
end
local function ateParada(c)
	local n = 0
	while not c.naParada and n < 8000 do
		Comboio.passo(c, 0.05, ESC)
		n += 1
	end
	assert(c.naParada, "não chegou")
end

test("percurso completo a 3,80 m/s com quatro paradas de 8 s", function()
	local c = corrida()
	anda(c, 600, ESC)
	assert(c.entregue)
	assert(perto(c.tEntrega, T.comprimento / 3.8 + 32, 1e-3), string.format("%.3f", c.tEntrega))
	assert(perto(c.s, T.comprimento, 1e-6))
end)

test("mais escoltadores não aceleram; sem escolta para", function()
	local a, b = corrida(), corrida()
	anda(a, 10, ESC)
	anda(b, 10, { escolta = 8, defesa = 0, reparadores = 0 })
	assert(perto(a.s, b.s) and perto(a.s, 38, 1e-6))
	local s = a.s
	anda(a, 5, NADA)
	assert(a.s == s and Comboio.estado(a, NADA) == "aguardando")
end)

test("defensor contesta e interrompe, mesmo com escolta e proteção", function()
	local c = corrida()
	anda(c, 5, ESC)
	local s = c.s
	c.protegidoAte = c.t + 100
	local e = { escolta = 5, defesa = 1, reparadores = 0 }
	anda(c, 5, e)
	assert(c.s == s and Comboio.estado(c, e) == "contestado")
end)

test("checkpoint: pausa sem perder progresso e só conclui com 8 s válidos", function()
	local c = corrida()
	ateParada(c)
	local s = c.s
	local p0 = c.cpProg -- o resto do passo em que chegou já conta na parada
	anda(c, 3, ESC)
	assert(perto(c.cpProg, p0 + 3, 1e-6) and Comboio.estado(c, ESC) == "checkpoint")
	anda(c, 4, NADA)
	assert(perto(c.cpProg, p0 + 3, 1e-6), "perdeu sem escolta")
	anda(c, 2, { escolta = 1, defesa = 2, reparadores = 0 })
	assert(perto(c.cpProg, p0 + 3, 1e-6), "contou contestado")
	anda(c, 5.25, ESC)
	assert(c.cp == 2 and not c.naParada and c.s >= s)
end)

test("o teto de dano é 10 por segundo e um evento não conta duas vezes", function()
	local c = corrida()
	Comboio.dano(c, "e1", 500)
	Comboio.dano(c, "e1", 500)
	Comboio.passo(c, 1, NADA)
	assert(perto(c.integridade, 90, 1e-6), tostring(c.integridade))
	local d = corrida()
	Comboio.dano(d, "x", 4)
	Comboio.dano(d, "x", 4)
	Comboio.passo(d, 1, NADA)
	assert(perto(d.integridade, 96, 1e-6), "evento repetido")
end)

local function imobiliza(c)
	while not c.imobilizadoAte do
		Comboio.dano(c, tostring(c.t) .. ":" .. math.random(), 100)
		Comboio.passo(c, 1, NADA)
	end
end

test("zerar a integridade imobiliza por até 15 s; volta com 25 e 20 s de proteção", function()
	local c = corrida()
	imobiliza(c)
	local fim = c.imobilizadoAte
	assert(c.integridade == 0 and Comboio.estado(c, ESC) == "imobilizado")
	anda(c, fim - c.t + 0.01, NADA, 0.01)
	assert(not c.imobilizadoAte and c.integridade == 25)
	assert(perto(c.protegidoAte - c.t, 20, 0.02))
	Comboio.dano(c, "protegido", 50)
	Comboio.passo(c, 1, NADA)
	assert(c.integridade == 25, "tomou dano protegido")
end)

test("reparo: 6 pessoa-segundos, no máximo dois ao mesmo tempo", function()
	local c = corrida()
	imobiliza(c)
	local dois = { escolta = 0, defesa = 0, reparadores = 2 }
	assert(Comboio.estado(c, dois) == "reparando")
	anda(c, 2.75, dois)
	assert(c.imobilizadoAte, "antes dos 3 s")
	anda(c, 0.25, dois)
	assert(not c.imobilizadoAte and c.integridade == 25)
	local d = corrida()
	imobiliza(d)
	anda(d, 2.75, { escolta = 0, defesa = 0, reparadores = 5 })
	assert(d.imobilizadoAte, "cinco reparadores não podem ser mais rápidos que dois")
end)

test("reparo interrompido para de contar e retoma de onde estava", function()
	local c = corrida()
	imobiliza(c)
	anda(c, 2, { escolta = 0, defesa = 0, reparadores = 1 })
	assert(perto(c.reparo, 2, 1e-6))
	anda(c, 3, NADA)
	assert(perto(c.reparo, 2, 1e-6))
end)

test("a recuperação só libera o movimento se as outras condições valem", function()
	local c = corrida()
	anda(c, 3, ESC)
	local s = c.s
	imobiliza(c)
	anda(c, 3, { escolta = 0, defesa = 1, reparadores = 2 })
	assert(not c.imobilizadoAte and c.s == s)
end)

test("no máximo duas imobilizações por trecho; o checkpoint zera só essa contagem", function()
	local c = corrida()
	for _ = 1, 2 do
		imobiliza(c)
		anda(c, 3, { escolta = 0, defesa = 0, reparadores = 2 })
		c.protegidoAte = -math.huge
	end
	assert(c.imobNoTrecho == 2)
	for i = 1, 40 do
		Comboio.dano(c, "limite" .. i, 100)
		Comboio.passo(c, 1, NADA)
	end
	assert(not c.imobilizadoAte and c.integridade == 1, "não pode parar uma terceira vez")
	ateParada(c)
	anda(c, 8, ESC)
	assert(c.imobNoTrecho == 0 and c.integridade == 1, "o checkpoint não cura")
end)

test("o progresso não retrocede em nenhum estado", function()
	local c = corrida()
	local antes = 0
	for i = 1, 3000 do
		local e =
			{ escolta = i % 7 == 0 and 0 or 1, defesa = i % 11 == 0 and 1 or 0, reparadores = i % 5 == 0 and 2 or 0 }
		if i % 13 == 0 then
			Comboio.dano(c, i, 30)
		end
		Comboio.passo(c, 0.25, e)
		assert(c.s >= antes)
		antes = c.s
	end
end)

test("entrega exata no último passo vale", function()
	local c = corrida()
	c.s = c.cps[4]
	c.cp = 4
	c.naParada = true
	c.cpProg = 7.75
	Comboio.passo(c, 0.25, ESC)
	assert(c.entregue and perto(c.tEntrega, 0.25))
end)

test("resultado: entrega, tempo, distância, captura e empate exato", function()
	local function r(t)
		local c = corrida()
		for k, v in t do
			c[k] = v
		end
		return c
	end
	assert(Comboio.resultado(r({ entregue = true, tEntrega = 400 }), r({ s = 800 })) == 1)
	assert(Comboio.resultado(r({ s = 800 }), r({ entregue = true, tEntrega = 500 })) == 2)
	assert(Comboio.resultado(r({ entregue = true, tEntrega = 400 }), r({ entregue = true, tEntrega = 399.99 })) == 2)
	assert(Comboio.resultado(r({ s = 300 }), r({ s = 300.0001 })) == 2, "sem tolerância de distância")
	assert(Comboio.resultado(r({ s = 300, cp = 2, cpProg = 5 }), r({ s = 300, cp = 2, cpProg = 4 })) == 1)
	local q, m = Comboio.resultado(r({ s = 300, cp = 2, cpProg = 4 }), r({ s = 300, cp = 2, cpProg = 4 }))
	assert(q == 0 and m == "empate")
	local q2 = Comboio.resultado(r({ entregue = true, tEntrega = 400 }), r({ entregue = true, tEntrega = 400 }))
	assert(q2 == 0)
end)

print(string.format("%d ok, %d falhas", ok, falhas))
if falhas > 0 then
	error("modos_mapas: falhou")
end
