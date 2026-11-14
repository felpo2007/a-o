--!strict
-- Ferrolho dos fuzis de precisão em 1ª pessoa (2026-11-12, "faça sniper"). Módulo à parte por causa
-- do limite de locais do WeaponVisuals, que chama Ferrolho.step(v) antes de pôr a arma na câmera.
-- O WeaponController avisa cada tiro de ferrolho pelo Bus ("bolt_cycle", duração em s). No ciclo:
--   - a arma cede e inclina para a esquerda (a mão direita sai do punho para a alavanca);
--   - a peça "Ferrolho" do modelo do Blender (assets/blender/arma_*) gira a alavanca para cima, recua,
--     volta e baixa, em torno do eixo do ferrolho (WeaponArt.bolt, no espaço da malha publicada).
--     Sem a peça (arma provisória ou ainda sem ID), só a arma mexe.
-- Curso e giro: PLACEHOLDER (curso de ~10 cm de um ferrolho de .30-06 / 7,62x54R; giro de 90°).
-- D-108 (espingarda Winchester 12, modo "pump"):
--   - bomba: a peça "Telha" (a telha de madeira do modelo do Blender, tools/blender/ESPINGARDA.txt)
--     corre para trás e volta ao longo do cano; a arma recua um pouco e sobe a boca. Sem a peça, só a
--     arma mexe;
--   - recarga cartucho a cartucho ("reload_start" com o tipo "shotgun"): a arma gira de lado com a
--     portinhola de carga para a mão esquerda e balança a cada cartucho que entra, com o som de cada
--     um (SomArmas.mec_cartucho) e, vazia, a bomba no fim. Tempos: Weapons.reloadTime.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SomArmas = require(ReplicatedStorage.Shared.SomArmas)
local WeaponArt = require(ReplicatedStorage.Shared.WeaponArt) :: any
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Som = require(script.Parent.Som)

local Ferrolho = {}

local M = 0.28
local STROKE_M: { [string]: number } = { m70 = 0.095, mosin = 0.11 }
local LIFT_DEG = 90
local PUMP_M = 0.1 -- curso da telha (~10 cm, PLACEHOLDER)

local cycle = { t0 = -1, dur = 1, pump = false }
-- recarga da espingarda: começo, duração, cartuchos, tempos da arma e se bombeia no fim
local shells = { t0 = -1, dur = 1, n = 0, startS = 0.4, shellS = 0.55 }
-- posição de repouso das peças animadas no espaço da peça principal, por modelo de 1ª pessoa
local rest: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function isPump(id: string?): boolean
	local wp = if id then Weapons.get(id) else nil
	return wp ~= nil and wp.modes[1] == "pump"
end

Bus.on("bolt_cycle", function(dur: number, weaponId: string?)
	cycle.t0, cycle.dur = os.clock(), math.max(dur, 0.2)
	cycle.pump = isPump(weaponId)
end)

Bus.on("reload_start", function(dur: number, kind: string?, n: number?, empty: boolean?, weaponId: string?)
	if kind ~= "shotgun" then
		shells.t0 = -1
		return
	end
	local id = weaponId or "win12"
	local wp = Weapons.get(id)
	shells.t0, shells.dur, shells.n = os.clock(), math.max(dur, 0.2), math.max(n or 0, 0)
	shells.startS = (wp and wp.reloadStartS) or 0.4
	shells.shellS = (wp and wp.shellS) or 0.55
	-- o som de cada cartucho e a bomba no fim (vazia); escala com a vantagem de recarga (dur)
	local base = (shells.startS + shells.n * shells.shellS + (if empty then (wp and wp.reloadEndS or 0.5) else 0))
	local k = if base > 0 then shells.dur / base else 1
	local a = SomArmas.arma(id, "shotgun")
	for i = 1, shells.n do
		Som.play(a.cartucho or "mec_cartucho", {
			delay = (shells.startS + (i - 0.35) * shells.shellS) * k,
			vol = 0.9,
			pitch = 0.95 + math.random() * 0.1,
		})
	end
	if empty then
		Som.play(a.mecanica or "mec_bomba", { delay = (shells.startS + shells.n * shells.shellS + 0.05) * k })
	end
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

-- D-108: bomba (fração do ciclo -> curso da telha 0..1, peso da pose 0..1): a telha vai para trás
-- rápido logo depois do tiro e volta
function Ferrolho.pumpCurve(p: number): (number, number)
	local back = smooth((p - 0.08) / 0.22) * (1 - smooth((p - 0.42) / 0.25))
	local w = smooth(p / 0.12) * (1 - smooth((p - 0.7) / 0.3))
	return back, w
end

-- D-108: recarga cartucho a cartucho (tempo desde o começo -> pose de lado 0..1, balanço 0..1)
function Ferrolho.shellCurve(t: number, dur: number, startS: number, shellS: number, n: number): (number, number)
	local side = smooth(t / math.max(startS, 0.05)) * (1 - smooth((t - dur + 0.3) / 0.3))
	local bob = 0
	if n > 0 and t > startS then
		local i = (t - startS) / math.max(shellS, 0.05)
		if i < n then
			local f = i - math.floor(i)
			bob = math.sin(f * math.pi)
		end
	end
	return side, bob
end

-- escala da arma de 1ª pessoa (frente de armas maiores: Corpo.ARMA_K, atributo "VT65Escala" do
-- modelo): o curso do ferrolho e da telha e o ponto do ferrolho crescem junto
local function scaleOf(v: Model): number
	local k = v:GetAttribute("VT65Escala")
	return if type(k) == "number" and k > 0 then k else 1
end

-- peça animada com o repouso guardado
local function restOf(primary: BasePart, part: BasePart): CFrame
	local r0 = rest[part]
	if not r0 then
		r0 = primary.CFrame:ToObjectSpace(part.CFrame)
		rest[part] = r0
	end
	return r0
end

local function stepPump(v: Model, p: number): CFrame
	local back, w = Ferrolho.pumpCurve(p)
	local primary = v.PrimaryPart
	if primary then
		local muzzle = primary:FindFirstChild("Muzzle") :: Attachment?
		local axis = if muzzle then muzzle.CFrame.Rotation else CFrame.identity
		-- para trás ao longo do cano (+Z da boca); a face do ferrolho ("Culatra") recua junto. Curso
		-- medido no modelo do Blender (WeaponArt.pumpM, 0,09 m)
		local id = v:GetAttribute("WeaponId")
		local art = if type(id) == "string" then WeaponArt[id] else nil
		local stroke = (if art and type(art.pumpM) == "number" then art.pumpM else PUMP_M) / M * scaleOf(v)
		local slide = axis * CFrame.new(0, 0, back * stroke) * axis:Inverse()
		for _, name in { "Telha", "Culatra" } do
			local part = v:FindFirstChild(name, true)
			if part and part:IsA("BasePart") then
				part.CFrame = primary.CFrame * (slide * restOf(primary, part))
			end
		end
	end
	return CFrame.new(0, -0.01 / M * w, 0.03 / M * back) * CFrame.Angles(math.rad(3) * w, 0, math.rad(-4) * w)
end

-- Passo do quadro: anima a peça (relativa à principal, antes do PivotTo) e devolve a pose da arma.
function Ferrolho.step(v: Model?): CFrame
	if not v then
		return CFrame.identity
	end
	local pose = CFrame.identity
	-- recarga da espingarda (cartucho a cartucho)
	if shells.t0 >= 0 then
		local t = os.clock() - shells.t0
		if t >= shells.dur then
			shells.t0 = -1
		else
			local side, bob = Ferrolho.shellCurve(t, shells.dur, shells.startS, shells.shellS, shells.n)
			pose = CFrame.new(0.02 / M * side, -0.04 / M * side - 0.012 / M * bob, 0.015 / M * bob)
				* CFrame.Angles(math.rad(6) * side, math.rad(-8) * side, math.rad(-55) * side)
		end
	end
	if cycle.t0 < 0 then
		return pose
	end
	local p = (os.clock() - cycle.t0) / cycle.dur
	if cycle.pump then
		if p >= 1 then
			cycle.t0 = -1
			local primary = v.PrimaryPart
			for _, name in { "Telha", "Culatra" } do
				local part = v:FindFirstChild(name, true)
				if primary and part and part:IsA("BasePart") and rest[part] then
					part.CFrame = primary.CFrame * rest[part]
				end
			end
			return pose
		end
		return pose * stepPump(v, p)
	end
	local primary = v.PrimaryPart
	local part = v:FindFirstChild("Ferrolho", true)
	local id = v:GetAttribute("WeaponId")
	local art = if type(id) == "string" then WeaponArt[id] else nil
	if primary and part and part:IsA("BasePart") then
		local r0 = restOf(primary, part)
		local lift, back = 0, 0
		if p < 1 then
			lift, back = Ferrolho.curve(p)
		end
		local muzzle = primary:FindFirstChild("Muzzle") :: Attachment?
		local bolt = art and art.bolt
		if muzzle and typeof(bolt) == "Vector3" then
			-- D-108: a arma de 1ª pessoa é "VT65Escala" vezes maior (WeaponVisuals)
			local esc = v:GetAttribute("VT65Escala")
			local k = if type(esc) == "number" then esc else 1
			local axis = CFrame.new(bolt * k) * muzzle.CFrame.Rotation -- −Z = boca
			local stroke = (STROKE_M[id :: string] or 0.1) * k / M
			local anim = axis * CFrame.new(0, 0, back * stroke) * CFrame.Angles(0, 0, math.rad(LIFT_DEG) * lift)
			part.CFrame = primary.CFrame * (anim * axis:Inverse() * r0)
		end
	end
	if p >= 1 then
		cycle.t0 = -1
		return pose
	end
	local _, _, w = Ferrolho.curve(p)
	return pose
		* CFrame.new(0.01 / M * w, -0.035 / M * w, 0.02 / M * w)
		* CFrame.Angles(math.rad(-5) * w, 0, math.rad(-14) * w)
end

return Ferrolho
