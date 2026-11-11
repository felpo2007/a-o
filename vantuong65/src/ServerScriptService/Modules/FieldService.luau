--!strict
-- Serviços de campo da Parte 12, todos validados no servidor:
--   configurações de controle salvas na conta (Settings_Get / Settings_Save);
--   tipo de entrada de cada jogador (Input_Type): atributo + AnalyticsService, para medir
--     equilíbrio controle x mouse (Parte 12.4);
--   marcações e mensagens predefinidas para o squad ou o comando (sem digitar, Parte 12.5);
--   granadas de fragmentação e de fumaça;
--   corpo a corpo (coronhada ou baioneta).
-- Números marcados PLACEHOLDER estão na D-43.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comms = require(ReplicatedStorage.Shared.Comms)
local Kit = require(ReplicatedStorage.Shared.Kit)
local Radio = require(ReplicatedStorage.Shared.Radio)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Smoke = require(ReplicatedStorage.Shared.Smoke)
local Combatants = require(script.Parent.Combatants)
local ExplosionService = require(script.Parent.ExplosionService)
local MedicalService = require(script.Parent.MedicalService)
local PlayerData = require(script.Parent.PlayerData)

local FieldService = {}
local M = 0.28
local rng = Rng.new(1965)
local last: { [Player]: { [string]: number } } = {}

local function throttle(p: Player, key: string, seconds: number): boolean
	last[p] = last[p] or {}
	local now = os.clock()
	if now - (last[p][key] or 0) < seconds then
		return false
	end
	last[p][key] = now
	return true
end

local function alive(p: Player): Model?
	local c = p.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if c and hum and hum.Health > 0 and not c:GetAttribute("Downed") then
		return c
	end
	return nil
end

local function finite(v: any): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

-- ===== marcações e mensagens =====
local function recipients(p: Player, channel: string): { Player }
	local out = {}
	local f, sq = p:GetAttribute("Faction"), p:GetAttribute("SquadId")
	for _, o in Players:GetPlayers() do
		if o:GetAttribute("Faction") == f then
			if channel == "command" then
				local r = o:GetAttribute("Role")
				if o == p or r == "commander" or r == "squad_leader" then
					table.insert(out, o)
				end
			elseif sq ~= nil and o:GetAttribute("SquadId") == sq then
				table.insert(out, o)
			end
		end
	end
	if #out == 0 then
		table.insert(out, p)
	end
	return out
end

local markRng = Random.new()
local function onMark(p: Player, req: any)
	local c = alive(p)
	if not c or type(req) ~= "table" or not finite(req.pos) or not throttle(p, "mark", 1) then
		return
	end
	local pos: Vector3 = req.pos
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- marcação de lugar (não revela inimigo): até 1.500 m de onde o jogador está
	if root and (pos - root.Position).Magnitude * M > 1500 then
		return
	end
	local kind = if req.kind == "target" or req.kind == "map" then req.kind else "point"
	local msg = { x = pos.X, y = pos.Y, z = pos.Z, from = p.DisplayName, kind = kind } :: any
	if kind == "target" and root then
		-- inimigo: área aproximada (erro cresce com a distância); quem recebe não sabe o ponto exato
		local r = Comms.markError((pos - root.Position).Magnitude * M)
		local ox, oz = Comms.markOffset(r, markRng:NextNumber(), markRng:NextNumber())
		msg.x, msg.z = pos.X + ox / M, pos.Z + oz / M
		msg.r, msg.ttl = r, Comms.MARK_TTL_S
	end
	for _, o in recipients(p, "squad") do
		Net.event("Squad_Mark"):FireClient(o, msg)
	end
end

local function onMessage(p: Player, req: any)
	if
		type(req) ~= "table"
		or type(req.id) ~= "string"
		or not Comms.MESSAGES[req.id]
		or not throttle(p, "msg", 1.5)
	then
		return
	end
	local channel = if req.channel == "command" then "command" else "squad"
	-- canal Comando: só com o rádio do squad (Parte 11), o comandante ou o morteiro
	if
		channel == "command"
		and not Radio.canTalkToCommand(p:GetAttribute("Role") :: string?, p:GetAttribute("Radio") == true)
	then
		Net.event("Squad_Message"):FireClient(p, { id = "no_radio", from = "", channel = "squad" })
		return
	end
	for _, o in recipients(p, channel) do
		Net.event("Squad_Message"):FireClient(o, { id = req.id, from = p.DisplayName, channel = channel })
	end
end

-- ===== granadas =====
local THROW_MS = 15 -- velocidade de arremesso (PLACEHOLDER)
local FUSE_S = 4.5 -- espoleta (PLACEHOLDER: manual da granada a confirmar)
local smokeFolder: Folder

local function spawnSmoke(pos: Vector3)
	local p = Instance.new("Part")
	p.Name = "Cloud"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos + Vector3.new(0, 1.5 / M, 0)
	p:SetAttribute("R", Smoke.RADIUS_M / M)
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 40
	pe.Lifetime = NumberRange.new(8, 12)
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 22) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(205, 205, 200))
	pe.Parent = p
	p.Parent = smokeFolder
	task.delay(Smoke.DURATION_S, function()
		pe.Enabled = false
		task.wait(12)
		p:Destroy()
	end)
end

local function onThrow(p: Player, req: any)
	local c = alive(p)
	if not c or type(req) ~= "table" or not finite(req.dir) or not throttle(p, "throw", 1.2) then
		return
	end
	local kind = if req.kind == "smoke" then "smoke" else "frag"
	local attr = if kind == "smoke" then "Smokes" else "Frags"
	local left = (p:GetAttribute(attr) :: number?) or 0
	if left <= 0 then
		return
	end
	p:SetAttribute(attr, left - 1)
	local head = c:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local dir: Vector3 = (req.dir :: Vector3).Unit
	local g = Instance.new("Part")
	g.Name = "Grenade"
	g.Shape = Enum.PartType.Ball
	g.Size = Vector3.one * (0.08 / M)
	g.Color = Color3.fromRGB(60, 66, 44)
	g.CanQuery = false
	g.Position = head.Position + dir * (0.6 / M)
	g.Parent = workspace
	g:SetNetworkOwner(nil)
	g.AssemblyLinearVelocity = (dir + Vector3.new(0, 0.25, 0)).Unit * THROW_MS / M
	local faction = p:GetAttribute("Faction")
	task.delay(if kind == "smoke" then 1.5 else FUSE_S, function()
		if not g.Parent then
			return
		end
		local pos = g.Position
		g:Destroy()
		if kind == "smoke" then
			spawnSmoke(pos)
		else
			ExplosionService.detonate(if faction == "VC" then "grenade_vc" else "grenade_us", pos, p)
		end
	end)
end

-- ===== corpo a corpo =====
local BAYONET_OK = { m14 = true, sks = true, type56 = true }
local function zoneOf(part: Instance): string
	local n = part.Name
	if n == "Head" then
		return "head"
	elseif string.find(n, "Arm") or string.find(n, "Hand") then
		return "arm"
	elseif string.find(n, "Leg") or string.find(n, "Foot") then
		return "leg"
	end
	return "torso"
end

local function onMelee(p: Player, req: any)
	local c = alive(p)
	if not c or type(req) ~= "table" or not finite(req.dir) or not throttle(p, "melee", 0.9) then
		return
	end
	local head = c:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bayonet = c:GetAttribute("Bayonet") == true
	local reach = (if bayonet then 2.4 else 1.8) / M -- alcance com o fuzil (PLACEHOLDER)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c }
	local hit = workspace:Raycast(head.Position, (req.dir :: Vector3).Unit * reach, params)
	if not hit then
		return
	end
	local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
	local e = model and Combatants.get(model)
	if not e or e.faction == p:GetAttribute("Faction") then
		return
	end
	-- energia transferida (PLACEHOLDER): coronhada não incapacita sozinha; baioneta fere grave
	MedicalService.hit(e.model, zoneOf(hit.Instance), if bayonet then 900 else 250, rng:next())
end

function FieldService.start()
	smokeFolder = Instance.new("Folder")
	smokeFolder.Name = "Smoke"
	smokeFolder.Parent = workspace

	Net.func("Settings_Get").OnServerInvoke = function(p: Player)
		local prof = PlayerData.get(p)
		return InputMap.validate(prof and prof.settings)
	end
	Net.event("Settings_Save").OnServerEvent:Connect(function(p, raw)
		local prof = PlayerData.get(p)
		if prof and throttle(p, "settings", 1) then
			prof.settings = InputMap.validate(raw)
		end
	end)
	Net.event("Input_Type").OnServerEvent:Connect(function(p, t)
		if (t == "gamepad" or t == "kbm" or t == "touch") and throttle(p, "itype", 2) then
			if p:GetAttribute("InputType") ~= t then
				p:SetAttribute("InputType", t)
				pcall(function()
					AnalyticsService:LogCustomEvent(p, "input_type_" .. t)
				end)
			end
		end
	end)
	Net.event("Squad_Mark").OnServerEvent:Connect(onMark)
	Net.event("Squad_Message").OnServerEvent:Connect(onMessage)
	Net.event("Throw_Request").OnServerEvent:Connect(onThrow)
	Net.event("Combat_Melee").OnServerEvent:Connect(onMelee)
	Net.event("Posture_Set").OnServerEvent:Connect(function(p, req: any)
		if type(req) == "table" and type(req.bayonet) == "boolean" then
			FieldService.setBayonet(p, req.bayonet)
		end
	end)

	Net.event("Kit_Set").OnServerEvent:Connect(function(p: Player, raw: any)
		if not throttle(p, "kit", 0.5) then
			return
		end
		local wid = string.split(tostring(p:GetAttribute("Loadout") or ""), ",")[1]
		local wp = Weapons.get(wid)
		local k = Kit.validate(raw, if wp then wp.kind else "rifle")
		p:SetAttribute("KitMags", k.mags)
		p:SetAttribute("KitFrags", k.frags)
		p:SetAttribute("KitSmokes", k.smokes)
		p:SetAttribute("KitBandages", k.bandages)
	end)
	-- itens por vida: 2 granadas e 1 fumaça (PLACEHOLDER); baioneta começa recolhida
	local function arm(p: Player)
		p.CharacterAdded:Connect(function(c)
			-- equipamento por peso (Kit): validado no Kit_Set; padrão 2 granadas e 1 fumaça
			-- + equipamento liberado (D-72, ProgressionService.applyGear)
			local gf, gs = p:GetAttribute("GearFrags"), p:GetAttribute("GearSmokes")
			local kf, ks = p:GetAttribute("KitFrags"), p:GetAttribute("KitSmokes")
			p:SetAttribute("Frags", (if type(kf) == "number" then kf else 2) + (if type(gf) == "number" then gf else 0))
			p:SetAttribute(
				"Smokes",
				(if type(ks) == "number" then ks else 1) + (if type(gs) == "number" then gs else 0)
			)
			c:SetAttribute("Bayonet", false)
		end)
	end
	for _, p in Players:GetPlayers() do
		arm(p)
	end
	Players.PlayerAdded:Connect(arm)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
end

-- baioneta: o cliente pede; o servidor confere a arma na mão
function FieldService.setBayonet(p: Player, on: boolean)
	local c = alive(p)
	local lo = p:GetAttribute("Loadout")
	local first = if type(lo) == "string" then string.split(lo, ",")[1] else ""
	if c then
		c:SetAttribute("Bayonet", on and BAYONET_OK[first] == true)
	end
end

return FieldService
