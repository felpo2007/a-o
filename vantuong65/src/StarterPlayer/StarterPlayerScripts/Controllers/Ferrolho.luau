--!strict
-- Ferrolho dos fuzis de precisão em 1ª pessoa (2026-11-12, "faça sniper"). Módulo à parte por causa
-- do limite de locais do WeaponVisuals, que chama Ferrolho.step(v) antes de pôr a arma na câmera.
-- O WeaponController avisa cada tiro de ferrolho pelo Bus ("bolt_cycle", duração em s). No ciclo:
--   - a arma cede e inclina para a esquerda (a mão direita sai do punho para a alavanca);
--   - a peça "Ferrolho" do modelo do Blender (assets/blender/arma_*) gira a alavanca para cima, recua,
--     volta e baixa, em torno do eixo do ferrolho (WeaponArt.bolt, no espaço da malha publicada).
--     Sem a peça (arma provisória ou ainda sem ID), só a arma mexe.
-- Curso e giro: PLACEHOLDER (curso de ~10 cm de um ferrolho de .30-06 / 7,62x54R; giro de 90°).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponArt = require(ReplicatedStorage.Shared.WeaponArt) :: any
local Bus = require(script.Parent.Bus)

local Ferrolho = {}

local M = 0.28
local STROKE_M: { [string]: number } = { m70 = 0.095, mosin = 0.11 }
local LIFT_DEG = 90

local cycle = { t0 = -1, dur = 1 }
-- posição de repouso da peça "Ferrolho" no espaço da peça principal, por modelo de 1ª pessoa
local rest: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

Bus.on("bolt_cycle", function(dur: number)
	cycle.t0, cycle.dur = os.clock(), math.max(dur, 0.2)
end)

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- fração do ciclo -> (giro 0..1, recuo 0..1, peso da pose da arma 0..1)
function Ferrolho.curve(p: number): (number, number, number)
	local lift = smooth((p - 0.12) / 0.16) * (1 - smooth((p - 0.68) / 0.14))
	local back = smooth((p - 0.3) / 0.16) * (1 - smooth((p - 0.5) / 0.15))
	local w = smooth((p - 0.04) / 0.12) * (1 - smooth((p - 0.8) / 0.18))
	return lift, back, w
end

-- Passo do quadro: anima a peça (relativa à principal, antes do PivotTo) e devolve a pose da arma.
function Ferrolho.step(v: Model?): CFrame
	if not v or cycle.t0 < 0 then
		return CFrame.identity
	end
	local p = (os.clock() - cycle.t0) / cycle.dur
	local primary = v.PrimaryPart
	local part = v:FindFirstChild("Ferrolho", true)
	local id = v:GetAttribute("WeaponId")
	local art = if type(id) == "string" then WeaponArt[id] else nil
	if primary and part and part:IsA("BasePart") then
		local r0 = rest[part]
		if not r0 then
			r0 = primary.CFrame:ToObjectSpace(part.CFrame)
			rest[part] = r0
		end
		local lift, back = 0, 0
		if p < 1 then
			lift, back = Ferrolho.curve(p)
		end
		local muzzle = primary:FindFirstChild("Muzzle") :: Attachment?
		local bolt = art and art.bolt
		if muzzle and typeof(bolt) == "Vector3" then
			local axis = CFrame.new(bolt) * muzzle.CFrame.Rotation -- −Z = boca
			local stroke = (STROKE_M[id :: string] or 0.1) / M
			local anim = axis * CFrame.new(0, 0, back * stroke) * CFrame.Angles(0, 0, math.rad(LIFT_DEG) * lift)
			part.CFrame = primary.CFrame * (anim * axis:Inverse() * r0)
		end
	end
	if p >= 1 then
		cycle.t0 = -1
		return CFrame.identity
	end
	local _, _, w = Ferrolho.curve(p)
	return CFrame.new(0.01 / M * w, -0.035 / M * w, 0.02 / M * w)
		* CFrame.Angles(math.rad(-5) * w, 0, math.rad(-14) * w)
end

return Ferrolho
