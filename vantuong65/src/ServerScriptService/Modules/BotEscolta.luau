--!strict
-- Bots no squad do jogador (decisão do dono, 2026-11-12: "os bots completam o squad do jogador quando
-- há pouca gente"). Regras e números em BotBrain.FILL (fillPlan, markActive).
--   - a cada 2 s: squad de humano de unidade leve (infantaria, recon; os de veículo e morteiro ficam de
--     fora) com menos de 4 membros recebe bots do mesmo lado até 4, sem passar do tamanho do squad;
--     entra ou sai um bot por squad por vez. São os bots que já existem (BotFill): o bot sai do squad
--     de bots (BotSquads) e volta para um deles quando é liberado;
--   - no modelo do bot: SquadId e BotName (o nascer no companheiro do SpawnService lê os dois);
--   - D-107 (pedido do dono, 2026-11-13: "bots não precisam seguir o líder"): não seguem mais o líder
--     humano. Os bots do squad de jogador formam um squad de bots próprio (BotSquads, campo `player`)
--     que vai ao objetivo e luta como os outros, e nascem como os outros (perto do objetivo do squad);
--   - a marca do líder na carta (Squad_Mark de tipo "map", de quem é líder ou o único humano do squad,
--     como no FieldService) continua valendo como ordem: fora de combate, vão até ela e ficam em
--     volta; ela vale 2 min e, depois de chegar, 45 s (BotBrain.markActive). O líder pode sair dali.
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

type Mark = { pos: Vector3, at: number, reachedAt: number? }
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

-- Põe (sid) ou tira (nil) o bot de um squad de jogador. D-107: com sid, entra no squad de bots próprio
-- daquele squad de jogador; sem, volta a um squad de bots (tripulante fica fora dos dois).
function BotEscolta.setSquad(bot: Bot, sid: string?)
	if bot.playerSquad == sid then
		return
	end
	bot.playerSquad = sid
	local m = bot.model
	if m then
		m:SetAttribute("SquadId", sid)
	end
	if bot.removed or bot.crew then
		BotSquads.remove(bot)
	else
		BotSquads.assign(bot, sid)
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
	marks[sid] = { pos = Vector3.new(pos.X, 0, pos.Z), at = now, reachedAt = nil }
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
	-- marcas de squads que sumiram
	for sid in marks do
		local faction = string.match(sid, "^(%a+):")
		if faction and not squadOf(faction, sid) then
			marks[sid] = nil
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

-- Fora de combate, bot de squad de jogador com a marca do líder valendo: vai até ela e fica em volta.
-- Devolve true se cuidou do movimento; sem marca, o BotService o leva com o squad de bots dele.
function BotEscolta.calm(bot: Bot, model: Model, root: BasePart, now: number): boolean
	local sid = bot.playerSquad
	local mk: Mark? = if sid then marks[sid] else nil
	if not (sid and mk) then
		return false
	end
	local reachedAt = mk.reachedAt
	if not BotBrain.markActive(now - mk.at, if reachedAt then now - reachedAt else nil) then
		marks[sid] = nil
		return false
	end
	-- cada um num lugar em volta da marca (6 m), olhando para fora
	local pos = root.Position
	local a = slotIndex(bot) * 2.399
	local out = Vector3.new(math.cos(a), 0, math.sin(a))
	local spot = mk.pos + out * (6 / M)
	spot = Vector3.new(spot.X, pos.Y, spot.Z)
	if flat(pos, mk.pos) * M <= F.markReachM and not reachedAt then
		mk.reachedAt = now
	end
	local d = flat(pos, spot) * M
	local hooks = BotTypes.hooks
	if d <= 2 then
		hooks.setStance(model, "crouch")
		BotLocomotion.stop(bot, spot + out * (20 / M))
	else
		hooks.setStance(model, "stand")
		if d > 60 then
			BotLocomotion.goFar(bot, spot, "jog", { tolerance = 3 / M })
		else
			BotLocomotion.go(bot, spot, if d > 20 then "jog" else "walk", { tolerance = 1.5 / M })
		end
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
