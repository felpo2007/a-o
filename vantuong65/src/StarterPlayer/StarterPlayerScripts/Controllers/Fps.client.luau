--!strict
-- FPS e ping na tela (v43, pedido do dono: "coloque os dados de fps no jogo"). Um rótulo pequeno no
-- canto de baixo à esquerda (no alto à direita encostava na faixa da frente em janela estreita e nos
-- botões do toque), só leitura, atualizado 2 vezes por segundo: quadros por segundo (média do meio
-- segundo) e o ping até o servidor. A cor avisa:
-- verde a partir de 50 fps, latão de 30 a 49, vermelho abaixo de 30. Liga e desliga em
-- Configurações > Gráficos ("FPS e ping na tela", Input.settings.showFps; padrão: mostrar).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer

local gui = UiKit.screen("VT65Fps", 46) -- acima dos avisos (45): é só leitura, pequeno
gui.IgnoreGuiInset = true

local label = Instance.new("TextLabel")
label.Name = "Fps"
label.AnchorPoint = Vector2.new(0, 1)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.55
label.BorderSizePixel = 0
label.AutomaticSize = Enum.AutomaticSize.X
label.Size = UDim2.fromOffset(0, 20)
label.FontFace = UiKit.HEAD_FONT
label.TextSize = 14
label.TextColor3 = Color3.fromRGB(150, 210, 120)
label.Text = ""
label.Active = false
label.Parent = gui
UiKit.corner(label, 4)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = label
end

local GOOD = Color3.fromRGB(150, 210, 120)
local MID = UiKit.BRASS_LIGHT
local BAD = Color3.fromRGB(230, 96, 80)

-- canto de baixo à esquerda, dentro da área segura (entalhe e barra de gestos do celular)
local function place()
	local vp = workspace.CurrentCamera.ViewportSize
	local _, br = GuiService:GetGuiInset()
	label.Position = UDim2.fromOffset(8, vp.Y - math.max(br.Y, 0) - 6)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
place()

local frames, t0 = 0, os.clock()
RunService.RenderStepped:Connect(function()
	frames += 1
	local now = os.clock()
	if now - t0 < 0.5 then
		return
	end
	local fps = frames / (now - t0)
	frames, t0 = 0, now
	local on = (Input.settings :: any).showFps ~= false
	gui.Enabled = on
	if not on then
		return
	end
	local ok, ping = pcall(function(): number
		return player:GetNetworkPing()
	end)
	local ms = if ok and type(ping) == "number" then math.floor(ping * 1000 + 0.5) else nil
	local f = math.floor(fps + 0.5)
	label.Text = if ms then string.format("%d FPS · %d ms", f, ms) else string.format("%d FPS", f)
	label.TextColor3 = if f >= 50 then GOOD elseif f >= 30 then MID else BAD
end)
