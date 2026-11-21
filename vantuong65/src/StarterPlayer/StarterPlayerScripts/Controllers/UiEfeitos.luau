--!strict
-- D-213 (pedido do dono de 20/11: "animação perfeita e realista com efeitos visuais para a loja e para
-- a abertura das caixas"): os efeitos de interface. A conta é do Shared/Efeitos (pura); aqui só se
-- desenha.
--   - faiscas: explosão de rastros e bolinhas de luz, com arrasto e gravidade;
--   - onda: o anel da onda de choque;
--   - raios: raios de luz girando atrás de uma peça;
--   - halo: luz redonda e macia, com pulso opcional;
--   - cintilas: brilhos de quatro pontas piscando numa área;
--   - varre: a faixa clara que passa por um cartão de tempos em tempos;
--   - brasas: brasas subindo devagar num cartão (em laço);
--   - tremer: o tranco de um quadro; clarao: o clarão de tela.
-- As texturas são as do tools/efeitos_ui.py (brancas; a cor vem do ImageColor3), publicadas como
-- Images.efeito_<nome> e resolvidas pelo servidor (Modules/ImagensUi: atributo "Img_efeito_<nome>").
-- Sem a imagem, cada efeito usa um quadro redondo de reserva.
-- Movimento reduzido (Estilo.reduzMovimento): nada voa nem treme; o halo fica parado e as faíscas não
-- saem. Um laço só (RenderStepped) anima tudo e se desliga quando não há nada.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Efeitos = require(ReplicatedStorage.Shared.Efeitos)
local Estilo = require(game:GetService("ReplicatedFirst"):WaitForChild("Estilo"))

local UiEfeitos = {}

-- ===== o laço =====
local ativos: { (dt: number) -> boolean } = {}
local laco: RBXScriptConnection? = nil

local function roda(f: (dt: number) -> boolean)
	table.insert(ativos, f)
	if laco then
		return
	end
	laco = RunService.RenderStepped:Connect(function(dt: number)
		for i = #ativos, 1, -1 do
			local ok, vivo = pcall(ativos[i], dt)
			if not ok or not vivo then
				table.remove(ativos, i)
			end
		end
		if #ativos == 0 and laco then
			laco:Disconnect()
			laco = nil
		end
	end)
end
UiEfeitos.roda = roda

-- quantos efeitos estão rodando (teste no Studio)
function UiEfeitos.ativos(): number
	return #ativos
end

function UiEfeitos.calmo(): boolean
	return Estilo.reduzMovimento()
end

-- ===== texturas =====
function UiEfeitos.imagem(nome: string): string?
	local v = ReplicatedStorage:GetAttribute("Img_efeito_" .. nome)
	return if type(v) == "number" and v ~= 0 then string.format("rbxassetid://%d", v) else nil
end

-- peça de efeito: a imagem pintada na cor, ou um quadro redondo de reserva
local function peca(pai: Instance, nome: string, cor: Color3, z: number): GuiObject
	local img = UiEfeitos.imagem(nome)
	if img then
		local i = Instance.new("ImageLabel")
		i.Name = "Efeito_" .. nome
		i.BackgroundTransparency = 1
		i.Image = img
		i.ImageColor3 = cor
		i.AnchorPoint = Vector2.new(0.5, 0.5)
		i.ZIndex = z
		i.Parent = pai
		return i
	end
	local f = Instance.new("Frame")
	f.Name = "Efeito_" .. nome
	f.BackgroundColor3 = cor
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.ZIndex = z
	Estilo.corner(f, 999)
	f.Parent = pai
	return f
end

local function transp(o: GuiObject, tr: number)
	if o:IsA("ImageLabel") then
		o.ImageTransparency = tr
	else
		o.BackgroundTransparency = math.max(tr, 0.35) -- o quadro de reserva é duro: mais apagado
	end
end

-- a tela que contém o quadro está ligada? (os laços da loja param com a loja fechada)
local function naTela(o: Instance): boolean
	local g = o:FindFirstAncestorWhichIsA("ScreenGui")
	return g ~= nil and g.Enabled
end

-- ===== faíscas =====
export type OpcoesFaiscas = {
	cone: number?, -- direção do meio (radianos; -pi/2 = para cima)
	abertura: number?, -- leque (radianos)
	vmin: number?,
	vmax: number?,
	gravidade: number?, -- px/s²
	arrasto: number?, -- 1/s
	tam: number?, -- px do rastro
	z: number?,
	semente: number?,
}

-- uma explosão de `n` faíscas saindo de `centro` (px no espaço do pai)
function UiEfeitos.faiscas(pai: GuiObject, centro: Vector2, cor: Color3, n: number, op: OpcoesFaiscas?)
	if n <= 0 or UiEfeitos.calmo() then
		return
	end
	local o: OpcoesFaiscas = op or {}
	local g = o.gravidade or 520
	local k = o.arrasto or 2.6
	local base = o.tam or 26
	local z = o.z or 30
	local lista = Efeitos.faiscas(
		n,
		o.semente or math.floor(os.clock() * 1000),
		o.cone or -math.pi / 2,
		o.abertura or math.pi * 2,
		o.vmin or 260,
		o.vmax or 760
	)
	local claro = cor:Lerp(Color3.new(1, 1, 1), 0.55)
	local pecas: { GuiObject } = {}
	for i, p in lista do
		local q = peca(pai, if p.brilho then "brilho" else "faisca", if i % 3 == 0 then claro else cor, z)
		q.Visible = false
		pecas[i] = q
	end
	local t = 0
	roda(function(dt: number): boolean
		t += dt
		if not pai.Parent then
			return false
		end
		local vivas = 0
		for i, p in lista do
			local q = pecas[i]
			local tt = t - p.atraso
			local x, y, tr, esc = Efeitos.particula(p, tt, if p.brilho then g * 0.25 else g, k)
			if tt >= p.vida then
				if q.Parent then
					q:Destroy()
				end
				continue
			end
			vivas += 1
			if tt < 0 then
				continue
			end
			q.Visible = true
			q.Position = UDim2.fromOffset(centro.X + x, centro.Y + y)
			transp(q, tr)
			if p.brilho then
				local s = base * 0.9 * esc
				q.Size = UDim2.fromOffset(s, s)
			else
				local vel, rumo = Efeitos.rumo(p, tt, g, k)
				local comp = base * esc * (0.7 + math.min(1.6, vel / 400))
				q.Size = UDim2.fromOffset(comp, comp * 0.25)
				q.Rotation = rumo
			end
		end
		return vivas > 0
	end)
end

-- ===== onda de choque =====
function UiEfeitos.onda(pai: GuiObject, centro: Vector2, cor: Color3, raio: number, dur: number?, z: number?)
	if UiEfeitos.calmo() then
		return
	end
	local q = peca(pai, "anel", cor, z or 28)
	q.Position = UDim2.fromOffset(centro.X, centro.Y)
	local d = dur or 0.55
	local t = 0
	roda(function(dt: number): boolean
		t += dt
		if not q.Parent then
			return false
		end
		local u = math.clamp(t / d, 0, 1)
		local e = 1 - (1 - u) ^ 3
		local s = raio * 2 * (0.15 + 0.85 * e)
		q.Size = UDim2.fromOffset(s, s)
		transp(q, 0.3 + 0.7 * u) -- mais leve: no Studio o anel cheio pesava sobre a caixa abrindo
		if u >= 1 then
			q:Destroy()
			return false
		end
		return true
	end)
end

-- ===== raios de luz =====
-- `n` imagens de raio (cada uma dá dois raios opostos) girando em volta de `centro`; devolve o quadro
-- (apague-o para parar). `vel` em graus por segundo; com movimento reduzido ficam parados.
function UiEfeitos.raios(
	pai: GuiObject,
	centro: Vector2,
	cor: Color3,
	tamanho: number,
	n: number,
	vel: number,
	z: number?
): Frame
	local box = Instance.new("Frame")
	box.Name = "Raios"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromOffset(centro.X, centro.Y)
	box.Size = UDim2.fromOffset(tamanho, tamanho)
	box.ZIndex = z or 2
	box.Parent = pai
	local pecas: { GuiObject } = {}
	for i = 1, n do
		local q = peca(box, "raio", cor, z or 2)
		q.Position = UDim2.fromScale(0.5, 0.5)
		if q:IsA("ImageLabel") then
			q.Size = UDim2.new(1, 0, 0.25, 0)
		else
			q.Size = UDim2.new(1, 0, 0, math.max(2, math.floor(tamanho * 0.02)))
		end
		q.Rotation = (i - 1) * 180 / n + (if i % 2 == 0 then 7 else 0)
		transp(q, 0.15)
		pecas[i] = q
	end
	if not UiEfeitos.calmo() then
		local t = 0
		roda(function(dt: number): boolean
			if not box.Parent then
				return false
			end
			if not naTela(box) then
				return true
			end
			t += dt
			for i, q in pecas do
				-- os raios pares giram ao contrário, mais devagar (a luz parece viva)
				local s = if i % 2 == 0 then -0.6 else 1
				q.Rotation = (i - 1) * 180 / n + s * vel * t
				transp(q, 0.15 + 0.2 * (0.5 + 0.5 * math.sin(t * 2.1 + i)))
			end
			return true
		end)
	end
	return box
end

-- ===== halo =====
-- luz redonda atrás de uma peça; `pulso` (s) faz respirar entre a transparência `tr` e um pouco mais
function UiEfeitos.halo(
	pai: GuiObject,
	centro: UDim2,
	cor: Color3,
	tamanho: number,
	tr: number,
	pulso: number?,
	z: number?
): GuiObject
	local q = peca(pai, "brilho", cor, z or 1)
	q.Name = "Halo"
	q.Position = centro
	q.Size = UDim2.fromOffset(tamanho, tamanho)
	transp(q, tr)
	local periodo = pulso
	if periodo and not UiEfeitos.calmo() then
		local t = math.random() * periodo
		roda(function(dt: number): boolean
			if not q.Parent then
				return false
			end
			if not naTela(q) then
				return true
			end
			t += dt
			local base = q:GetAttribute("Tr")
			local b = if type(base) == "number" then base else tr
			transp(q, math.clamp(b + 0.25 * Efeitos.pulso(t, periodo), 0, 1))
			return true
		end)
	end
	return q
end

-- ===== cintilas =====
-- `n` brilhos de quatro pontas piscando em pontos ao acaso da `area` (um por vez em cada vaga), por
-- `dur` s (nil: enquanto a área existir)
function UiEfeitos.cintilas(area: GuiObject, cor: Color3, n: number, dur: number?, z: number?)
	if UiEfeitos.calmo() or n <= 0 then
		return
	end
	local vagas: { { q: GuiObject, t: number, vida: number } } = {}
	for i = 1, n do
		local q = peca(area, "cintila", cor:Lerp(Color3.new(1, 1, 1), 0.6), z or 32)
		q.Visible = false
		vagas[i] = { q = q, t = -(i - 1) * 0.18, vida = 0.5 }
	end
	local total = 0
	roda(function(dt: number): boolean
		if not area.Parent then
			return false
		end
		total += dt
		local acaba = dur ~= nil and total >= dur
		local vivas = 0
		for _, v in vagas do
			v.t += dt
			if v.t >= v.vida then
				if acaba then
					v.q.Visible = false
					continue
				end
				v.t = -math.random() * 0.35
				v.vida = 0.35 + math.random() * 0.35
				local s = area.AbsoluteSize
				v.q.Position = UDim2.fromScale(0.1 + math.random() * 0.8, 0.1 + math.random() * 0.8)
				local lado = math.max(10, math.min(s.X, s.Y) * (0.08 + math.random() * 0.1))
				v.q.Size = UDim2.fromOffset(lado, lado)
			end
			vivas += 1
			if v.t < 0 then
				v.q.Visible = false
				continue
			end
			v.q.Visible = true
			local u = v.t / v.vida
			transp(v.q, 1 - math.sin(math.pi * u))
			v.q.Rotation = u * 45
		end
		if acaba and vivas == 0 then
			for _, v in vagas do
				v.q:Destroy()
			end
			return false
		end
		return true
	end)
end

-- ===== varredura =====
-- a faixa clara diagonal que passa pelo cartão a cada `periodo` s (o cartão precisa de
-- ClipsDescendants). Devolve o quadro da faixa.
function UiEfeitos.varre(cartao: GuiObject, periodo: number, cor: Color3?, z: number?, atraso: number?): Frame?
	if UiEfeitos.calmo() then
		return nil
	end
	local f = Instance.new("Frame")
	f.Name = "Varredura"
	f.BackgroundColor3 = cor or Color3.new(1, 1, 1)
	f.BackgroundTransparency = 0
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.new(0.22, 0, 2.2, 0)
	f.Rotation = 18
	f.ZIndex = z or 4
	local gr = Instance.new("UIGradient")
	gr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	gr.Parent = f
	f.Position = UDim2.fromScale(-0.5, 0.5)
	f.Parent = cartao
	local t = -(atraso or 0)
	roda(function(dt: number): boolean
		if not f.Parent then
			return false
		end
		if not naTela(f) then
			return true
		end
		t += dt
		if t < 0 then
			return true
		end
		local x = Efeitos.varredura(t, periodo, 0.9)
		f.Position = UDim2.fromScale(0.5 + x * 0.5, 0.5)
		return true
	end)
	return f
end

-- ===== brasas =====
-- brasas subindo devagar dentro do `quadro` (em laço, enquanto ele existir)
function UiEfeitos.brasas(quadro: GuiObject, cor: Color3, n: number, semente: number, z: number?)
	if UiEfeitos.calmo() or n <= 0 then
		return
	end
	local lista = Efeitos.brasas(n, semente)
	local pecas: { GuiObject } = {}
	for i, b in lista do
		local q = peca(quadro, "brilho", cor, z or 3)
		local s = math.floor(10 * b.tam + 0.5)
		q.Size = UDim2.fromOffset(s, s)
		pecas[i] = q
	end
	local t = math.random() * 10
	roda(function(dt: number): boolean
		if not quadro.Parent then
			return false
		end
		if not naTela(quadro) then
			return true
		end
		t += dt
		for i, b in lista do
			local x, y, tr = Efeitos.brasa(b, t)
			local q = pecas[i]
			q.Position = UDim2.fromScale(x, y)
			transp(q, 0.25 + 0.75 * tr)
		end
		return true
	end)
end

-- ===== tranco e clarão =====
-- sacode o quadro em volta da posição de agora por `dur` s (`forca` em px), e volta ao lugar
function UiEfeitos.tremer(o: GuiObject, dur: number, forca: number)
	if UiEfeitos.calmo() then
		return
	end
	local base = o:GetAttribute("TremerBase")
	local p0: UDim2 = if typeof(base) == "UDim2" then base else o.Position
	o:SetAttribute("TremerBase", p0)
	local t = 0
	roda(function(dt: number): boolean
		t += dt
		if not o.Parent then
			return false
		end
		if t >= dur then
			o.Position = p0
			o:SetAttribute("TremerBase", nil)
			return false
		end
		local a = forca * (1 - t / dur) ^ 2
		o.Position = p0
			+ UDim2.fromOffset(math.floor(a * math.sin(t * 71) + 0.5), math.floor(a * 0.7 * math.cos(t * 59) + 0.5))
		return true
	end)
end

-- clarão sobre o pai inteiro: aparece com `forca` (0 a 1) e some em `dur` s
function UiEfeitos.clarao(pai: Instance, cor: Color3, forca: number, dur: number, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Clarao"
	f.BackgroundColor3 = cor
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1 - math.clamp(forca, 0, 1)
	f.ZIndex = z or 40
	f.Parent = pai
	local tw = TweenService:Create(f, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	tw.Completed:Once(function()
		f:Destroy()
	end)
	tw:Play()
	return f
end

return UiEfeitos
