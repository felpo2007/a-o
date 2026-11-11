--!strict
-- Estado do veículo do jogador local, dividido entre o VehicleController (comando, física e câmera) e
-- o VehicleFx (arte, faixas da lagarta, rotor, poeira, fumaça e som), e o raio de chão dos dois.
-- Só no cliente.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleDrive = require(ReplicatedStorage.Shared.VehicleDrive)

local VehicleLive = {}
local M = 0.28
local VEHICLE_GROUP = "VT65Veiculo" -- AssetLoader.VEHICLE_GROUP: o raio passa pelo tronco como o chassi

-- O que o motorista local simula agora (VehicleController escreve a cada quadro). O VehicleFx usa no
-- veículo dele em vez da telemetria que volta do servidor (sem atraso).
VehicleLive.drive = {
	model = nil :: Model?,
	rpm = 0, -- rotação (fração da máxima); no helicóptero, o rotor
	load = 0, -- 0..1; no helicóptero, o coletivo
	throttle = 0,
	steer = 0,
	slip = 0,
	gear = 0,
	ground = "earth",
	floating = false,
	rotor = 0,
	cyclicX = 0, -- inclinação pedida (rad): o disco do rotor desenhado inclina antes da fuselagem
	cyclicY = 0,
}

-- Visual do veículo em que o jogador local está sentado (VehicleFx escreve; a câmera lê).
VehicleLive.view = {
	model = nil :: Model?,
	pitch = 0, -- mola + chão (rad)
	roll = 0,
	rough = 0, -- 0..1
	speed = 0, -- m/s
	rpm = 0,
	rotor = 0,
}

-- ===== raio de chão =====
-- "Sólido": respeita colisão (atravessa folhagem e a lâmina d'água do arrozal, que não colidem) e o
-- grupo do veículo (atravessa o tronco da mata, como o chassi). A lâmina é achada com outro raio.
local solid = RaycastParams.new()
solid.FilterType = Enum.RaycastFilterType.Exclude
solid.RespectCanCollide = true
local paddy = RaycastParams.new()
paddy.FilterType = Enum.RaycastFilterType.Include
local groupSet = false

-- Parâmetros do raio sólido sem os objetos da lista (o próprio veículo, o personagem, os efeitos)
function VehicleLive.solid(exclude: { Instance }): RaycastParams
	if not groupSet then
		groupSet = pcall(function()
			solid.CollisionGroup = VEHICLE_GROUP
		end)
	end
	solid.FilterDescendantsInstances = exclude
	solid.IgnoreWater = false
	return solid
end

-- Chão abaixo de `from` (até `len` studs): chave do VehicleDrive.GROUND (nil se não achou), fundura da
-- água (m, se for água) e o ponto da superfície achada (água, lâmina do arrozal ou chão). Chame
-- VehicleLive.solid antes.
function VehicleLive.groundAt(from: Vector3, len: number): (string?, number?, Vector3?)
	solid.IgnoreWater = false
	local hit = workspace:Raycast(from, Vector3.new(0, -len, 0), solid)
	if not hit then
		return nil, nil, nil
	end
	if hit.Instance == workspace.Terrain and hit.Material == Enum.Material.Water then
		solid.IgnoreWater = true
		local bottom = workspace:Raycast(hit.Position + Vector3.new(0, 0.05, 0), Vector3.new(0, -80, 0), solid)
		solid.IgnoreWater = false
		return "water", if bottom then (hit.Position.Y - bottom.Position.Y) * M else 30, hit.Position
	end
	local map = workspace:FindFirstChild("Map")
	local sheet = map and map:FindFirstChild("PaddyWater")
	if sheet then
		paddy.FilterDescendantsInstances = { sheet }
		local w = workspace:Raycast(from, Vector3.new(0, -(from.Y - hit.Position.Y) - 1, 0), paddy)
		if w then
			return "paddy", nil, w.Position
		end
	end
	local attr = hit.Instance:GetAttribute("Material")
	return VehicleDrive.groundOf(hit.Material.Name, if type(attr) == "string" then attr else nil, hit.Instance.Name),
		nil,
		hit.Position
end

-- Chão debaixo do chassi: chave, fundura da água (m) e a altura (studs) da superfície achada.
function VehicleLive.probe(chassis: BasePart): (string, number?, number?)
	-- do topo do chassi: flutuando, o centro do LVTP-5 fica abaixo da superfície e o raio que saía do
	-- centro acertava a areia do fundo
	local top = chassis.Position + Vector3.new(0, chassis.Size.Y / 2, 0)
	local g, depth, at = VehicleLive.groundAt(top, chassis.Size.Y * 1.5 + 8)
	return g or "earth", depth, if at then at.Y else nil
end

return VehicleLive
