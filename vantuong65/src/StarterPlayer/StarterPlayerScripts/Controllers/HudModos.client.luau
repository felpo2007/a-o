--!strict
-- D-243: o HUD dos dois modos dos mapas retangulares. Só mostra o que o servidor publica no Match_State.
-- Linha de Frente: A-B-C-D-E, setor ativo, direção do avanço, transição e relógio; ativo, território e bloqueio
-- diferem por texto, forma e cor. Comboio: barra única de percurso, checkpoints, entrega, relógio e o motivo real
-- da parada (Aguardando escolta, Avançando, Contestado, Imobilizado, Reparando, Concluindo checkpoint).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapaAtivo = require(ReplicatedStorage.Shared.MapaAtivo)
local Net = require(ReplicatedStorage.Shared.Net)
local UiKit = require(script.Parent.UiKit)

if not MapaAtivo.retangular() then
	return
end

local player = Players.LocalPlayer
local V = UiKit.V
local AZUL, VERMELHO = Color3.fromRGB(78, 118, 188), Color3.fromRGB(190, 64, 50)
local LATAO = UiKit.BRASS
local LETRAS = { "A", "B", "C", "D", "E" }

local gui = UiKit.screen("VT65HudModos", 15)

local function caixa(pai: Instance, nome: string, cor: Color3, transp: number): Frame
	local f = Instance.new("Frame")
	f.Name = nome
	f.BackgroundColor3 = cor
	f.BackgroundTransparency = transp
	f.BorderSizePixel = 0
	f.Parent = pai
	return f
end

local function rotulo(pai: Instance, tam: number, cor: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = UiKit.HEAD_FONT
	t.TextSize = UiKit.text(tam)
	t.TextColor3 = cor
	t.Parent = pai
	return t
end

local function relogio(s: number): string
	local n = math.max(0, math.ceil(s))
	return string.format("%d:%02d", n // 60, n % 60)
end

-- ===== Linha de Frente =====
local painelF = caixa(gui, "LinhaFrente", V.PANEL, 0.12)
painelF.AnchorPoint = Vector2.new(0.5, 0)
painelF.Position = UDim2.new(0.5, 0, 0, 62)
painelF.Size = UDim2.fromOffset(470, 74)
painelF.Visible = false
UiKit.corner(painelF, 4)
UiKit.edge(painelF, LATAO, 1, 0.55)

type Chip = { base: Frame, letra: TextLabel, nota: TextLabel }
local chips: { Chip } = {}
for i = 1, 5 do
	local cx = 235 + (i - 3) * 72
	local base = caixa(painelF, "Setor" .. LETRAS[i], V.PANEL, 0)
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.Position = UDim2.fromOffset(cx, 27)
	base.Size = UDim2.fromOffset(30, 30)
	local letra = rotulo(painelF, 17, Color3.new(1, 1, 1))
	letra.AnchorPoint = Vector2.new(0.5, 0.5)
	letra.Position = UDim2.fromOffset(cx, 27)
	letra.Size = UDim2.fromOffset(30, 30)
	letra.Text = LETRAS[i]
	letra.ZIndex = 2
	local nota = rotulo(painelF, 10, UiKit.KHAKI)
	nota.AnchorPoint = Vector2.new(0.5, 0)
	nota.Position = UDim2.fromOffset(cx, 49)
	nota.Size = UDim2.fromOffset(70, 14)
	chips[i] = { base = base, letra = letra, nota = nota }
end
local setaE = rotulo(painelF, 16, LATAO)
setaE.Position = UDim2.fromOffset(6, 18)
setaE.Size = UDim2.fromOffset(40, 20)
local setaD = rotulo(painelF, 16, LATAO)
setaD.Position = UDim2.new(1, -46, 0, 18)
setaD.Size = UDim2.fromOffset(40, 20)
local avisoF = rotulo(painelF, 12, UiKit.BRASS_LIGHT)
avisoF.AnchorPoint = Vector2.new(0.5, 0)
avisoF.Position = UDim2.new(0.5, 0, 1, 2)
avisoF.Size = UDim2.fromOffset(470, 18)
UiKit.edge(avisoF, Color3.new(0, 0, 0), 1, 0.4)

local function desenhaFrente(st: any)
	local l = st.linha
	painelF.Visible = true
	local minha = player:GetAttribute("Faction")
	for i, c in chips do
		local cor, texto, giro, tam, tr
		if i == l.ativo then
			cor, texto, giro, tam, tr = LATAO, if l.fase == "transicao" then "A SEGUIR" else "ATIVO", 45, 26, 0
		elseif i < l.ativo then
			cor, texto, giro, tam, tr = VERMELHO, "BLOQUEADO", 0, 24, 0.25
		else
			cor, texto, giro, tam, tr = AZUL, "BLOQUEADO", 0, 24, 0.25
		end
		c.base.BackgroundColor3 = cor
		c.base.BackgroundTransparency = tr
		c.base.Rotation = giro
		c.base.Size = UDim2.fromOffset(tam, tam)
		c.letra.TextColor3 = if i == l.ativo then Color3.fromRGB(28, 24, 16) else Color3.new(1, 1, 1)
		c.nota.Text = texto
		c.nota.TextColor3 = if i == l.ativo then LATAO else UiKit.KHAKI
	end
	-- o Oeste (VC) avança para a direita e o Leste (EUA) para a esquerda
	setaE.Text = if minha == "US" then "◄ ◄" else ""
	setaD.Text = if minha == "VC" then "► ►" else ""
	if l.fase == "transicao" then
		avisoF.Text = string.format("FRENTE EM MOVIMENTO · captura em %d s", math.ceil(l.transicaoS))
	elseif l.fase == "final" then
		avisoF.Text = string.format("DISPUTA FINAL · %s", relogio(l.finalS))
	else
		avisoF.Text = string.format("TEMPO %s", relogio(st.timeLeft or 0))
	end
end

-- ===== Comboio =====
local painelC = caixa(gui, "Comboio", V.PANEL, 0.12)
painelC.AnchorPoint = Vector2.new(0.5, 0)
painelC.Position = UDim2.new(0.5, 0, 0, 8)
painelC.Size = UDim2.fromOffset(600, 86)
painelC.Visible = false
UiKit.corner(painelC, 4)
UiKit.edge(painelC, LATAO, 1, 0.55)

local titulo = rotulo(painelC, 13, UiKit.KHAKI)
titulo.Position = UDim2.fromOffset(12, 5)
titulo.Size = UDim2.fromOffset(250, 18)
titulo.TextXAlignment = Enum.TextXAlignment.Left
local tempo = rotulo(painelC, 18, Color3.new(1, 1, 1))
tempo.AnchorPoint = Vector2.new(1, 0)
tempo.Position = UDim2.new(1, -12, 0, 3)
tempo.Size = UDim2.fromOffset(90, 22)
tempo.TextXAlignment = Enum.TextXAlignment.Right
local estadoT = rotulo(painelC, 15, LATAO)
estadoT.AnchorPoint = Vector2.new(0.5, 0)
estadoT.Position = UDim2.new(0.5, 0, 0, 4)
estadoT.Size = UDim2.fromOffset(250, 20)

local trilho = caixa(painelC, "Trilho", Color3.fromRGB(58, 56, 46), 0)
trilho.Position = UDim2.fromOffset(14, 34)
trilho.Size = UDim2.new(1, -28, 0, 10)
local cheio = caixa(trilho, "Cheio", LATAO, 0)
cheio.Size = UDim2.fromScale(0, 1)
local marcas: { { m: Frame, t: TextLabel } } = {}
local NOMES_CP = { "CP1", "CP2", "CP3", "ENTREGA" }
for i = 1, 4 do
	local m = caixa(trilho, "Marco" .. i, Color3.new(1, 1, 1), 0)
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.Size = UDim2.fromOffset(12, 12)
	m.Rotation = 45
	m.ZIndex = 2
	local t = rotulo(trilho, 10, UiKit.KHAKI)
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Size = UDim2.fromOffset(70, 14)
	t.Text = NOMES_CP[i]
	marcas[i] = { m = m, t = t }
end
local integ = caixa(painelC, "Integridade", Color3.fromRGB(58, 56, 46), 0)
integ.Position = UDim2.fromOffset(14, 68)
integ.Size = UDim2.new(1, -28, 0, 6)
local integCheia = caixa(integ, "Cheia", Color3.fromRGB(116, 170, 92), 0)
integCheia.Size = UDim2.fromScale(1, 1)

local COR_ESTADO: { [string]: Color3 } = {
	avancando = Color3.fromRGB(128, 196, 104),
	aguardando = UiKit.KHAKI,
	contestado = Color3.fromRGB(226, 90, 70),
	imobilizado = Color3.fromRGB(226, 90, 70),
	reparando = Color3.fromRGB(240, 190, 90),
	checkpoint = LATAO,
	entregue = Color3.fromRGB(128, 196, 104),
}

local function desenhaComboio(st: any)
	local c = st.comboio
	painelC.Visible = true
	local minha = player:GetAttribute("Faction")
	titulo.Text = string.format("RODADA %d de 2 · %s", c.rodada, if minha == c.escolta then "ESCOLTA" else "DEFESA")
	tempo.Text = relogio(c.restaS)
	estadoT.Text = UiKit.upper(c.texto)
	estadoT.TextColor3 = COR_ESTADO[c.estado] or LATAO
	if c.estado == "checkpoint" then
		estadoT.Text = string.format("%s · %d s", UiKit.upper(c.texto), math.ceil(c.cpTotal - c.cpProg))
	elseif c.estado == "imobilizado" then
		estadoT.Text = string.format("%s · %d s", UiKit.upper(c.texto), math.ceil(c.imobS))
	end
	cheio.Size = UDim2.fromScale(math.clamp(c.fracao, 0, 1), 1)
	for i, q in marcas do
		local f = c.marcos[i] or 1
		q.m.Position = UDim2.fromScale(f, 0.5)
		q.t.Position = UDim2.new(f, 0, 1, 3)
		q.m.BackgroundColor3 = if i < c.cp or c.entregue
			then LATAO
			elseif i == c.cp then Color3.new(1, 1, 1)
			else Color3.fromRGB(120, 116, 98)
	end
	integCheia.Size = UDim2.fromScale(math.clamp(c.integridade / 100, 0, 1), 1)
	integCheia.BackgroundColor3 = if c.integridade > 35
		then Color3.fromRGB(116, 170, 92)
		else Color3.fromRGB(214, 84, 62)
end

Net.event("Match_State").OnClientEvent:Connect(function(st: any)
	painelF.Visible = false
	painelC.Visible = false
	if st.ended then
		return
	end
	if st.linha then
		desenhaFrente(st)
	elseif st.comboio then
		desenhaComboio(st)
	end
end)
