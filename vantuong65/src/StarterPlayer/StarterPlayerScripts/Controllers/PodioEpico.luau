--!strict
-- D-240 (dono: "melhore a comemoração, faça algo épico e sensacional"). A virada do pódio: quando o 1º
-- crava no caixote, VITÓRIA cai em letras de latão com clarão, tranco e onda de choque, os raios abrem
-- atrás dos soldados e os fogos sobem até a câmera ir para o melhor da partida. Com "reduzir
-- movimento", o letreiro aparece parado e os fogos ficam de fora (UiEfeitos.calmo).
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Comemoracao = require(ReplicatedStorage.Shared.Comemoracao)
local UiEfeitos = require(script.Parent.UiEfeitos)
local UiKit = require(script.Parent.UiKit)

local PodioEpico = {}
PodioEpico.__index = PodioEpico

local F = UiKit.F
local OURO = Color3.fromRGB(255, 214, 120)
local FIM_FOGOS = 16 -- s de cena

-- o instante em que o 1º toca o tampo
local function pouso(): number
	local P = Comemoracao.PODIO
	return (P.entrada[1] or 1.7) + P.queda
end
PodioEpico.pouso = pouso

local function camada(pai: Instance, nome: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = nome
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = pai
	return f
end

local function letreiro(pai: Instance, nome: string, y: number, alto: number, font: Font): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = nome
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, y)
	t.Size = UDim2.fromScale(0.92, alto)
	t.FontFace = font
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeColor3 = Color3.fromRGB(14, 9, 3)
	t.TextStrokeTransparency = 1
	t.TextTransparency = 1
	t.ZIndex = 6
	t.Parent = pai
	return t
end

function PodioEpico.novo(pai: GuiObject)
	local self = setmetatable({}, PodioEpico) :: any
	self.pai = pai
	self.atras = camada(pai, "EpicoAtras", 2)
	self.frente = camada(pai, "EpicoFrente", 6)
	self.grande = letreiro(self.frente, "Vitoria", 0.2, 0.2, F.TITLE)
	local ouro = Instance.new("UIGradient")
	ouro.Rotation = 90
	ouro.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 226)),
		ColorSequenceKeypoint.new(0.46, Color3.fromRGB(255, 216, 122)),
		ColorSequenceKeypoint.new(0.54, Color3.fromRGB(226, 160, 62)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 92, 30)),
	})
	ouro.Parent = self.grande
	self.escala = Instance.new("UIScale")
	self.escala.Parent = self.grande
	self.linha = letreiro(self.frente, "Lado", 0.325, 0.05, F.TITLE_MED)
	self.som = Instance.new("Sound")
	self.som.Name = "VT65PodioFanfarra"
	self.som.SoundId = string.format("rbxassetid://%d", tonumber(AssetIds.Sounds.ganho_promocao) or 0)
	self.som.Volume = 0.9
	self.som.SoundGroup = SoundService:FindFirstChild("VT65Efeitos") :: SoundGroup?
	self.som.Parent = SoundService
	self.rng = Random.new()
	self.geracao = 0
	self:reiniciar("", "", OURO)
	return self
end

-- texto grande (VITÓRIA ou EMPATE), o nome do lado e a cor dele
function PodioEpico.reiniciar(self: any, grande: string, linha: string, cor: Color3)
	self.geracao += 1
	self.cor = cor
	self.feito = false
	self.proximo = pouso() + 0.25
	self.grande.Text = grande
	self.grande.TextTransparency = 1
	self.grande.TextStrokeTransparency = 1
	self.linha.Text = linha
	self.linha.TextColor3 = cor:Lerp(Color3.new(1, 1, 1), 0.6)
	self.linha.TextTransparency = 1
	self.linha.TextStrokeTransparency = 1
	self.escala.Scale = 1
	for _, c in self.atras:GetChildren() do
		c:Destroy()
	end
end

function PodioEpico._batida(self: any)
	self.feito = true
	local a = self.pai.AbsoluteSize
	local centro = Vector2.new(a.X * 0.5, a.Y * 0.2)
	self.grande.TextTransparency, self.grande.TextStrokeTransparency = 0, 0.15
	self.linha.TextStrokeTransparency = 0.35
	TweenService
		:Create(self.linha, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.22), {
			TextTransparency = 0,
		})
		:Play()
	self.som.TimePosition = 0
	self.som:Play()
	if UiEfeitos.calmo() then
		return
	end
	self.escala.Scale = 2.7
	TweenService
		:Create(self.escala, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0), {
			Scale = 1,
		})
		:Play()
	UiEfeitos.clarao(self.frente, Color3.fromRGB(255, 240, 206), 0.62, 0.55, 5)
	UiEfeitos.tremer(self.pai, 0.55, math.max(8, a.Y * 0.022))
	UiEfeitos.onda(self.frente, centro, OURO, a.X * 0.32, 0.7, 7)
	UiEfeitos.faiscas(self.frente, centro, OURO, 70, { vmin = 260, vmax = 980, gravidade = 420, z = 7 })
	UiEfeitos.raios(self.atras, Vector2.new(a.X * 0.5, a.Y * 0.46), OURO, a.Y * 1.7, 7, 7, 2)
end

-- um foguete sobe e estoura no céu
function PodioEpico._fogo(self: any)
	local a = self.pai.AbsoluteSize
	local alvo = Vector2.new(a.X * self.rng:NextNumber(0.07, 0.93), a.Y * self.rng:NextNumber(0.08, 0.44))
	local tinta = ({ self.cor:Lerp(Color3.new(1, 1, 1), 0.25), OURO, Color3.fromRGB(255, 246, 228) } :: { Color3 })[self.rng:NextInteger(
		1,
		3
	)]
	local rastro = Instance.new("Frame")
	rastro.Name = "Foguete"
	rastro.BackgroundColor3 = tinta
	rastro.BorderSizePixel = 0
	rastro.AnchorPoint = Vector2.new(0.5, 0.5)
	rastro.Size = UDim2.fromOffset(math.max(2, a.Y * 0.004), a.Y * 0.05)
	rastro.Position = UDim2.fromOffset(alvo.X + self.rng:NextNumber(-30, 30), a.Y * 0.95)
	rastro.ZIndex = 2
	rastro.Parent = self.atras
	local dur = self.rng:NextNumber(0.34, 0.5)
	local tw = TweenService:Create(rastro, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(alvo.X, alvo.Y),
		BackgroundTransparency = 0.5,
	})
	local g = self.geracao
	tw.Completed:Once(function()
		rastro:Destroy()
		if g ~= self.geracao then
			return
		end
		UiEfeitos.faiscas(self.atras, alvo, tinta, 34, {
			vmin = 90,
			vmax = a.Y * 0.62,
			gravidade = 150,
			arrasto = 1.5,
			tam = math.max(12, a.Y * 0.024),
			z = 2,
		})
		UiEfeitos.onda(self.atras, alvo, tinta, a.Y * 0.13, 0.5, 2)
	end)
	tw:Play()
end

-- t: tempo da cena; o letreiro sai quando a câmera vai até o melhor da partida
function PodioEpico.passo(self: any, t: number)
	if self.grande.Text == "" then
		return
	end
	if not self.feito and t >= pouso() then
		self:_batida()
	end
	if not self.feito then
		return
	end
	local P = Comemoracao.PODIO
	local some = math.clamp((t - P.zoom) / 0.6, 0, 1)
	if some > 0 then
		self.grande.TextTransparency = some
		self.grande.TextStrokeTransparency = 0.15 + 0.85 * some
		self.linha.TextTransparency = some
		self.linha.TextStrokeTransparency = 0.35 + 0.65 * some
	end
	if t >= self.proximo and t < FIM_FOGOS and not UiEfeitos.calmo() then
		self.proximo = t + self.rng:NextNumber(0.38, 0.85)
		self:_fogo()
	end
end

return PodioEpico
