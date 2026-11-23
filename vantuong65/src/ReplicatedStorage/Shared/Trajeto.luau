--!strict
-- D-243: a trajetória do comboio. Módulo PURO. Passa por todos os nós (Catmull-Rom centripeta, sem laços nem
-- cúspides), com um trecho reto de reserva antes do primeiro e depois do último. A distância `s` é medida ao
-- longo da curva, com o relevo quando há função de altura, e s = 0 fica no primeiro nó.
local Trajeto = {}

export type No = { x: number, y: number }
export type Trajeto = {
	X: { number },
	Y: { number },
	Z: { number },
	A: { number }, -- comprimento acumulado desde a ponta da extensão inicial
	s0: number, -- valor de A no primeiro nó
	comprimento: number, -- do primeiro ao último nó
	sNos: { number },
	extensao: number,
}

local PASSO = 0.25 -- metros entre amostras

-- Comprimento da polilinha plana dos nós.
function Trajeto.polilinha(nos: { No }): number
	local soma = 0
	for i = 2, #nos do
		soma += math.sqrt((nos[i].x - nos[i - 1].x) ^ 2 + (nos[i].y - nos[i - 1].y) ^ 2)
	end
	return soma
end

local function catmull(p0: No, p1: No, p2: No, p3: No, u: number): (number, number)
	local function nt(t: number, a: No, b: No): number
		local d = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		return t + math.sqrt(math.max(d, 1e-6))
	end
	local t0 = 0
	local t1 = nt(t0, p0, p1)
	local t2 = nt(t1, p1, p2)
	local t3 = nt(t2, p2, p3)
	local t = t1 + (t2 - t1) * u
	local function mix(a: number, b: number, ta: number, tb: number): number
		return (tb - t) / (tb - ta) * a + (t - ta) / (tb - ta) * b
	end
	local function ponto(c: string): number
		local v0, v1, v2, v3 = (p0 :: any)[c], (p1 :: any)[c], (p2 :: any)[c], (p3 :: any)[c]
		local a1, a2, a3 = mix(v0, v1, t0, t1), mix(v1, v2, t1, t2), mix(v2, v3, t2, t3)
		local b1, b2 = mix(a1, a2, t0, t2), mix(a2, a3, t1, t3)
		return mix(b1, b2, t1, t2)
	end
	return ponto("x"), ponto("y")
end

function Trajeto.novo(nos: { No }, extensao: number, altura: ((x: number, y: number) -> number)?): Trajeto
	local n = #nos
	local function fora(a: No, b: No, d: number): No
		local dx, dy = a.x - b.x, a.y - b.y
		local m = math.sqrt(dx * dx + dy * dy)
		return { x = a.x + dx / m * d, y = a.y + dy / m * d }
	end
	-- os dois pontos fantasmas de cada ponta mantêm a tangente da extensão
	local ini = fora(nos[1], nos[2], extensao)
	local fim = fora(nos[n], nos[n - 1], extensao)
	local cheia: { No } = { fora(ini, nos[1], extensao), ini }
	for _, p in nos do
		table.insert(cheia, p)
	end
	table.insert(cheia, fim)
	table.insert(cheia, fora(fim, nos[n], extensao))
	local X, Y, idxNo = {}, {}, {} :: { number }
	for i = 2, #cheia - 2 do
		local a, b = cheia[i], cheia[i + 1]
		local corda = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		local k = math.max(4, math.ceil(corda / PASSO))
		if i >= 3 and i <= n + 2 then
			idxNo[i - 2] = #X + 1
		end
		for j = 0, k - 1 do
			local x, y = catmull(cheia[i - 1], a, b, cheia[i + 2], j / k)
			table.insert(X, x)
			table.insert(Y, y)
		end
	end
	local ultimo = cheia[#cheia - 1]
	table.insert(X, ultimo.x)
	table.insert(Y, ultimo.y)
	local Z, A = table.create(#X, 0) :: { number }, table.create(#X, 0) :: { number }
	for i = 1, #X do
		Z[i] = if altura then altura(X[i], Y[i]) else 0
		if i > 1 then
			A[i] = A[i - 1] + math.sqrt((X[i] - X[i - 1]) ^ 2 + (Y[i] - Y[i - 1]) ^ 2 + (Z[i] - Z[i - 1]) ^ 2)
		end
	end
	local s0 = A[idxNo[1]]
	local sNos: { number } = {}
	for i = 1, n do
		sNos[i] = A[idxNo[i]] - s0
	end
	return { X = X, Y = Y, Z = Z, A = A, s0 = s0, comprimento = sNos[n], sNos = sNos, extensao = extensao }
end

-- Média móvel na altura (m de cada lado) e recálculo da distância: o chão de voxel não sacode o caminhão.
function Trajeto.suaviza(t: Trajeto, janelaM: number)
	local n = #t.X
	local k = math.max(1, math.round(janelaM / PASSO))
	local somas = table.create(n + 1, 0) :: { number }
	for i = 1, n do
		somas[i + 1] = somas[i] + t.Z[i]
	end
	local novoZ = table.create(n, 0) :: { number }
	for i = 1, n do
		local a, b = math.max(1, i - k), math.min(n, i + k)
		novoZ[i] = (somas[b + 1] - somas[a]) / (b - a + 1)
	end
	-- índice de cada nó, antes de a distância mudar
	local idx: { number } = {}
	for i, s in t.sNos do
		local alvo = s + t.s0
		local lo, hi = 1, n
		while lo < hi do
			local m = (lo + hi) // 2
			if t.A[m] < alvo - 1e-9 then
				lo = m + 1
			else
				hi = m
			end
		end
		idx[i] = lo
	end
	t.Z = novoZ
	for i = 2, n do
		t.A[i] = t.A[i - 1]
			+ math.sqrt((t.X[i] - t.X[i - 1]) ^ 2 + (t.Y[i] - t.Y[i - 1]) ^ 2 + (novoZ[i] - novoZ[i - 1]) ^ 2)
	end
	t.s0 = t.A[idx[1]]
	for i = 1, #t.sNos do
		t.sNos[i] = t.A[idx[i]] - t.s0
	end
	t.comprimento = t.sNos[#t.sNos]
end

-- Índice i com A[i] <= alvo < A[i+1].
local function busca(t: Trajeto, alvo: number): number
	local lo, hi = 1, #t.A - 1
	while lo < hi do
		local m = (lo + hi + 1) // 2
		if t.A[m] <= alvo then
			lo = m
		else
			hi = m - 1
		end
	end
	return lo
end

-- Posição na distância s (s pode entrar nas extensões): x, y, z.
function Trajeto.pos(t: Trajeto, s: number): (number, number, number)
	local alvo = math.clamp(s + t.s0, 0, t.A[#t.A])
	local i = busca(t, alvo)
	local d = t.A[i + 1] - t.A[i]
	local u = if d > 0 then (alvo - t.A[i]) / d else 0
	return t.X[i] + (t.X[i + 1] - t.X[i]) * u, t.Y[i] + (t.Y[i + 1] - t.Y[i]) * u, t.Z[i] + (t.Z[i + 1] - t.Z[i]) * u
end

-- Direção unitária da trajetória em s (plano): dx, dy.
function Trajeto.dir(t: Trajeto, s: number): (number, number)
	local x0, y0 = Trajeto.pos(t, s - 0.75)
	local x1, y1 = Trajeto.pos(t, s + 0.75)
	local dx, dy = x1 - x0, y1 - y0
	local m = math.sqrt(dx * dx + dy * dy)
	if m < 1e-6 then
		return 1, 0
	end
	return dx / m, dy / m
end

-- Menor raio de curva (m) entre as distâncias a e b, medido em cordas de `base` metros.
function Trajeto.raioMinimo(t: Trajeto, a: number?, b: number?, base: number?): number
	local b0 = base or 4
	local ini, fim = a or 0, b or t.comprimento
	local menor = math.huge
	local s = ini
	while s <= fim do
		local x1, y1 = Trajeto.pos(t, s - b0)
		local x2, y2 = Trajeto.pos(t, s)
		local x3, y3 = Trajeto.pos(t, s + b0)
		local aa = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		local bb = math.sqrt((x3 - x2) ^ 2 + (y3 - y2) ^ 2)
		local cc = math.sqrt((x3 - x1) ^ 2 + (y3 - y1) ^ 2)
		local area = math.abs((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) / 2
		if area > 1e-6 then
			menor = math.min(menor, aa * bb * cc / (4 * area))
		end
		s += 1
	end
	return menor
end

return Trajeto
