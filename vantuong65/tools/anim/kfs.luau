--!strict
-- Grava cada clipe do soldado (assets/mocap/soldado/<nome>.json, saído do tools/anim/retarget.py)
-- como KeyframeSequence num .rbxm: Keyframe -> Pose em hierarquia (HumanoidRootPart > LowerTorso >
-- UpperTorso > ...). Pose.CFrame = Transform da junta (AnimationConstraint/Motor6D) relativo ao
-- repouso; só a Root tem translação. Camadas de cima (recarregar, granada) levam só tronco, cabeça e
-- braços: a LowerTorso entra com Weight 0, só como elo da hierarquia, e as pernas ficam de fora.
-- Depois de gravar, relê o arquivo e confere quadros, laço, prioridade, AuthoredHipHeight e poses.
-- Uso (na pasta vantuong65):  lune run tools/anim/kfs.luau [nome ...]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local CFrame = roblox.CFrame
local Instance = roblox.Instance
local Enum = roblox.Enum :: any

local DIR = "assets/mocap/soldado"
local PARENT: { [string]: string } = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
}
local ORDER = {
	"LowerTorso",
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local function cf(v: { number }): any
	return CFrame.new(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
end

-- peças que entram: peso > 0 ou pai de alguma que entra
local function included(weights: { [string]: number }): { [string]: boolean }
	local inc: { [string]: boolean } = {}
	for _, part in ORDER do
		if (weights[part] or 0) > 0 then
			local p: string? = part
			while p and p ~= "HumanoidRootPart" do
				inc[p] = true
				p = PARENT[p]
			end
		end
	end
	return inc
end

local function build(d: any): any
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = "VT65_" .. d.nome
	kfs.Loop = d.laco == true
	kfs.Priority = Enum.AnimationPriority[d.prioridade]
	kfs.AuthoredHipHeight = d.authoredHipHeight
	local weights = d.pesos :: { [string]: number }
	local inc = included(weights)
	for _, q in d.quadros do
		local kf = Instance.new("Keyframe")
		kf.Time = q.t
		local poses: { [string]: any } = {}
		local hrp = Instance.new("Pose")
		hrp.Name = "HumanoidRootPart"
		hrp.Weight = 0
		hrp.Parent = kf
		poses.HumanoidRootPart = hrp
		for _, part in ORDER do
			if inc[part] then
				local p = Instance.new("Pose")
				p.Name = part
				p.CFrame = cf(q.poses[part])
				p.Weight = if (weights[part] or 0) > 0 then 1 else 0
				p.EasingStyle = Enum.PoseEasingStyle.Linear
				p.EasingDirection = Enum.PoseEasingDirection.In
				p.Parent = poses[PARENT[part]]
				poses[part] = p
			end
		end
		kf.Parent = kfs
	end
	return kfs, inc
end

-- confere o .rbxm relido contra o JSON
local function check(path: string, d: any, inc: { [string]: boolean }): (boolean, string)
	local back = roblox.deserializeModel(fs.readFile(path))[1] :: any
	if not back or back.ClassName ~= "KeyframeSequence" then
		return false, "não é KeyframeSequence"
	end
	local kfs = back:GetChildren()
	if #kfs ~= #d.quadros then
		return false, string.format("%d quadros (JSON %d)", #kfs, #d.quadros)
	end
	if back.Loop ~= (d.laco == true) or back.Priority ~= Enum.AnimationPriority[d.prioridade] then
		return false, "laço ou prioridade"
	end
	if math.abs(back.AuthoredHipHeight - d.authoredHipHeight) > 1e-3 then
		return false, "AuthoredHipHeight"
	end
	local maxErr = 0
	for _, kf in kfs do
		local i = math.round(kf.Time / d.duracao * (#d.quadros - 1)) + 1
		local q = d.quadros[i]
		if not q or math.abs(q.t - kf.Time) > 1e-3 then
			return false, "tempo do quadro " .. tostring(kf.Time)
		end
		for _, pose in kf:GetDescendants() do
			if pose.Name ~= "HumanoidRootPart" then
				if not inc[pose.Name] then
					return false, "pose a mais: " .. pose.Name
				end
				local want = cf(q.poses[pose.Name])
				local got = pose.CFrame
				maxErr = math.max(maxErr, (want.Position - got.Position).Magnitude)
				for _, ax in { "XVector", "YVector", "ZVector" } do
					maxErr = math.max(maxErr, ((want :: any)[ax] - (got :: any)[ax]).Magnitude)
				end
			end
		end
	end
	if maxErr > 1e-3 then
		return false, string.format("pose diverge %.2g", maxErr)
	end
	return true, string.format("%d quadros, erro máx %.1g", #kfs, maxErr)
end

local names = process.args
if #names == 0 then
	names = {}
	for _, f in fs.readDir(DIR) do
		local n = string.match(f, "^(.+)%.json$")
		if n and n ~= "ids" then -- ids.json: os IDs publicados (subir.py)
			table.insert(names, n)
		end
	end
	table.sort(names)
end

local failed = 0
for _, name in names do
	local d = serde.decode("json", fs.readFile(DIR .. "/" .. name .. ".json"))
	local kfs, inc = build(d)
	local out = DIR .. "/" .. name .. ".rbxm"
	fs.writeFile(out, roblox.serializeModel({ kfs }))
	local ok, msg = check(out, d, inc)
	print(
		string.format(
			"%s %-15s %5.2f s laço=%s %s %6d bytes  %s",
			if ok then "ok  " else "FALHA",
			name,
			d.duracao,
			tostring(d.laco),
			d.prioridade,
			#fs.readFile(out),
			msg
		)
	)
	if not ok then
		failed += 1
	end
end
if failed > 0 then
	process.exit(1)
end
