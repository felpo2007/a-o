--!strict
-- Palco do lobby (D-206; prompt de interface §6 e as referências do dono, 2026-11-20: "quero q vc se
-- baseie nas imagens para criar o lobby ... transições de qualidade"). Das referências vem a
-- composição: o soldado grande, de pé, na luz, à direita do centro; a navegação à esquerda, no escuro.
-- A identidade é deste jogo: um acampamento de 1965 ao fim da tarde.
--   - EUA: barraca de comando com lampião, barraca de lona, caixas de munição, rádio de campanha,
--     sacos de areia, galões, tambores, o M151, o mastro e o UH-34D pousado ao longe, entre coqueiros;
--   - VC: abrigo de folha, rede, armário de armas, caixote, sacos de arroz, lamparina de barro e a
--     cozinha Hoàng Cầm, entre bambus e bananeiras.
-- O soldado é o do próprio jogador (PreviewService.pessoal: cosméticos, skins e a arma do último papel,
-- na PlayerGui.VT65MeuSoldado); sem ele ainda, o manequim do lado.
-- Tudo local (peças criadas no cliente e cópias de VT65Preview.Props), longe do mapa, e só no Workspace
-- com o palco aberto. A luz: o sol real do fim da tarde (o MenuPrincipal acerta a hora) atrás e à
-- direita do soldado, uma luz principal quente do lado da câmera e o lampião.
-- Câmera: enquadramentos por tela (LobbyPalco.enquadrar), em curva suave de 0,55 s (corta com
-- movimento reduzido); na abertura, a câmera desce num travelling curto e a luz principal acende.
-- Girar o soldado: arrastar com o mouse ou o dedo fora dos botões, ou o analógico direito; volta de
-- frente sozinho depois de 8 s parado.
-- Estúdio: workspace "VT65DevPalco" = "US" ou "VC" força o lado do acampamento.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local JogarAgora = require(ReplicatedStorage.Shared.JogarAgora) :: any
local SoldierPreview = require(script.Parent.SoldierPreview)
local UiKit = require(script.Parent.UiKit)

local LobbyPalco = {}
local player = Players.LocalPlayer
local Estilo = UiKit.Estilo

local M = MapConfig.STUD_M -- 0,28 m por stud
local B = MapConfig.Bounds
-- longe do mapa e das cenas da mesa (LobbyScene fica do lado +Z)
local BASE = Vector3.new((B.minX + B.maxX) / 2, 2600, B.minZ - 3600)
local MOVE_S = 0.55 -- s de um enquadramento a outro
local ARRIVE_S = 1.7 -- s do travelling de chegada
local VOLTA_S = 8 -- s parado até o soldado voltar de frente

-- ===== enquadramentos (metros, no quadro do palco: soldado na origem, câmera do lado +Z) =====
-- cam: onde a câmera fica; alvo: o ponto do soldado enquadrado; y: a altura do alvo na tela (0 em
-- cima, 1 embaixo). A posição na horizontal não é fixa: o alvo vai para LobbyPalco.telaX (o meio do
-- espaço livre entre as colunas do menu, medido na tela; no Studio, com a janela estreita, a coluna
-- da direita cobria o soldado). x: força uma posição (as telas largas da loja e do passe).
export type Quadro = { cam: Vector3, alvo: Vector3, fov: number, y: number, x: number? }
local QUADROS: { [string]: Quadro } = {
	-- de corpo inteiro, de três quartos, um pouco de baixo (a figura de herói das referências)
	inicio = { cam = Vector3.new(-0.95, 1.3, 4.4), alvo = Vector3.new(0, 1.12, 0), fov = 36, y = 0.52 },
	jogar = { cam = Vector3.new(-0.75, 1.32, 3.7), alvo = Vector3.new(0, 1.18, 0), fov = 35, y = 0.5 },
	-- (no Studio, a 2,25 m a arma enchia a tela e, a 1,55 m, o rosto: o soldado tem 2,2 m e a frente
	-- dele fica ~0,4 m adiante da origem)
	arsenal = { cam = Vector3.new(-0.75, 1.3, 3.2), alvo = Vector3.new(0.05, 1.05, 0), fov = 34, y = 0.5 },
	missoes = { cam = Vector3.new(-1.8, 1.8, 4.7), alvo = Vector3.new(0, 1.12, 0), fov = 36, y = 0.52 },
	perfil = { cam = Vector3.new(-0.5, 1.7, 2.8), alvo = Vector3.new(0, 1.5, 0), fov = 32, y = 0.46 },
	-- loja e passe: o soldado no canto direito, para os painéis largos (lotes da loja e do passe)
	loja = { cam = Vector3.new(-1.0, 1.35, 4.8), alvo = Vector3.new(0, 1.12, 0), fov = 36, y = 0.52, x = 0.82 },
	passe = { cam = Vector3.new(-1.35, 1.5, 4.6), alvo = Vector3.new(0, 1.15, 0), fov = 36, y = 0.52, x = 0.82 },
}
QUADROS.config = QUADROS.inicio
QUADROS.tutorial = QUADROS.jogar
LobbyPalco.QUADROS = QUADROS
-- de onde a câmera chega (mais alta e mais longe)
local CHEGADA: Quadro = { cam = Vector3.new(-1.9, 2.7, 8.0), alvo = Vector3.new(0, 1.3, 0), fov = 40, y = 0.5 }
-- onde o alvo fica na horizontal (0 a 1), posto pelo menu
LobbyPalco.telaX = 0.56

-- ===== estado =====
local root: Model? = nil -- o palco (fora do Workspace quando fechado)
local sets: { [string]: Model } = {}
local setAtual: string? = nil
local soldado: SoldierPreview.Preview? = nil
local aberto = false
local yawPalco = 0 -- giro do palco no mundo (o sol atrás e à direita do soldado)
local quadroAtual = "inicio"
local camDe: Quadro = QUADROS.inicio
local camPara: Quadro = QUADROS.inicio
local camT0 = 0
local camDur = MOVE_S
local girar = 0 -- giro do soldado (rad), alvo e atual
local girarAtual = 0
local ultimoGiro = 0
local stickX = 0
local arrastando: InputObject? = nil
local arrasteX = 0
local luzes: { key: SpotLight?, lampiao: { PointLight }, fill: PointLight? } = { key = nil, lampiao = {}, fill = nil }
local poeira: ParticleEmitter? = nil
local dof: DepthOfFieldEffect? = nil
local cor: ColorCorrectionEffect? = nil
local fonte: Model? = nil -- o soldado do jogador (PlayerGui) que está no palco agora

LobbyPalco.podeGirar = function(): boolean
	return true
end

-- ===== peças =====
local function baseCF(): CFrame
	return CFrame.new(BASE) * CFrame.Angles(0, yawPalco, 0)
end
local function W(x: number, y: number, z: number): Vector3
	return Vector3.new(x / M, y / M, z / M)
end
local function part(
	parent: Instance,
	size: Vector3, -- metros
	cf: CFrame, -- no quadro do palco, em studs
	color: Color3,
	mat: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if shape then
		p.Shape = shape -- antes do tamanho (a forma não pode reajustar o tamanho depois)
	end
	p.Size = size / M
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function at(x: number, y: number, z: number, yawDeg: number?): CFrame
	return CFrame.new(W(x, y, z)) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
end

-- modelo publicado (VT65Preview.Props), só quando chegou inteiro
local function propSrc(key: string): Model?
	local f = ReplicatedStorage:FindFirstChild("VT65Preview")
	local props = f and f:FindFirstChild("Props")
	local m = props and props:FindFirstChild(key)
	if not (m and m:IsA("Model")) then
		return nil
	end
	local want = m:GetAttribute("Parts")
	if type(want) == "number" then
		local n = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		if n < want then
			return nil
		end
	end
	return m
end

-- lugar de um modelo publicado no palco: posto quando ele chega (pode chegar depois de montar)
type Vaga = { key: string, holder: Model, cf: CFrame, sobre: string?, feito: boolean }
local vagas: { Vaga } = {}
local function vaga(holder: Model, key: string, cf: CFrame, sobre: string?)
	table.insert(vagas, { key = key, holder = holder, cf = cf, sobre = sobre, feito = false })
end
local function preencher()
	for _, v in vagas do
		if not v.feito then
			local src = propSrc(v.key)
			if src then
				local m = src:Clone()
				m.Name = v.key
				local cf = v.cf
				-- empilhado: em cima da caixa da vaga de baixo
				if v.sobre then
					local baixo = v.holder:FindFirstChild(v.sobre)
					if baixo and baixo:IsA("Model") then
						local bcf, bs = baixo:GetBoundingBox()
						local local0 = v.holder:GetPivot():ToObjectSpace(bcf)
						cf = CFrame.new(cf.Position.X, local0.Position.Y + bs.Y / 2, cf.Position.Z) * cf.Rotation
					else
						continue
					end
				end
				m:PivotTo(v.holder:GetPivot() * cf)
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanQuery = false
						d.CanTouch = false
					end
				end
				m.Parent = v.holder
				v.feito = true
			end
		end
	end
end

-- ===== o chão e o horizonte =====
local function chao(holder: Model, cor0: Color3, cor1: Color3, mat: Enum.Material)
	-- 4 placas de 2048 studs (o máximo de uma peça) em volta: a névoa do céu esconde a borda
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local p =
			part(holder, Vector3.new(2048 * M, 1, 2048 * M), CFrame.new(o[1] * 1024, -0.5 / M, o[2] * 1024), cor0, mat)
		p.Name = "Chao"
	end
	-- manchas de terra batida perto do soldado (o chão não fica liso)
	local rng = Random.new(65)
	for i = 1, 26 do
		local x, z = rng:NextNumber(-14, 14), rng:NextNumber(-22, 4)
		local s = rng:NextNumber(1.2, 4.2)
		-- disco achatado (cilindro deitado em X, girado para ficar de pé em Y)
		local p = part(
			holder,
			Vector3.new(0.04, s, s),
			at(x, -0.01 + i * 0.0004, z, rng:NextNumber(0, 180)) * CFrame.Angles(0, 0, math.rad(90)),
			cor1:Lerp(cor0, rng:NextNumber(0, 0.5)),
			Enum.Material.Ground,
			Enum.PartType.Cylinder
		)
		p.Name = "Mancha"
	end
end

-- lampião (EUA) ou lamparina (VC): a luz quente do fundo, com a chama tremendo
local function lampiao(holder: Model, x: number, y: number, z: number, vc: boolean)
	local corpo =
		part(holder, Vector3.new(0.14, 0.24, 0.14), at(x, y, z), Color3.fromRGB(60, 58, 48), Enum.Material.Metal)
	corpo.Name = "Lampiao"
	local vidro =
		part(holder, Vector3.new(0.1, 0.12, 0.1), at(x, y + 0.02, z), Color3.fromRGB(255, 196, 110), Enum.Material.Neon)
	vidro.Transparency = 0.15
	local l = Instance.new("PointLight")
	l.Color = if vc then Color3.fromRGB(255, 164, 84) else Color3.fromRGB(255, 184, 104)
	l.Range = 26
	l.Brightness = 2.2
	l.Shadows = false
	l.Parent = vidro
	table.insert(luzes.lampiao, l)
end

-- rádio de campanha de peças (não há modelo publicado): caixa, painel, fone e antena
local function radio(holder: Model, cf: CFrame)
	local olive = Color3.fromRGB(78, 82, 58)
	local caixa = part(holder, Vector3.new(0.3, 0.26, 0.12), cf, olive, Enum.Material.Metal)
	caixa.Name = "Radio"
	part(holder, Vector3.new(0.24, 0.16, 0.01), cf * CFrame.new(0, 0.01 / M, 0.065 / M), Color3.fromRGB(40, 40, 34))
	-- antena: o cilindro do Roblox tem o eixo em X; de pé, girado 90° (menos 8° de inclinação)
	part(
		holder,
		Vector3.new(0.9, 0.012, 0.012),
		cf * CFrame.new(0.11 / M, 0.58 / M, -0.03 / M) * CFrame.Angles(0, 0, math.rad(82)),
		Color3.fromRGB(30, 30, 28),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
end

-- ===== os dois acampamentos =====
local function montarUS(): Model
	local h = Instance.new("Model")
	h.Name = "Acampamento_US"
	local pivot = part(h, Vector3.new(0.1, 0.1, 0.1), CFrame.identity, Color3.new(), nil)
	pivot.Name = "Pivo"
	pivot.Transparency = 1
	h.PrimaryPart = pivot
	-- terra batida acinzentada: o sol baixo e a cor quente da tela já avermelham (no Studio, com a
	-- terra mais marrom, o chão saía vermelho)
	chao(h, Color3.fromRGB(86, 80, 66), Color3.fromRGB(70, 62, 50), Enum.Material.Ground)
	vaga(h, "us_command_tent", at(4.2, 0, -9.5, 196))
	vaga(h, "us_tent_gp_medium", at(-7.5, 0, -15, 168))
	vaga(h, "sandbag_wall", at(1.9, 0, -3.4, 8))
	vaga(h, "caixa_municao_us", at(2.15, 0, -1.55, 24))
	vaga(h, "ammo_crate", at(2.2, 0, -1.6, 18), "caixa_municao_us")
	vaga(h, "us_jerrycans", at(-1.9, 0, -2.6, -22))
	vaga(h, "us_fuel_drums", at(6.2, 0, -4.8, 10))
	vaga(h, "m151", at(-5.8, 0, -6.8, 38))
	vaga(h, "us_flagpole", at(9.5, 0, -19, 0))
	vaga(h, "uh34d_v3", at(17, 0, -42, 118))
	for _, p in { { -13, -26 }, { 19, -24 }, { 28, -52 }, { -24, -55 }, { 7, -66 }, { -40, -40 }, { 44, -36 } } do
		vaga(h, "coconut_palm", at(p[1], 0, p[2], (p[1] * 37) % 360))
	end
	vaga(h, "banana", at(8.2, 0, -8.2, 40))
	vaga(h, "banana", at(-9.6, 0, -10.5, 200))
	vaga(h, "bamboo_clump", at(-15, 0, -14, 0))
	radio(h, at(1.55, 0.13, -2.9, 14))
	lampiao(h, 3.0, 1.85, -7.6, false)
	return h
end

local function montarVC(): Model
	local h = Instance.new("Model")
	h.Name = "Acampamento_VC"
	local pivot = part(h, Vector3.new(0.1, 0.1, 0.1), CFrame.identity, Color3.new(), nil)
	pivot.Name = "Pivo"
	pivot.Transparency = 1
	h.PrimaryPart = pivot
	chao(h, Color3.fromRGB(62, 60, 46), Color3.fromRGB(50, 46, 34), Enum.Material.Ground)
	vaga(h, "vc_lean_to", at(4.0, 0, -8.8, 200))
	vaga(h, "vc_hammock", at(-5.6, 0, -9.5, 160))
	vaga(h, "vc_weapon_rack", at(-2.0, 0, -3.1, -12))
	vaga(h, "caixa_municao_vc", at(2.1, 0, -1.6, 20))
	vaga(h, "rice_sack", at(3.0, 0, -2.3, 60))
	vaga(h, "rice_sack", at(3.4, 0, -1.7, 15))
	vaga(h, "clay_lamp", at(2.1, 0, -1.6, 0), "caixa_municao_vc")
	vaga(h, "vc_hoang_cam_kitchen", at(7.5, 0, -12, 190))
	for _, p in { { -7.5, -5.5 }, { 9.5, -6.5 }, { -14, -16 }, { 15, -18 } } do
		vaga(h, "bamboo_clump", at(p[1], 0, p[2], (p[1] * 53) % 360))
	end
	for _, p in { { -12, -24 }, { 18, -27 }, { 26, -50 }, { -26, -48 }, { 4, -62 } } do
		vaga(h, "coconut_palm", at(p[1], 0, p[2], (p[1] * 37) % 360))
	end
	vaga(h, "banana", at(6.8, 0, -7.0, 30))
	vaga(h, "banana", at(-8.8, 0, -8.8, 220))
	lampiao(h, 2.2, 1.0, -8.0, true)
	return h
end

-- ===== luz e efeitos =====
local function montarLuzes(holder: Instance)
	-- luz principal: do lado da câmera, de cima, quente (a referência: o soldado aceso no escuro)
	local kp = part(holder :: any, Vector3.new(0.1, 0.1, 0.1), at(-2.6, 3.4, 4.2), Color3.new(), nil)
	kp.Name = "LuzPrincipal"
	kp.Transparency = 1
	kp.CFrame = CFrame.lookAt(kp.Position, W(0, 1.2, 0))
	local key = Instance.new("SpotLight")
	key.Face = Enum.NormalId.Front
	key.Angle = 46
	key.Range = 40
	key.Brightness = 0
	key.Color = Color3.fromRGB(255, 220, 172)
	key.Shadows = false
	key.Parent = kp
	luzes.key = key
	-- luz de preenchimento: fraca, fria, da direita
	local fp = part(holder :: any, Vector3.new(0.1, 0.1, 0.1), at(2.4, 1.6, 3.0), Color3.new(), nil)
	fp.Name = "LuzPreenche"
	fp.Transparency = 1
	local fill = Instance.new("PointLight")
	fill.Range = 18
	fill.Brightness = 0.45
	fill.Color = Color3.fromRGB(176, 190, 214)
	fill.Parent = fp
	luzes.fill = fill
	-- poeira no facho da luz (some com movimento reduzido)
	local pp = part(holder :: any, Vector3.new(3.2, 2.2, 2.4), at(-0.6, 1.4, 0.8), Color3.new(), nil)
	pp.Name = "Poeira"
	pp.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.Rate = 7
	e.Lifetime = NumberRange.new(6, 9)
	e.Speed = NumberRange.new(0.02, 0.12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 0.03, 0)
	e.Size = NumberSequence.new(0.035)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.35),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Color3.fromRGB(255, 226, 180))
	e.LightEmission = 0.6
	e.LightInfluence = 0.4
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = pp
	poeira = e
end

local function efeitos(on: boolean)
	if on then
		if not cor then
			local c = Instance.new("ColorCorrectionEffect")
			c.Name = "VT65PalcoCor"
			-- quente e contrastado: o fundo cai para o escuro e o soldado na luz se destaca
			c.TintColor = Color3.fromRGB(255, 232, 206)
			c.Contrast = 0.22
			c.Saturation = 0.02
			c.Brightness = -0.06
			c.Parent = Lighting
			cor = c
		end
		if not dof then
			local d = Instance.new("DepthOfFieldEffect")
			d.Name = "VT65PalcoDof"
			d.FarIntensity = 0.42
			d.NearIntensity = 0
			d.InFocusRadius = 9
			d.FocusDistance = 20
			d.Parent = Lighting
			dof = d
		end
	else
		if cor then
			cor:Destroy()
			cor = nil
		end
		if dof then
			dof:Destroy()
			dof = nil
		end
	end
end

-- ===== o soldado =====
local function standCF(): CFrame
	-- de frente para a câmera (+Z), girado pelo jogador
	return baseCF() * CFrame.Angles(0, math.pi + girarAtual, 0)
end

local function ladoDesejado(): string
	if RunService:IsStudio() then
		local d = workspace:GetAttribute("VT65DevPalco")
		if d == "US" or d == "VC" then
			return d
		end
	end
	local f = fonte and fonte:GetAttribute("Faction")
	if f == "US" or f == "VC" then
		return f
	end
	local fa = player:GetAttribute("Faction")
	if fa == "US" or fa == "VC" then
		return fa
	end
	local c = JogarAgora.decode(player:GetAttribute("UltimaEscolha"))
	return if c.f == "VC" then "VC" else "US"
end

-- o soldado do jogador chegou (ou mudou): troca o do palco
local function meuSoldado(): Model?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local f = pg and pg:FindFirstChild("VT65MeuSoldado")
	local m = f and f:FindFirstChild("Soldado")
	if not (m and m:IsA("Model")) then
		return nil
	end
	local want = m:GetAttribute("Parts")
	if type(want) == "number" then
		local n = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		if n < want then
			return nil
		end
	end
	return m
end

local function atualizarSoldado()
	local p = soldado
	if not p then
		return
	end
	local m = meuSoldado()
	if m and m ~= fonte then
		fonte = m
		SoldierPreview.setModel(p, m:Clone())
	elseif not m and not fonte then
		SoldierPreview.set(p, ladoDesejado(), nil)
	end
end

-- ===== montar e trocar o lado =====
local function garantir()
	if root then
		return
	end
	local r = Instance.new("Model")
	r.Name = "VT65Palco"
	local pivot = Instance.new("Part")
	pivot.Name = "Pivo"
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.Transparency = 1
	pivot.Size = Vector3.new(0.2, 0.2, 0.2)
	pivot.CFrame = CFrame.identity
	pivot.Parent = r
	r.PrimaryPart = pivot
	local sf = Instance.new("Folder")
	sf.Name = "Soldado"
	sf.Parent = r
	local luzesF = Instance.new("Model")
	luzesF.Name = "Luzes"
	local lp = Instance.new("Part")
	lp.Name = "Pivo"
	lp.Anchored = true
	lp.Transparency = 1
	lp.CanCollide = false
	lp.CanQuery = false
	lp.Size = Vector3.new(0.2, 0.2, 0.2)
	lp.CFrame = CFrame.identity
	lp.Parent = luzesF
	luzesF.PrimaryPart = lp
	montarLuzes(luzesF)
	luzesF.Parent = r
	root = r
	soldado = SoldierPreview.newWorld(sf, CFrame.identity)
end

local function trocarLado(f: string)
	if setAtual == f then
		return
	end
	if setAtual and sets[setAtual] then
		sets[setAtual].Parent = nil
	end
	local s = sets[f]
	if not s then
		table.clear(luzes.lampiao)
		s = if f == "VC" then montarVC() else montarUS()
		sets[f] = s
	else
		-- as luzes do lampião do lado de agora
		table.clear(luzes.lampiao)
		for _, d in s:GetDescendants() do
			if d:IsA("PointLight") then
				table.insert(luzes.lampiao, d)
			end
		end
	end
	s:PivotTo(baseCF())
	s.Parent = root
	setAtual = f
	preencher()
end

-- ===== câmera =====
local function smooth(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end
-- o quadro de agora (entre camDe e camPara), no quadro do palco
local xSuave = 0.56 -- telaX amortecido (a janela muda de tamanho sem tranco)
local function quadroAgora(now: number): Quadro
	local t = math.clamp((now - camT0) / math.max(camDur, 1e-3), 0, 1)
	local s = smooth(t)
	local a, b = camDe, camPara
	local xa = a.x or xSuave
	local xb = b.x or xSuave
	return {
		cam = a.cam:Lerp(b.cam, s),
		alvo = a.alvo:Lerp(b.alvo, s),
		fov = a.fov + (b.fov - a.fov) * s,
		y = a.y + (b.y - a.y) * s,
		x = xa + (xb - xa) * s,
	}
end

-- a câmera olha para o alvo e gira o necessário para ele cair em (x, y) da tela
local function cfDoQuadro(q: Quadro, cam: Camera): CFrame
	local b = baseCF()
	local pos = b:PointToWorldSpace(q.cam / M)
	local alvo = b:PointToWorldSpace(q.alvo / M)
	local vp = cam.ViewportSize
	local aspect = if vp.Y > 1 then vp.X / vp.Y else 16 / 9
	local tv = math.tan(math.rad(q.fov / 2))
	local x = q.x or xSuave
	local yaw = math.atan((x - 0.5) * 2 * tv * aspect)
	local pitch = math.atan((q.y - 0.5) * 2 * tv)
	return CFrame.lookAt(pos, alvo) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

local function passo(dt: number)
	local cam = workspace.CurrentCamera
	if not (aberto and cam) then
		return
	end
	local now = os.clock()
	-- giro do soldado: arraste ou analógico, com amortecimento; volta de frente depois de parado
	if math.abs(stickX) > 0.18 and LobbyPalco.podeGirar() then
		girar += stickX * dt * 2.6
		ultimoGiro = now
	end
	if now - ultimoGiro > VOLTA_S and arrastando == nil then
		girar = girar % (2 * math.pi)
		if girar > math.pi then
			girar -= 2 * math.pi
		end
		girar *= math.exp(-dt * 1.4)
	end
	local alvo = girar
	local novo = girarAtual + (alvo - girarAtual) * (1 - math.exp(-dt * 10))
	if math.abs(novo - girarAtual) > 1e-4 then
		girarAtual = novo
		local p = soldado
		if p then
			SoldierPreview.place(p, standCF())
		end
	end
	-- câmera: o quadro de agora, com um respiro leve (parado com movimento reduzido)
	xSuave += (LobbyPalco.telaX - xSuave) * (1 - math.exp(-dt * 6))
	local q = quadroAgora(now)
	if not Estilo.reduzMovimento() then
		q.cam += Vector3.new(math.sin(now * 0.31) * 0.03, math.sin(now * 0.43) * 0.018, 0)
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local cf = cfDoQuadro(q, cam)
	cam.CFrame = cf
	cam.FieldOfView = q.fov
	local d = dof
	if d then
		d.FocusDistance = (cf.Position - baseCF():PointToWorldSpace(q.alvo / M)).Magnitude
	end
	-- a chama do lampião
	for i, l in luzes.lampiao do
		l.Brightness = 2.0 + math.noise(now * 3.1, i * 7.3) * 0.5
	end
end

-- ===== entrada do jogador (girar) =====
UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
	if not aberto or processed or not LobbyPalco.podeGirar() then
		return
	end
	local t = io.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		-- só fora dos botões e da coluna da esquerda (o gesto não aciona nada)
		local cam = workspace.CurrentCamera
		local vx = if cam then cam.ViewportSize.X else 1280
		if io.Position.X > vx * 0.36 then
			arrastando = io
			arrasteX = io.Position.X
		end
	end
end)
UserInputService.InputChanged:Connect(function(io: InputObject)
	if io.KeyCode == Enum.KeyCode.Thumbstick2 then
		stickX = io.Position.X
		return
	end
	local a = arrastando
	if not a then
		return
	end
	if
		(a.UserInputType == Enum.UserInputType.MouseButton1 and io.UserInputType == Enum.UserInputType.MouseMovement)
		or (a.UserInputType == Enum.UserInputType.Touch and io == a)
	then
		local x = io.Position.X
		girar += (x - arrasteX) * 0.011
		arrasteX = x
		ultimoGiro = os.clock()
	end
end)
UserInputService.InputEnded:Connect(function(io: InputObject)
	local a = arrastando
	if a and (io == a or io.UserInputType == a.UserInputType) then
		arrastando = nil
	end
	if io.KeyCode == Enum.KeyCode.Thumbstick2 then
		stickX = 0
	end
end)

-- ===== API =====
function LobbyPalco.aberto(): boolean
	return aberto
end

function LobbyPalco.lado(): string?
	return setAtual
end

-- vai para um enquadramento (nome de QUADROS); cancela o que estava andando, partindo de onde está
function LobbyPalco.enquadrar(nome: string)
	local q = QUADROS[nome]
	if not q or (nome == quadroAtual and aberto) then
		return
	end
	quadroAtual = nome
	if not aberto then
		camDe, camPara = q, q
		return
	end
	local now = os.clock()
	camDe = quadroAgora(now) -- parte de onde está (troca rápida não dá tranco)
	camPara = q
	camT0 = now
	camDur = if Estilo.reduzMovimento() then 0 else MOVE_S
end

function LobbyPalco.abrir()
	if aberto then
		return
	end
	garantir()
	-- o palco gira para o sol ficar atrás e à direita do soldado (luz de contorno e o céu claro atrás)
	local sun = Lighting:GetSunDirection()
	local h = Vector3.new(sun.X, 0, sun.Z)
	if h.Magnitude > 0.05 then
		local want = Vector3.new(0.5, 0, -0.86) -- atrás (−Z) e à direita (+X) do soldado
		yawPalco = math.atan2(h.X, h.Z) - math.atan2(want.X, want.Z)
	end
	local r = root :: Model
	r:PivotTo(baseCF())
	trocarLado(ladoDesejado())
	local s = sets[setAtual :: string]
	if s then
		s:PivotTo(baseCF())
	end
	girar, girarAtual, ultimoGiro = 0, 0, 0
	local p = soldado
	if p then
		SoldierPreview.place(p, standCF())
	end
	atualizarSoldado()
	r.Parent = workspace
	efeitos(true)
	aberto = true
	-- chegada: a câmera desce até o quadro de agora e a luz principal acende
	local parado = Estilo.reduzMovimento()
	camDe = if parado then QUADROS[quadroAtual] else CHEGADA
	camPara = QUADROS[quadroAtual]
	camT0 = os.clock()
	camDur = if parado then 0 else ARRIVE_S
	local key = luzes.key
	if key then
		key.Brightness = if parado then 3.2 else 0
		UiKit.tween(key, TweenInfo.new(if parado then 0 else 1.2, Enum.EasingStyle.Sine), { Brightness = 3.2 })
	end
	local e = poeira
	if e then
		e.Enabled = not parado
	end
	pcall(function()
		player:RequestStreamAroundAsync(BASE, 2)
	end)
	RunService:BindToRenderStep("VT65Palco", Enum.RenderPriority.Camera.Value + 5, passo)
	passo(0)
end

function LobbyPalco.fechar()
	if not aberto then
		return
	end
	aberto = false
	arrastando = nil
	RunService:UnbindFromRenderStep("VT65Palco")
	efeitos(false)
	local r = root
	if r then
		r.Parent = nil
	end
end

-- os modelos e o soldado chegam do servidor aos poucos
task.spawn(function()
	local f = ReplicatedStorage:WaitForChild("VT65Preview", 120)
	local props = f and f:WaitForChild("Props", 120)
	if props then
		local pend = false
		props.DescendantAdded:Connect(function()
			if not pend then
				pend = true
				task.delay(0.5, function()
					pend = false
					preencher()
				end)
			end
		end)
		preencher()
	end
end)
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	local pend = false
	local function logo()
		if not pend then
			pend = true
			task.delay(0.4, function()
				pend = false
				atualizarSoldado()
				-- o lado do soldado novo pode ser outro: troca o acampamento
				if aberto then
					trocarLado(ladoDesejado())
				end
			end)
		end
	end
	pg.DescendantAdded:Connect(function(d)
		if d:IsDescendantOf(pg) and d:FindFirstAncestor("VT65MeuSoldado") then
			logo()
		end
	end)
	pg.ChildAdded:Connect(function(c)
		if c.Name == "VT65MeuSoldado" then
			logo()
		end
	end)
	logo()
end)
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevPalco"):Connect(function()
		if aberto then
			trocarLado(ladoDesejado())
			atualizarSoldado()
		end
	end)
end

return LobbyPalco
