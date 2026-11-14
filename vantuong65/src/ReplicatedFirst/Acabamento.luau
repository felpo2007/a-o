--!strict
-- Acabamento de época compartilhado pelas telas (pedido do dono, 2026-11-11: "melhore a qualidade
-- gráfica das animações e telas ... mais fluido ... com maestria", realismo de 1965, nada de
-- cartoon). Fica no ReplicatedFirst porque a tela de entrada (LoadingScreen) roda antes de tudo; os
-- Controllers também usam (LobbyScene, DeployScreen, SpawnTransition).
-- Sem asset novo: só texturas que vêm com o cliente do Roblox (conferidas na pasta content\textures
-- de duas versões do RobloxPlayer instaladas, 2026-11-11):
--   - loading/loadingvignette.png: vinheta preta 16:9 (alfa 4 no centro, 176 na borda do meio);
--   - ui/InGameMenu/BackgroundGlow@3x.png: luz branca radial e fraca (alfa 38 no centro), tingida
--     de âmbar vira a luz do lampião;
--   - ui/Lobby/Buttons/glow_nine_slice.png: borda macia em 9-slice (64 px de queda), tingida de
--     preto vira a sombra de um papel.
-- Peças:
--   - filme(): vinheta, grão (pontos que mudam a 24 quadros por segundo, como a película), poeira,
--     riscos verticais que derivam, tremor de luz do projetor e luz quente de lampião;
--   - sombra(): sombra macia sob um papel (irmã do alvo, segue posição, tamanho e giro);
--   - datilografar(): texto de máquina de escrever (MaxVisibleGraphemes por tween);
--   - linha() / tracar(): linha de avanço a lápis que se desenha e depois "corre" (onda de tinta);
--   - marca() / pulsar(): marca de ponto de inserção piscando (ponto e anel de radar).
-- Desempenho: tudo é criado uma vez. Por quadro só a vinheta e a luz de cada filme ligado (duas
-- propriedades); o grão anda a 24 Hz (posição e transparência de umas 40 peças); o resto são tweens
-- do motor. Nenhuma instância é criada depois da montagem.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Acabamento = {}

Acabamento.VINHETA = "rbxasset://textures/loading/loadingvignette.png"
Acabamento.LUZ = "rbxasset://textures/ui/InGameMenu/BackgroundGlow@3x.png"
Acabamento.SOMBRA = "rbxasset://textures/ui/Lobby/Buttons/glow_nine_slice.png"
local SOMBRA_MEIO = Rect.new(64, 64, 92, 92) -- platô do 9-slice (imagem de 156 x 156)
local SOMBRA_QUEDA = 64 -- px da queda macia na imagem

local CLARO = Color3.fromRGB(230, 220, 190) -- grão claro (emulsão)
local AMBAR = Color3.fromRGB(255, 172, 92) -- chama de querosene
local rng = Random.new()

-- ===== filme =====
export type FilmeOpcoes = {
	vinheta: number?, -- 0..1: opacidade da vinheta (padrão 0,85)
	grao: number?, -- 0..1: força do grão e da poeira (padrão 0,5)
	poeira: number?, -- quantos pontos de grão (padrão 28)
	riscos: number?, -- riscos verticais (padrão 2)
	tremor: number?, -- 0..1: tremor de luz do projetor (padrão 0,5)
	lampiao: number?, -- 0..1: luz quente (padrão 0: apagada)
	z: number?, -- ZIndex da camada (padrão 50)
}

export type Filme = {
	raiz: Frame,
	vinheta: ImageLabel,
	lampiao: ImageLabel,
	nucleo: ImageLabel, -- miolo mais quente da luz (a textura é fraca: duas camadas)
	nivel: NumberValue, -- 0..1: força geral (tween para entrar e sair)
	ativo: boolean,
	luz: number, -- intensidade da luz quente pedida por quem usa, antes do tremor da chama
	pontos: { Frame },
	riscos: { Frame },
	riscoX: { number },
	manchas: { Frame },
	tremor: Frame,
	forcaVinheta: number,
	forcaGrao: number,
	forcaTremor: number,
	proximo: number,
	semente: number,
	token: number,
}

local filmes: { Filme } = {}

local function camada(parent: Instance, z: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- nada desta camada recebe clique nem tapa o cursor virtual (Active fica falso)
local function inerte(o: GuiObject)
	pcall(function()
		o.Interactable = false
	end)
end

function Acabamento.filme(parent: Instance, o: FilmeOpcoes?): Filme
	local op: FilmeOpcoes = o or {}
	local z = op.z or 50
	local raiz = Instance.new("Frame")
	raiz.Name = "Filme"
	raiz.BackgroundTransparency = 1
	raiz.Size = UDim2.fromScale(1, 1)
	raiz.ZIndex = z
	raiz.Visible = false
	inerte(raiz)

	-- luz quente: duas manchas radiais tingidas de âmbar (halo largo e miolo)
	local lamp = Instance.new("ImageLabel")
	lamp.Name = "Lampiao"
	lamp.BackgroundTransparency = 1
	lamp.Image = Acabamento.LUZ
	lamp.ImageColor3 = AMBAR
	lamp.ImageTransparency = 1
	lamp.AnchorPoint = Vector2.new(0.5, 0.5)
	lamp.Position = UDim2.fromScale(0.2, 0.15)
	lamp.SizeConstraint = Enum.SizeConstraint.RelativeYY
	lamp.Size = UDim2.fromScale(1.6, 1.6)
	lamp.ZIndex = z
	lamp.Parent = raiz
	local core = lamp:Clone()
	core.Name = "Miolo"
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.SizeConstraint = Enum.SizeConstraint.RelativeXY
	core.Size = UDim2.fromScale(0.5, 0.5)
	core.ImageColor3 = Color3.fromRGB(255, 206, 140)
	core.Parent = lamp

	local vin = Instance.new("ImageLabel")
	vin.Name = "Vinheta"
	vin.BackgroundTransparency = 1
	vin.Image = Acabamento.VINHETA
	vin.ImageColor3 = Color3.new(0, 0, 0)
	vin.ScaleType = Enum.ScaleType.Stretch
	vin.Size = UDim2.fromScale(1, 1)
	vin.ImageTransparency = 1
	vin.ZIndex = z + 1
	vin.Parent = raiz

	local tremor = camada(raiz, z + 2)
	tremor.Name = "Tremor"
	tremor.BackgroundColor3 = Color3.new(0, 0, 0)

	local pontos: { Frame } = {}
	for i = 1, op.poeira or 28 do
		local p = Instance.new("Frame")
		p.Name = "Grao"
		p.BorderSizePixel = 0
		p.BackgroundColor3 = if i % 3 == 0 then Color3.new(0, 0, 0) else CLARO
		p.BackgroundTransparency = 1
		p.Size = UDim2.fromOffset(1 + i % 3, 1 + (i * 7) % 2)
		p.ZIndex = z + 3
		p.Parent = raiz
		table.insert(pontos, p)
	end
	local riscos: { Frame } = {}
	local riscoX: { number } = {}
	for _ = 1, op.riscos or 2 do
		local r = Instance.new("Frame")
		r.Name = "Risco"
		r.BorderSizePixel = 0
		r.BackgroundColor3 = CLARO
		r.BackgroundTransparency = 1
		r.Size = UDim2.new(0, 1, 1, 0)
		r.ZIndex = z + 3
		r.Parent = raiz
		table.insert(riscos, r)
		table.insert(riscoX, rng:NextNumber(0.1, 0.9))
	end
	local manchas: { Frame } = {}
	for i = 1, 2 do
		local m = Instance.new("Frame")
		m.Name = "Mancha"
		m.BorderSizePixel = 0
		m.BackgroundColor3 = if i == 1 then Color3.new(0, 0, 0) else CLARO
		m.BackgroundTransparency = 1
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = m
		m.ZIndex = z + 3
		m.Parent = raiz
		table.insert(manchas, m)
	end

	local nivel = Instance.new("NumberValue")
	nivel.Value = 0
	local f: Filme = {
		raiz = raiz,
		vinheta = vin,
		lampiao = lamp,
		nucleo = core,
		nivel = nivel,
		ativo = false,
		luz = op.lampiao or 0,
		pontos = pontos,
		riscos = riscos,
		riscoX = riscoX,
		manchas = manchas,
		tremor = tremor,
		forcaVinheta = op.vinheta or 0.85,
		forcaGrao = op.grao or 0.5,
		forcaTremor = op.tremor or 0.5,
		proximo = 0,
		semente = rng:NextNumber(0, 100),
		token = 0,
	}
	raiz.Parent = parent
	table.insert(filmes, f)
	raiz.Destroying:Connect(function() -- tela destruída: o laço do grão esquece este filme
		f.ativo = false
		local i = table.find(filmes, f)
		if i then
			table.remove(filmes, i)
		end
	end)
	return f
end

-- Liga ou desliga o filme esmaecendo (tempo em s; 0 = na hora).
function Acabamento.ligar(f: Filme, on: boolean, tempo: number?)
	f.token += 1
	local my = f.token
	local t = tempo or 0.4
	if on then
		f.ativo = true
		f.raiz.Visible = true
	end
	if t <= 0 then
		f.nivel.Value = if on then 1 else 0
		if not on then
			f.ativo = false
			f.raiz.Visible = false
		end
		return
	end
	local tw = TweenService:Create(
		f.nivel,
		TweenInfo.new(t, Enum.EasingStyle.Sine, if on then Enum.EasingDirection.Out else Enum.EasingDirection.In),
		{ Value = if on then 1 else 0 }
	)
	if not on then
		tw.Completed:Once(function()
			if f.token == my then
				f.ativo = false
				f.raiz.Visible = false
			end
		end)
	end
	tw:Play()
end

-- Onde fica a luz quente (posição na camada), o tamanho (fração da altura da tela) e a força.
function Acabamento.luz(f: Filme, pos: UDim2?, tamanho: number?, intensidade: number?)
	if pos then
		f.lampiao.Position = pos
	end
	if tamanho then
		f.lampiao.Size = UDim2.fromScale(tamanho, tamanho)
	end
	if intensidade then
		f.luz = intensidade
	end
end

-- um quadro de película (24 por segundo): grão, riscos e manchas novos, luz do projetor
local function pelicula(f: Filme, k: number)
	local g = f.forcaGrao * k
	for _, p in f.pontos do
		p.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
		p.BackgroundTransparency = 1 - g * rng:NextNumber(0.2, 0.65)
	end
	for i, r in f.riscos do
		-- o risco é do filme: fica no mesmo lugar por vários quadros, derivando, e some e volta
		local x = f.riscoX[i] + rng:NextNumber(-0.003, 0.003)
		if rng:NextNumber() < 0.025 or x < 0.03 or x > 0.97 then
			x = rng:NextNumber(0.06, 0.94)
		end
		f.riscoX[i] = x
		r.Position = UDim2.fromScale(x, 0)
		r.BackgroundTransparency = if rng:NextNumber() < 0.5 then 1 - g * rng:NextNumber(0.12, 0.35) else 1
	end
	for _, m in f.manchas do
		if rng:NextNumber() < 0.05 then
			local s = rng:NextInteger(3, 6)
			m.Size = UDim2.fromOffset(s, s + rng:NextInteger(-1, 2))
			m.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
			m.BackgroundTransparency = 1 - g * 0.55
		else
			m.BackgroundTransparency = 1
		end
	end
	f.tremor.BackgroundTransparency = 1 - f.forcaTremor * k * rng:NextNumber(0.008, 0.06)
end

RunService.Heartbeat:Connect(function()
	if #filmes == 0 then
		return
	end
	local agora = os.clock()
	for _, f in filmes do
		if not f.ativo then
			continue
		end
		local k = f.nivel.Value
		f.vinheta.ImageTransparency = 1 - f.forcaVinheta * k
		local luz = f.luz * k
		if luz > 0.001 then
			-- chama de querosene: respira devagar e treme um pouco
			local n = math.noise(agora * 1.7, f.semente) + 0.35 * math.noise(agora * 7.3, f.semente + 9)
			local a = math.clamp(luz * (0.88 + 0.3 * n), 0, 1)
			f.lampiao.ImageTransparency = 1 - a
			f.nucleo.ImageTransparency = 1 - a * 0.9
		else
			f.lampiao.ImageTransparency = 1
			f.nucleo.ImageTransparency = 1
		end
		if agora >= f.proximo then
			f.proximo = agora + 1 / 24
			pelicula(f, k)
		end
	end
end)

-- ===== sombra de papel =====
-- Sombra macia sob `alvo` (irmã dele, logo abaixo). raio = px da queda; desloc = luz vindo de cima;
-- forca = opacidade no miolo. Segue posição, tamanho, âncora, giro e visibilidade do alvo, e a
-- escala do UIScale dele (o realce que "levanta" o papel): o papel que cresce se afasta da mesa,
-- então a sombra cresce junto e se desloca mais.
-- Não use dentro de UIListLayout/UIGridLayout (a sombra entraria na fila).
function Acabamento.sombra(alvo: GuiObject, raio: number?, desloc: Vector2?, forca: number?): ImageLabel
	local r = raio or 16
	local d = desloc or Vector2.new(0, 6)
	local s = Instance.new("ImageLabel")
	s.Name = "Sombra"
	s.BackgroundTransparency = 1
	s.Image = Acabamento.SOMBRA
	s.ImageColor3 = Color3.new(0, 0, 0)
	s.ImageTransparency = 1 - (forca or 0.5)
	s.ScaleType = Enum.ScaleType.Slice
	s.SliceCenter = SOMBRA_MEIO
	s.SliceScale = r / SOMBRA_QUEDA
	s.ZIndex = alvo.ZIndex - 1
	inerte(s)
	local escala: UIScale? = alvo:FindFirstChildOfClass("UIScale")
	local function sync()
		local a = alvo.AnchorPoint
		local k = if escala then escala.Scale else 1
		local lift = 1 + math.max(k - 1, 0) * 10 -- 1,03 de escala: sombra 30% mais longe
		local dx, dy = d.X * lift, d.Y * lift
		local sz = alvo.Size
		s.AnchorPoint = a
		-- a caixa da sombra é o alvo (escalado pela âncora, como o UIScale faz) com r px de folga
		-- em volta, deslocada por d
		s.Position = alvo.Position + UDim2.fromOffset(dx + r * (2 * a.X - 1), dy + r * (2 * a.Y - 1))
		s.Size = UDim2.new(sz.X.Scale * k, sz.X.Offset * k + 2 * r, sz.Y.Scale * k, sz.Y.Offset * k + 2 * r)
		s.Rotation = alvo.Rotation
		s.Visible = alvo.Visible
	end
	local function watchScale(u: UIScale)
		escala = u
		u:GetPropertyChangedSignal("Scale"):Connect(sync)
		sync()
	end
	if escala then
		watchScale(escala)
	end
	alvo.ChildAdded:Connect(function(c: Instance)
		if not escala and c:IsA("UIScale") then
			watchScale(c)
		end
	end)
	sync()
	for _, prop in { "Position", "Size", "AnchorPoint", "Rotation", "Visible" } do
		alvo:GetPropertyChangedSignal(prop):Connect(sync)
	end
	alvo:GetPropertyChangedSignal("Parent"):Connect(function()
		s.Parent = alvo.Parent
	end)
	s.Parent = alvo.Parent
	return s
end

-- ===== máquina de escrever =====
-- Mostra o texto letra a letra (cps = letras por segundo). Devolve o tween (quem quiser espera o
-- Completed). Terminado, o limite sai (-1): trocar o texto depois não corta nada.
-- D-84: a tradução (Traducao.client) troca o texto logo depois de escrito, com outro tamanho; as
-- letras visíveis saem da fração do tempo sobre o texto que está no rótulo, não do português.
local typing: { [TextLabel]: number } = setmetatable({}, { __mode = "k" }) :: any
local function graphemes(l: TextLabel): number
	local t = l.Text
	local plain = if l.RichText then string.gsub(t, "<[^>]+>", "") else t -- as marcas não contam
	return utf8.len(plain) or #plain
end
function Acabamento.datilografar(l: TextLabel, texto: string, cps: number?, atraso: number?): Tween
	l.Text = texto
	l.MaxVisibleGraphemes = 0
	local token = (typing[l] or 0) + 1
	typing[l] = token
	local plain = if l.RichText then string.gsub(texto, "<[^>]+>", "") else texto
	local n = utf8.len(plain) or #plain
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	progress.Changed:Connect(function(v: number)
		if typing[l] == token then
			l.MaxVisibleGraphemes = math.floor(v * graphemes(l) + 0.5)
		end
	end)
	local tw = TweenService:Create(
		progress,
		TweenInfo.new(
			math.max(n / (cps or 45), 0.05),
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out,
			0,
			false,
			atraso or 0
		),
		{ Value = 1 }
	)
	tw.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and typing[l] == token then
			l.MaxVisibleGraphemes = -1
		end
		progress:Destroy()
	end)
	tw:Play()
	return tw
end

-- Palavras com letra vietnamita no Arimo (a SpecialElite não tem Ư, ờ, ạ...): devolve RichText.
-- Ligue RichText no rótulo. O texto não pode ter < > & (marque depois: viet primeiro, tags depois).
-- Só as letras de U+0100 a U+1FFF (bytes iniciais C4 a E1: Đ, Ư, ơ, ạ, ờ...); o latim-1 (é, ç, ã) e
-- os símbolos (…, ►, ◎, de E2 em diante) ficam na fonte do rótulo.
function Acabamento.viet(texto: string): string
	local out = string.gsub(texto, "(%S*[\196-\225][\128-\191]+%S*)", '<font face="Arimo">%1</font>')
	return out
end

-- ===== linha de avanço (lápis de cera na carta) =====
-- Em coordenadas de escala (u, v) de um pai QUADRADO (a carta). Feita de trechos encostados: o
-- traço cresce do começo ao fim (velocidade em Sine InOut, como a mão), a ponta de seta aparece e
-- uma onda de tinta corre pela linha enquanto ela estiver na tela.
export type Linha = {
	partes: { Frame },
	asas: { Frame },
	px: number,
	base: number, -- transparência de projeto
	tweens: { Tween },
	geracao: number,
}

function Acabamento.linha(parent: Instance, cor: Color3, px: number, partes: number?, z: number?): Linha
	local l: Linha = { partes = {}, asas = {}, px = px, base = 0.08, tweens = {}, geracao = 0 }
	local function trecho(): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = cor
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Size = UDim2.fromOffset(0, px)
		f.ZIndex = z or 3
		f.Parent = parent
		return f
	end
	for _ = 1, partes or 16 do
		table.insert(l.partes, trecho())
	end
	for _ = 1, 2 do
		table.insert(l.asas, trecho())
	end
	return l
end

local function pararLinha(l: Linha)
	for _, t in l.tweens do
		t:Cancel()
	end
	table.clear(l.tweens)
end

-- Desenha a linha de (u1, v1) até (u2, v2) em `tempo` s, depois de `atraso` s.
function Acabamento.tracar(l: Linha, u1: number, v1: number, u2: number, v2: number, tempo: number, atraso: number?)
	pararLinha(l)
	l.geracao += 1
	local g = l.geracao
	local n = #l.partes
	local du, dv = u2 - u1, v2 - v1
	local ang = math.deg(math.atan2(dv, du))
	local d0 = atraso or 0
	for i, p in l.partes do
		local a0, a1 = (i - 1) / n, i / n
		local e0 = TweenService:GetValue(a0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local e1 = TweenService:GetValue(a1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local su, sv = u1 + du * a0, v1 + dv * a0
		local eu, ev = u1 + du * a1, v1 + dv * a1
		local len = math.sqrt((eu - su) ^ 2 + (ev - sv) ^ 2)
		-- o centro do trecho anda junto com a largura: o começo fica parado (o giro é pelo centro)
		p.Rotation = ang
		p.Position = UDim2.fromScale(su, sv)
		p.Size = UDim2.fromOffset(0, l.px)
		p.BackgroundTransparency = l.base
		local tw = TweenService:Create(
			p,
			TweenInfo.new(
				math.max(tempo * (e1 - e0), 0.01),
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.Out,
				0,
				false,
				d0 + tempo * e0
			),
			{ Position = UDim2.fromScale((su + eu) / 2, (sv + ev) / 2), Size = UDim2.new(len, 1, 0, l.px) }
		)
		tw:Play()
		table.insert(l.tweens, tw)
	end
	-- ponta de seta: duas asas de 4,5% da carta, abertas 30° para trás
	local a = math.atan2(dv, du)
	local wl = 0.045
	for k, asa in l.asas do
		local b = a + math.pi + (if k == 1 then 0.52 else -0.52)
		local cu, cv = u2 + math.cos(b) * wl / 2, v2 + math.sin(b) * wl / 2
		asa.Rotation = math.deg(b)
		asa.Position = UDim2.fromScale(cu, cv)
		asa.Size = UDim2.new(wl, 1, 0, l.px)
		asa.BackgroundTransparency = 1
		local tw = TweenService:Create(
			asa,
			TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, d0 + tempo),
			{ BackgroundTransparency = l.base }
		)
		tw:Play()
		table.insert(l.tweens, tw)
	end
	-- onda de tinta: cada trecho clareia e escurece, com a fase andando do começo para a ponta
	for i, p in l.partes do
		local tw = TweenService:Create(
			p,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = math.min(l.base + 0.45, 1) }
		)
		table.insert(l.tweens, tw)
		task.delay(d0 + tempo + 0.25 + i * 0.045, function()
			if l.geracao == g then
				tw:Play()
			end
		end)
	end
end

-- Some com a linha (fim da tela).
function Acabamento.apagar(l: Linha)
	pararLinha(l)
	l.geracao += 1
	for _, p in l.partes do
		p.BackgroundTransparency = 1
	end
	for _, p in l.asas do
		p.BackgroundTransparency = 1
	end
end

-- ===== marca piscando (ponto de inserção, objetivo) =====
export type Marca = {
	raiz: Frame,
	ponto: Frame,
	aneis: { Frame },
	tracos: { UIStroke },
	tweens: { Tween },
	geracao: number,
}

local function circulo(parent: Instance, cor: Color3, z: number): (Frame, UIStroke)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.ZIndex = z
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = 2
	s.Transparency = 1
	s.Parent = f
	f.Parent = parent
	return f, s
end

-- px = diâmetro da marca (o anel de radar abre até ~2,2x)
function Acabamento.marca(parent: Instance, cor: Color3, px: number, z: number?): Marca
	local zz = z or 4
	local raiz = Instance.new("Frame")
	raiz.Name = "Marca"
	raiz.AnchorPoint = Vector2.new(0.5, 0.5)
	raiz.Size = UDim2.fromOffset(px, px)
	raiz.BackgroundTransparency = 1
	raiz.ZIndex = zz
	raiz.Parent = parent
	local fixo, fs = circulo(raiz, cor, zz)
	fixo.Name = "Anel"
	fs.Transparency = 0.1
	fs.Thickness = math.max(2, px / 10)
	local ponto = Instance.new("Frame")
	ponto.Name = "Ponto"
	ponto.AnchorPoint = Vector2.new(0.5, 0.5)
	ponto.Position = UDim2.fromScale(0.5, 0.5)
	ponto.Size = UDim2.fromScale(0.34, 0.34)
	ponto.BackgroundColor3 = cor
	ponto.BorderSizePixel = 0
	ponto.ZIndex = zz + 1
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = ponto
	ponto.Parent = raiz
	local aneis: { Frame } = {}
	local tracos: { UIStroke } = {}
	for _ = 1, 2 do
		local a, s = circulo(raiz, cor, zz)
		table.insert(aneis, a)
		table.insert(tracos, s)
	end
	return { raiz = raiz, ponto = ponto, aneis = aneis, tracos = tracos, tweens = {}, geracao = 0 }
end

-- Liga ou desliga o piscar (anéis de radar abrindo e o ponto piscando). Desligada, a marca fica
-- parada e visível.
function Acabamento.pulsar(m: Marca, on: boolean)
	for _, t in m.tweens do
		t:Cancel()
	end
	table.clear(m.tweens)
	m.geracao += 1
	local g = m.geracao
	for i, a in m.aneis do
		a.Size = UDim2.fromScale(1, 1)
		m.tracos[i].Transparency = 1
	end
	m.ponto.BackgroundTransparency = 0
	if not on then
		return
	end
	local blink = TweenService:Create(
		m.ponto,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.7 }
	)
	blink:Play()
	table.insert(m.tweens, blink)
	local ciclo = 1.6
	for i, a in m.aneis do
		local info = TweenInfo.new(ciclo, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, -1)
		local t1 = TweenService:Create(a, info, { Size = UDim2.fromScale(2.4, 2.4) })
		local t2 = TweenService:Create(m.tracos[i], info, { Transparency = 1 })
		table.insert(m.tweens, t1)
		table.insert(m.tweens, t2)
		task.delay((i - 1) * ciclo / 2, function()
			if m.geracao == g then
				m.tracos[i].Transparency = 0.15
				t1:Play()
				t2:Play()
			end
		end)
	end
end

return Acabamento
