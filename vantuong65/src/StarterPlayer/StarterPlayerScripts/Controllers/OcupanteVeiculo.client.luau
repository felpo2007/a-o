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

-- D-237: quem está numa torreta do LVTP-5 aparece com as duas mãos na metralhadora; o fuzil dele some
local naTorreta: { [Model]: boolean } = {}
local function ponto(p: BasePart, nome: string, cf: CFrame): Attachment
	local a = p:FindFirstChild(nome) :: Attachment?
	if not a then
		local novo = Instance.new("Attachment")
		novo.Name = nome
		novo.CFrame = p.CFrame:ToObjectSpace(cf)
		novo.Parent = p
		a = novo
	end
	return a :: Attachment
end

local function ik(hum: Humanoid, corpo: Model, nome: string, lado: string, alvo: Attachment)
	if hum:FindFirstChild(nome) then
		return
	end
	local raiz = corpo:FindFirstChild(lado .. "UpperArm")
	local mao = corpo:FindFirstChild(lado .. "Hand")
	if not (raiz and mao) then
		return
	end
	local c = Instance.new("IKControl")
	c.Name = nome
	c.Type = Enum.IKControlType.Position
	c.ChainRoot = raiz
	c.EndEffector = mao
	c.Target = alvo
	c.Weight = 1
	c.Parent = hum
end

local function maosNaArma(corpo: Model, v: Model, seat: Seat, id: string)
	local hum = corpo:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local arma = v:FindFirstChild("Arma_" .. id)
	local w = arma and arma:FindFirstChild("Weapon") :: Model?
	local prim = w and w.PrimaryPart
	local aD = prim and prim:FindFirstChild("Grip") :: Attachment?
	local aE = prim and prim:FindFirstChild("Support") :: Attachment?
	if not (aD and aE) then
		-- a cúpula da frente é parte da malha: dois pontos na frente do peito, presos à torre
		local torre = v:FindFirstChild("Torre", true)
		if not (torre and torre:IsA("BasePart")) then
			return
		end
		aD = ponto(torre, "VT65MaoD", seat.CFrame * CFrame.new(0.6, 2.2, -2.2))
		aE = ponto(torre, "VT65MaoE", seat.CFrame * CFrame.new(-0.6, 2.3, -3.1))
	end
	ik(hum, corpo, "VT65TorretaD", "Right", aD :: Attachment)
	ik(hum, corpo, "VT65TorretaE", "Left", aE :: Attachment)
	local fuzil = corpo:FindFirstChild("Weapon")
	if fuzil then
		pinta(fuzil :: any, 1)
	end
end

local function soltaMaos(corpo: Model)
	local hum = corpo:FindFirstChildOfClass("Humanoid")
	for _, n in { "VT65TorretaD", "VT65TorretaE" } do
		local c = hum and hum:FindFirstChild(n)
		if c then
			c:Destroy()
		end
	end
	local fuzil = corpo:FindFirstChild("Weapon")
	if fuzil then
		pinta(fuzil :: any, 0)
	end
end

local function varre()
	local torreta: { [Model]: boolean } = {}
	local quer: { [Model]: boolean } = {}
	local pasta = workspace:FindFirstChild("Vehicles")
	for _, v in if pasta then pasta:GetChildren() else {} do
		local spec = v:GetAttribute("Spec")
		if type(spec) == "string" then
			for _, s in v:GetChildren() do
				if s:IsA("Seat") and s.Occupant then
					local id = s:GetAttribute("SeatId")
					local corpo = s.Occupant.Parent
					if spec == "lvtp5" and (id == "gunner" or id == "commander") and corpo and corpo:IsA("Model") then
						torreta[corpo] = true
						maosNaArma(corpo, v, s, id)
					end
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
	for m in naTorreta do
		if not torreta[m] then
			naTorreta[m] = nil
			if m.Parent then
				soltaMaos(m)
			end
		end
	end
	for m in torreta do
		naTorreta[m] = true
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
