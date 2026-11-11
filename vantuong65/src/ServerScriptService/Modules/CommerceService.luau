--!strict
-- Monetização no servidor: posse de passes, Premium, assinatura, recibos de produtos,
-- equipar cosméticos e funil de análise da loja. Tudo cosmético/apoio (Parte 11).
local AnalyticsService = game:GetService("AnalyticsService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)

local CommerceService = {}
local ownership: { [Player]: Commerce.Ownership } = {}
-- produto entregue (grants "respawn"/"tip"); `now` = entregue agora (não um recibo repetido).
-- Posto pelo ProgressionService (D-72).
CommerceService.onGrant = nil :: ((player: Player, grants: string, now: boolean) -> ())?
-- passes mudaram (compra de Game Pass, Premium, assinatura)
CommerceService.onRefresh = nil :: ((player: Player) -> ())?

local function passOwned(player: Player, id: number): boolean
	if id == 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	return ok and owns == true
end

local function subscribed(player: Player): boolean
	local sid = Commerce.IDS.SUBSCRIPTION_UNIT_RESERVE
	if sid == "" then
		return false
	end
	local ok, status = pcall(function()
		return MarketplaceService:GetUserSubscriptionStatusAsync(player, sid)
	end)
	return ok and type(status) == "table" and status.IsSubscribed == true
end

-- cosméticos ganhos em jogo (recompensa diária), lidos do perfil
local function earnedOf(player: Player): { [string]: boolean }
	local p = PlayerData.get(player)
	return if p then table.clone(p.earned) else {}
end

function CommerceService.ownership(player: Player): Commerce.Ownership
	return ownership[player] or { passes = {}, premium = false, subscription = false, earned = earnedOf(player) }
end

local function stateFor(player: Player)
	local own = CommerceService.ownership(player)
	local p = PlayerData.get(player)
	return {
		passes = own.passes,
		premium = own.premium,
		subscription = own.subscription,
		unlocked = Commerce.unlockedIds(own),
		equipped = p and p.equipped or {},
	}
end

local function push(player: Player)
	Net.event("Commerce_State"):FireClient(player, stateFor(player))
	-- atributos lidos pelo aparelhador de cosméticos e pelo relatório pós-ação
	local own = CommerceService.ownership(player)
	player:SetAttribute("Supporter", own.passes.PASS_SUPPORTER == true)
	player:SetAttribute("UnitPass", own.passes.PASS_UNIT == true)
end

function CommerceService.refresh(player: Player)
	local passes = {}
	for _, pass in Commerce.Passes do
		local id = (Commerce.IDS :: any)[pass.key] :: number
		passes[pass.key] = passOwned(player, id)
	end
	ownership[player] = {
		passes = passes,
		premium = player.MembershipType == Enum.MembershipType.Premium,
		subscription = subscribed(player),
		earned = earnedOf(player),
	}
	-- se algo equipado deixou de valer (ex.: assinatura vencida), volta ao padrão
	local p = PlayerData.get(player)
	if p then
		for faction, slots in p.equipped do
			for slot, id in slots do
				if not Commerce.canEquip(id, faction, slot, ownership[player]) then
					slots[slot] = Commerce.defaultLoadout(faction)[slot]
				end
			end
		end
	end
	push(player)
	if CommerceService.onRefresh then
		task.spawn(CommerceService.onRefresh, player)
	end
end

-- Depois de um resgate diário: relê os itens ganhos do perfil e manda o armário de novo (sem refazer
-- as consultas de passe, que vão à rede).
function CommerceService.earnedChanged(player: Player)
	local own = ownership[player]
	if own then
		own.earned = earnedOf(player)
	end
	push(player)
end

local function track(player: Player, step: string, item: string?)
	local idx = table.find(Commerce.FunnelSteps, step)
	if not idx then
		return
	end
	pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, "Store", nil, idx, step, { item = item or "" })
	end)
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player or not PlayerData.get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = Commerce.productKeyById(info.ProductId)
	if not key then
		warn("[Commerce] produto desconhecido", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local grants = Commerce.productGrants(key)
	local ok, now = PlayerData.applyReceipt(player, tostring(info.PurchaseId), function(p)
		if grants == "respawn" then
			-- renascer onde caiu (D-72): vira um "renascer guardado", gasto só quando acontecer
			p.respawnCredits = math.min(p.respawnCredits + 1, 1000)
		elseif string.find(key, "TIP") then
			p.tips += 1
		end
	end)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if now and grants == "respawn" then
		PlayerData.bump(player, "respawnCredits", 1)
	end
	if grants and CommerceService.onGrant then
		task.spawn(CommerceService.onGrant, player, grants, now)
	end
	track(player, "purchase", key)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "robux_spent", tonumber(info.CurrencySpent) or 0, { sku = key })
	end)
	push(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function CommerceService.start()
	MarketplaceService.ProcessReceipt = processReceipt

	PlayerData.Loaded:Connect(function(player: Player)
		CommerceService.refresh(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		ownership[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
		if purchased then
			track(player, "purchase", "pass")
			CommerceService.refresh(player)
		end
	end)
	Players.PlayerMembershipChanged:Connect(function(player)
		CommerceService.refresh(player)
	end)
	Players.UserSubscriptionStatusChanged:Connect(function(player, _sid)
		CommerceService.refresh(player)
	end)

	Net.func("Commerce_GetState").OnServerInvoke = function(player)
		return stateFor(player)
	end
	Net.event("Commerce_Equip").OnServerEvent:Connect(function(player, faction, slot, id)
		if type(faction) ~= "string" or type(slot) ~= "string" or type(id) ~= "string" then
			return
		end
		local p = PlayerData.get(player)
		if not p or not Commerce.canEquip(id, faction, slot, CommerceService.ownership(player)) then
			return
		end
		p.equipped[faction] = p.equipped[faction] or Commerce.defaultLoadout(faction)
		p.equipped[faction][slot] = id
		push(player)
	end)
	Net.event("Commerce_Track").OnServerEvent:Connect(function(player, step, item)
		if type(step) == "string" and (item == nil or type(item) == "string") then
			track(player, step, item)
		end
	end)
end

return CommerceService
