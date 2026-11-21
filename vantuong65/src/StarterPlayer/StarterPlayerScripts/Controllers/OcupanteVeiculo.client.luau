--!strict
-- D-236 (dono: "os soldados devem ficar dentro dos tanques e veiculos sem aparecerem para fora"). Quem
-- está num lugar fechado some para este cliente (Vehicles.ocupanteAparece decide): o corpo de 2 m não
-- atravessa mais o teto do carro nem sai da escotilha. Só muda o desenho: colisão e acerto continuam.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local player = Players.LocalPlayer
local escondidos: { [Model]: boolean } = {}

local function pinta(m: Model, v: number)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = v
		elseif d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = v
		end
	end
end

local function varre()
	local quer: { [Model]: boolean } = {}
	local pasta = workspace:FindFirstChild("Vehicles")
	for _, v in if pasta then pasta:GetChildren() else {} do
		local spec = v:GetAttribute("Spec")
		if type(spec) == "string" then
			for _, s in v:GetChildren() do
				if s:IsA("Seat") and s.Occupant then
					local id = s:GetAttribute("SeatId")
					local corpo = s.Occupant.Parent
					if
						type(id) == "string"
						and corpo
						and corpo:IsA("Model")
						and not Vehicles.ocupanteAparece(spec, id)
					then
						quer[corpo] = true
					end
				end
			end
		end
	end
	for m in escondidos do
		if not quer[m] then
			escondidos[m] = nil
			if m.Parent then
				pinta(m, 0)
			end
		end
	end
	for m in quer do
		escondidos[m] = true
		if m ~= player.Character then
			pinta(m, 1) -- de novo a cada volta: a arma e o equipamento podem chegar depois de sentar
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.2)
		varre()
	end
end)

-- o próprio corpo: o módulo de câmera do Roblox refaz a transparência a cada quadro; esta passa depois
RunService:BindToRenderStep("VT65OcupanteOculto", Enum.RenderPriority.Camera.Value + 25, function()
	local c = player.Character
	if c and escondidos[c] then
		pinta(c, 1)
	end
end)
