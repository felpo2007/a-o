--!strict
-- Rádio do squad (Parte 11): atributo "Radio" no jogador que carrega, antena visível nas costas,
-- rádio caído ao morrer (prompt "Pegar o rádio" para o mesmo lado). Regras em Shared/Radio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Radio = require(ReplicatedStorage.Shared.Radio)

local RadioService = {}
local M = 0.28

-- antena de chicote do PRC-10/PRC-25 (~1,2 m) presa nas costas.
-- O personagem vem de LoadCharacterWithHumanoidDescriptionAsync (D-70): depois do CharacterAdded a
-- descrição troca o tronco pelo do corpo "Man", a solda ia junto com o tronco velho e a antena caía
-- do mapa (o operador de rádio nascia sem antena; Studio, 2026-11-11). Agora a antena é refeita a
-- cada tronco novo, com Weld de deslocamento fixo (vale mesmo antes de o tronco ir para o lugar).
local function antenna(char: Model)
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	if not torso then
		return
	end
	local old = char:FindFirstChild("RadioAntenna")
	if old then
		local w = old:FindFirstChildOfClass("Weld")
		if w and w.Part0 == torso then
			return -- já presa a este tronco
		end
		old:Destroy()
	end
	local a = Instance.new("Part")
	a.Name = "RadioAntenna"
	a.Size = Vector3.new(0.012 / M, 1.2 / M, 0.012 / M)
	a.Color = Color3.fromRGB(40, 42, 34)
	a.CanCollide, a.CanQuery, a.CanTouch, a.Massless = false, false, false, true
	local w = Instance.new("Weld")
	w.Part0, w.Part1 = torso, a
	w.C0 = CFrame.new(0.12 / M, 0.6 / M, 0.18 / M)
	w.Parent = a
	a.CFrame = torso.CFrame * w.C0
	a.Parent = char
end

local function give(p: Player)
	p:SetAttribute("Radio", true)
	if p.Character then
		antenna(p.Character)
	end
end

local function drop(pos: Vector3, faction: string)
	local r = Instance.new("Part")
	r.Name = "RadioCaido"
	r.Size = Vector3.new(0.3 / M, 0.25 / M, 0.12 / M)
	r.Color = Color3.fromRGB(70, 74, 52)
	r.Anchored, r.CanCollide = true, false
	r.CFrame = CFrame.new(pos)
	r:SetAttribute("Faction", faction)
	r.Parent = workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pegar o rádio"
	prompt.ObjectText = "link com o comando"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 8
	prompt.Parent = r
	prompt.Triggered:Connect(function(p: Player)
		local c = p.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local alive = hum ~= nil and hum.Health > 0 and not (c :: Model):GetAttribute("Downed")
		if r.Parent and Radio.canPickUp(faction, p:GetAttribute("Faction") :: string?, alive) then
			r:Destroy()
			give(p)
		end
	end)
	task.delay(Radio.TTL_S, function()
		r:Destroy()
	end)
end

local function track(p: Player)
	p.CharacterAdded:Connect(function(char)
		p:SetAttribute("Radio", Radio.startsWithRadio(p:GetAttribute("Role") :: string?))
		if p:GetAttribute("Radio") then
			antenna(char)
		end
		-- tronco trocado pela descrição (ou pelo uniforme): refaz a antena no novo
		char.ChildAdded:Connect(function(c: Instance)
			if (c.Name == "UpperTorso" or c.Name == "Torso") and p:GetAttribute("Radio") then
				task.defer(antenna, char)
			end
		end)
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Once(function()
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if p:GetAttribute("Radio") and root then
					p:SetAttribute("Radio", false)
					drop(root.Position, tostring(p:GetAttribute("Faction")))
				end
			end)
		end
	end)
end

function RadioService.start()
	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
end

return RadioService
