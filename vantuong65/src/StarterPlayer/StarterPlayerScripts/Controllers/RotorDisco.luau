--!strict
-- D-199: o disco borrado do rotor girando, deste cliente (VehicleFx e HeliEvento).
-- Uma peça invisível do tamanho do rotor com a textura (tools/rotor_borrao.py) em Decal nas duas
-- faces; o servidor resolve a imagem do decal publicado (Modules/ImagensUi, "Img_rotor_borrao").
-- Sem a imagem, fica o disco cinza de antes (cilindro translúcido), de reserva. Sem colisão, sem
-- consulta de raio e sem sombra.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Disco = {
	peca: BasePart,
	decals: { Decal },
	reserva: BasePart,
	eixo: string, -- "Y": rotor principal (giro em Y); "Z": de cauda (giro em Z)
	ang: number,
}

local RotorDisco = {}

local imagem: string? = nil
local vivos: { [Disco]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function lerImagem()
	local id = ReplicatedStorage:GetAttribute("Img_rotor_borrao")
	imagem = if type(id) == "number" and id ~= 0 then "rbxassetid://" .. id else nil
	for d in vivos do
		for _, dc in d.decals do
			dc.Texture = imagem or ""
		end
	end
end
ReplicatedStorage:GetAttributeChangedSignal("Img_rotor_borrao"):Connect(lerImagem)
lerImagem()

function RotorDisco.temImagem(): boolean
	return imagem ~= nil
end

local function peca(nome: string, size: Vector3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = nome
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- raio em studs; eixo "Y" (rotor principal) ou "Z" (de cauda)
function RotorDisco.novo(nome: string, raio: number, eixo: string, parent: Instance): Disco
	local size = if eixo == "Y" then Vector3.new(2 * raio, 0.02, 2 * raio) else Vector3.new(2 * raio, 2 * raio, 0.02)
	local p = peca(nome, size, parent)
	local faces: { Enum.NormalId } = if eixo == "Y"
		then { Enum.NormalId.Top, Enum.NormalId.Bottom }
		else { Enum.NormalId.Front, Enum.NormalId.Back }
	local decals: { Decal } = {}
	for _, f in faces do
		local dc = Instance.new("Decal")
		dc.Face = f
		dc.Texture = imagem or ""
		dc.Transparency = 1
		dc.Parent = p
		table.insert(decals, dc)
	end
	local r = peca(nome .. "Reserva", Vector3.new(if eixo == "Y" then 0.12 else 0.08, 2 * raio, 2 * raio), parent)
	r.Shape = Enum.PartType.Cylinder
	r.Color = if eixo == "Y" then Color3.fromRGB(48, 48, 44) else Color3.fromRGB(60, 60, 56)
	local d: Disco = { peca = p, decals = decals, reserva = r, eixo = eixo, ang = 0 }
	vivos[d] = true
	return d
end

-- CFrames do disco e da reserva com o cubo em `cubo` (o eixo de giro é o Y ou o Z dele) e o giro
-- visual `d.ang`.
function RotorDisco.cframes(d: Disco, cubo: CFrame): (CFrame, CFrame)
	if d.eixo == "Y" then
		local c = cubo * CFrame.Angles(0, d.ang, 0)
		return c, c * CFrame.Angles(0, 0, math.pi / 2)
	end
	local c = cubo * CFrame.Angles(0, 0, d.ang)
	return c, c * CFrame.Angles(0, math.pi / 2, 0)
end

-- transparência do disco (0 = cheio, 1 = some): na imagem, ou na reserva (que é mais fraca)
function RotorDisco.transparencia(d: Disco, t: number)
	if imagem then
		for _, dc in d.decals do
			dc.Transparency = t
		end
		d.reserva.Transparency = 1
	else
		for _, dc in d.decals do
			dc.Transparency = 1
		end
		d.reserva.Transparency = 1 - 0.22 * (1 - t)
	end
end

function RotorDisco.destruir(d: Disco)
	vivos[d] = nil
	d.peca:Destroy()
	d.reserva:Destroy()
end

-- pás e rotor de cauda da malha (Pa_*, RotorCauda): só neste cliente, sem brigar com o servidor
function RotorDisco.esconder(pecas: { BasePart }, t: number)
	for _, p in pecas do
		p.LocalTransparencyModifier = t
	end
end

return RotorDisco
