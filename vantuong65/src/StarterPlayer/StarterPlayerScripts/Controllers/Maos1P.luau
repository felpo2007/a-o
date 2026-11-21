--!strict
-- Mãos e antebraços de 1ª pessoa (D-99). Pedido do dono, com foto: "as mãos da pistola em 1ª pessoa
-- são duas bolas laranjas". Antes (D-69) cada mão era uma elipsoide da cor da pele; agora:
-- - a forma de cada pega vem do Shared/MaosPose (dedos fechados no punho, palma, polegar, pulso);
-- - com a arte publicada (tools/maos no Blender: assets/blender/maos_1p/maos_us_1p.glb e
--   maos_vc_1p.glb, chaves AssetIds.Models.maos_us_1p / maos_vc_1p; o Characters põe a cópia em
--   ReplicatedStorage.VT65MaosArt) entram as MeshParts, com os pontos de Shared/MaosArte;
-- - sem a arte, cápsulas de peças (bola + cilindro) com as mesmas medidas, movidas de uma vez
--   (BulkMoveTo);
-- - antebraço: pulso de pele e manga do uniforme (EUA: OG-107 arregaçada; VC: manga lisa cáqui),
--   do punho até o cotovelo (no máximo 27 cm).
-- A cor da pele é a da cabeça do soldado. Usado pelo WeaponVisuals (arma, faca, carta) e pelo
-- ItemView (itens): Maos1P.ensure(), Maos1P.hand(lado, cframe, pega), Maos1P.forearm(...).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Corpo = require(ReplicatedStorage.Shared.Corpo)
local MaosPose = require(ReplicatedStorage.Shared.MaosPose)

local Maos1P = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local FAR = CFrame.new(0, -1e4, 0)
local SLEEVE_COLOR: { [string]: Color3 } = { US = Color3.fromRGB(84, 88, 60), VC = Color3.fromRGB(142, 126, 92) }
local CUFF_COLOR: { [string]: Color3 } = { US = Color3.fromRGB(74, 78, 52), VC = Color3.fromRGB(128, 112, 80) }

-- pontos da arte por lado (Shared/MaosArte, gerado pelo tools/maos/produzir.py)
type ArtPoint = { size: { number }, pivot: { number } }
local ART_ALL: { [string]: { [string]: ArtPoint } } = {}
do
	local mod = ReplicatedStorage.Shared:FindFirstChild("MaosArte")
	if mod and mod:IsA("ModuleScript") then
		local ok, t = pcall(require, mod)
		if ok and type(t) == "table" then
			ART_ALL = t :: any
		end
	end
end
local ART_POINTS: { [string]: ArtPoint } = {}

type Group = { parts: { BasePart }, offs: { CFrame } }
type Fore = { wrist: BasePart, sleeve: BasePart, cuff: BasePart?, art: boolean, artLen: number }
local S = {
	model = nil :: Model?,
	key = "",
	faction = "US",
	skin = Color3.fromRGB(196, 150, 112),
	art = nil :: Model?,
	groups = {} :: { [string]: Group }, -- "R:grip", "L:support"...
	cur = { R = "", L = "" } :: { [string]: string },
	fore = {} :: { [string]: Fore },
	hidden = false,
	-- D-108: mãos e antebraços do tamanho da arma de 1ª pessoa (Corpo.ARMA_K): a pega foi desenhada
	-- no punho de tamanho real, e com a arma maior os dedos entrariam nele
	k = Corpo.ARMA_K,
}

local function bare(p: BasePart)
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
end

local function part(shape: Enum.PartType, size: Vector3, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = mat
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	bare(p)
	return p
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3]) * S.k / M
end

-- cápsulas de peças: bola em cada ponto (afinando para a ponta) e cilindro entre eles
local function buildParts(pose: MaosPose.Pose, parent: Model): Group
	local g: Group = { parts = {}, offs = {} }
	local function put(p: BasePart, off: CFrame)
		p.Parent = parent
		table.insert(g.parts, p)
		table.insert(g.offs, off)
	end
	for _, b in pose.boxes do
		put(part(Enum.PartType.Block, v3(b.s), S.skin, Enum.Material.SmoothPlastic), CFrame.new(v3(b.c)))
	end
	for _, ch in pose.chains do
		local n = #ch.pts
		local radii = {}
		for i = 1, n do
			radii[i] = ch.r * S.k * (1 - 0.14 * (i - 1) / math.max(n - 1, 1)) / M
		end
		for i = 1, n do
			local d = radii[i] * 2
			put(
				part(Enum.PartType.Ball, Vector3.one * d, S.skin, Enum.Material.SmoothPlastic),
				CFrame.new(v3(ch.pts[i]))
			)
			if i < n then
				local a, b = v3(ch.pts[i]), v3(ch.pts[i + 1])
				local len = (b - a).Magnitude
				if len > 1e-4 then
					local r = (radii[i] + radii[i + 1])
					local c = part(Enum.PartType.Cylinder, Vector3.new(len, r, r), S.skin, Enum.Material.SmoothPlastic)
					put(c, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0))
				end
			end
		end
	end
	return g
end

-- MeshPart da arte (MaoD_grip, MaoE_support...): P fica em `pivot` (studs, tamanho nativo)
local function buildArt(meshName: string, parent: Model): Group?
	local art = S.art
	local pt = ART_POINTS[meshName]
	local src = art and art:FindFirstChild(meshName, true)
	if not (pt and src and src:IsA("BasePart")) then
		return nil
	end
	local p = src:Clone()
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceAppearance") or c:IsA("JointInstance") or c:IsA("WeldConstraint") then
			c:Destroy()
		end
	end
	bare(p)
	p.Size *= S.k
	p.Color = S.skin
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	local scale = if pt.size[1] > 0 then p.Size.X / pt.size[1] else 1
	return { parts = { p }, offs = { CFrame.new(-Vector3.new(pt.pivot[1], pt.pivot[2], pt.pivot[3]) * scale) } }
end

local function group(side: string, pose: string): Group
	local key = side .. ":" .. pose
	local have = S.groups[key]
	if have then
		return have
	end
	local m = S.model :: Model
	local built = buildArt((if side == "R" then "MaoD_" else "MaoE_") .. pose, m)
	local g = built or buildParts(MaosPose.get(pose, side), m)
	S.groups[key] = g
	return g
end

local function moveGroup(g: Group, cf: CFrame)
	local cfs = table.create(#g.parts)
	for i, off in g.offs do
		cfs[i] = cf * off
	end
	workspace:BulkMoveTo(g.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function buildFore(m: Model): Fore
	local sl = MaosPose.SLEEVE[S.faction] or MaosPose.SLEEVE.US
	local artSleeve = S.art and S.art:FindFirstChild("Manga", true)
	if artSleeve and artSleeve:IsA("BasePart") and ART_POINTS.Manga then
		local p = artSleeve:Clone()
		for _, c in p:GetChildren() do
			if c:IsA("SurfaceAppearance") then
				c:Destroy()
			end
		end
		bare(p)
		p.Size *= S.k
		p.Color = SLEEVE_COLOR[S.faction] or SLEEVE_COLOR.US
		p.Material = Enum.Material.Fabric
		p.Parent = m
		local w = part(Enum.PartType.Cylinder, Vector3.one, S.skin, Enum.Material.SmoothPlastic)
		w.Parent = m
		return { wrist = w, sleeve = p, cuff = nil, art = true, artLen = ART_POINTS.Manga.size[1] * S.k }
	end
	local w = part(Enum.PartType.Cylinder, Vector3.one, S.skin, Enum.Material.SmoothPlastic)
	w.Parent = m
	local s =
		part(Enum.PartType.Cylinder, Vector3.one, SLEEVE_COLOR[S.faction] or SLEEVE_COLOR.US, Enum.Material.Fabric)
	s.Parent = m
	local cuff: BasePart? = nil
	if sl.cuff > 0 then
		local c =
			part(Enum.PartType.Cylinder, Vector3.one, CUFF_COLOR[S.faction] or CUFF_COLOR.US, Enum.Material.Fabric)
		c.Parent = m
		cuff = c
	end
	return { wrist = w, sleeve = s, cuff = cuff, art = false, artLen = 0 }
end

-- Garante o modelo (refaz quando muda o lado ou a cor da pele).
function Maos1P.ensure()
	local faction = player:GetAttribute("Faction")
	local fac = if faction == "VC" then "VC" else "US"
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	local skin = if head then head.Color else Color3.fromRGB(196, 150, 112)
	local folder = ReplicatedStorage:FindFirstChild("VT65MaosArt")
	local art = folder and folder:FindFirstChild(if fac == "VC" then "maos_vc_1p" else "maos_us_1p")
	local key = fac .. ":" .. skin:ToHex() .. ":" .. tostring(art ~= nil) .. ":" .. S.k
	if S.model and S.model.Parent and key == S.key then
		return
	end
	if S.model then
		S.model:Destroy()
	end
	S.key, S.faction, S.skin = key, fac, skin
	S.art = if art and art:IsA("Model") then art else nil
	ART_POINTS = ART_ALL[fac] or {}
	table.clear(S.groups)
	S.cur.R, S.cur.L = "", ""
	local m = Instance.new("Model")
	m.Name = "VT65Arms"
	m.Parent = camera
	S.model = m
	S.fore.R = buildFore(m)
	S.fore.L = buildFore(m)
end

-- Mão de um lado ("R"/"L") com o ponto da mão em cf (rotação da pega + posição), na pega `pose`
-- (padrão: direita "grip", esquerda "support").
function Maos1P.hand(side: string, cf: CFrame, pose: string?)
	if not S.model then
		return
	end
	S.hidden = false
	local want = pose or (if side == "R" then "grip" else "support")
	if S.cur[side] ~= want then
		local old = S.groups[side .. ":" .. S.cur[side]]
		if old then
			moveGroup(old, FAR)
		end
		S.cur[side] = want
	end
	moveGroup(group(side, want), cf)
end

-- Antebraço do punho (wrist) ao cotovelo, no máximo MaosPose.FOREARM_M.
function Maos1P.forearm(wrist: Vector3, elbow: Vector3, side: string)
	local f = S.fore[side]
	if not f then
		return
	end
	local dir = elbow - wrist
	local len = dir.Magnitude
	if len < 1e-3 then
		return
	end
	local u = dir / len
	local k = S.k
	len = math.min(len, MaosPose.FOREARM_M * k / M)
	local sl = MaosPose.SLEEVE[S.faction] or MaosPose.SLEEVE.US
	local wl = math.min(MaosPose.WRIST.len * k / M, len * 0.3)
	local wEnd = wrist + u * wl
	local function along(a: Vector3, b: Vector3): CFrame
		return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local wr = MaosPose.WRIST.r * 2 * k / M
	f.wrist.Size = Vector3.new(wl + wr * 0.3, wr, wr)
	f.wrist.CFrame = along(wrist - u * wr * 0.15, wEnd)
	local slen = len - wl
	if f.art then
		local base = f.sleeve.Size -- a malha estica só no comprimento
		f.sleeve.Size = Vector3.new(slen, base.Y, base.Z)
		f.sleeve.CFrame = along(wEnd, wrist + u * len)
		return
	end
	local rs = (sl.r0 + sl.r1) * k / M -- diâmetro médio
	f.sleeve.Size = Vector3.new(slen, rs, rs)
	f.sleeve.CFrame = along(wEnd, wrist + u * len)
	local cuff = f.cuff
	if cuff then
		local cl = math.min(sl.cuffLen * k / M, slen * 0.4)
		local cd = sl.cuff * 2 * k / M
		cuff.Size = Vector3.new(cl, cd, cd)
		cuff.CFrame = along(wEnd, wEnd + u * cl)
	end
end

-- Fora da vista (sem destruir; uma vez só até a próxima mão posta).
function Maos1P.hide()
	local m = S.model
	if m and not S.hidden then
		S.hidden = true
		m:PivotTo(FAR)
	end
end

function Maos1P.model(): Model?
	return S.model
end

-- D-108: escala das mãos de 1ª pessoa (a da arma). Mudou: refaz no próximo ensure().
function Maos1P.setScale(k: number)
	S.k = k
end

function Maos1P.scale(): number
	return S.k
end

return Maos1P
