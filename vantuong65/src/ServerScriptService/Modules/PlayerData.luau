--!strict
-- Perfil persistente do jogador (DataStore), com versão de esquema e repetição em falha (Parte 7).
-- Recibos de compra são gravados de forma ATÔMICA (UpdateAsync) para nunca entregar duas vezes.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProfileSchema = require(script.Parent.ProfileSchema)

local MAX_RECEIPTS = 200

export type Profile = ProfileSchema.Profile

local PlayerData = {}
local profiles: { [Player]: Profile } = {}
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
	loadedSignal:Fire(player, profile)
	return profile
end

function PlayerData.save(player: Player): boolean
	local ds = getStore()
	local p = profiles[player]
	if not (ds and p) or player:GetAttribute("DataReadOnly") then
		return false
	end
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
			prune(p)
			return p
		end)
	end)
	return ok
end

-- Aplica um recibo uma única vez. Devolve true se entregue agora ou antes.
function PlayerData.applyReceipt(player: Player, purchaseId: string, mutate: (Profile) -> ()): boolean
	local ds = getStore()
	if not ds then
		return false
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
		return false
	end
	if newData ~= nil then
		local mem = profiles[player]
		local fresh = PlayerData.migrate(newData)
		if mem then
			mem.tips = fresh.tips
			mem.purchases = fresh.purchases
		end
	end
	return true
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
