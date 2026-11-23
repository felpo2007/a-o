--!strict
-- D-221 (dono: "essa comemoração esta horrosa sem trabalho nenhum sem animações fodas efeitos
-- especiais, qualidade visual"): os efeitos do pódio, em duas camadas em volta do ViewportFrame:
-- - atrás dos soldados: o sol do vencedor, os fachos de holofote e os sinalizadores no céu;
-- - na frente: confete, brasas subindo, fumaça rasteira, vinheta e as faixas de cinema.
-- Cada pouso (Cena.aoPousar) acende o facho daquele lugar, com poeira, faíscas e onda de choque; o do
-- 1º dispara os canhões de confete e abre os sinalizadores. Com "reduzir movimento": só a luz parada.
local TweenService = game:GetService("TweenService")

local UiEfeitos = require(script.Parent.UiEfeitos)

local PodioEfeitos = {}
PodioEfeitos.__index = PodioEfeitos

local CONFETE, BRASAS, FUMACA = 64, 22, 6
local GRAVIDADE = 0.62 -- frações da altura por s²
local COR_LUGAR = {
	[1] = Color3.fromRGB(255, 214, 120),
	[2] = Color3.fromRGB(206, 220, 236),
	[3] = Color3.fromRGB(240, 170, 110),
} :: { [number]: Color3 }
-- de onde vem o facho de cada lugar (fração da cena, acima do quadro)
local ORIGEM = {
	[1] = { 0.5, -0.16 },
	[2] = { 0.08, -0.14 },
	[3] = { 0.92, -0.14 },
} :: { [number]: { number } }

type Confete = { q: Frame, x: number, y: number, vx: number, vy: number, r: number, vr: number, f: number, w: number }
type Brasa = { q: Frame, x: number, y: number, v: number, vida: number, dur: number, fase: number }
type Facho = { q: ImageLabel, lugar: number, k: number, alvo: number, fase: number }
type Fumaca = { q: ImageLabel, x: number, y: number, v: number, s: number, fase: number }
type Sinal = { q: ImageLabel, x: number, y: number, vy: number, t: number, dur: number, cor: Color3 }

local function camada(pai: Instance, nome: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = nome
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = pai
	return f
end

-- A luz macia (textura do UiEfeitos). Sem a textura fica vazia: um quadro aqui viraria um retângulo
-- de borda dura na tela; o `reiniciar` põe a imagem quando ela já chegou.
local function macia(pai: Instance, nome: string, cor: Color3): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = nome
	i.BackgroundTransparency = 1
	i.Image = UiEfeitos.imagem("brilho") or ""
	i.ImageColor3 = cor
	i.ImageTransparency = 1
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Parent = pai
	return i
end

local function alfa(o: ImageLabel, tr: number)
	o.ImageTransparency = tr
end

function PodioEfeitos.novo(pai: GuiObject, cena: any)
	local self = setmetatable({}, PodioEfeitos) :: any
	self.pai, self.cena = pai, cena
	self.rng = Random.new()
	self.fundo = camada(pai, "EfeitosFundo", 2)
	self.frente = camada(pai, "EfeitosFrente", 4)
	self.cor = COR_LUGAR[1]
	self.t = 0
	self.proximoSinal = math.huge
	self.sol = macia(self.fundo, "Sol", self.cor)
	self.solK = 0
	self.fachos = {} :: { Facho }
	for _, l in { 3, 2, 1 } do
		local q = macia(self.fundo, string.format("Facho%d", l), COR_LUGAR[l])
		table.insert(self.fachos, { q = q, lugar = l, k = 0, alvo = 0, fase = l * 1.7 })
	end
	self.confete = {} :: { Confete }
	for _ = 1, CONFETE do
		local q = Instance.new("Frame")
		q.Name = "Confete"
		q.BorderSizePixel = 0
		q.AnchorPoint = Vector2.new(0.5, 0.5)
		q.Visible = false
		q.Parent = self.frente
		table.insert(self.confete, { q = q, x = 0, y = 2, vx = 0, vy = 0, r = 0, vr = 0, f = 0, w = 6 })
	end
	self.brasas = {} :: { Brasa }
	for _ = 1, BRASAS do
		local q = Instance.new("Frame")
		q.Name = "Brasa"
		q.BorderSizePixel = 0
		q.AnchorPoint = Vector2.new(0.5, 0.5)
		q.BackgroundColor3 = Color3.fromRGB(255, 176, 84)
		q.Visible = false
		q.Parent = self.frente
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = q
		table.insert(self.brasas, { q = q, x = 0, y = 2, v = 0, vida = 0, dur = 0, fase = 0 })
	end
	self.fumaca = {} :: { Fumaca }
	for k = 1, FUMACA do
		local q = macia(self.frente, "Fumaca", Color3.fromRGB(176, 158, 140))
		table.insert(self.fumaca, {
			q = q,
			x = (k - 0.5) / FUMACA,
			y = 0.93 + self.rng:NextNumber(-0.03, 0.03),
			v = self.rng:NextNumber(0.008, 0.02) * (if k % 2 == 0 then 1 else -1),
			s = self.rng:NextNumber(0.34, 0.52),
			fase = self.rng:NextNumber(0, 6.28),
		})
	end
	-- a neblina na linha onde a clareira encontra o cenário
	self.neblina = macia(self.frente, "Neblina", Color3.fromRGB(240, 150, 96))
	self.sinais = {} :: { Sinal }
	-- vinheta (em cima e embaixo) e as faixas de cinema, que entram no começo
	for _, cima in { true, false } do
		local v = Instance.new("Frame")
		v.Name = if cima then "VinhetaCima" else "VinhetaBaixo"
		v.BorderSizePixel = 0
		v.BackgroundColor3 = Color3.new(0, 0, 0)
		v.Size = UDim2.fromScale(1, 0.34)
		v.Position = UDim2.fromScale(0, if cima then 0 else 0.66)
		v.Parent = self.frente
		local g = Instance.new("UIGradient")
		g.Rotation = if cima then 90 else -90
		g.Transparency = NumberSequence.new(0.42, 1)
		g.Parent = v
	end
	self.barras = {} :: { Frame }
	for _, cima in { true, false } do
		local b = Instance.new("Frame")
		b.Name = if cima then "FaixaCima" else "FaixaBaixo"
		b.BorderSizePixel = 0
		b.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
		b.AnchorPoint = Vector2.new(0, if cima then 1 else 0)
		b.Size = UDim2.fromScale(1, 0.075)
		b.Parent = self.frente
		self.barras[if cima then 1 else 2] = b
	end
	self:reiniciar(COR_LUGAR[1])
	return self
end

-- Tamanho da cena em px de projeto (ela fica dentro do UIScale da tela)
function PodioEfeitos._tam(self: any): Vector2
	local a = self.frente.AbsoluteSize
	local k = 1
	local o: Instance? = self.frente
	while o do
		local u = o:FindFirstChildOfClass("UIScale")
		if u then
			k *= u.Scale
		end
		o = o.Parent
	end
	return Vector2.new(a.X / math.max(k, 0.01), a.Y / math.max(k, 0.01))
end

-- Começo de uma comemoração: tudo apagado, na cor do lado que venceu
function PodioEfeitos.reiniciar(self: any, cor: Color3)
	self.cor = cor:Lerp(COR_LUGAR[1], 0.35)
	self.t = 0
	self.solK = 0
	self.proximoSinal = math.huge
	for _, f in self.fachos do
		f.k, f.alvo = 0, 0
		alfa(f.q, 1)
	end
	alfa(self.sol, 1)
	self.sol.ImageColor3 = self.cor
	-- a textura pode ter chegado depois de a tela nascer
	local luz = UiEfeitos.imagem("brilho") or ""
	self.sol.Image, self.neblina.Image = luz, luz
	for _, f in self.fachos do
		f.q.Image = luz
	end
	for _, m in self.fumaca do
		m.q.Image = luz
	end
	for _, c in self.confete do
		c.y = 2
		c.q.Visible = false
	end
	for _, s in self.sinais do
		s.q:Destroy()
	end
	table.clear(self.sinais)
	local calmo = UiEfeitos.calmo()
	for _, b in self.brasas do
		b.vida = -self.rng:NextNumber(0, 3)
		b.q.Visible = false
	end
	self.barras[1].Position = UDim2.fromScale(0, if calmo then 0.075 else 0)
	self.barras[2].Position = UDim2.fromScale(0, if calmo then 0.925 else 1)
end

-- Um canhão de confete no canto (lado -1 esquerda, 1 direita), atirando para o meio e para cima
function PodioEfeitos._canhao(self: any, lado: number, n: number)
	local cores = { self.cor, Color3.fromRGB(255, 214, 120), Color3.new(1, 1, 1), Color3.fromRGB(226, 78, 58) }
	local feitos = 0
	for _, c in self.confete do
		if feitos >= n then
			break
		end
		if c.y > 1.15 then
			feitos += 1
			local r: Random = self.rng
			c.x = if lado < 0 then r:NextNumber(0, 0.05) else r:NextNumber(0.95, 1)
			c.y = r:NextNumber(0.92, 1.02)
			c.vx = -lado * r:NextNumber(0.1, 0.62)
			c.vy = -r:NextNumber(0.72, 1.34)
			c.r = r:NextNumber(0, 360)
			c.vr = r:NextNumber(-520, 520)
			c.f = r:NextNumber(0, 6.28)
			c.w = r:NextNumber(5, 10)
			c.q.BackgroundColor3 = cores[r:NextInteger(1, #cores)]
			c.q.Visible = true
		end
	end
end

-- O soldado do lugar tocou o tampo
function PodioEfeitos.impacto(self: any, lugar: number)
	for _, f in self.fachos do
		if f.lugar == lugar then
			f.alvo = 1
		end
	end
	if lugar == 1 then
		self.solK = 1
		self.proximoSinal = self.t + 0.5
	end
	if UiEfeitos.calmo() then
		return
	end
	local tam = self:_tam()
	local fx, fy = self.cena:tela(lugar, 0.2)
	local centro = Vector2.new(fx * tam.X, fy * tam.Y)
	local forte = lugar == 1
	UiEfeitos.onda(self.frente, centro, COR_LUGAR[lugar], tam.Y * (if forte then 0.42 else 0.24), 0.6, 8)
	-- a poeira sai para os lados, rente ao tampo, e as faíscas para cima
	UiEfeitos.faiscas(self.frente, centro, Color3.fromRGB(196, 170, 136), if forte then 26 else 14, {
		cone = -math.pi / 2,
		abertura = math.pi * 1.1,
		vmin = 120,
		vmax = if forte then 620 else 380,
		gravidade = 620,
		z = 8,
	})
	UiEfeitos.faiscas(self.frente, centro, COR_LUGAR[lugar], if forte then 34 else 14, {
		cone = -math.pi / 2,
		abertura = math.pi * 0.7,
		vmin = 260,
		vmax = if forte then 1050 else 620,
		gravidade = 760,
		z = 9,
	})
	if forte then
		UiEfeitos.clarao(self.frente, Color3.fromRGB(255, 232, 186), 0.5, 0.55, 12)
		self:_canhao(-1, 30)
		self:_canhao(1, 30)
	end
end

-- Um sinalizador: sobe atrás dos soldados e estoura no céu
function PodioEfeitos._sinal(self: any)
	local r: Random = self.rng
	local cores = { self.cor, Color3.fromRGB(255, 214, 120), Color3.fromRGB(255, 244, 226) }
	local cor = cores[r:NextInteger(1, #cores)]
	local q = macia(self.fundo, "Sinal", cor)
	q.Size = UDim2.fromOffset(26, 26)
	alfa(q, 0.05)
	-- longe do meio, para o estouro não ficar atrás do rosto do 1º
	local lado = if r:NextNumber() < 0.5 then -1 else 1
	table.insert(self.sinais, {
		q = q,
		x = 0.5 + lado * r:NextNumber(0.14, 0.42),
		y = 0.9,
		vy = -r:NextNumber(1.05, 1.4),
		t = 0,
		dur = r:NextNumber(0.5, 0.68),
		cor = cor,
	})
end

function PodioEfeitos.passo(self: any, dt: number)
	self.t += dt
	local t: number = self.t
	local calmo = UiEfeitos.calmo()
	local tam = self:_tam()
	local W, H = tam.X, tam.Y
	-- faixas de cinema entram no primeiro meio segundo
	local b = math.clamp(t / 0.5, 0, 1)
	b = 1 - (1 - b) ^ 3
	self.barras[1].Position = UDim2.fromScale(0, 0.075 * b)
	self.barras[2].Position = UDim2.fromScale(0, 1 - 0.075 * b)
	-- fachos: da origem até o soldado, com um balanço lento e a luz abrindo
	for _, f in self.fachos do
		f.k += (f.alvo - f.k) * math.clamp(dt * 6, 0, 1)
		if f.k < 0.01 then
			alfa(f.q, 1)
			continue
		end
		local o = ORIGEM[f.lugar]
		local fx, fy = self.cena:tela(f.lugar, 3.6)
		local balanco = if calmo then 0 else 0.012 * math.sin(t * 0.9 + f.fase)
		local dx, dy = (fx + balanco - o[1]) * W, (fy - o[2]) * H
		local d = math.sqrt(dx * dx + dy * dy) * 1.42
		f.q.Position = UDim2.fromOffset(o[1] * W + dx * 0.71, o[2] * H + dy * 0.71)
		f.q.Size = UDim2.fromOffset(H * (if f.lugar == 1 then 0.62 else 0.46), d)
		f.q.Rotation = math.deg(math.atan2(-dx, dy))
		local pulso = if calmo then 0 else 0.035 * math.sin(t * 2.3 + f.fase)
		alfa(f.q, 1 - (0.3 + pulso) * f.k)
	end
	local _, fyChao = self.cena:telaPonto(Vector3.new(0, 0, -14))
	self.neblina.Position = UDim2.fromScale(0.5, fyChao)
	self.neblina.Size = UDim2.fromOffset(W * 1.7, H * 0.17)
	alfa(self.neblina, 0.62)
	-- o sol atrás do vencedor
	if self.solK > 0 then
		local fx, fy = self.cena:tela(1, 5.2)
		self.sol.Position = UDim2.fromScale(fx, fy)
		local s = H * (1.16 + (if calmo then 0 else 0.05 * math.sin(t * 1.4)))
		self.sol.Size = UDim2.fromOffset(s, s)
		alfa(self.sol, 0.42)
	end
	if calmo then
		for _, c in self.confete do
			c.q.Visible = false
		end
		return
	end
	-- confete: sobe no tiro, freia no ar e cai balançando
	for _, c in self.confete do
		if c.y <= 1.15 then
			c.vy += GRAVIDADE * dt
			c.vy = math.min(c.vy, 0.3)
			c.vx *= math.exp(-dt * 1.1)
			c.f += dt * 5
			c.x += (c.vx + 0.05 * math.sin(c.f)) * dt
			c.y += c.vy * dt
			c.r += c.vr * dt
			c.q.Position = UDim2.fromScale(c.x, c.y)
			c.q.Rotation = c.r
			c.q.Size = UDim2.fromOffset(c.w, math.max(1.5, c.w * 1.5 * math.abs(math.cos(c.f))))
			if c.y > 1.15 then
				c.q.Visible = false
			end
		end
	end
	-- brasas subindo do chão
	for _, e in self.brasas do
		e.vida += dt
		if e.vida >= e.dur then
			local r: Random = self.rng
			e.x, e.y = r:NextNumber(0.02, 0.98), r:NextNumber(0.88, 1.02)
			e.v = r:NextNumber(0.05, 0.14)
			e.dur = r:NextNumber(2.2, 4.4)
			e.vida = 0
			e.fase = r:NextNumber(0, 6.28)
			local s = r:NextInteger(2, 5)
			e.q.Size = UDim2.fromOffset(s, s)
		end
		if e.vida >= 0 then
			e.y -= e.v * dt
			local u = e.vida / e.dur
			e.q.Visible = true
			e.q.Position = UDim2.fromScale(e.x + 0.012 * math.sin(e.vida * 1.8 + e.fase), e.y)
			e.q.BackgroundTransparency = 0.15 + 0.85 * math.max(1 - math.min(u * 6, 1), (u - 0.45) / 0.55)
		end
	end
	-- fumaça rasteira
	for _, m in self.fumaca do
		m.x += m.v * dt
		if m.x < -0.3 then
			m.x = 1.3
		elseif m.x > 1.3 then
			m.x = -0.3
		end
		m.q.Position = UDim2.fromScale(m.x, m.y)
		m.q.Size = UDim2.fromOffset(W * m.s, H * 0.42)
		m.q.ImageTransparency = 0.84 + 0.05 * math.sin(t * 0.7 + m.fase)
	end
	-- sinalizadores
	if t >= self.proximoSinal then
		self:_sinal()
		self.proximoSinal = t + self.rng:NextNumber(0.9, 1.7)
	end
	for i = #self.sinais, 1, -1 do
		local s = self.sinais[i]
		s.t += dt
		s.y += s.vy * dt
		s.vy += 0.9 * dt
		s.q.Position = UDim2.fromScale(s.x, s.y)
		if s.t >= s.dur then
			local c = Vector2.new(s.x * W, s.y * H)
			UiEfeitos.faiscas(self.fundo, c, s.cor, 28, {
				abertura = math.pi * 2,
				vmin = 120,
				vmax = 460,
				gravidade = 170,
				arrasto = 2.1,
				z = 3,
			})
			-- o clarão do estouro: luz macia que abre e apaga
			local g = macia(self.fundo, "Estouro", s.cor)
			g.Position = UDim2.fromOffset(c.X, c.Y)
			g.Size = UDim2.fromOffset(H * 0.2, H * 0.2)
			g.ImageTransparency = 0.2
			local tw = TweenService:Create(g, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = 1,
				Size = UDim2.fromOffset(H * 0.46, H * 0.46),
			})
			tw.Completed:Once(function()
				g:Destroy()
			end)
			tw:Play()
			s.q:Destroy()
			table.remove(self.sinais, i)
		end
	end
end

return PodioEfeitos
