--!strict
-- Armadilhas VC (Parte 11): a peça é invisível no servidor. Aqui ela aparece SÓ para quem é do
-- lado de quem armou (para não pisar) ou depois de detectada pelo engenheiro inimigo (atributo
-- Detected, que vale para todos). Mudança local: não replica.
local Players = game:GetService("Players")

local Traps = require(game:GetService("ReplicatedStorage").Shared.Traps)

local player = Players.LocalPlayer

local function show(p: BasePart)
	local mine = p:GetAttribute("Faction") == player:GetAttribute("Faction")
	local detected = p:GetAttribute("Detected") == true
	local visible = mine or detected
	p.Transparency = if visible then (if mine then 0.6 else 0.2) else 1
	p.Color = if detected and not mine then Color3.fromRGB(200, 40, 30) else Color3.fromRGB(120, 100, 60)
	p.Material = Enum.Material.SmoothPlastic
	local bb = p:FindFirstChild("VT65TrapLabel") :: BillboardGui?
	if visible and not bb then
		local g = Instance.new("BillboardGui")
		g.Name = "VT65TrapLabel"
		g.Size = UDim2.fromOffset(140, 26)
		g.StudsOffset = Vector3.new(0, 1.5, 0)
		g.MaxDistance = 40
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextColor3 = if mine then Color3.fromRGB(230, 220, 160) else Color3.fromRGB(255, 120, 90)
		t.TextStrokeTransparency = 0.3
		t.Font = Enum.Font.GothamBold
		t.TextSize = 14
		local kind = Traps.KINDS[p:GetAttribute("Trap") :: string]
		t.Text = "⚠ " .. (if kind then kind.name else "armadilha")
		t.Parent = g
		g.Parent = p
	elseif not visible and bb then
		bb:Destroy()
	end
end

task.spawn(function()
	local folder = workspace:WaitForChild("Traps", 60)
	if not folder then
		return
	end
	local function hook(p: Instance)
		if p:IsA("BasePart") then
			show(p)
			p:GetAttributeChangedSignal("Detected"):Connect(function()
				show(p)
			end)
		end
	end
	for _, p in folder:GetChildren() do
		hook(p)
	end
	folder.ChildAdded:Connect(hook)
	player:GetAttributeChangedSignal("Faction"):Connect(function()
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				show(p)
			end
		end
	end)
end)
