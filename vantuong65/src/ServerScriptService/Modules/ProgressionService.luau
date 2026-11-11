--!strict
-- Progressão no servidor (D-72): XP e posto, créditos de intendência (CI), equipamento liberado
-- (posto, CI ou Game Pass) e o "renascer guardado" do Developer Product. As regras e os números
-- ficam em Shared/Progression (puro, testado no Lune); o renascer onde caiu é do SpawnService.
-- Ganchos (sem dependência circular): MedicalService.onCare, MatchService.onEvent/onEnd,
-- CommerceService.onGrant/onRefresh.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Combatants = require(script.Parent.Combatants)
local CommerceService = require(script.Parent.CommerceService)
local MatchService = require(script.Parent.MatchService)
local MedicalService = require(script.Parent.MedicalService)
local PlayerData = require(script.Parent.PlayerData)

local ProgressionService = {}

type Sess = {
	window: Progression.Window,
	pairs: { [string]: number },
	teamSince: number?,
	faction: string?,
}
local sess: { [Player]: Sess } = {}

-- avisado quando um renascer guardado chega (o SpawnService põe o jogador onde caiu)
ProgressionService.onRespawnCredit = nil :: ((player: Player) -> ())?

local function passes(p: Player): { [string]: boolean }
	return (CommerceService.ownership(p).passes :: any) or {}
end

local function factionOf(p: Player): string?
	local f = p:GetAttribute("Faction")
	return if f == "US" or f == "VC" then f else nil
end

local function kindOf(p: Player): string
	local wid = string.split(tostring(p:GetAttribute("Loadout") or ""), ",")[1]
	local wp = Weapons.get(wid)
	return if wp then wp.kind else "rifle"
end

function ProgressionService.rank(p: Player): number
	local prof = PlayerData.get(p)
	return if prof then Progression.rankFor(prof.xp) else 1
end

local function stateFor(p: Player, extra: { [string]: any }?): { [string]: any }?
	local prof = PlayerData.get(p)
	if not prof then
		return nil
	end
	local faction = factionOf(p)
	local rank, inRank, need = Progression.progress(prof.xp)
	local ps = passes(p)
	local gear = {}
	for _, g in Progression.gearList(faction or "US") do
		local ok, how = Progression.gearUnlocked(g.id, rank, ps, prof.gear)
		table.insert(gear, {
			id = g.id,
			name = g.name,
			effect = g.effect,
			kg = g.kg,
			price = g.price,
			buyRank = g.buyRank,
			tier = g.tier,
			unlocked = ok,
			how = how,
			on = prof.gearOn[g.id] ~= false,
		})
	end
	local tiers = {}
	for _, t in Progression.TIERS do
		table.insert(tiers, {
			tier = t.tier,
			name = t.name,
			rank = t.rank,
			rankName = Progression.rankName(faction, t.rank),
			key = t.key,
			passId = (Commerce.IDS :: any)[t.key] or 0,
			owned = ps[t.key] == true,
		})
	end
	local nextName = if rank < Progression.MAX_RANK then Progression.rankName(faction, rank + 1) else nil
	return {
		xp = prof.xp,
		rank = rank,
		rankName = Progression.rankName(faction, rank),
		nextName = nextName,
		inRank = inRank,
		need = need,
		credits = prof.credits,
		respawnCredits = prof.respawnCredits,
		cur = Progression.CUR,
		currency = Progression.CURRENCY,
		tiers = tiers,
		gear = gear,
		faction = faction,
		respawnProductId = Commerce.IDS.PRODUCT_RESPAWN_INPLACE,
		gain = extra and extra.gain,
		rankUp = extra and extra.rankUp,
		result = extra and extra.result,
	}
end

function ProgressionService.push(p: Player, extra: { [string]: any }?)
	local prof = PlayerData.get(p)
	if not prof then
		return
	end
	local r = Progression.rankFor(prof.xp)
	-- atributos lidos pelo lobby (plaqueta do posto), pelo HUD e pelo SpawnService
	p:SetAttribute("XP", prof.xp)
	p:SetAttribute("Rank", r)
	p:SetAttribute("RankName", Progression.rankName(factionOf(p), r))
	p:SetAttribute("Credits", prof.credits)
	p:SetAttribute("RespawnCredits", prof.respawnCredits)
	local st = stateFor(p, extra)
	if st then
		Net.event("Progress_State"):FireClient(p, st)
	end
end
local push = ProgressionService.push

-- Soma XP e CI já liberados pelo teto (ou do fim de partida, que fica fora do teto). Promoção dá o
-- soldo do posto novo.
local function add(p: Player, gx: number, gc: number, label: string)
	local prof = PlayerData.get(p)
	if not prof or (gx <= 0 and gc <= 0) then
		return
	end
	local before = Progression.rankFor(prof.xp)
	prof.xp = math.min(prof.xp + gx, 1000000000)
	prof.credits = math.min(prof.credits + gc, Progression.MAX_CREDITS)
	local after = Progression.rankFor(prof.xp)
	local extra: { [string]: any } = { gain = { label = label, xp = gx, cr = gc } }
	if after > before then
		local bonus = Progression.rankUpCredits(before, after)
		prof.credits = math.min(prof.credits + bonus, Progression.MAX_CREDITS)
		extra.rankUp = {
			from = before,
			to = after,
			name = Progression.rankName(factionOf(p), after),
			pt = Progression.rankDef(factionOf(p), after).pt,
			bonus = bonus,
		}
	end
	push(p, extra)
end

-- Recompensa por ação (Progression.REWARDS), com teto por minuto e, para cuidar de alguém, espera
-- por par (quem ajuda, quem é ajudado).
function ProgressionService.award(p: Player, kind: string, pairKey: string?)
	local s = sess[p]
	local rw = Progression.REWARDS[kind]
	if not (s and rw and PlayerData.get(p)) then
		return
	end
	local now = os.clock()
	local cd = Progression.PAIR_COOLDOWN[kind]
	if pairKey and cd and not Progression.pairReady(s.pairs, kind .. ":" .. pairKey, now, cd) then
		return
	end
	local gx, gc = Progression.grant(s.window, now, rw.xp, rw.cr)
	add(p, gx, gc, rw.label)
end
local award = ProgressionService.award

-- Equipamento do próximo spawn: atributos lidos pelo CombatService (carregadores), FieldService
-- (granadas e fumaça), MedicalService (curativos), ExplosionService (colete) e Movement (peso e
-- fôlego). Devolve os ids levados.
function ProgressionService.applyGear(p: Player): { string }
	local prof = PlayerData.get(p)
	local faction = factionOf(p)
	local ids: { string } = {}
	if prof and faction then
		ids = Progression.equipped(faction, Progression.rankFor(prof.xp), passes(p), prof.gear, prof.gearOn)
	end
	local b = Progression.gearBonus(ids, kindOf(p))
	p:SetAttribute("GearMags", b.mags)
	p:SetAttribute("GearFrags", b.frags)
	p:SetAttribute("GearSmokes", b.smokes)
	p:SetAttribute("GearBandages", b.bandages)
	p:SetAttribute("GearTourniquets", b.tourniquets)
	p:SetAttribute("GearKg", b.kg)
	p:SetAttribute("FragFactor", b.fragFactor)
	p:SetAttribute("StaminaRegen", b.stamina)
	p:SetAttribute("Gear", table.concat(ids, ","))
	return ids
end

-- CI fora do teto por minuto (recompensa diária)
function ProgressionService.addCredits(p: Player, amount: number, label: string)
	add(p, 0, math.max(math.floor(amount), 0), label)
end

-- Gasta CI (renascer onde caiu). Devolve false se não houver saldo.
function ProgressionService.spendCredits(p: Player, amount: number): boolean
	local prof = PlayerData.get(p)
	if not prof or prof.credits < amount then
		return false
	end
	prof.credits -= amount
	push(p)
	return true
end

-- Gasta um renascer guardado (comprado em Robux)
function ProgressionService.useRespawnCredit(p: Player): boolean
	local prof = PlayerData.get(p)
	if not prof or prof.respawnCredits < 1 then
		return false
	end
	prof.respawnCredits -= 1
	push(p)
	task.spawn(PlayerData.save, p) -- gasto do que foi pago em Robux grava logo
	return true
end

-- quem está vivo e dentro do raio do ponto forte
local function playersAt(sector: number, faction: string): { Player }
	local out = {}
	local sp = MatchService.points[sector]
	if not sp then
		return out
	end
	local r2 = (MapConfig.CaptureRadiusStuds or (60 / 0.28)) ^ 2
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and factionOf(p) == faction then
			local dx, dz = root.Position.X - sp.x, root.Position.Z - sp.z
			if dx * dx + dz * dz <= r2 then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function newSess(p: Player)
	sess[p] = { window = Progression.newWindow(), pairs = {}, teamSince = nil, faction = factionOf(p) }
end

function ProgressionService.start()
	PlayerData.Loaded:Connect(function(p: Player)
		if not sess[p] then
			newSess(p)
		end
		push(p)
	end)
	Players.PlayerAdded:Connect(function(p)
		newSess(p)
		p:GetAttributeChangedSignal("Faction"):Connect(function()
			local s = sess[p]
			if s then
				s.faction = factionOf(p)
				s.teamSince = if s.faction then os.clock() else nil
			end
			push(p) -- o nome do posto muda com o lado
		end)
	end)
	for _, p in Players:GetPlayers() do
		newSess(p)
		if PlayerData.get(p) then
			push(p)
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		sess[p] = nil
	end)

	-- abate e assistência: na morte, o último jogador inimigo que acertou leva o abate (até 2 min
	-- antes, cobre caído e sangrando) e os outros que acertaram no último minuto levam assistência
	Combatants.Added:Connect(function(e: any)
		local hum = Combatants.humanoid(e)
		if not hum then
			return
		end
		hum.Died:Once(function()
			if e.model:GetAttribute("Evacuated") == true then
				return -- medevac não é baixa
			end
			local now = os.clock()
			local killer: Player? = nil
			local best = -math.huge
			local hits = MedicalService.attackers(e.model)
			for who, t in hits do
				if
					factionOf(who)
					and factionOf(who) ~= e.faction
					and now - t <= Progression.KILL_WINDOW_S
					and t > best
				then
					killer, best = who, t
				end
			end
			if killer then
				award(killer, "kill")
			end
			for who, t in hits do
				if
					who ~= killer
					and factionOf(who)
					and factionOf(who) ~= e.faction
					and now - t <= Progression.ASSIST_WINDOW_S
				then
					award(who, "assist")
				end
			end
		end)
	end)

	-- cuidar de um companheiro (curativo, tratamento, reanimação)
	MedicalService.onCare = function(actor: Player, target: Model, op: string)
		local tp = Players:GetPlayerFromCharacter(target)
		local key = if tp then tostring(tp.UserId) else target.Name
		award(actor, op, key)
	end

	-- captura (quem capturou) e neutralização (o lado que atacava)
	MatchService.onEvent = function(kind: string, sector: number, team: string?)
		local attacker: string? = nil
		if kind == "captured" then
			attacker = team
		elseif kind == "neutralized" then
			attacker = if team == "US" then "VC" elseif team == "VC" then "US" else nil
		end
		if attacker == "US" or attacker == "VC" then
			for _, p in playersAt(sector, attacker) do
				award(p, if kind == "captured" then "capture" else "neutralize")
			end
		end
	end

	-- fim de partida: vitória vale mais, proporcional ao tempo no time (fora do teto por minuto)
	MatchService.onEnd = function(winner: string, seconds: number)
		local now = os.clock()
		for _, p in Players:GetPlayers() do
			local s = sess[p]
			local f = factionOf(p)
			if s and f and s.teamSince then
				local result = if winner == f then "win" elseif winner == "draw" then "draw" else "loss"
				local on = math.min(now - s.teamSince, seconds)
				local gx, gc = Progression.matchReward(result, on, seconds)
				local r = Progression.MATCH[result]
				add(p, gx, gc, "Fim de partida: " .. (if r then r.label else result))
				s.teamSince = now -- a próxima partida conta do zero
			end
			task.spawn(PlayerData.save, p)
		end
	end

	-- passes comprados ou perdidos: o nível do kit muda
	CommerceService.onRefresh = function(p: Player)
		push(p)
	end
	CommerceService.onGrant = function(p: Player, grants: string, now: boolean)
		if grants == "respawn" then
			push(p, { result = if now then "Renascer guardado recebido" else nil })
			if ProgressionService.onRespawnCredit then
				ProgressionService.onRespawnCredit(p)
			end
		end
	end

	-- tempo em campo: um minuto vivo e com lado rende um pouco
	task.spawn(function()
		while true do
			task.wait(Progression.TIME_EVERY_S)
			for _, p in Players:GetPlayers() do
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and factionOf(p) and not MatchService.ended then
					award(p, "time")
				end
			end
		end
	end)

	Net.func("Progress_Get").OnServerInvoke = function(p: Player)
		return stateFor(p)
	end

	-- compra permanente com CI (gravada logo; o saldo e a união dos itens vão pelo delta da sessão)
	local lastBuy: { [Player]: number } = {}
	Net.event("Gear_Buy").OnServerEvent:Connect(function(p: Player, id: any)
		if type(id) ~= "string" then
			return
		end
		local now = os.clock()
		if lastBuy[p] and now - lastBuy[p] < 0.5 then
			return
		end
		lastBuy[p] = now
		local prof = PlayerData.get(p)
		if not prof then
			return
		end
		local rank = Progression.rankFor(prof.xp)
		local ok, why = Progression.canBuyGear(id, factionOf(p), rank, passes(p), prof.gear, prof.credits)
		if not ok then
			push(p, { result = why })
			return
		end
		local g = Progression.GEAR[id]
		prof.credits -= g.price
		prof.gear[id] = true
		prof.gearOn[id] = nil
		push(p, { result = string.format("%s comprado por %d %s", g.name, g.price, Progression.CUR) })
		task.spawn(PlayerData.save, p)
	end)

	-- levar ou deixar um item liberado no próximo spawn (só guarda os desmarcados)
	Net.event("Gear_Equip").OnServerEvent:Connect(function(p: Player, id: any, on: any)
		local prof = PlayerData.get(p)
		if not prof or type(id) ~= "string" or type(on) ~= "boolean" or not Progression.GEAR[id] then
			return
		end
		if on then
			prof.gearOn[id] = nil
		else
			prof.gearOn[id] = false
		end
		push(p)
	end)
end

return ProgressionService
