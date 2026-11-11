--!strict
-- Perfil persistente do jogador (DataStore), com versão de esquema e repetição em falha (Parte 7).
-- Recibos de compra, o resgate da recompensa diária e a compra de equipamento com créditos são
-- gravados de forma ATÔMICA (UpdateAsync) para nunca entregar duas vezes, nem em dois servidores ao
-- mesmo tempo. XP, créditos e renasceres guardados (v3) são gravados como "delta" da sessão
-- (ProfileSchema.applySession): o que esta sessão mudou soma ao que estiver salvo.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local ProfileSchema = require(script.Parent.ProfileSchema)

local MAX_RECEIPTS = 200

export type Profile = ProfileSchema.Profile

local PlayerData = {}
local profiles: { [Player]: Profile } = {}
-- XP, créditos e renasceres guardados já gravados (base do "delta" da sessão, ProfileSchema)
local bases: { [Player]: ProfileSchema.Synced } = {}
local loadedSignal = Instance.new("BindableEvent")
PlayerData.Loaded = loadedSignal.Event

local store: DataStore? = nil
local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore("VT65_Player_v1")
	end)
	if ok then
		store = s
	end
	return store
end

local function default(): Profile
	return ProfileSchema.default()
end

PlayerData.migrate = ProfileSchema.migrate

-- mantém só os MAX_RECEIPTS recibos mais recentes
local function prune(p: Profile)
	local list = {}
	for id, t in p.purchases do
		table.insert(list, { id = id, t = t })
	end
	if #list <= MAX_RECEIPTS then
		return
	end
	table.sort(list, function(a, b)
		return a.t > b.t
	end)
	for i = MAX_RECEIPTS + 1, #list do
		p.purchases[list[i].id] = nil
	end
end

local function retry<T>(fn: () -> T, tries: number?): (boolean, T?)
	local n = tries or 4
	for i = 1, n do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		warn(string.format("[PlayerData] tentativa %d falhou: %s", i, tostring(res)))
		task.wait(2 ^ (i - 1))
	end
	return false, nil
end

local function key(userId: number): string
	return "u_" .. userId
end

-- progresso que só cresce: a recompensa mais nova, a união dos cosméticos ganhos e a das skins
-- compradas (dst <- src)
local function mergeProgress(dst: Profile, src: Profile)
	dst.daily = ProfileSchema.newerDaily(dst.daily, src.daily)
	for id in src.earned do
		dst.earned[id] = true
	end
	ProfileSchema.mergeSkins(dst.skins, src.skins)
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.load(player: Player): Profile
	local ds = getStore()
	local profile = default()
	if ds then
		local ok, raw = retry(function()
			return (ds :: DataStore):GetAsync(key(player.UserId))
		end)
		if ok then
			profile = PlayerData.migrate(raw)
		else
			warn("[PlayerData] perfil não carregou; sessão sem salvar para não sobrescrever dados")
			player:SetAttribute("DataReadOnly", true)
		end
	end
	profiles[player] = profile
	bases[player] = ProfileSchema.synced(profile)
	loadedSignal:Fire(player, profile)
	return profile
end

-- Algo já foi gravado direto no DataStore (recibo atômico): a memória e a base andam juntas, e o
-- delta da sessão não muda (D-72).
function PlayerData.bump(player: Player, field: string, amount: number)
	local p, b = profiles[player], bases[player]
	if not (p and b) then
		return
	end
	if field == "respawnCredits" then
		p.respawnCredits += amount
		b.respawnCredits += amount
	elseif field == "credits" then
		p.credits += amount
		b.credits += amount
	end
end

function PlayerData.save(player: Player): boolean
	local ds = getStore()
	local p = profiles[player]
	if not (ds and p) or player:GetAttribute("DataReadOnly") then
		return false
	end
	local base = bases[player] or ProfileSchema.synced(p)
	-- o que a sessão tinha no instante da gravação (o que entrar depois fica para a próxima)
	local snap = ProfileSchema.synced(p)
	local view = table.clone(p)
	view.xp, view.credits, view.respawnCredits = snap.xp, snap.credits, snap.respawnCredits
	local wrote: ProfileSchema.Synced? = nil
	local ok = retry(function()
		return (ds :: DataStore):UpdateAsync(key(player.UserId), function(old)
			local o = PlayerData.migrate(old)
			-- união dos recibos: outro servidor pode ter gravado um recibo entre o load e o save
			for id, t in o.purchases do
				if p.purchases[id] == nil then
					p.purchases[id] = t
				end
			end
			p.tips = math.max(p.tips, o.tips)
			mergeProgress(p, o) -- outro servidor pode ter carimbado o dia depois do load
			prune(p)
			-- progressão (v3): gravado + o que a sessão mudou (nunca apaga o ganho de outro servidor)
			local rec = table.clone(p)
			wrote = ProfileSchema.applySession(rec, o, view, base)
			return rec
		end)
	end)
	local w = wrote
	if ok and w then
		bases[player] = ProfileSchema.afterWrite(p, snap, w)
	end
	return ok
end

-- Aplica um recibo uma única vez. Devolve true se entregue agora ou antes, e se foi agora.
function PlayerData.applyReceipt(player: Player, purchaseId: string, mutate: (Profile) -> ()): (boolean, boolean)
	local ds = getStore()
	if not ds then
		return false, false
	end
	local ok, newData = retry(function()
		return (ds :: DataStore):UpdateAsync(key(player.UserId), function(old)
			local p = PlayerData.migrate(old)
			if p.purchases[purchaseId] then
				return nil -- já entregue: não altera nada
			end
			mutate(p)
			p.purchases[purchaseId] = os.time()
			prune(p)
			return p
		end)
	end)
	if not ok then
		return false, false
	end
	if newData ~= nil then
		local mem = profiles[player]
		local fresh = PlayerData.migrate(newData)
		if mem then
			mem.tips = fresh.tips
			mem.purchases = fresh.purchases
			-- skin comprada em Robux (Developer Product): a memória ganha a posse já gravada
			ProfileSchema.mergeSkins(mem.skins, fresh.skins)
		end
	end
	return true, newData ~= nil
end

local function applyDaily(p: Profile, r: Commerce.DailyResult)
	p.daily = { run = r.state.run, lastDay = r.state.lastDay, total = r.state.total }
	for _, id in r.items do
		p.earned[id] = true
	end
end

-- Resgate da recompensa diária. `today` é o dia UTC do relógio do servidor (Commerce.dayIndex).
-- Devolve o status ("ok" | "already" | "clock" | "loading" | "readonly" | "error") e o resultado.
-- O resgate vai direto para o DataStore (UpdateAsync, como os recibos); a memória só copia o que
-- ficou gravado. Sem DataStore (perfil não carregou), só no Studio vale em memória, para testar.
function PlayerData.claimDaily(player: Player, today: number): (string, Commerce.DailyResult?)
	local mem = profiles[player]
	if not mem then
		return "loading", nil
	end
	local ds = getStore()
	if not ds or player:GetAttribute("DataReadOnly") then
		if not RunService:IsStudio() then
			return "readonly", nil
		end
		local r = Commerce.dailyClaim(mem.daily, today, mem.earned)
		if r.ok then
			applyDaily(mem, r)
			return "ok", r
		end
		return r.reason or "already", r
	end
	local result: Commerce.DailyResult? = nil
	local stored: Profile? = nil
	local ok = retry(function()
		return (ds :: DataStore):UpdateAsync(key(player.UserId), function(old)
			local p = PlayerData.migrate(old)
			mergeProgress(p, mem) -- a memória nunca fica atrás do salvo, mas não custa
			local r = Commerce.dailyClaim(p.daily, today, p.earned)
			result, stored = r, p
			if not r.ok then
				return nil -- já carimbado hoje (aqui ou noutro servidor): não grava nada
			end
			applyDaily(p, r)
			prune(p)
			return p
		end)
	end, 3)
	if not ok then
		return "error", nil
	end
	local s = stored
	if s then
		mergeProgress(mem, s)
	end
	local r = result
	if r and r.ok then
		return "ok", r
	end
	return (r and r.reason) or "error", r
end

function PlayerData.start()
	local function added(player: Player)
		task.spawn(PlayerData.load, player)
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		PlayerData.save(player)
		profiles[player] = nil
		bases[player] = nil
	end)
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		for _, player in Players:GetPlayers() do
			PlayerData.save(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(300) -- autosave a cada 5 min
			for _, player in Players:GetPlayers() do
				PlayerData.save(player)
			end
		end
	end)
end

return PlayerData
