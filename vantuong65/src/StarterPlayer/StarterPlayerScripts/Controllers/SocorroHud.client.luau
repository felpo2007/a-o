--!strict
-- D-236 (dono: "melhore o jeito de curar os aliados"). Agora a tela diz quem precisa de ajuda:
-- - cruz no mundo sobre quem caiu (para todos) e sobre os feridos (para o médico), com a distância;
-- - cartão perto da mira quando há alguém ao alcance: nome, estado, vida, a tecla e o que ela faz, e a
--   barra da ação que o servidor está contando (atributos VT65AcaoT e VT65AcaoS).
-- Só mostra: quem age é o MedicalController (tecla) e o Interagir (botão do toque).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Socorro = require(ReplicatedStorage.Shared.Socorro)
local Input = require(script.Parent.Input)
local SocorroAlvo = require(script.Parent.SocorroAlvo)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V = UiKit.V

local VERMELHO = Color3.fromRGB(214, 58, 48)
local AMBAR = Color3.fromRGB(232, 168, 62)
local VERDE = Color3.fromRGB(116, 186, 96)
local CLARO = Color3.fromRGB(244, 236, 214)
local FUNDO = Color3.fromRGB(20, 22, 17)

local gui = UiKit.screen("VT65Socorro", 14)
gui.Enabled = false

-- ===== o cartão =====
local W, H = 372, 104
local card = Instance.new("Frame")
card.Name = "Cartao"
card.AnchorPoint = Vector2.new(0.5, 1)
card.Position = UDim2.fromScale(0.5, 0.74)
card.Size = UDim2.fromOffset(W, H)
card.BackgroundColor3 = FUNDO
card.BackgroundTransparency = 0.12
card.BorderSizePixel = 0
card.Visible = false
card.Parent = gui
UiKit.corner(card, 6)
local borda = UiKit.edge(card, VERMELHO, 1.5, 0.15)
local escala = Instance.new("UIScale")
escala.Parent = card

local faixa = Instance.new("Frame")
faixa.Name = "Faixa"
faixa.Size = UDim2.new(0, 5, 1, 0)
faixa.BackgroundColor3 = VERMELHO
faixa.BorderSizePixel = 0
faixa.Parent = card
UiKit.corner(faixa, 3)

-- cruz desenhada (sem imagem: nítida em qualquer tela)
local function cruz(parent: Instance, lado: number, cor: Color3): (Frame, Frame, Frame)
	local fundo = Instance.new("Frame")
	fundo.Size = UDim2.fromOffset(lado, lado)
	fundo.BackgroundColor3 = cor
	fundo.BorderSizePixel = 0
	fundo.Parent = parent
	UiKit.corner(fundo, math.floor(lado / 2))
	UiKit.lit(fundo, 0.74)
	local a = Instance.new("Frame")
	a.AnchorPoint = Vector2.new(0.5, 0.5)
	a.Position = UDim2.fromScale(0.5, 0.5)
	a.Size = UDim2.fromScale(0.58, 0.18)
	a.BackgroundColor3 = Color3.new(1, 1, 1)
	a.BorderSizePixel = 0
	a.Parent = fundo
	local b = a:Clone()
	b.Size = UDim2.fromScale(0.18, 0.58)
	b.Parent = fundo
	return fundo, a, b
end

local icone = cruz(card, 58, VERMELHO)
icone.Position = UDim2.fromOffset(18, 14)

local nome = UiKit.rotulo(card, 20, CLARO, UiKit.HEAD_FONT)
nome.Name = "Nome"
nome.Position = UDim2.fromOffset(90, 10)
nome.Size = UDim2.new(1, -196, 0, 26)
nome.TextTruncate = Enum.TextTruncate.AtEnd

local estado = UiKit.rotulo(card, 14, CLARO, UiKit.HEAD_FONT)
estado.Name = "Estado"
estado.AnchorPoint = Vector2.new(1, 0)
estado.Position = UDim2.new(1, -12, 0, 12)
estado.Size = UDim2.fromOffset(94, 22)
estado.TextXAlignment = Enum.TextXAlignment.Center
estado.BackgroundTransparency = 0
estado.BackgroundColor3 = VERMELHO
UiKit.corner(estado, 3)

local trilho = Instance.new("Frame")
trilho.Name = "Vida"
trilho.Position = UDim2.fromOffset(90, 41)
trilho.Size = UDim2.new(1, -102, 0, 7)
trilho.BackgroundColor3 = Color3.fromRGB(54, 54, 44)
trilho.BorderSizePixel = 0
trilho.Parent = card
UiKit.corner(trilho, 3)
local vida = Instance.new("Frame")
vida.Size = UDim2.fromScale(0.5, 1)
vida.BackgroundColor3 = VERDE
vida.BorderSizePixel = 0
vida.Parent = trilho
UiKit.corner(vida, 3)

local tecla = Instance.new("Frame")
tecla.Name = "Tecla"
tecla.Position = UDim2.fromOffset(90, 58)
tecla.Size = UDim2.fromOffset(32, 30)
tecla.BackgroundColor3 = CLARO
tecla.BorderSizePixel = 0
tecla.Parent = card
UiKit.corner(tecla, 4)
local teclaTxt = UiKit.rotulo(tecla, 17, FUNDO, UiKit.HEAD_FONT)
teclaTxt.Size = UDim2.fromScale(1, 1)
teclaTxt.TextXAlignment = Enum.TextXAlignment.Center
local teclaImg = Instance.new("ImageLabel")
teclaImg.BackgroundTransparency = 1
teclaImg.Size = UDim2.fromScale(1, 1)
teclaImg.Visible = false
teclaImg.Parent = tecla

local acao = UiKit.rotulo(card, 18, V.TEXT or CLARO, UiKit.HEAD_FONT)
acao.Name = "Acao"
acao.Position = UDim2.fromOffset(130, 59)
acao.Size = UDim2.new(1, -142, 0, 28)

local barra = Instance.new("Frame")
barra.Name = "Progresso"
barra.AnchorPoint = Vector2.new(0, 1)
barra.Position = UDim2.fromScale(0, 1)
barra.Size = UDim2.new(0, 0, 0, 5)
barra.BackgroundColor3 = VERDE
barra.BorderSizePixel = 0
barra.Parent = card

-- ===== cruzes no mundo =====
type Marca = {
	bb: BillboardGui,
	fundo: Frame,
	dist: TextLabel,
	cuida: TextLabel,
}
local marcas: { Marca } = {}
for i = 1, Socorro.MAX_MARCAS do
	local bb = Instance.new("BillboardGui")
	bb.Name = "CruzSocorro" .. i
	bb.Size = UDim2.fromOffset(62, 66)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Enabled = false
	bb.Parent = gui
	local fundo = cruz(bb, 32, VERMELHO)
	fundo.AnchorPoint = Vector2.new(0.5, 0)
	fundo.Position = UDim2.fromScale(0.5, 0)
	UiKit.edge(fundo, Color3.new(1, 1, 1), 1.5, 0.1)
	local dist = UiKit.rotulo(bb, 14, CLARO, UiKit.HEAD_FONT)
	dist.Position = UDim2.fromOffset(0, 34)
	dist.Size = UDim2.new(1, 0, 0, 16)
	dist.TextXAlignment = Enum.TextXAlignment.Center
	dist.TextStrokeTransparency = 0.35
	local cuida = UiKit.rotulo(bb, 11, VERDE, UiKit.HEAD_FONT)
	cuida.Position = UDim2.fromOffset(0, 50)
	cuida.Size = UDim2.new(1, 0, 0, 14)
	cuida.TextXAlignment = Enum.TextXAlignment.Center
	cuida.TextStrokeTransparency = 0.35
	cuida.Text = "CUIDANDO"
	cuida.Visible = false
	table.insert(marcas, { bb = bb, fundo = fundo, dist = dist, cuida = cuida })
end

-- ===== atualização =====
local function corDe(a: Socorro.Aliado): (Color3, string)
	if a.downed then
		return VERMELHO, "CAÍDO"
	elseif a.bleeding then
		return AMBAR, "SANGRANDO"
	end
	return AMBAR, "FERIDO"
end

local function mostraTecla()
	if Input.touchActive() then
		tecla.Visible = false
		acao.Position = UDim2.fromOffset(90, 59)
		return
	end
	tecla.Visible = true
	acao.Position = UDim2.fromOffset(130, 59)
	local img, txt = Input.glyph("interact", "infantry")
	teclaImg.Image = img or ""
	teclaImg.Visible = img ~= nil
	teclaTxt.Visible = img == nil
	teclaTxt.Text = txt
	tecla.BackgroundTransparency = if img then 1 else 0
end

local function podeMostrar(): boolean
	local st = Input.state
	if not InputMap.acceptsGame(st) or st.downed or st.vehicle ~= nil then
		return false
	end
	local char = player.Character
	local h = char and char:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and player:GetAttribute("Downed") ~= true
end

local function atualizaCartao(it: SocorroAlvo.Item?)
	-- no meio de uma ação em alguém, a barra continua mesmo que o alvo mude de estado
	local char = player.Character
	local t0 = char and char:GetAttribute("VT65AcaoT")
	local dur = char and char:GetAttribute("VT65AcaoS")
	local rodando = char ~= nil
		and char:GetAttribute("VT65Acao") ~= nil
		and type(t0) == "number"
		and type(dur) == "number"
	if not it or player:GetAttribute("PromptShown") == true then
		card.Visible = false
		return
	end
	local a = SocorroAlvo.acao(it)
	if not a then
		card.Visible = false
		return
	end
	card.Visible = true
	escala.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 900, 0.72, 1.15)
	local cor, txt = corDe(it.info)
	nome.Text = it.nome
	estado.Text = txt
	estado.BackgroundColor3 = cor
	estado.TextColor3 = if cor == AMBAR then FUNDO else CLARO
	borda.Color = cor
	faixa.BackgroundColor3 = cor
	icone.BackgroundColor3 = cor
	vida.Size = UDim2.fromScale(it.info.frac, 1)
	vida.BackgroundColor3 = if it.info.frac > 0.6 then VERDE elseif it.info.frac > 0.3 then AMBAR else VERMELHO
	if a.op then
		mostraTecla()
		acao.TextColor3 = CLARO
		acao.Text = if Input.touchActive()
			then string.format("%s · %d s", a.titulo, a.segundos)
			else string.format("SEGURAR · %s · %d s", a.titulo, a.segundos)
	else
		tecla.Visible = false
		acao.Position = UDim2.fromOffset(90, 59)
		acao.TextColor3 = AMBAR
		acao.Text = a.motivo or ""
	end
	if rodando then
		local k = math.clamp((workspace:GetServerTimeNow() - (t0 :: number)) / math.max(dur :: number, 0.1), 0, 1)
		barra.Size = UDim2.new(k, 0, 0, 5)
		acao.TextColor3 = VERDE
		acao.Text = string.format("%s...", a.titulo)
		tecla.Visible = false
		acao.Position = UDim2.fromOffset(90, 59)
	else
		barra.Size = UDim2.new(0, 0, 0, 5)
	end
end

local function atualizaMarcas(lista: { SocorroAlvo.Item })
	local medico = SocorroAlvo.medico()
	local fila: { SocorroAlvo.Item } = {}
	for _, it in lista do
		-- quem já está ao alcance fica com o cartão; a cruz sobre ele só atrapalharia a mira
		if Socorro.marca(it.info, medico) and it.info.distM > Socorro.ALCANCE_M then
			table.insert(fila, it)
		end
	end
	table.sort(fila, function(x, y)
		return Socorro.nota(x.info) < Socorro.nota(y.info)
	end)
	local pulso = 0.5 + 0.5 * math.sin(os.clock() * 5)
	for i, mk in marcas do
		local it = fila[i]
		if it then
			mk.bb.Adornee = it.head
			mk.bb.Enabled = true
			local cor = corDe(it.info)
			mk.fundo.BackgroundColor3 = cor
			local lado = if it.info.downed then 30 + 4 * pulso else 28
			mk.fundo.Size = UDim2.fromOffset(lado, lado)
			mk.dist.Text = string.format("%d m", math.round(it.info.distM))
			mk.cuida.Visible = it.cuidando
		else
			mk.bb.Enabled = false;
			(mk.bb :: any).Adornee = nil
		end
	end
end

local espera = 0
local cache: { SocorroAlvo.Item } = {}
RunService.Heartbeat:Connect(function(dt: number)
	local ok = podeMostrar()
	if gui.Enabled ~= ok then
		gui.Enabled = ok
	end
	if not ok then
		return
	end
	espera -= dt
	if espera <= 0 then
		espera = 0.12
		cache = SocorroAlvo.aliados()
		atualizaMarcas(cache)
	end
	atualizaCartao(SocorroAlvo.alvo(cache))
end)
