--!strict
-- Corpo e cura no cliente: sem barra de vida. A visão perde cor e escurece com a vida, borra
-- depois da reanimação e quando caído. Entradas no fim do arquivo (camada Input, Parte 12).
-- Caído e morto: a tela de queda e a ficha de baixa ficam no CasualtyScreen (2026-11-11); caído, a
-- visão turva pulsa com o coração dele.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local CasualtyScreen = require(script.Parent.CasualtyScreen)
local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "VT65Body"
cc.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Name = "VT65BodyBlur"
blur.Size = 0
blur.Parent = Lighting

local state: any = nil
Net.event("Medical_State").OnClientEvent:Connect(function(s)
	state = s
	state.recvAt = os.clock()
	CasualtyScreen.setMedical(s)
end)

-- aliado mais próximo (jogador ou bot) a até 3 m
local function nearestAlly(): Model?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and root) then
		return nil
	end
	local myFaction = player:GetAttribute("Faction")
	local candidates: { Model } = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			table.insert(candidates, p.Character)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				table.insert(candidates, m)
			end
		end
	end
	local best, bestD = nil, 3 / 0.28
	for _, m in candidates do
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and m:GetAttribute("Faction") == myFaction then
			local d = (r.Position - root.Position).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

-- Entradas pela camada única (Parte 12): direcional ↓ / G = bandagem rápida (trata o sangramento
-- mais urgente: arterial pede torniquete); T ou roda = torniquete; X segurado / F = interagir com
-- aliado (reanimar, tratar, fazer curativo) quando não há outra interação na tela; caído: B
-- segurado ou H = desistir.
local function selfOp(op: string)
	if op == "giveup" then
		CasualtyScreen.noteGiveUp()
	end
	Net.event("Medical_Action"):FireServer({ op = op })
end

local function quickBandage()
	-- D-99: o servidor diz se há ferimento arterial (a taxa de sangramento caiu ~5x e o limiar antigo
	-- de 4 nunca mais dispararia)
	local arterial = state ~= nil and state.arterial == true
	if arterial and (state.tourniquets or 0) > 0 then
		selfOp("tourniquet")
	else
		selfOp("bandage")
	end
end

local function interactAlly()
	if player:GetAttribute("PromptShown") then
		return -- há uma interação do mundo (caixote, túnel, construção) sob a mira
	end
	local ally = nearestAlly()
	if ally then
		local op = if ally:GetAttribute("Downed")
			then "revive"
			elseif player:GetAttribute("Role") == "medic" then "treat"
			else "bandage"
		Net.event("Medical_Action"):FireServer({ op = op, target = ally })
	end
end

Input.on("quick_bandage", "press", quickBandage) -- tecla G
Input.on("quick_bandage", "tap", quickBandage) -- ↓ tocar (segurar: rádio do squad)
Input.on("tourniquet", "press", function()
	selfOp("tourniquet")
end)
Input.on("give_up", "press", function()
	selfOp("giveup")
end)
Input.on("interact", "holdStart", interactAlly)
-- toque (Parte 13): o botão contextual (Interagir) chama o mesmo, quando o Input.virtual não existe
Bus.on("interact_ally", interactAlly)
Bus.on("equip_item", function(id: string)
	if id == "bandage" then
		quickBandage()
	elseif id == "tourniquet" then
		selfOp("tourniquet")
	end
end)
-- caído: B segurado desiste (o B normal agacha/deita, mas caído não há postura)
local bDown = 0
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.ButtonB and player:GetAttribute("Downed") then
		bDown = os.clock()
		local t0 = bDown
		CasualtyScreen.holdGiveUp(t0) -- o anel da tela de queda enche enquanto segura
		task.delay(1.0, function()
			if bDown == t0 and player:GetAttribute("Downed") then
				selfOp("giveup")
			end
		end)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.ButtonB then
		bDown = 0
		CasualtyScreen.holdGiveUp(nil)
	end
end)

RunService.RenderStepped:Connect(function()
	if not state then
		cc.Saturation, cc.Brightness = 0, 0
		blur.Size = 0
		return
	end
	local h = math.clamp(state.health or 100, 0, 100) / 100
	-- menos vida: menos cor e mais escuro (a correção global de -0,1 fica no Lighting)
	cc.Saturation = -0.9 * (1 - h)
	cc.Brightness = -0.25 * (1 - h)
	local now = os.clock() - (state.recvAt or os.clock()) + (state.now or 0)
	local blurred = state.downedAt ~= nil or (state.blurUntil or 0) > now
	-- caído: a visão turva pulsa com o coração (CasualtyScreen.beat, 0..1) e perde ainda mais a cor
	if state.downedAt then
		local b = CasualtyScreen.beat()
		blur.Size = 14 + 8 * b
		cc.Saturation = -0.95
		cc.Brightness = -0.28 - 0.06 * b
	else
		blur.Size = if blurred then 8 else 0
	end
end)

player.CharacterAdded:Connect(function()
	state = nil
end)
