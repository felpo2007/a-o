--!strict
-- Campanha no servidor (plano de diversão, volta diária e Robux, 2026-11-12; seções 1 a 5b e as
-- ordens do comandante da 6). Junta tudo o que faz o jogador voltar e mostra num estado só, o
-- Campanha_State (formato no contrato da campanha; cliente: Controllers/CampanhaCliente):
--   - ordens do dia e da semana (Shared/Missoes), com uma troca grátis por dia;
--   - Passe de Campanha (Shared/Temporada): estrelas de partidas, missões, selo diário e ordens;
--     trilha Veterano pelo Game Pass da temporada, com o que já passou entregue na compra;
--   - mercado do dia (Shared/Mercado), igual em todos os servidores pela data UTC;
--   - reforços (Shared/Reforcos): XP/créditos dobrados com hora de fim no perfil e o XP dobrado de
--     fim de semana; 10% a mais de XP com amigo no squad; Veterano: 10% a mais de créditos;
--   - medalhas e cartão do jogador (Shared/Medalhas); placar semanal de XP (OrderedDataStore) com
--     o emblema do top 10;
--   - convite de amigo: os dois ganham créditos quando o convidado joga a 1ª partida até o fim;
--   - Pacote de Recruta (Game Pass, compra única) e vantagens compradas (Shared/Vantagens): o
--     servidor grava os atributos Vant_<chave> no jogador; quem aplica o efeito é o dono de cada
--     sistema (Vantagens.mult / Vantagens.extra);
--   - ordens do comandante: o squad recebe uma ordem curta ligada ao objetivo do time (tomar ou
--     segurar um ponto forte); cumprida, bônus para todos do squad.
-- Eventos de jogo chegam pelo CampanhaEventos (ProgressionService e DailyRewardService). O perfil
-- (ProfileSchema v4, campo `campaign`) é a fonte de tudo; entre servidores, máximo e união.
-- Studio (barra de comando do SERVIDOR): workspace:SetAttribute("VT65DevCampanha", x), x =
-- "estrelas" (+1 nível), "missoes" (conclui todas), "reforco" (XP dobrado 1 h), "medalhas" (todas),
-- "ordem" (ordens novas agora), "veterano" (trilha Veterano liberada nesta sessão).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Calendario = require(ReplicatedStorage.Shared.Calendario)
local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Front = require(ReplicatedStorage.Shared.Front)
local Medalhas = require(ReplicatedStorage.Shared.Medalhas)
local Mercado = require(ReplicatedStorage.Shared.Mercado)
local Missoes = require(ReplicatedStorage.Shared.Missoes)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Reforcos = require(ReplicatedStorage.Shared.Reforcos)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Temporada = require(ReplicatedStorage.Shared.Temporada)
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local CampanhaEventos = require(script.Parent.CampanhaEventos)
local CommerceService = require(script.Parent.CommerceService)
local MatchService = require(script.Parent.MatchService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressionService = require(script.Parent.ProgressionService)
local TeamService = require(script.Parent.TeamService)

local CampanhaService = {}

local REFERRAL_CREDITS = 300 -- convite: cada um dos dois
local REFERRAL_MAX = 10 -- convites pagos por jogador (contra abuso)
local ORDER_BONUS = { xp = 150, cr = 20 }
local ORDER_ATTACK_S = 360
local ORDER_DEFEND_S = 180
local RECRUIT_OFFER_MATCHES = 3
local RECRUIT_CREDITS = 1000
local RECRUIT_BOOST_S = 3 * 86400
local RECRUIT_SKINS = { "skin_us_duck", "skin_vc_black", "skin_m14_tape", "skin_type56_tape" }

-- ===== estado de sessão =====
type Rt = {
	lastSend: number,
	queued: boolean,
	dueAt: number,
	result: { [string]: any }?,
	friendSquad: boolean,
	vetDev: boolean,
	lastAction: number,
}
local rt: { [Player]: Rt } = {}

local function rtOf(p: Player): Rt
	local r = rt[p]
	if not r then
		r = {
			lastSend = 0,
			queued = false,
			dueAt = 0,
			result = nil,
			friendSquad = false,
			vetDev = false,
			lastAction = 0,
		}
		rt[p] = r
	end
	return r
end

local function passes(p: Player): { [string]: boolean }
	return (CommerceService.ownership(p).passes :: any) or {}
end

local function veteran(p: Player): boolean
	return passes(p).PASS_SEASON_S1 == true or rtOf(p).vetDev
end

local function factionOf(p: Player): string?
	local f = p:GetAttribute("Faction")
	return if f == "US" or f == "VC" then f else nil
end

-- ===== períodos (dia e semana UTC) =====
local function ensurePeriods(p: Player, c: any, now: number)
	local day, week = Calendario.dayIndex(now), Calendario.weekIndex(now)
	if c.missions.day ~= day then
		c.missions.day = day
		c.missions.daily = Missoes.fresh("daily", day, p.UserId)
	end
	if c.missions.week ~= week then
		c.missions.week = week
		c.missions.weekly = Missoes.fresh("weekly", week, p.UserId)
	end
	if c.board.week ~= week then
		c.board.week = week
		c.board.xp = 0
	end
end

-- ===== placar da semana (OrderedDataStore por semana) =====
local board = { week = -1, top = {} :: { { name: string, xp: number } }, names = {} :: { [number]: string } }
local function boardStore(week: number): OrderedDataStore?
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore(string.format("VT65_Placar_%d", week))
	end)
	return if ok then s else nil
end

local function nameOf(userId: number): string
	local n = board.names[userId]
	if n then
		return n
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		board.names[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local out = if ok and type(name) == "string" then name else "?"
	board.names[userId] = out
	return out
end

-- ===== estado (Campanha_State) =====
local orders: { [string]: any } = {} -- squad id -> ordem

local function orderFor(p: Player): { [string]: any }?
	local sid = p:GetAttribute("SquadId")
	local o = if type(sid) == "string" then orders[sid] else nil
	if not o then
		return nil
	end
	return { text = o.text, arg = o.arg, sector = o.sector, untilT = o.untilT, done = o.done, kind = o.kind }
end

function CampanhaService.state(p: Player): { [string]: any }?
	local prof = PlayerData.get(p)
	if not prof then
		return nil
	end
	local c = prof.campaign
	local now = os.time()
	ensurePeriods(p, c, now)
	local ps = passes(p)
	local vet = veteran(p)
	local r = rtOf(p)
	-- missões
	local daily, weekly = {}, {}
	for _, m in c.missions.daily do
		local v = Missoes.view(m)
		if v then
			table.insert(daily, v)
		end
	end
	for _, m in c.missions.weekly do
		local v = Missoes.view(m)
		if v then
			table.insert(weekly, v)
		end
	end
	local today = Calendario.dayIndex(now)
	local used = if c.missions.rerollDay == today then c.missions.rerolls else 0
	-- passe
	local s = Temporada.SEASON
	local lvl, inLvl = Temporada.levelOf(c.season.stars)
	-- reforços
	local xm, cm = Reforcos.mult(c.boosts, now, vet, r.friendSquad)
	local wk, wkEnd = Reforcos.weekend(now)
	-- mercado (com a posse de cada item)
	local items = {}
	for _, it in Mercado.rotation(today) do
		local sk = Skins.get(it.id)
		it.owned = sk ~= nil and (Skins.owns(sk, prof.skins.owned, ps))
		table.insert(items, it)
	end
	local featured = Mercado.featured(Calendario.weekIndex(now))
	if featured then
		local sk = Skins.get(featured.id)
		featured.owned = sk ~= nil and (Skins.owns(sk, prof.skins.owned, ps))
	end
	-- medalhas
	local medals = {}
	for id, t in c.medals do
		table.insert(medals, { id = id, at = t })
	end
	table.sort(medals, function(a, b)
		return a.at < b.at
	end)
	local recruitOwned = ps.PASS_RECRUIT == true or c.recruit.granted
	local matches = c.stats.matches or 0
	return {
		now = now,
		missions = {
			daily = daily,
			weekly = weekly,
			rerollLeft = math.max(0, Missoes.REROLLS_PER_DAY - used),
			dailyResetAt = Calendario.nextDay(now),
			weeklyResetAt = Calendario.nextWeek(now),
			notify = c.notify,
		},
		season = {
			id = s.id,
			name = s.name,
			level = lvl,
			stars = c.season.stars,
			starsInLevel = inLvl,
			starsPerLevel = s.starsPerLevel,
			maxLevel = s.maxLevel,
			veteran = vet,
			endsAt = s.endsAt,
			active = Temporada.active(now),
			claimed = { free = c.season.claimedFree, vet = c.season.claimedVet },
			free = Temporada.FREE,
			vet = Temporada.VET,
		},
		boosts = {
			xpUntil = c.boosts.xpUntil,
			crUntil = c.boosts.crUntil,
			weekend = wk,
			weekendEndsAt = wkEnd,
			xpMult = xm,
			crMult = cm,
		},
		market = {
			day = Calendario.dateString(today),
			items = items,
			weekly = featured,
			resetsAt = Calendario.nextDay(now),
		},
		medals = medals,
		card = { emblem = c.card.emblem, title = c.card.title, medals = c.card.medals },
		owned = c.owned, -- emblemas, títulos, cartões de abate, gestos, música (+ os de todo mundo)
		perks = Vantagens.compute(ps),
		recruit = {
			owned = recruitOwned,
			offer = not recruitOwned and matches < RECRUIT_OFFER_MATCHES and c.recruit.shown < RECRUIT_OFFER_MATCHES,
			matches = matches,
		},
		social = { friendInSquad = r.friendSquad, xpBonus = if r.friendSquad then Reforcos.FRIEND_XP else 0 },
		order = orderFor(p),
		board = {
			week = board.week,
			top = board.top,
			me = c.board.xp,
		},
		result = r.result,
	}
end

-- Envia o estado: no máximo 2 por segundo. `soon` = evento de jogo (abate, tempo...): junta tudo o
-- que chegar em até 2 s num envio só. Um pedido do jogador passa na frente (0,5 s).
local function send(p: Player, soon: boolean?)
	local r = rtOf(p)
	local due = r.lastSend + (if soon then 2 else 0.5)
	if r.queued and (soon or r.dueAt <= due) then
		return -- já vai um envio antes disso
	end
	r.queued = true
	r.dueAt = due
	local my = due
	task.delay(math.max(0, due - os.clock()), function()
		if r.dueAt ~= my then
			return -- outro envio mais cedo tomou o lugar
		end
		r.queued = false
		if not p.Parent then
			return
		end
		r.lastSend = os.clock()
		local st = CampanhaService.state(p)
		r.result = nil
		if st then
			Net.event("Campanha_State"):FireClient(p, st)
		end
	end)
end
CampanhaService.send = send

local function setResult(p: Player, op: string, ok: boolean, msg: string?)
	rtOf(p).result = { op = op, ok = ok, msg = msg }
end

-- ===== estrelas, medalhas e recompensas =====
local function addStars(p: Player, c: any, n: number)
	if n <= 0 or not Temporada.active(os.time()) then
		return
	end
	c.season.stars = math.min(c.season.stars + n, 100000)
end

local function checkMedals(p: Player, c: any)
	local now = os.time()
	for _, id in Medalhas.earned(c.stats, c.medals) do
		c.medals[id] = now
		local m = Medalhas.get(id)
		if m then
			setResult(p, "medal", true, string.format("Medalha: %s", m.name))
		end
	end
end

local function bump(c: any, stat: string, n: number?)
	c.stats[stat] = (c.stats[stat] or 0) + (n or 1)
end

-- entrega um nível do passe
local function giveReward(p: Player, prof: any, rw: Temporada.Reward)
	local c = prof.campaign
	if rw.kind == "credits" then
		ProgressionService.bonus(p, 0, rw.amount or 0, "Passe de Campanha")
	elseif rw.kind == "camo" or rw.kind == "uniform" then
		local ids = rw.ids
		if ids then
			for _, id in ids do
				if Skins.get(id) then
					prof.skins.owned[id] = true
				end
			end
		end
		ProgressionService.push(p)
	elseif rw.kind == "boost" then
		Reforcos.extend(c.boosts, rw.id or "xp", rw.amount or 0, os.time())
	elseif rw.id then
		c.owned[rw.id] = true -- emblema, título, cartão de abate, gesto, música
	end
end

local function claimLevel(p: Player, prof: any, track: string, level: number): boolean
	local c = prof.campaign
	local claimed = if track == "vet" then c.season.claimedVet else c.season.claimedFree
	if not Temporada.claimable(track, level, c.season.stars, veteran(p), claimed) then
		return false
	end
	local rw = Temporada.reward(track, level)
	if not rw then
		return false
	end
	claimed[tostring(level)] = true
	giveReward(p, prof, rw)
	return true
end

local function claimMission(p: Player, prof: any, id: string): boolean
	local c = prof.campaign
	for _, list in { c.missions.daily, c.missions.weekly } do
		for _, r in list do
			if r.id == id and Missoes.claimable(r) then
				local d = Missoes.def(id)
				if not d then
					return false
				end
				r.claimed = true
				ProgressionService.bonus(p, d.reward.xp, d.reward.cr, "Missão cumprida")
				addStars(p, c, d.reward.stars)
				return true
			end
		end
	end
	return false
end

-- ===== passes: Veterano, Recruta e vantagens =====
local function applyPasses(p: Player)
	local prof = PlayerData.get(p)
	if not prof then
		return
	end
	local c = prof.campaign
	local ps = passes(p)
	-- vantagens: atributos no jogador (quem aplica o efeito lê Vantagens.mult / Vantagens.extra)
	local perks = Vantagens.compute(ps)
	for key in Vantagens.KEYS do
		p:SetAttribute(Vantagens.attr(key), perks[key])
	end
	-- Veterano comprado agora (ou no meio da temporada): entrega o que já passou na trilha Veterano
	if veteran(p) and not c.season.vetSeen then
		-- o gancho de Studio ("veterano") entrega sem marcar: a compra de verdade ainda entrega depois
		c.season.vetSeen = not rtOf(p).vetDev
		local n = 0
		for _, lvl in Temporada.owedOnPurchase(c.season.stars, c.season.claimedVet) do
			if claimLevel(p, prof, "vet", lvl) then
				n += 1
			end
		end
		setResult(p, "veteran", true, if n > 0 then string.format("Veterano: %d níveis entregues", n) else nil)
	end
	-- Pacote de Recruta: entregue uma vez
	if ps.PASS_RECRUIT == true and not c.recruit.granted then
		c.recruit.granted = true
		for _, id in RECRUIT_SKINS do
			if Skins.get(id) then
				prof.skins.owned[id] = true
			end
		end
		Reforcos.extend(c.boosts, "xp", RECRUIT_BOOST_S, os.time())
		ProgressionService.bonus(p, 0, RECRUIT_CREDITS, "Pacote de Recruta")
		setResult(p, "recruit", true, "Pacote de Recruta recebido")
		task.spawn(PlayerData.save, p)
	end
	send(p)
end

-- ===== convite =====
local referralStore: DataStore? = nil
local function referrals(): DataStore?
	if referralStore then
		return referralStore
	end
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore("VT65_Convites_v1")
	end)
	if ok then
		referralStore = s
	end
	return referralStore
end

local function payReferrer(referrerId: number)
	local ref = Players:GetPlayerByUserId(referrerId)
	local rp = ref and PlayerData.get(ref)
	if ref and rp then
		if rp.campaign.social.referralsPaid < REFERRAL_MAX then
			rp.campaign.social.referralsPaid += 1
			ProgressionService.bonus(ref, 0, REFERRAL_CREDITS, "Amigo convidado jogou")
			send(ref)
		end
		return
	end
	-- fora deste servidor: fica pendente e é pago quando ele entrar
	local ds = referrals()
	if ds then
		pcall(function()
			(ds :: DataStore):UpdateAsync(string.format("u_%d", referrerId), function(old)
				return math.clamp((tonumber(old) or 0) + 1, 0, REFERRAL_MAX)
			end)
		end)
	end
end

local function collectReferrals(p: Player)
	local ds = referrals()
	local prof = PlayerData.get(p)
	if not (ds and prof) or p:GetAttribute("DataReadOnly") then
		return
	end
	local got = 0
	pcall(function()
		(ds :: DataStore):UpdateAsync(string.format("u_%d", p.UserId), function(old)
			got = tonumber(old) or 0
			return if got > 0 then 0 else nil
		end)
	end)
	local room = REFERRAL_MAX - prof.campaign.social.referralsPaid
	local n = math.clamp(got, 0, math.max(room, 0))
	if n > 0 then
		prof.campaign.social.referralsPaid += n
		ProgressionService.bonus(p, 0, REFERRAL_CREDITS * n, "Amigos convidados jogaram")
	end
end

-- ===== eventos de jogo =====
local function onEvent(p: Player, name: string, data: { [string]: any })
	local prof = PlayerData.get(p)
	if not prof then
		return
	end
	local c = prof.campaign
	local now = os.time()
	ensurePeriods(p, c, now)
	local function mission(ev: string, d: { [string]: any })
		local done = Missoes.apply(c.missions.daily, ev, d)
		for _, id in Missoes.apply(c.missions.weekly, ev, d) do
			table.insert(done, id)
		end
		if #done > 0 then
			setResult(p, "mission", true, "Missão cumprida: receba a recompensa")
		end
	end
	if name == "kill" then
		bump(c, "kills")
		mission("kill", data)
	elseif name == "assist" then
		bump(c, "assists")
		mission("assist", data)
	elseif name == "capture" then
		bump(c, "captures")
		mission("capture", data)
	elseif name == "revive" then
		bump(c, "revives")
		mission("revive", data)
	elseif name == "treat" or name == "bandage" then
		mission(name, data)
	elseif name == "was_revived" then
		bump(c, "wasRevived")
	elseif name == "time" then
		mission("time", { seconds = Progression.TIME_EVERY_S })
	elseif name == "sector_time" then
		mission("sector_time", data)
	elseif name == "match_end" then
		local secs = tonumber(data.seconds) or 0
		if secs < Progression.MATCH_MIN_S then
			return -- entrou no fim: não conta como partida jogada
		end
		local result = tostring(data.result)
		bump(c, "matches")
		if result == "win" then
			bump(c, "wins")
			bump(c, if data.faction == "VC" then "winsVC" else "winsUS")
		end
		mission("match_end", data)
		addStars(
			p,
			c,
			Temporada.STARS[if result == "win"
				then "match_win"
				elseif result == "draw" then "match_draw"
				else "match_loss"] or 0
		)
		if rtOf(p).friendSquad then
			bump(c, "friendMatches")
			mission("match_friend", {})
		end
		-- convite: a 1ª partida do convidado paga os dois
		local soc = c.social
		if soc.referredBy > 0 and not soc.referralDone then
			soc.referralDone = true
			ProgressionService.bonus(p, 0, REFERRAL_CREDITS, "Convite aceito")
			payReferrer(soc.referredBy)
		end
	elseif name == "daily_seal" then
		local day = tonumber(data.day) or 1
		addStars(p, c, if day == 3 or day == 7 then Temporada.STARS.daily_seal_rare else Temporada.STARS.daily_seal)
	elseif name == "order" then
		bump(c, "orders")
		addStars(p, c, Temporada.STARS.order)
	end
	checkMedals(p, c)
	send(p, true)
end

-- ===== ordens do comandante =====
local function pointName(sector: number): string
	local sp = MatchService.points[sector]
	return if sp and sp.name then sp.name else string.format("S%d", sector)
end

local function squadPlayers(faction: string, sq: any): { Player }
	local out = {}
	for _, uid in sq.members do
		local m = Players:GetPlayerByUserId(uid)
		if m and m:GetAttribute("SquadId") == sq.id and factionOf(m) == faction then
			table.insert(out, m)
		end
	end
	return out
end

local function tickOrders(force: boolean?)
	local st = MatchService.state :: any
	if MatchService.ended or not st then
		table.clear(orders)
		return
	end
	local now = os.time()
	local seen: { [string]: boolean } = {}
	for faction, sst in TeamService.squads do
		for _, sq in (sst :: any).squads do
			seen[sq.id] = true
			local members = squadPlayers(faction, sq)
			if #members == 0 then
				orders[sq.id] = nil
				continue
			end
			local o = orders[sq.id]
			local changed = false
			if o and not o.done then
				local own = st.owner[o.sector] == faction
				if o.kind == "attack" and own then
					o.done, changed = true, true
				elseif o.kind == "defend" and now >= o.untilT and own then
					o.done, changed = true, true
				elseif now >= o.untilT or (o.kind == "defend" and not own) then
					orders[sq.id], o, changed = nil, nil, true
				end
				if o and o.done then
					o.untilT = now + 20 -- a ordem cumprida fica 20 s na tela
					for _, m in members do
						ProgressionService.bonus(m, ORDER_BONUS.xp, ORDER_BONUS.cr, "Ordem do comandante cumprida")
						CampanhaEventos.fire(m, "order")
					end
				end
			elseif o and o.done and now >= o.untilT then
				orders[sq.id], o, changed = nil, nil, true
			end
			if (not o or force) and (sq.leader ~= nil) then
				local role, sector = Front.objective(st.owner, st.active, faction, nil)
				if role and sector then
					local attack = role == "attack"
					orders[sq.id] = {
						kind = role,
						sector = sector,
						text = if attack then "Tomar %s" else "Segurar %s",
						arg = pointName(sector),
						untilT = now + (if attack then ORDER_ATTACK_S else ORDER_DEFEND_S),
						done = false,
					}
					changed = true
				end
			end
			if changed then
				for _, m in members do
					send(m)
				end
			end
		end
	end
	for id in orders do
		if not seen[id] then
			orders[id] = nil
		end
	end
end

-- ===== pedidos do cliente =====
local function onAction(p: Player, msg: any)
	if type(msg) ~= "table" or type(msg.op) ~= "string" then
		return
	end
	local r = rtOf(p)
	local now = os.clock()
	if now - r.lastAction < 0.25 then
		return -- pedido demais
	end
	r.lastAction = now
	local prof = PlayerData.get(p)
	if not prof then
		setResult(p, msg.op, false, "Perfil ainda carregando")
		send(p)
		return
	end
	local c = prof.campaign
	ensurePeriods(p, c, os.time())
	local op = msg.op
	if op == "reroll" and type(msg.id) == "string" then
		local today = Calendario.dayIndex(os.time())
		if c.missions.rerollDay ~= today then
			c.missions.rerollDay, c.missions.rerolls = today, 0
		end
		local d = Missoes.def(msg.id)
		local ok = false
		if d and c.missions.rerolls < Missoes.REROLLS_PER_DAY then
			local list = if d.scope == "daily" then c.missions.daily else c.missions.weekly
			local key = if d.scope == "daily" then c.missions.day else c.missions.week
			ok = Missoes.reroll(list, msg.id, d.scope, key, p.UserId, c.missions.rerolls + 1)
			if ok then
				c.missions.rerolls += 1
			end
		end
		setResult(p, op, ok, if ok then nil else "Sem troca grátis agora")
	elseif op == "claim_mission" and type(msg.id) == "string" then
		local ok = claimMission(p, prof, msg.id)
		setResult(p, op, ok, if ok then "Recompensa recebida" else nil)
	elseif op == "claim_level" and (msg.track == "free" or msg.track == "vet") and type(msg.level) == "number" then
		local ok = claimLevel(p, prof, msg.track, math.floor(msg.level))
		setResult(p, op, ok, if ok then "Nível recebido" else nil)
	elseif op == "claim_all" then
		local n = 0
		for _, list in { c.missions.daily, c.missions.weekly } do
			for _, m in list do
				if Missoes.claimable(m) and claimMission(p, prof, m.id) then
					n += 1
				end
			end
		end
		for lvl = 1, Temporada.SEASON.maxLevel do
			if claimLevel(p, prof, "free", lvl) then
				n += 1
			end
			if claimLevel(p, prof, "vet", lvl) then
				n += 1
			end
		end
		setResult(p, op, n > 0, if n > 0 then string.format("%d recompensas recebidas", n) else nil)
	elseif op == "market_buy" and type(msg.id) == "string" then
		local now2 = os.time()
		local price = Mercado.priceToday(msg.id, Calendario.dayIndex(now2), Calendario.weekIndex(now2))
		local sk = Skins.get(msg.id)
		local ps = passes(p)
		if not (price and sk) then
			setResult(p, op, false, "Este item não está no mercado hoje")
		elseif Skins.owns(sk, prof.skins.owned, ps) then
			setResult(p, op, false, "Já é seu")
		elseif prof.credits < price then
			setResult(p, op, false, string.format("Faltam %s", Progression.money(price - prof.credits)))
		else
			prof.credits -= price
			prof.skins.owned[msg.id] = true
			ProgressionService.push(p, {
				result = string.format("%s comprada por %s", sk.name, Progression.money(price)),
			})
			setResult(p, op, true, string.format("%s comprada por %s", sk.name, Progression.money(price)))
			task.spawn(PlayerData.save, p)
		end
	elseif op == "card_set" then
		local owned = table.clone(c.owned)
		for k in Medalhas.BASE_OWNED do
			owned[k] = true
		end
		local card = Medalhas.validCard({
			emblem = msg.emblem or c.card.emblem,
			title = msg.title or c.card.title,
			medals = msg.medals or c.card.medals,
		}, owned, c.medals)
		if card then
			c.card = card
		end
		setResult(p, op, card ~= nil, nil)
	elseif op == "invite" then
		setResult(p, op, true, nil) -- o convite em si é do cliente (SocialService)
	elseif op == "notify" and type(msg.on) == "boolean" then
		c.notify = msg.on
		setResult(p, op, true, nil)
	elseif op == "recruit_seen" then
		c.recruit.shown = math.min(c.recruit.shown + 1, 1000)
		setResult(p, op, true, nil)
	else
		return
	end
	checkMedals(p, c)
	send(p)
end

-- ===== laços =====
-- amigo no mesmo squad (IsFriendsWith vai à rede: cache por par)
local friendCache: { [string]: boolean } = {}
local function areFriends(a: Player, b: Player): boolean
	local lo, hi = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local k = string.format("%d:%d", lo, hi)
	local v = friendCache[k]
	if v == nil then
		local ok, res = pcall(function()
			return a:IsFriendsWithAsync(b.UserId)
		end)
		v = ok and res == true
		friendCache[k] = v
	end
	return v :: boolean
end

local function tickFriends()
	for _, p in Players:GetPlayers() do
		local sid = p:GetAttribute("SquadId")
		local f = factionOf(p)
		local has = false
		if type(sid) == "string" and f then
			for _, o in Players:GetPlayers() do
				if o ~= p and o:GetAttribute("SquadId") == sid and factionOf(o) == f and areFriends(p, o) then
					has = true
					break
				end
			end
		end
		local r = rtOf(p)
		if r.friendSquad ~= has then
			r.friendSquad = has
			send(p, true)
		end
	end
end

local SECTOR_TICK = 10
local function tickSectors()
	if MatchService.ended then
		return
	end
	for _, p in Players:GetPlayers() do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		local sector = p:GetAttribute("Sector")
		if hum and hum.Health > 0 and factionOf(p) and type(sector) == "number" then
			onEvent(p, "sector_time", { sector = sector, seconds = SECTOR_TICK })
		end
	end
end

local lastBoardWrite: { [Player]: number } = {}
local function tickBoard()
	local now = os.time()
	local week = Calendario.weekIndex(now)
	local store = boardStore(week)
	if not store then
		return
	end
	for _, p in Players:GetPlayers() do
		local prof = PlayerData.get(p)
		if prof and not p:GetAttribute("DataReadOnly") and prof.campaign.board.week == week then
			local xp = prof.campaign.board.xp
			if xp > 0 and lastBoardWrite[p] ~= xp then
				local ok = pcall(function()
					(store :: OrderedDataStore):SetAsync(tostring(p.UserId), xp)
				end)
				if ok then
					lastBoardWrite[p] = xp
				end
			end
		end
	end
	local top = {}
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, 10)
	end)
	if ok and pages then
		local okP, list = pcall(function()
			return (pages :: DataStorePages):GetCurrentPage()
		end)
		if okP and type(list) == "table" then
			for _, e in list do
				local uid = tonumber(e.key)
				if uid then
					table.insert(top, { name = nameOf(uid), xp = tonumber(e.value) or 0 })
				end
			end
		end
	end
	board.week, board.top = week, top
end

-- emblema do top 10 da semana que passou (uma vez por semana, ao entrar)
local function checkLastWeek(p: Player)
	local prof = PlayerData.get(p)
	if not prof then
		return
	end
	local c = prof.campaign
	local last = Calendario.weekIndex(os.time()) - 1
	if c.board.checked >= last then
		return
	end
	c.board.checked = last
	local store = boardStore(last)
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, 10)
	end)
	if not (ok and pages) then
		return
	end
	local okP, list = pcall(function()
		return (pages :: DataStorePages):GetCurrentPage()
	end)
	if okP and type(list) == "table" then
		for _, e in list do
			if tonumber(e.key) == p.UserId then
				c.owned.emb_top10 = true
				bump(c, "top10")
				checkMedals(p, c)
				setResult(p, "top10", true, "Você ficou entre os 10 melhores da semana")
				send(p)
				break
			end
		end
	end
end

-- ===== início =====
function CampanhaService.start()
	CampanhaEventos.connect(onEvent)

	-- multiplicadores de XP e créditos para o que se ganha jogando
	ProgressionService.mult = function(p: Player): (number, number)
		local prof = PlayerData.get(p)
		if not prof then
			return 1, 1
		end
		return Reforcos.mult(prof.campaign.boosts, os.time(), veteran(p), rtOf(p).friendSquad)
	end
	-- XP da semana (placar)
	ProgressionService.onGain = function(p: Player, xp: number, _cr: number)
		local prof = PlayerData.get(p)
		if prof and xp > 0 then
			local c = prof.campaign
			ensurePeriods(p, c, os.time())
			c.board.xp = math.min(c.board.xp + xp, 1000000000)
		end
	end

	CommerceService.onPasses = applyPasses
	CommerceService.onCampaign = function(p: Player, key: string, now: boolean)
		local cp = Commerce.campaignProduct(key)
		setResult(p, "purchase", true, if now and cp then string.format("%s: recebido", cp.name) else nil)
		send(p)
	end

	PlayerData.Loaded:Connect(function(p: Player)
		local prof = PlayerData.get(p)
		if prof then
			-- convidado: o Roblox diz quem convidou (só conta para quem ainda não jogou)
			local okJ, join = pcall(function()
				return p:GetJoinData()
			end)
			local ref = if okJ and type(join) == "table" then tonumber((join :: any).ReferredByPlayerId) else nil
			local soc = prof.campaign.social
			if
				ref
				and ref > 0
				and ref ~= p.UserId
				and soc.referredBy == 0
				and prof.xp == 0 -- conta nova de verdade (nunca ganhou XP)
			then
				soc.referredBy = ref
			end
		end
		task.spawn(collectReferrals, p)
		task.spawn(checkLastWeek, p)
		applyPasses(p)
	end)
	Players.PlayerRemoving:Connect(function(p)
		rt[p] = nil
		lastBoardWrite[p] = nil
	end)

	Net.func("Campanha_Get").OnServerInvoke = function(p: Player)
		return CampanhaService.state(p)
	end
	Net.event("Campanha_Action").OnServerEvent:Connect(onAction)

	task.spawn(function()
		local t = 0
		while true do
			task.wait(SECTOR_TICK)
			t += SECTOR_TICK
			pcall(tickSectors)
			pcall(tickOrders)
			if t % 20 == 0 then
				pcall(tickFriends)
			end
			if t % 300 == 0 then
				pcall(tickBoard)
			end
		end
	end)
	task.delay(15, function()
		pcall(tickBoard)
	end)

	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevCampanha"):Connect(function()
			local v = workspace:GetAttribute("VT65DevCampanha")
			if type(v) ~= "string" then
				return
			end
			for _, p in Players:GetPlayers() do
				local prof = PlayerData.get(p)
				if prof then
					local c = prof.campaign
					ensurePeriods(p, c, os.time())
					if v == "estrelas" then
						c.season.stars += Temporada.SEASON.starsPerLevel
					elseif v == "missoes" then
						for _, list in { c.missions.daily, c.missions.weekly } do
							for _, m in list do
								local d = Missoes.def(m.id)
								if d then
									m.p = d.goal
								end
							end
						end
					elseif v == "reforco" then
						Reforcos.extend(c.boosts, "xp", 3600, os.time())
					elseif v == "medalhas" then
						for _, m in Medalhas.LIST do
							c.medals[m.id] = os.time()
						end
					elseif v == "veterano" then
						rtOf(p).vetDev = true
						applyPasses(p)
					end
					send(p)
				end
			end
			if v == "ordem" then
				pcall(tickOrders, true)
			end
			task.defer(function()
				workspace:SetAttribute("VT65DevCampanha", nil)
			end)
		end)
	end
end

return CampanhaService
