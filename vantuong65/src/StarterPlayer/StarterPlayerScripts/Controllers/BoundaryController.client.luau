--!strict
-- Aviso de saída da área de combate (lê o atributo publicado pelo MapService).
-- D-231 (relatório do dono: o aviso tem que responder "o que aconteceu?", "quanto tempo tenho?" e
-- "para onde preciso ir?", sem tomar a tela): um cartão compacto no alto, com a seta girando para o
-- ponto mais perto dentro da área, a contagem grande e a distância. Nos últimos 3 s fica vermelho.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Geometry = require(ReplicatedStorage.Shared.Geometry)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local M = MapConfig.STUD_M

local gui = Instance.new("ScreenGui")
gui.Name = "BoundaryWarning"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 16
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local W, H = 300, 66
local card = Instance.new("Frame")
card.Name = "Aviso"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.fromScale(0.5, 0.15)
card.Size = UDim2.fromOffset(W, H)
card.BackgroundColor3 = V.PANEL
card.BackgroundTransparency = 0.12
card.BorderSizePixel = 0
card.Parent = gui
UiKit.corner(card, 4)
local borda = UiKit.edge(card, V.AMBAR, 2, 0)
UiKit.fit(gui, card, W, H, 8)

local seta = Instance.new("TextLabel")
seta.Name = "Seta"
seta.BackgroundTransparency = 1
seta.Position = UDim2.fromOffset(8, 8)
seta.Size = UDim2.fromOffset(50, 50)
seta.Font = Enum.Font.GothamBold
seta.Text = "▲"
seta.TextSize = 34
seta.TextColor3 = V.AMBAR
seta.Parent = card

local titulo = UiKit.rotulo(card, 18, V.TEXT, F.TITLE)
titulo.Name = "Titulo"
titulo.Text = "FORA DA ÁREA"
titulo.Position = UDim2.fromOffset(66, 7)
titulo.Size = UDim2.fromOffset(160, 26)

local rumo = UiKit.rotulo(card, 15, V.DIM, F.TITLE_MED)
rumo.Name = "Rumo"
rumo.Position = UDim2.fromOffset(66, 35)
rumo.Size = UDim2.fromOffset(160, 22)

local conta = UiKit.rotulo(card, 38, V.AMBAR, F.TITLE)
conta.Name = "Contagem"
conta.AnchorPoint = Vector2.new(1, 0.5)
conta.Position = UDim2.new(1, -12, 0.5, 0)
conta.Size = UDim2.fromOffset(62, 50)
conta.TextXAlignment = Enum.TextXAlignment.Right

local ligado: RBXScriptConnection? = nil

local function aponta()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera
	if not (root and cam) then
		return
	end
	local p = root.Position
	local tx, tz, d = Geometry.voltaParaArea(MapConfig.Bounds, p.X, p.Z, 12)
	local alvo = Vector3.new(tx - p.X, 0, tz - p.Z)
	local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	if alvo.Magnitude > 1e-3 and look.Magnitude > 1e-3 then
		local a, b = look.Unit, alvo.Unit
		seta.Rotation = math.deg(math.atan2(a.X * b.Z - a.Z * b.X, a:Dot(b)))
	end
	rumo.Text = string.format("Volte: siga a seta · %d m", math.ceil(d * M))
end

local function refresh()
	local left = player:GetAttribute("OOBSecondsLeft")
	local on = type(left) == "number"
	gui.Enabled = on
	if on then
		local n = left :: number
		conta.Text = string.format("%d", n)
		local cor = if n <= 3 then V.RED_HI else V.AMBAR
		conta.TextColor3, seta.TextColor3, borda.Color = cor, cor, cor
		if not ligado then
			ligado = RunService.RenderStepped:Connect(aponta)
		end
	elseif ligado then
		ligado:Disconnect()
		ligado = nil
	end
end

player:GetAttributeChangedSignal("OOBSecondsLeft"):Connect(refresh)
refresh()

-- Studio: workspace "VT65DevLimite" = segundos mostra o aviso sem sair do mapa (nil apaga)
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevLimite"):Connect(function()
		player:SetAttribute("OOBSecondsLeft", workspace:GetAttribute("VT65DevLimite"))
	end)
end
