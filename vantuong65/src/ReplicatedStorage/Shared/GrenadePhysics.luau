--!strict
-- D-191 (dono: granada com "quiques e rolamento compatíveis com a superfície", "perda gradual de
-- energia até repousar" e sem "atravessamento de superfícies"): números da granada no chão. Módulo
-- PURO (tests/luau/superficie.luau). O servidor (FieldService) simula; o cliente só desenha.
--   - groundDamp: a cada 0,1 s tocando o chão, a velocidade vezes isto (lama e arrozal seguram,
--     madeira, metal e pedra deixam rolar); antes era 0,72 em qualquer chão;
--   - restitution e bounce: o quique de quando o raio da varredura pega uma face que a bola pulou
--     entre dois quadros (a física do Roblox cuida do resto).
-- PLACEHOLDER de jogo (nenhum número medido em playtest).
local Superficie = require(script and (script :: any).Parent.Superficie or "./Superficie") :: any

local GrenadePhysics = {}

GrenadePhysics.SWEEP_MIN_STUDS = 0.4 -- passo menor que isto não pula nada (a bola tem 1 stud)

GrenadePhysics.DAMP = {
	mud = 0.45,
	paddy = 0.4,
	water = 0.35,
	sand = 0.55,
	grass = 0.72,
	wood = 0.82,
	metal = 0.85,
	stone = 0.84,
} :: { [string]: number }

GrenadePhysics.RESTITUTION = {
	mud = 0.05,
	paddy = 0.05,
	water = 0.02,
	sand = 0.12,
	grass = 0.25,
	wood = 0.38,
	metal = 0.45,
	stone = 0.42,
} :: { [string]: number }

function GrenadePhysics.groundDamp(surface: string): number
	return GrenadePhysics.DAMP[surface] or 0.72
end

function GrenadePhysics.restitution(surface: string): number
	return GrenadePhysics.RESTITUTION[surface] or 0.25
end

-- A velocidade depois do quique numa face de normal n: a parte contra a face volta vezes e (perde
-- energia), a parte ao longo dela perde um pouco no atrito. Nunca sai mais rápida que entrou.
function GrenadePhysics.bounce(v: Vector3, n: Vector3, e: number): Vector3
	local into = v:Dot(n)
	if into >= 0 then
		return v -- já saindo da face
	end
	local normal = n * into
	local along = v - normal
	return along * 0.85 - normal * math.clamp(e, 0, 1)
end

-- o piso do raio (no Roblox): a peça e o material do ponto
function GrenadePhysics.surfaceOf(inst: Instance, material: Enum.Material): string
	local terrain = inst:IsA("Terrain")
	local attr = inst:GetAttribute("Material")
	return Superficie.of(
		terrain,
		material.Name,
		inst.Name,
		if type(attr) == "string" then attr else nil,
		inst:FindFirstAncestor("log_bridge") ~= nil
	)
end

return GrenadePhysics
