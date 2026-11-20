--!strict
-- D-184: o rotor do helicóptero do evento (inserção e medevac, EventosService) gira neste cliente. O
-- modelo é só arte ancorada com a etiqueta Eventos.HELI_TAG: não é veículo, e o VehicleFx não o vê.
-- - As pás da malha (Pa_*) giram em volta do cubo (RotorPrincipal), no eixo para cima do casco;
-- - o rotor de cauda (RotorCauda) gira no próprio lugar, no eixo de lado do casco (Z da malha: o nariz
--   fica em −x e a direita em −z, VehicleDrive.ART).
-- O servidor move o modelo na descida e na subida (PivotTo): a conta parte do cubo e do casco de cada
-- quadro, e as pás ficam no lugar certo mesmo com o modelo andando.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Eventos = require(ReplicatedStorage.Shared.Eventos)
local VehicleDrive = require(ReplicatedStorage.Shared.VehicleDrive)

type Blade = { part: BasePart, rel: CFrame }
type Heli = {
	hub: BasePart,
	hull: BasePart,
	blades: { Blade },
	tail: BasePart?,
	tailRel: CFrame?,
	ang: number,
	tang: number,
}
local helis: { [Instance]: Heli } = {}

local function hubFrame(hub: BasePart, hull: BasePart): CFrame
	return CFrame.new(hub.Position) * hull.CFrame.Rotation
end

local function add(m: Instance)
	if helis[m] or not m:IsA("Model") then
		return
	end
	local hub = m:FindFirstChild("RotorPrincipal", true)
	local hull = m:FindFirstChild("Casco", true)
	if not (hub and hub:IsA("BasePart") and hull and hull:IsA("BasePart")) then
		return -- sem a arte do Blender (modelo velho ou caixa): fica parado, como antes
	end
	local f = hubFrame(hub, hull)
	local blades: { Blade } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 3) == "Pa_" then
			table.insert(blades, { part = d, rel = f:ToObjectSpace(d.CFrame) })
		end
	end
	local tail = m:FindFirstChild("RotorCauda", true)
	local h: Heli = {
		hub = hub,
		hull = hull,
		blades = blades,
		tail = if tail and tail:IsA("BasePart") then tail else nil,
		tailRel = if tail and tail:IsA("BasePart") then hull.CFrame:ToObjectSpace(tail.CFrame) else nil,
		ang = 0,
		tang = 0,
	}
	helis[m] = h
end

CollectionService:GetInstanceAddedSignal(Eventos.HELI_TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(Eventos.HELI_TAG):Connect(function(m: Instance)
	helis[m] = nil
end)
for _, m in CollectionService:GetTagged(Eventos.HELI_TAG) do
	add(m)
end

RunService.RenderStepped:Connect(function(dt: number)
	local H = VehicleDrive.HELI
	for m, h in helis do
		if m.Parent == nil or h.hub.Parent == nil or h.hull.Parent == nil then
			helis[m] = nil
			continue
		end
		h.ang = (h.ang + H.rotorRpm / 60 * 2 * math.pi * dt) % (2 * math.pi)
		h.tang = (h.tang + H.tailRpm / 60 * 2 * math.pi * dt) % (2 * math.pi)
		local f = hubFrame(h.hub, h.hull) * CFrame.Angles(0, h.ang, 0)
		for _, b in h.blades do
			b.part.CFrame = f * b.rel
		end
		local tail, rel = h.tail, h.tailRel
		if tail and rel then
			tail.CFrame = h.hull.CFrame * CFrame.new(rel.Position) * CFrame.Angles(0, 0, h.tang) * rel.Rotation
		end
	end
end)
