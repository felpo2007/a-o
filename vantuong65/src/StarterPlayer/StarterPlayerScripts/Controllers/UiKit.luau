--!strict
-- Interface para TV e controle (Parte 12.5): texto mínimo de 24 px na TV (IsTenFootInterface),
-- nada essencial fora da área segura (ScreenInsets = DeviceSafeInsets), foco sempre visível com
-- moldura de alto contraste e toda tela abrindo com um item focado (GuiService.SelectedObject).
-- No lobby o controle usa o cursor virtual (VirtualCursor): todo UiKit.button já fica registrado
-- nele, e o foco automático fica desligado enquanto o cursor estiver na tela.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Lang = require(game:GetService("ReplicatedStorage").Shared.Lang)
local Input = require(script.Parent.Input)
local VirtualCursor = require(script.Parent.VirtualCursor)

local UiKit = {}
local player = Players.LocalPlayer

UiKit.PAPER = Color3.fromRGB(214, 203, 170)
UiKit.INK = Color3.fromRGB(40, 36, 28)
UiKit.OLIVE = Color3.fromRGB(86, 90, 62)
-- dossiê de operações de 1965 (tela de deslocamento e mapa): pasta parda, ficha pautada, carimbo
UiKit.NIGHT = Color3.fromRGB(20, 22, 16) -- fundo verde-oliva quase preto
UiKit.DRAB = Color3.fromRGB(46, 50, 36) -- painel oliva escuro
UiKit.KHAKI = Color3.fromRGB(201, 186, 140) -- texto claro sobre oliva
UiKit.MANILA = Color3.fromRGB(190, 166, 116) -- pasta parda
UiKit.CARD = Color3.fromRGB(234, 226, 200) -- ficha de arquivo
UiKit.RULE_RED = Color3.fromRGB(176, 62, 48) -- linha de cabeçalho da ficha
UiKit.RULE_BLUE = Color3.fromRGB(118, 138, 168) -- pauta da ficha
UiKit.STAMP = Color3.fromRGB(150, 40, 30) -- tinta de carimbo
UiKit.BRASS = Color3.fromRGB(214, 172, 72) -- latão: recompensa e botão em destaque

-- tipografia dos avisos e do tutorial, a mesma do lobby: título condensado (Oswald) e texto legível
UiKit.HEAD_FONT = Font.fromName("Oswald", Enum.FontWeight.Bold)
UiKit.BODY_FONT = Enum.Font.Arimo

-- O Oswald pode não ter as letras do vietnamita (como a máquina de escrever do lobby): texto com
-- letra fora do Latin-1 vai no Arimo, que tem.
function UiKit.headFont(text: string): Font
	return if string.find(text, "[\196-\244]") then Font.fromEnum(Enum.Font.ArimoBold) else UiKit.HEAD_FONT
end

-- Caixa alta que também sobe as letras acentuadas do português e do vietnamita (o string.upper só
-- mexe no ASCII; no Studio "An Cường" saía "AN CườNG"). Mora no Shared/Lang (a tradução usa a
-- mesma para achar "FUZILEIRO" no dicionário de "Fuzileiro").
UiKit.upper = Lang.upper

-- Primeira letra em maiúscula (texto do servidor chega em minúscula: "alvo fora do mapa").
function UiKit.capitalize(s: string): string
	if string.byte(s, 1) == 195 then
		return UiKit.upper(string.sub(s, 1, 2)) .. string.sub(s, 3)
	end
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

function UiKit.tv(): boolean
	local ok, v = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and v == true
end

-- tamanho de texto: na TV nunca abaixo de 24 px (1080p)
function UiKit.text(size: number): number
	return if UiKit.tv() then math.max(size, 24) else size
end

-- Texto dentro de uma tela com UIScale: na TV o tamanho NA TELA (size × scale) nunca fica abaixo de
-- 24 px. Fora da TV devolve o tamanho de projeto.
function UiKit.textAt(size: number, scale: number): number
	if not UiKit.tv() then
		return size
	end
	return math.max(size, math.ceil(24 / math.max(scale, 0.05)))
end

function UiKit.screen(name: string, order: number?): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.DisplayOrder = order or 10
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	g.Parent = player:WaitForChild("PlayerGui")
	return g
end

-- ===== movimento (pedido do dono, 2026-11-11: "mais fluido") =====
-- Tempos de interface: QUICK para realce e cor, SOFT para escala e entrada de cartão.
UiKit.QUICK = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
UiKit.SOFT = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function UiKit.tween(o: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local t = TweenService:Create(o, info, props)
	t:Play()
	return t
end

-- Realce animado de um botão (mouse, foco do Roblox e cursor virtual chamam set): cresce um pouco,
-- a borda vira latão e o fundo passa para `quente`. base() troca a cor de repouso (ficha cheia,
-- trancada) com a mesma transição. A escala usa o UIScale "Escala" do botão (criado se faltar), o
-- mesmo que a entrada escalonada dos cartões anima.
export type Realce = {
	set: (on: boolean) -> (),
	base: (color: Color3) -> (),
	hot: () -> boolean,
}
function UiKit.realce(b: GuiObject, base: Color3?, quente: Color3?, escala: number?): Realce
	local sc = b:FindFirstChild("Escala")
	if not (sc and sc:IsA("UIScale")) then
		local s = Instance.new("UIScale")
		s.Name = "Escala"
		s.Parent = b
		sc = s
	end
	local scale = sc :: UIScale
	local ring: UIStroke? = nil
	for _, c in b:GetChildren() do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			ring = c
			break
		end
	end
	if not ring then
		local s = Instance.new("UIStroke")
		s.Name = "Realce"
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Color = UiKit.BRASS
		s.Thickness = 2
		s.Transparency = 1
		s.Parent = b
		ring = s
	end
	local edge = ring :: UIStroke
	local rest = { color = edge.Color, thick = edge.Thickness, tr = edge.Transparency }
	local on = false
	local cold: Color3? = base
	local function paint()
		local c = if on and quente then quente else cold
		if c then
			UiKit.tween(b, UiKit.QUICK, { BackgroundColor3 = c })
		end
	end
	return {
		set = function(v: boolean)
			if v == on then
				return
			end
			on = v
			UiKit.tween(scale, UiKit.SOFT, { Scale = if v then (escala or 1.035) else 1 })
			UiKit.tween(edge, UiKit.QUICK, {
				Color = if v then UiKit.BRASS else rest.color,
				Thickness = if v then math.max(rest.thick, 2) else rest.thick,
				Transparency = if v then 0 else rest.tr,
			})
			paint()
		end,
		base = function(c: Color3)
			if c == cold then
				return -- a tela redesenha muito: só anima quando a cor muda de fato
			end
			cold = c
			paint()
		end,
		hot = function(): boolean
			return on
		end,
	}
end

-- moldura de foco de alto contraste (amarelo sobre preto, 4 px). Ao trocar de item ela "fecha" sobre
-- o novo (vem de 10 px para 4) e depois respira devagar: o foco do controle nunca some nem pula seco.
local focusFrame = Instance.new("Frame")
focusFrame.Name = "VT65Focus"
focusFrame.BackgroundTransparency = 1
focusFrame.Size = UDim2.new(1, 8, 1, 8)
focusFrame.Position = UDim2.fromOffset(-4, -4)
local stroke = Instance.new("UIStroke")
stroke.Thickness = 4
stroke.Color = Color3.fromRGB(255, 214, 0)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = focusFrame
UiKit.FOCUS = focusFrame

local breathe: Tween? = nil
GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
	local b = breathe
	if b then
		b:Cancel()
		breathe = nil
	end
	stroke.Transparency = 0
	if not GuiService.SelectedObject then
		return
	end
	focusFrame.Size = UDim2.new(1, 20, 1, 20)
	focusFrame.Position = UDim2.fromOffset(-10, -10)
	UiKit.tween(focusFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 8, 1, 8),
		Position = UDim2.fromOffset(-4, -4),
	})
	local t = TweenService:Create(
		stroke,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.25),
		{ Transparency = 0.4 }
	)
	t:Play()
	breathe = t
end)

function UiKit.button(parent: Instance, text: string, onClick: () -> (), order: number?): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -8, 0, if UiKit.tv() then 48 else 34)
	b.BackgroundColor3 = Color3.fromRGB(120, 112, 84)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = UiKit.text(16)
	b.TextWrapped = true
	b.Text = text
	b.Selectable = true
	b.SelectionImageObject = focusFrame
	b.LayoutOrder = order or 0
	b.Parent = parent
	b.Activated:Connect(onClick)
	VirtualCursor.bind(b, onClick)
	return b
end

-- Liga um botão feito à mão ao clique (mouse, toque, A da navegação do Roblox) e ao cursor virtual
-- do controle; hover (opcional) recebe também o passar do cursor virtual.
function UiKit.bind(b: GuiButton, onClick: () -> (), hover: ((boolean) -> ())?)
	b.Activated:Connect(onClick)
	VirtualCursor.bind(b, onClick, hover)
end

function UiKit.label(parent: Instance, text: string, size: number?, height: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -8, 0, height or (if UiKit.tv() then 34 else 26))
	t.BackgroundTransparency = 1
	t.TextColor3 = UiKit.INK
	t.Font = Enum.Font.GothamBold
	t.TextSize = UiKit.text(size or 18)
	t.TextWrapped = true
	t.Text = text
	t.Parent = parent
	return t
end

local function firstSelectable(root: Instance): GuiObject?
	local best: GuiObject? = nil
	local bestKey = math.huge
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.Selectable and d.Visible then
			local p = d.AbsolutePosition
			local key = p.Y * 10000 + p.X
			if key < bestKey then
				best, bestKey = d, key
			end
		end
	end
	return best
end

-- Põe o foco no primeiro item (de cima para baixo) se o jogador estiver no controle.
function UiKit.focus(root: Instance)
	if not Input.isGamepad() or VirtualCursor.isActive() then
		return -- com o cursor virtual, quem escolhe é o cursor (A não pode ativar dois botões)
	end
	task.defer(function()
		local cur = GuiService.SelectedObject
		if cur and cur:IsDescendantOf(root) and cur.Visible then
			return
		end
		local f = firstSelectable(root)
		if f then
			GuiService.SelectedObject = f
		end
	end)
end

-- Vigia: tela visível no controle sem foco nela vira aviso e é corrigida (Parte 12.7).
local watched: { { root: GuiObject, active: () -> boolean, warned: boolean } } = {}
function UiKit.watch(root: GuiObject, active: () -> boolean)
	table.insert(watched, { root = root, active = active, warned = false })
end
task.spawn(function()
	while true do
		task.wait(0.5)
		if Input.isGamepad() and GuiService.GuiNavigationEnabled and not VirtualCursor.isActive() then
			for _, w in watched do
				if w.active() and w.root.Visible then
					local cur = GuiService.SelectedObject
					if not (cur and cur:IsDescendantOf(w.root)) then
						if not firstSelectable(w.root) then
							if not w.warned then
								w.warned = true
								warn("[VT65] tela sem item focável:", w.root:GetFullName())
							end
						else
							UiKit.focus(w.root)
						end
					end
				end
			end
		end
	end
end)

Input.DeviceChanged:Connect(function(d)
	if d ~= "gamepad" then
		GuiService.SelectedObject = nil
	end
end)

return UiKit
