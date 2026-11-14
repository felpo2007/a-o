--!strict
-- Recompensa diária no servidor (a caderneta de serviço do lobby). O cliente só PEDE (Daily_Claim);
-- o dia é o do relógio do servidor (UTC), a regra é a de Shared/Commerce (dailyClaim) e o resgate é
-- gravado de forma atômica no perfil (PlayerData.claimDaily). Depois de um resgate, o armário da
-- loja recebe os cosméticos ganhos (CommerceService.earnedChanged).
-- Remotes: Daily_Get (estado), Daily_Claim (pedido) e Daily_State (estado + resultado do pedido).
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Net = require(ReplicatedStorage.Shared.Net)
local CommerceService = require(script.Parent.CommerceService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressionService = require(script.Parent.ProgressionService)

local DailyRewardService = {}
-- créditos de intendência por dia de serviço resgatado (D-72: 30 CI + 10 por dia da sequência). D-130:
-- o valor mora na trilha (Commerce.DailyTrack), que a janela da entrada também mostra
local function dailyCredits(day: number): number
	local entry = Commerce.DailyTrack[day]
	return if entry then entry.credits else Commerce.DailyTrack[1].credits
end

local MIN_INTERVAL = 1.5 -- s entre pedidos do mesmo jogador
local busy: { [Player]: boolean } = {}
local lastAsk: { [Player]: number } = {}

local function today(): number
	return Commerce.dayIndex(os.time())
end

-- só os itens da trilha (o cliente marca "já é seu" nos dias 3 e 7)
local function trackItems(earned: { [string]: boolean }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, d in Commerce.DailyTrack do
		local items = d.items
		if items then
			for _, id in items do
				if earned[id] then
					out[id] = true
				end
			end
		end
	end
	return out
end

function DailyRewardService.view(player: Player, result: { [string]: any }?): { [string]: any }
	local p = PlayerData.get(player)
	if not p then
		return { ready = false, result = result }
	end
	local v = Commerce.dailyView(p.daily, today())
	return {
		ready = true,
		canClaim = v.canClaim,
		claimedToday = v.claimedToday,
		clockBehind = v.clockBehind,
		broken = v.broken,
		day = v.day,
		run = v.run,
		total = p.daily.total,
		earned = trackItems(p.earned),
		resetIn = Commerce.secondsToNextDay(os.time()),
		-- D-130: arquivo local no Studio (PlaceId 0) não tem DataStore: o resgate fica só na memória
		saved = player:GetAttribute("DataReadOnly") ~= true and game.PlaceId ~= 0,
		result = result,
	}
end

local function push(player: Player, result: { [string]: any }?)
	Net.event("Daily_State"):FireClient(player, DailyRewardService.view(player, result))
end

local function claim(player: Player)
	if busy[player] then
		return
	end
	local now = os.clock()
	local last = lastAsk[player]
	if last and now - last < MIN_INTERVAL then
		return
	end
	lastAsk[player] = now
	busy[player] = true
	local ok, status, r = pcall(PlayerData.claimDaily, player, today())
	busy[player] = nil
	if not player.Parent then
		return -- saiu enquanto gravava
	end
	if not ok then
		warn("[VT65] recompensa diária:", status)
		push(player, { ok = false, reason = "error" })
		return
	end
	if status == "ok" and r then
		CommerceService.earnedChanged(player)
		-- D-130: o que entrou de fato (com os multiplicadores da campanha) vai no resultado: a caderneta
		-- mostra o mesmo número do aviso
		local got = ProgressionService.addCredits(player, dailyCredits(tonumber(r.day) or 1), "Dia de serviço")
		require(script.Parent.CampanhaEventos).fire(player, "daily_seal", { day = r.day }) -- estrelas do passe
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "daily_claim", r.day)
		end)
		push(player, { ok = true, day = r.day, run = r.run, items = r.items, newItems = r.newItems, credits = got })
	else
		push(player, { ok = false, reason = status })
	end
end

function DailyRewardService.start()
	Net.func("Daily_Get").OnServerInvoke = function(player: Player)
		return DailyRewardService.view(player, nil)
	end
	Net.event("Daily_Claim").OnServerEvent:Connect(function(player: Player)
		claim(player)
	end)
	PlayerData.Loaded:Connect(function(player: Player)
		push(player, nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		lastAsk[player] = nil
	end)
	-- virada do dia UTC: quem está no servidor vê o selo novo sem reabrir a caderneta
	task.spawn(function()
		local shown = today()
		while true do
			task.wait(30)
			local d = today()
			if d ~= shown then
				shown = d
				for _, player in Players:GetPlayers() do
					if PlayerData.get(player) then
						push(player, nil)
					end
				end
			end
		end
	end)
end

return DailyRewardService
