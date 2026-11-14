--!strict
-- HUD de MEDIÇÃO da F1 (F3 liga/desliga). Não é HUD de jogo: o jogo final não tem HUD assim.
-- Mostra: fps médio, tempo de quadro p99 (últimos 600 quadros), grade de 1965, setor,
-- velocidade (m/s) e cronômetro de travessia leste->oeste (dispara ao cruzar as bordas).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Geometry = require(ReplicatedStorage.Shared.Geometry)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "VT65DebugHud"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local text = Instance.new("TextLabel")
text.Position = UDim2.fromOffset(8, 8)
text.Size = UDim2.fromOffset(380, 190)
text.BackgroundTransparency = 0.4
text.BackgroundColor3 = Color3.new(0, 0, 0)
text.TextColor3 = Color3.new(1, 1, 1)
text.TextXAlignment = Enum.TextXAlignment.Left
text.TextYAlignment = Enum.TextYAlignment.Top
text.Font = Enum.Font.Code
text.TextSize = 14
text.Parent = gui

-- Ferramentas de teste do controle (Parte 12.7), só no teclado do testador:
-- F8 começa/para a gravação das entradas do controle (o JSON vai para o Output);
-- F9 reproduz a última gravação pela mesma camada de entrada do jogo.
local Input = require(script.Parent.Input)
local HttpService = game:GetService("HttpService")
local recording = false
local lastTape: { any }? = nil
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F3 then
		gui.Enabled = not gui.Enabled
	elseif input.KeyCode == Enum.KeyCode.F8 then
		if recording then
			lastTape = Input.stopRecording()
			recording = false
			print("[VT65] gravação do controle:", HttpService:JSONEncode(lastTape))
		else
			Input.startRecording()
			recording = true
			print("[VT65] gravando entradas do controle (F8 para parar)")
		end
	elseif input.KeyCode == Enum.KeyCode.F9 and lastTape then
		print("[VT65] reproduzindo", #lastTape, "eventos")
		task.spawn(Input.replay, lastTape)
	end
end)

local N = 600
local frames = table.create(N, 0) :: { number }
local idx = 0
local cross: { start: number?, done: number? } = {}
local B = MapConfig.Bounds
local EDGE = 50 / MapConfig.STUD_M -- 50 m das bordas

RunService.RenderStepped:Connect(function(dt)
	idx = idx % N + 1
	frames[idx] = dt
	if not gui.Enabled then
		return
	end
	local sorted = table.clone(frames)
	table.sort(sorted)
	local p99 = sorted[math.floor(N * 0.99)]
	local sum = 0
	for _, v in frames do
		sum += v
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local line2, line3 = "-", "-"
	if root then
		local p = root.Position
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude * MapConfig.STUD_M
		line2 = string.format(
			"%s  setor %s  %.2f m/s",
			Geometry.gridRef1965(MapConfig.GridOrigin1965, p.X, p.Z, MapConfig.STUD_M),
			tostring(player:GetAttribute("Sector") or "-"),
			speed
		)
		-- cronômetro: parte a menos de 50 m da borda leste, para a menos de 50 m da oeste
		if p.X > B.maxX - EDGE then
			cross.start, cross.done = os.clock(), nil
		elseif cross.start and not cross.done and p.X < B.minX + EDGE then
			cross.done = os.clock() - cross.start
		end
		if cross.done then
			line3 = string.format("travessia L->O: %.0f s (%.1f min)", cross.done, cross.done / 60)
		elseif cross.start then
			line3 = string.format("travessia em curso: %.0f s", os.clock() - cross.start)
		end
	end
	local heightM = 0
	if char then
		heightM = (char :: Model):GetExtentsSize().Y * MapConfig.STUD_M
	end
	text.Text = string.format(
		"VT65 — medição\nfps médio %.1f | p99 %.1f ms (meta <= 16,7)\n%s\n%s\nX %.0f Z %.0f studs | soldado %.2f m (meta 2,00)\nSol: az %.1f° el %.1f° (ajuste %.2f°)",
		N / sum,
		p99 * 1000,
		line2,
		line3,
		root and root.Position.X or 0,
		root and root.Position.Z or 0,
		heightM,
		ReplicatedStorage:GetAttribute("SunAzimuth") or 0,
		ReplicatedStorage:GetAttribute("SunElevation") or 0,
		ReplicatedStorage:GetAttribute("SunFitErrorDeg") or 0
	)
end)
