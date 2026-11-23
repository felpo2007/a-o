--!strict
-- D-184: o rotor do helicóptero do evento (inserção e medevac, EventosService) gira neste cliente. O
-- modelo é só arte ancorada com a etiqueta Eventos.HELI_TAG: não é veículo, e o VehicleFx não o vê.
-- - As pás da malha (Pa_*) giram em volta do cubo (RotorPrincipal), no eixo para cima do casco;
-- - o rotor de cauda (RotorCauda) gira no próprio lugar, no eixo de lado do casco (Z da malha: o nariz
--   fica em −x e a direita em −z, VehicleDrive.ART).
-- O servidor move o modelo na descida e na subida (PivotTo): a conta parte do cubo e do casco de cada
-- quadro, e as pás ficam no lugar certo mesmo com o modelo andando.
-- D-199: o rotor do evento está sempre na rotação cheia: as pás somem e fica o disco borrado
-- (RotorVisual, RotorDisco), mais fraco longe. As pás invisíveis não são movidas.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Eventos = require(ReplicatedStorage.Shared.Eventos)
local RotorVisual = require(ReplicatedStorage.Shared.RotorVisual)
local VehicleDrive = require(ReplicatedStorage.Shared.VehicleDrive)
local RotorDisco = require(script.Parent.RotorDisco)

local camera = workspace.CurrentCamera
local M = 0.28
local ROTOR = 1 -- o evento só aparece com o rotor girando

local folder = Instance.new("Folder")
folder.Name = "VT65HeliEvento"
folder.Parent = camera

type Blade = { part: BasePart, rel: CFrame }
type Heli = {
	hub: BasePart,
	hull: BasePart,
	blades: { Blade },
	pecas: { BasePart },
	tail: BasePart?,
	tailRel: CFrame?,
	ang: number,
	tang: number,
	disco: RotorDisco.Disco?,
	discoCauda: RotorDisco.Disco?,
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
	local pecas: { BasePart } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 3) == "Pa_" then
			table.insert(blades, { part = d, rel = f:ToObjectSpace(d.CFrame) })
			table.insert(pecas, d)
		end
	end
	local tail = m:FindFirstChild("RotorCauda", true)
	local tailPart = if tail and tail:IsA("BasePart") then tail else nil
	if tailPart then
		table.insert(pecas, tailPart)
	end
	-- raio dos discos pela ficha (studs) na escala da malha (a caixa do Casco / a do ART)
	local art = VehicleDrive.ART.uh34d
	local s = if art then hull.Size.X / art.box[1] else 1
	local h: Heli = {
		hub = hub,
		hull = hull,
		blades = blades,
		pecas = pecas,
		tail = tailPart,
		tailRel = if tailPart then hull.CFrame:ToObjectSpace(tailPart.CFrame) else nil,
		ang = 0,
		tang = 0,
		disco = if art and art.rotor then RotorDisco.novo("RotorDiscoEvento", art.rotor.r * s, "Y", folder) else nil,
		discoCauda = if art
				and art.tail
				and tailPart
			then RotorDisco.novo("CaudaDiscoEvento", art.tail.r * s, "Z", folder)
			else nil,
	}
	helis[m] = h
end

local function remove(m: Instance)
	local h = helis[m]
	if not h then
		return
	end
	helis[m] = nil
	for _, d in { h.disco, h.discoCauda } do
		if d then
			RotorDisco.destruir(d)
		end
	end
	RotorDisco.esconder(h.pecas, 0)
end

CollectionService:GetInstanceAddedSignal(Eventos.HELI_TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(Eventos.HELI_TAG):Connect(remove)
for _, m in CollectionService:GetTagged(Eventos.HELI_TAG) do
	add(m)
end

RunService.RenderStepped:Connect(function(dt: number)
	local H = VehicleDrive.HELI
	local camPos = camera.CFrame.Position
	for m, h in helis do
		if m.Parent == nil or h.hub.Parent == nil or h.hull.Parent == nil then
			remove(m)
			continue
		end
		h.ang = (h.ang + H.rotorRpm / 60 * 2 * math.pi * dt) % (2 * math.pi)
		h.tang = (h.tang + H.tailRpm / 60 * 2 * math.pi * dt) % (2 * math.pi)
		local pasT, discoT = RotorVisual.estado(ROTOR, (h.hub.Position - camPos).Magnitude * M)
		RotorDisco.esconder(h.pecas, pasT)
		local giro = RotorVisual.giro(ROTOR) * dt
		local cubo = hubFrame(h.hub, h.hull)
		if pasT < 0.999 then
			local f = cubo * CFrame.Angles(0, h.ang, 0)
			for _, b in h.blades do
				b.part.CFrame = f * b.rel
			end
		end
		local tail, rel = h.tail, h.tailRel
		local tcf = if tail and rel then h.hull.CFrame * CFrame.new(rel.Position) else nil
		if tail and rel and tcf and pasT < 0.999 then
			tail.CFrame = tcf * CFrame.Angles(0, 0, h.tang) * rel.Rotation
		end
		local d = h.disco
		if d then
			d.ang = (d.ang + giro) % (2 * math.pi)
			RotorDisco.transparencia(d, discoT)
			local c1, c2 = RotorDisco.cframes(d, cubo)
			d.peca.CFrame, d.reserva.CFrame = c1, c2
		end
		local dc = h.discoCauda
		if dc and tcf then
			dc.ang = (dc.ang + giro * 2.3) % (2 * math.pi)
			RotorDisco.transparencia(dc, discoT)
			local c1, c2 = RotorDisco.cframes(dc, tcf)
			dc.peca.CFrame, dc.reserva.CFrame = c1, c2
		end
	end
end)
