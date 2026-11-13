--!strict
-- Bots no squad do jogador (decisão do dono, 2026-11-12: "os bots completam o squad do jogador quando
-- há pouca gente"). Regras e números em BotBrain.FILL (fillPlan, escortSlot, escortHold, markActive).
--   - a cada 2 s: squad de humano de unidade leve (infantaria, recon; os de veículo e morteiro ficam de
--     fora) com menos de 4 membros recebe bots do mesmo lado até 4, sem passar do tamanho do squad;
--     entra ou sai um bot por squad por vez. São os bots que já existem (BotFill): o bot sai do squad
--     de bots (BotSquads) e volta para ele quando é liberado;
--   - no modelo do bot: SquadId e BotName (o nascer no companheiro do SpawnService lê os dois);
--   - fora de combate: segue o líder humano (se ele não está em campo, o humano do squad que está) a
--     10–30 m, num leque atrás dele; com a marca do líder na carta (Squad_Mark de tipo "map", de quem
--     é líder ou o único humano do squad, como no FieldService), vai até ela e fica em volta; em
--     combate, o BotService cuida como de qualquer bot;
--   - nasce no ponto livre mais perto do humano que segue.
-- Não dirige carro: tripulação de blindado é do BotVehicles, e o bot que vira tripulante sai do squad.
-- Studio: workspace:SetAttribute("VT65DevBots", "squad") mostra os squads com bots no Output;
-- "squad0" desliga o enchimento (libera todos) e "squad1" liga de novo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local BotLocomotion = require(script.Parent.BotLocomotion)
local BotSquads = require(script.Parent.BotSquads)
local BotTypes = require(script.Parent.BotTypes)
local TeamService = require(script.Parent.TeamService)

type Bot = BotTypes.Bot

local BotEscolta = {}
local M = 0.28
local F = BotBrain.FILL
local enabled = true
local getBots: () -> { Bot } = function()
	return {}
end

type Mark = { pos: Vector3, at: number, reached: boolean }
local marks: { [string]: Mark } = {}
local lastMark: { [Player]: number } = {}

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- squad de jogador (TeamService) pelo id
local function squadOf(faction: string, sid: string): any
	local st = TeamService.squads[faction]
	for _, s in (if st then st.squads else {}) :: { any } do
		if s.id == sid then
			return s
		end
	end
	return nil
end

local function rootIfAlive(p: Player?): BasePart?
	local c = if p then p.Character else nil
	local hum = if c then c:FindFirstChildOfClass("Humanoid") else nil
	local r = if c then c:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if hum and r and hum.Health > 0 then
		return r
	end
	return nil
end

-- Humano que o bot segue: o líder; se ele não está em campo, outro humano do squad em campo.
function BotEscolta.anchor(bot: Bot): BasePart?
	local sid = bot.playerSquad
	local s = if sid then squadOf(bot.faction, sid) else nil
	if not s then
		return nil
	end
	local lr = if s.leader then rootIfAlive(Players:GetPlayerByUserId(s.leader)) else nil
	if lr then
		return lr
	end
	for _, uid in s.members :: { number } do
		local r = rootIfAlive(Players:GetPlayerByUserId(uid))
		if r then
			return r
		end
	end
	return nil
end

-- Onde o bot deve nascer perto (o humano que ele segue), se houver.
function BotEscolta.spawnAnchor(bot: Bot): Vector3?
	local r = BotEscolta.anchor(bot)
	return if r then r.Position else nil
end

-- Põe (sid) ou tira (nil) o bot de um squad de jogador.
function BotEscolta.setSquad(bot: Bot, sid: string?)
	if bot.playerSquad == sid then
		return
	end
	bot.playerSquad = sid
	local m = bot.model
	if m then
		m:SetAttribute("SquadId", sid)
	end
	if sid then
		BotSquads.remove(bot)
	elseif not bot.removed then
		BotSquads.assign(bot)
	end
	bot.cover, bot.coverSector, bot.goal, bot.goalSector = nil, nil, nil, nil
end

-- Bot removido pelo rebalance: só esquece o squad (não volta para um squad de bots).
function BotEscolta.forget(bot: Bot)
	bot.playerSquad = nil
end

-- Marca do líder na carta (o FieldService repassa aos humanos; aqui vira ordem para os bots)
local function onMark(p: Player, req: any)
	if type(req) ~= "table" or req.kind ~= "map" or typeof(req.pos) ~= "Vector3" then
		return
	end
	local pos = req.pos :: Vector3
	if pos.X ~= pos.X or pos.Z ~= pos.Z then
		return
	end
	local now = os.clock()
	if now - (lastMark[p] or 0) < 1 then
		return
	end
	lastMark[p] = now
	local sid, faction = p:GetAttribute("SquadId"), p:GetAttribute("Faction")
	if type(sid) ~= "string" or type(faction) ~= "string" or not rootIfAlive(p) then
		return
	end
	local s = squadOf(faction, sid)
	local leader = p:GetAttribute("Role") == "squad_leader" or (s ~= nil and #(s.members :: { number }) == 1)
	local b = MapConfig.Bounds
	if not leader or pos.X < b.minX or pos.X > b.maxX or pos.Z < b.minZ or pos.Z > b.maxZ then
		return
	end
	marks[sid] = { pos = Vector3.new(pos.X, 0, pos.Z), at = now, reached = false }
end

-- quem sai primeiro do squad de bots: o que ainda não nasceu, depois quem não está em combate
local function freeOrder(a: Bot, b: Bot): boolean
	local am, bm = a.model == nil, b.model == nil
	if am ~= bm then
		return am
	end
	if a.inCombat ~= b.inCombat then
		return not a.inCombat
	end
	return a.id < b.id
end

local function tickFill(bots: { Bot })
	for _, faction in { "US", "VC" } do
		local st = TeamService.squads[faction]
		local list: { BotBrain.FillSquad } = {}
		local byId: { [string]: BotBrain.FillSquad } = {}
		for _, s in (if st then st.squads else {}) :: { any } do
			local def = Roles.units[faction][s.unit]
			if def and not def.heavy then
				local e: BotBrain.FillSquad = { id = s.id, humans = #s.members, size = def.size, bots = {} }
				table.insert(list, e)
				byId[s.id] = e
			end
		end
		local free: { Bot } = {}
		local byBot: { [number]: Bot } = {}
		for _, b in bots do
			if b.faction == faction and not b.removed then
				byBot[b.id] = b
				local sid = b.playerSquad
				if sid then
					local e = byId[sid]
					if not e or b.crew or not enabled then
						BotEscolta.setSquad(b, nil) -- o squad sumiu, virou tripulação ou o enchimento desligou
					else
						table.insert(e.bots, b.id)
					end
				elseif not b.crew and not b.tunnel then
					table.insert(free, b)
				end
			end
		end
		if enabled then
			table.sort(free, freeOrder)
			local ids: { number } = {}
			for _, b in free do
				table.insert(ids, b.id)
			end
			local add, remove = BotBrain.fillPlan(list, ids)
			for _, id in remove do
				local b = byBot[id]
				if b then
					BotEscolta.setSquad(b, nil)
				end
			end
			for _, a in add do
				local b = byBot[a.bot]
				if b then
					BotEscolta.setSquad(b, a.squad)
				end
			end
		end
	end
end

-- lugar do bot entre os bots do mesmo squad de jogador (1, 2, ...)
local function slotIndex(bot: Bot): number
	local k = 0
	for _, b in getBots() do
		if b.playerSquad == bot.playerSquad and b.faction == bot.faction then
			k += 1
			if b == bot then
				return k
			end
		end
	end
	return 1
end

-- Fora de combate, bot de squad de jogador: devolve true se cuidou do movimento.
function BotEscolta.calm(bot: Bot, model: Model, root: BasePart, now: number): boolean
	local sid = bot.playerSquad
	if not sid then
		return false
	end
	local anchor = BotEscolta.anchor(bot)
	local pos = root.Position
	local mk: Mark? = marks[sid]
	if mk then
		local leaderToMark = if anchor then flat(anchor.Position, mk.pos) * M else 0
		if not BotBrain.markActive(now - mk.at, mk.reached, leaderToMark) then
			marks[sid] = nil
			mk = nil
		end
	end
	local idx = slotIndex(bot)
	local hooks = BotTypes.hooks
	if mk then
		-- a marca do líder: vai até ela; lá, cada um num lugar em volta (6 m), olhando para fora
		local a = idx * 2.399
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local spot = mk.pos + out * (6 / M)
		spot = Vector3.new(spot.X, pos.Y, spot.Z)
		if flat(pos, mk.pos) * M <= F.markReachM then
			mk.reached = true
		end
		local d = flat(pos, spot) * M
		hooks.setStance(model, "stand")
		if d <= 2 then
			BotLocomotion.stop(bot, spot + out * (20 / M))
		elseif d > 60 then
			BotLocomotion.goFar(bot, spot, "jog", { tolerance = 3 / M })
		else
			BotLocomotion.go(bot, spot, if d > 20 then "jog" else "walk", { tolerance = 1.5 / M })
		end
		return true
	end
	if not anchor then
		return false -- nenhum humano do squad em campo: vai para o objetivo como qualquer bot
	end
	local look = anchor.CFrame.LookVector
	local dx, dz = BotBrain.escortSlot(idx, look.X, look.Z)
	local slot = anchor.Position + Vector3.new(dx / M, 0, dz / M)
	slot = Vector3.new(slot.X, pos.Y, slot.Z)
	local toLeader = flat(pos, anchor.Position) * M
	local toSlot = flat(pos, slot) * M
	hooks.setStance(model, "stand")
	if BotBrain.escortHold(toLeader, toSlot) then
		-- no lugar: olha para fora do leque
		BotLocomotion.stop(bot, pos + Vector3.new(dx, 0, dz).Unit * (20 / M))
		return true
	end
	local gait = BotBrain.gait({
		stance = "stand",
		distM = toSlot,
		urgent = false,
		cautious = toLeader <= F.maxM,
		aiming = false,
		behindM = math.max(toLeader - F.maxM, 0),
		legImpaired = model:GetAttribute("LegImpaired") == true,
	})
	if toSlot > 60 then
		BotLocomotion.goFar(bot, slot, gait, { tolerance = 3 / M })
	else
		BotLocomotion.go(bot, slot, gait, { tolerance = 1.5 / M })
	end
	return true
end

-- Studio: "squad" mostra os squads com bots; "squad0" desliga o enchimento; "squad1" liga
function BotEscolta.dev(v: string)
	if v == "squad0" or v == "squad1" then
		enabled = v == "squad1"
		tickFill(getBots())
	end
	for _, faction in { "US", "VC" } do
		local st = TeamService.squads[faction]
		for _, s in (if st then st.squads else {}) :: { any } do
			local names = {}
			for _, b in getBots() do
				if b.playerSquad == s.id and b.model then
					table.insert(names, tostring((b.model :: Model):GetAttribute("BotName")))
				end
			end
			-- uma linha só por print: o extrator de textos de tela (tools/i18n) pula linhas com print
			local mark = marks[s.id] ~= nil
			print("[VT65 TESTE] squad (humanos, bots, marca)", s.id, #s.members, table.concat(names, ","), mark)
		end
	end
	print(string.format("[VT65 TESTE] enchimento de squads %s", if enabled then "ligado" else "desligado"))
end

function BotEscolta.start(get: () -> { Bot })
	getBots = get
	Net.event("Squad_Mark").OnServerEvent:Connect(onMark)
	Players.PlayerRemoving:Connect(function(p)
		lastMark[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(F.everyS)
			local ok, err = pcall(function(): any
				tickFill(getBots())
				return nil
			end)
			if not ok then
				warn("[VT65] bots: squad de jogador falhou:", err)
			end
		end
	end)
end

return BotEscolta
