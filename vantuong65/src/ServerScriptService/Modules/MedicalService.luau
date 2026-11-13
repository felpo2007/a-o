--!strict
-- Ferimentos no servidor (Parte 10.2), para jogadores e bots (chave = modelo do personagem).
-- O cliente só recebe o próprio estado (sem barra de vida: efeitos no corpo).
-- D-107: caído deita de costas (gancho onDowned, posto pelo PostureService), desiste a qualquer hora e
-- a morte vira queda de boneco e corpo no chão (CorposService, ligado aqui).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Corpos = require(ReplicatedStorage.Shared.Corpos)
local Medical = require(ReplicatedStorage.Shared.Medical)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Units = require(ReplicatedStorage.Shared.Units)
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local Combatants = require(script.Parent.Combatants)
local CorposService = require(script.Parent.CorposService)

local MedicalService = {}
local states: { [Model]: Medical.State } = {}
local busy: { [Model]: number } = {}
local REACH = 3 / 0.28 -- 3 m
-- D-107: "Downed" mudou (caiu ou foi reanimado): o PostureService deita ou levanta o corpo
MedicalService.onDowned = nil :: ((model: Model, on: boolean) -> ())?

function MedicalService.get(model: Model): Medical.State?
	return states[model]
end

local function humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function root(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function apply(model: Model)
	local s, hum = states[model], humanoid(model)
	if not (s and hum) then
		return
	end
	local e = Combatants.get(model)
	local player = e and e.player
	-- D-99: vantagens compradas (atributos Vant_* que o servidor grava no jogador; 1 sem passe):
	-- vida máxima e sangramento acompanham o passe mesmo se ele chegar depois do nascimento
	local who: Instance = player or model
	local maxH = Medical.C.health * Vantagens.mult(who, "health")
	if math.abs(maxH - s.maxHealth) > 1e-6 then
		if not s.downedAt and not s.dead and maxH > s.maxHealth then
			s.health += maxH - s.maxHealth
		end
		s.maxHealth = maxH
		s.health = math.min(s.health, maxH)
	end
	s.bleedMult = Vantagens.mult(who, "bleed")
	if hum.MaxHealth ~= maxH then
		hum.MaxHealth = maxH
	end
	if s.dead then
		hum.Health = 0
		return
	end
	local was = model:GetAttribute("Downed") == true
	model:SetAttribute("Downed", s.downedAt ~= nil)
	if was ~= (s.downedAt ~= nil) and MedicalService.onDowned then
		MedicalService.onDowned(model, s.downedAt ~= nil) -- deita de costas / levanta (D-107)
	end
	if s.downedAt then
		hum.Health = 1
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	else
		hum.Health = math.clamp(s.health, 1, maxH)
		-- postura e corrida (PostureService): deitado rasteja, agachado anda devagar, correndo só
		-- de pé e sem perna ferida. Teto único em Shared/Movement.serverSpeed (o cliente nunca passa
		-- dele, teste "movimento"); o VC, mais leve, tem teto 12% maior (D-93).
		local stance = if model:GetAttribute("Prone")
			then "prone"
			elseif model:GetAttribute("Crouched") then "crouch"
			else "stand"
		local faction = model:GetAttribute("Faction")
		hum.WalkSpeed = Movement.serverSpeed(
			stance,
			model:GetAttribute("Sprinting") == true,
			s.legImpaired,
			false,
			if type(faction) == "string" then faction else nil,
			Vantagens.mult(who, "speed") -- D-99: trote e corrida (o cliente usa o mesmo)
		) / Units.STUD_M
		hum.JumpPower = if s.legImpaired then 0 else 30
	end
	model:SetAttribute("ArmImpaired", s.armImpaired)
	model:SetAttribute("LegImpaired", s.legImpaired)
	if player then
		player:SetAttribute("Downed", s.downedAt ~= nil)
		player:SetAttribute("ArmImpaired", s.armImpaired)
		Net.event("Medical_State"):FireClient(player, {
			health = s.health,
			maxHealth = s.maxHealth,
			bleed = Medical.bleedRate(s),
			arterial = Medical.arterial(s), -- D-99: a taxa mudou; quem decide pelo arterial lê isto
			downedAt = s.downedAt,
			now = os.clock(),
			blurUntil = s.blurUntil,
			arm = s.armImpaired,
			leg = s.legImpaired,
			bandages = s.bandages,
			tourniquets = s.tourniquets,
		})
	end
end
MedicalService.apply = apply

-- Progressão (D-72): quem acertou quem e quando, para o abate e a assistência na morte, e o aviso
-- de cuidado com um companheiro. Ganchos postos pelo ProgressionService (sem dependência circular).
local attackers: { [Model]: { [Player]: number } } = {}
MedicalService.onCare = nil :: ((actor: Player, target: Model, op: string) -> ())?

-- jogadores que acertaram a vítima (instante do último acerto de cada um)
function MedicalService.attackers(victim: Model): { [Player]: number }
	return attackers[victim] or {}
end

-- chamado pelo CombatService após validar o tiro (by = quem atirou, se for jogador)
function MedicalService.hit(victim: Model, zone: string, energyJ: number, roll: number, by: Player?)
	local s = states[victim]
	if not s then
		return
	end
	if by and by.Character ~= victim then
		attackers[victim] = attackers[victim] or {}
		attackers[victim][by] = os.clock()
	end
	if busy[victim] then
		busy[victim] = nil -- levar dano interrompe a ação (e a animação dela, D-99)
		victim:SetAttribute("ActionUntil", nil)
		victim:SetAttribute("VT65Acao", nil)
	end
	Medical.applyHit(s, zone, energyJ, roll, os.clock())
	apply(victim)
end

local function still(model: Model): boolean
	local r = root(model)
	return r ~= nil and Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude < 1
end

-- ação com tempo; cancela se mexer, levar dano ou o alvo sair do alcance. D-99: o atributo
-- "VT65Acao" (curativo, torniquete, tratar, reanimar) replica para todos; o SoldierAnimations e o
-- ItemView animam o soldado e as mãos de 1ª pessoa pela duração de "ActionUntil".
local function timed(actor: Model, target: Model, seconds: number, fn: () -> boolean, op: string?, anim: string)
	local token = os.clock()
	busy[actor] = token
	actor:SetAttribute("ActionUntil", os.clock() + seconds)
	actor:SetAttribute("VT65AcaoT", workspace:GetServerTimeNow()) -- relógio comum a todos
	actor:SetAttribute("VT65AcaoS", seconds)
	actor:SetAttribute("VT65Acao", anim)
	task.delay(seconds, function()
		if busy[actor] ~= token then
			return
		end
		actor:SetAttribute("ActionUntil", nil)
		actor:SetAttribute("VT65Acao", nil)
		busy[actor] = nil
		local ra, rt = root(actor), root(target)
		if not (ra and rt) or (ra.Position - rt.Position).Magnitude > REACH or not still(actor) then
			return
		end
		if fn() then
			apply(target)
			apply(actor)
			local who = Players:GetPlayerFromCharacter(actor)
			if op and who and target ~= actor and MedicalService.onCare then
				MedicalService.onCare(who, target, op)
			end
		end
	end)
end

-- ===== gancho do Studio (D-107): caído, morte e corpos =====
-- Barra de comando do SERVIDOR: workspace:SetAttribute("VT65DevFerido", X), X =
--   "boneco"     soldado do outro lado, parado a 4 m na frente do primeiro jogador
--   "caido"      o último boneco vivo (sem boneco: o bot mais perto) cai ferido; "morto" morre;
--                "reanimar" levanta
--   "eu_caido"   o primeiro jogador cai ferido; "eu_morto" morre; "eu_reanimar" levanta
--   "lote"       8 bonecos em fila a 6 m: metade cai ferida e, 1,5 s depois, todos morrem
--   "info"       no Output: corpos caindo / no chão / sumindo e, de cada caído, a inclinação do
--                tronco e a altura das costas sobre o terreno
local dummies: { Model } = {}
local M = Units.STUD_M

local function firstPlayer(): (Player?, BasePart?)
	for _, p in Players:GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			return p, r
		end
	end
	return nil, nil
end

local function makeDummy(p: Player, at: CFrame): Model?
	local Characters = require(script.Parent.Characters) :: any
	local AssetLoader = require(script.Parent.AssetLoader) :: any
	local faction = if p:GetAttribute("Faction") == "VC" then "US" else "VC"
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(
			Characters.describe(faction, nil, 7 + #dummies),
			Enum.HumanoidRigType.R15
		)
	end)
	if not ok or not model then
		warn("[VT65 TESTE] VT65DevFerido: não criou o boneco", model)
		return nil
	end
	local m = model :: Model
	m.Name = "Boneco_Ferido"
	m:SetAttribute("Bot", true)
	m:SetAttribute("Role", "rifleman")
	m:PivotTo(at)
	local folder = workspace:FindFirstChild("Combatants") or Instance.new("Folder")
	folder.Name = "Combatants"
	folder.Parent = workspace
	m.Parent = folder
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root:SetNetworkOwner(nil)
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		-- morto: a cópia fica no chão (CorposService); o original, que o BotService destruiria num bot
		-- de verdade, sai aqui
		hum.Died:Once(function()
			task.delay(Corpos.ASSENTAR_MAX_S + 1, function()
				m:Destroy()
			end)
		end)
	end
	Combatants.register(m, faction, nil)
	AssetLoader.attachWeapon(m, if faction == "VC" then "sks" else "m14")
	Characters.dress(m, faction, nil)
	table.insert(dummies, m)
	return m
end

local function devTarget(): Model?
	for i = #dummies, 1, -1 do
		local m = dummies[i]
		local h = m.Parent and m:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			return m
		end
	end
	local _, r = firstPlayer()
	local best, bestD = nil, math.huge
	for _, e in Combatants.list() do
		local rr, h = Combatants.root(e), Combatants.humanoid(e)
		if r and e.bot and rr and h and h.Health > 0 then
			local d = (rr.Position - r.Position).Magnitude
			if d < bestD then
				best, bestD = e.model, d
			end
		end
	end
	return best
end

local function devDown(m: Model)
	local s = states[m]
	if s and not s.dead and not s.downedAt then
		Medical.applyHit(s, "torso", Medical.C.torsoDownJ + 100, 0.5, os.clock())
		apply(m)
	end
end

local function devKill(m: Model)
	local s = states[m]
	if s and not s.dead then
		s.dead = true
		apply(m)
	end
end

local function devRevive(m: Model)
	local s = states[m]
	if s and Medical.revive(s, os.clock()) then
		apply(m)
	end
end

local function devInfo()
	local n, chao, some = CorposService.info()
	print(
		string.format(
			"[VT65 TESTE] corpos: %d caindo, %d no chão, %d sumindo (teto %d, %d s no chão)",
			n,
			chao,
			some,
			Corpos.TETO,
			Corpos.VIDA_S
		)
	)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	for _, e in Combatants.list() do
		local ut = e.model:FindFirstChild("UpperTorso") :: BasePart?
		local lt = e.model:FindFirstChild("LowerTorso") :: BasePart?
		if e.model:GetAttribute("Downed") == true and ut and lt then
			local tilt = math.deg(math.acos(math.clamp(ut.CFrame.UpVector.Y, -1, 1)))
			local cf, sz = lt.CFrame, lt.Size
			local half = (
				math.abs(cf.RightVector.Y) * sz.X
				+ math.abs(cf.UpVector.Y) * sz.Y
				+ math.abs(cf.LookVector.Y) * sz.Z
			) / 2
			local hit = workspace:Raycast(lt.Position + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
			local gap = if hit then (lt.Position.Y - half - hit.Position.Y) * M else 0 / 0
			local face = if ut.CFrame.LookVector.Y > 0.5 then "de costas" else "NÃO de costas"
			print(
				string.format(
					"[VT65 TESTE] caído %s: tronco a %.0f° da vertical (%s), costas a %.2f m do chão",
					e.model.Name,
					tilt,
					face,
					gap
				)
			)
		end
	end
end

local function devHook()
	local v = workspace:GetAttribute("VT65DevFerido")
	if type(v) ~= "string" then
		return
	end
	workspace:SetAttribute("VT65DevFerido", nil)
	if v == "info" then
		devInfo()
		return
	end
	local p, r = firstPlayer()
	if not (p and r) then
		warn("[VT65 TESTE] VT65DevFerido: nenhum jogador em campo")
		return
	end
	local pl, rt = p :: Player, r :: BasePart
	local function facing(dx: number, dz: number): CFrame
		local at = rt.CFrame * CFrame.new(dx / M, 0, -dz / M)
		return CFrame.lookAt(at.Position, Vector3.new(rt.Position.X, at.Y, rt.Position.Z))
	end
	local me = pl.Character
	if v == "boneco" then
		task.spawn(makeDummy, pl, facing(0, 4))
	elseif v == "caido" or v == "morto" or v == "reanimar" then
		local m = devTarget()
		if not m then
			warn("[VT65 TESTE] VT65DevFerido: nenhum boneco nem bot vivo")
			return
		end
		if v == "caido" then
			devDown(m)
		elseif v == "morto" then
			devKill(m)
		else
			devRevive(m)
		end
		print("[VT65 TESTE] VT65DevFerido:", v, m.Name)
	elseif me and (v == "eu_caido" or v == "eu_morto" or v == "eu_reanimar") then
		if v == "eu_caido" then
			devDown(me)
		elseif v == "eu_morto" then
			devKill(me)
		else
			devRevive(me)
		end
		print("[VT65 TESTE] VT65DevFerido:", v, pl.Name)
	elseif v == "lote" then
		task.spawn(function()
			local made: { Model } = {}
			for i = 1, 8 do
				local m = makeDummy(pl, facing((i - 4.5) * 1.5, 6))
				if m then
					table.insert(made, m)
				end
			end
			task.wait(1)
			for i, m in made do
				if i % 2 == 0 then
					devDown(m)
				end
			end
			task.wait(1.5)
			for _, m in made do
				devKill(m)
			end
			print(string.format("[VT65 TESTE] VT65DevFerido: lote de %d bonecos mortos (metade caída antes)", #made))
		end)
	else
		warn("[VT65 TESTE] VT65DevFerido: comando desconhecido", v)
	end
end

function MedicalService.start()
	CorposService.start() -- D-107: queda de boneco e corpos no chão
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevFerido"):Connect(devHook)
	end
	Combatants.Added:Connect(function(e: Combatants.Entry)
		-- D-99: vantagens "health" e "bleed" (1 sem passe; bots não têm)
		local who: Instance = e.player or e.model
		states[e.model] =
			Medical.new(Combatants.role(e) == "medic", Vantagens.mult(who, "health"), Vantagens.mult(who, "bleed"))
		local kb = e.player and e.player:GetAttribute("KitBandages")
		if type(kb) == "number" then
			-- médico mantém a dotação de médico se ela for maior; os outros levam o que escolheram
			local s = states[e.model]
			s.bandages = if Combatants.role(e) == "medic" then math.max(s.bandages, kb) else kb
		end
		-- equipamento liberado (D-72, ProgressionService.applyGear): curativos e torniquetes a mais
		if e.player then
			local s = states[e.model]
			local gb, gt = e.player:GetAttribute("GearBandages"), e.player:GetAttribute("GearTourniquets")
			s.bandages += if type(gb) == "number" then gb else 0
			s.tourniquets += if type(gt) == "number" then gt else 0
		end
		busy[e.model] = nil
		attackers[e.model] = nil
		e.model.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				states[e.model] = nil
				busy[e.model] = nil
				attackers[e.model] = nil
			end
		end)
		task.defer(apply, e.model)
	end)

	Net.event("Medical_Action").OnServerEvent:Connect(function(player, req)
		if type(req) ~= "table" or type(req.op) ~= "string" then
			return
		end
		local actor = player.Character
		local mine = actor and states[actor]
		if not (actor and mine) or mine.dead then
			return
		end
		-- D-107 (pedido do dono: "permita desistir quando morre sempre"): caído desiste na hora, sem
		-- esperar tempo mínimo nem outra condição (a tela de queda lê Medical.C.giveUpAfter = 0)
		if req.op == "giveup" then
			if mine.downedAt then
				mine.dead = true
				apply(actor)
			end
			return
		end
		local target: Model = actor
		if typeof(req.target) == "Instance" then
			local te = Combatants.get(req.target)
			if te then
				target = te.model
			end
		elseif type(req.target) == "number" then
			local tp = Players:GetPlayerByUserId(req.target)
			if tp and tp.Character then
				target = tp.Character
			end
		end
		local ts = states[target]
		if not ts or (target ~= actor and target:GetAttribute("Faction") ~= actor:GetAttribute("Faction")) then
			return
		end
		local C = Medical.C
		local isMedic = player:GetAttribute("Role") == "medic"
		-- D-99: vantagem "bandage" (0,74 do tempo de curativo e torniquete; 1 sem passe)
		local quick = Vantagens.mult(player, "bandage")
		if mine.downedAt then
			return -- caído não faz nada além de desistir
		elseif req.op == "bandage" and target == actor then
			-- D-99: a bandagem rápida estanca: torniquete na artéria (se houver um) e curativo no resto
			if #mine.wounds == 0 or (mine.bandages <= 0 and not (Medical.arterial(mine) and mine.tourniquets > 0)) then
				return
			end
			local anim = if Medical.arterial(mine) and mine.tourniquets > 0 then "tourniquet" else "bandage"
			timed(actor, actor, C.bandageSelf * quick, function()
				return (Medical.quickDress(mine))
			end, nil, anim)
		elseif req.op == "bandage" then
			timed(actor, target, C.bandageOther * quick, function()
				if mine.bandages <= 0 then
					return false
				end
				local stock = ts.bandages
				ts.bandages = 1
				local ok = Medical.bandage(ts)
				ts.bandages = stock
				if ok then
					mine.bandages -= 1
				end
				return ok
			end, "bandage", "bandage_other")
		elseif req.op == "tourniquet" and target == actor then
			if not (Medical.arterial(mine) and mine.tourniquets > 0) then
				return
			end
			timed(actor, actor, C.tourniquet * quick, function()
				return Medical.tourniquet(mine)
			end, nil, "tourniquet")
		elseif req.op == "treat" and isMedic and target ~= actor then
			timed(actor, target, C.medicTreat, function()
				return Medical.treat(ts)
			end, "treat", "treat")
		elseif req.op == "revive" and isMedic and target ~= actor then
			timed(actor, target, C.reviveTime, function()
				return Medical.revive(ts, os.clock())
			end, "revive", "revive")
		end
	end)

	task.spawn(function()
		while true do
			local dt = 0.25
			task.wait(dt)
			local now = os.clock()
			for model, s in states do
				local ev = Medical.tick(s, dt, now)
				if ev or s.downedAt or Medical.bleedRate(s) > 0 then
					apply(model)
				end
			end
		end
	end)
end

return MedicalService
