--!strict
-- Monetização no servidor: posse de passes, Premium, assinatura, recibos de produtos,
-- equipar cosméticos e funil de análise da loja. Tudo cosmético/apoio (Parte 11).
-- Skins (Shared/Skins, 2026-11-11): posse dos Game Passes de skin (uniforme e camuflagem) junto dos
-- outros passes, e o recibo idempotente dos Developer Products de skin de arma (a posse vai para o
-- perfil, PlayerData.applyReceipt).
local AnalyticsService = game:GetService("AnalyticsService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local CompraVeiculo = require(ReplicatedStorage.Shared.CompraVeiculo)
local Net = require(ReplicatedStorage.Shared.Net)
local Reforcos = require(ReplicatedStorage.Shared.Reforcos)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Temporada = require(ReplicatedStorage.Shared.Temporada)
local PlayerData = require(script.Parent.PlayerData)

local CommerceService = {}
local ownership: { [Player]: Commerce.Ownership } = {}
-- passes comprados nesta sessão: o UserOwnsGamePassAsync guarda a resposta antiga por um tempo e
-- diria "não" logo depois da compra
local boughtPasses: { [Player]: { [string]: boolean } } = {}
-- produto entregue (grants "respawn"/"tip"); `now` = entregue agora (não um recibo repetido).
-- Posto pelo ProgressionService (D-72).
CommerceService.onGrant = nil :: ((player: Player, grants: string, now: boolean) -> ())?
-- passes mudaram (compra de Game Pass, Premium, assinatura)
CommerceService.onRefresh = nil :: ((player: Player) -> ())?
-- skin recebida por Robux (recibo de Developer Product ou compra de Game Pass); `now` = agora
CommerceService.onSkin = nil :: ((player: Player, skinId: string, now: boolean) -> ())?
-- campanha (2026-11-12): posse dos passes relida (Veterano, Recruta, vantagens) e produto da
-- campanha entregue (pular nível, reforço, créditos); postos pelo CampanhaService
CommerceService.onPasses = nil :: ((player: Player) -> ())?
CommerceService.onCampaign = nil :: ((player: Player, key: string, now: boolean) -> ())?
-- D-103: veículo ao nascer pago em Robux (postos pelo CompraVeiculoService). vehicleReady: o lugar
-- reservado para esta viatura ainda vale (o recibo vira o veículo); vehicleGrant: recibo novo
-- aplicado, deliver = entregar no lugar reservado (false = virou CI no perfil).
CommerceService.vehicleReady = nil :: ((player: Player, spec: string) -> boolean)?
CommerceService.vehicleGrant = nil :: ((player: Player, spec: string, deliver: boolean, credits: number) -> ())?

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
	-- Game Passes de skin (uniforme e camuflagem); com ID 0 nem consulta
	for _, key in Skins.passKeys() do
		passes[key] = passOwned(player, Skins.IDS[key] or 0)
	end
	-- campanha: passe da temporada, Pacote de Recruta e vantagens
	for _, pass in Commerce.CampaignPasses do
		passes[pass.key] = passOwned(player, (Commerce.IDS :: any)[pass.key] or 0)
	end
	local bought = boughtPasses[player]
	if bought then
		for key in bought do
			passes[key] = true
		end
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
	if CommerceService.onPasses then
		task.spawn(CommerceService.onPasses, player)
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

-- Recibo de skin de arma (Developer Product): a posse vai para o perfil uma única vez por
-- PurchaseId (gravação atômica). Repetido ou não, a memória fica com a posse.
local function skinReceipt(player: Player, info: { [string]: any }, skinId: string): Enum.ProductPurchaseDecision
	local ok, now = PlayerData.applyReceipt(player, tostring(info.PurchaseId), function(p)
		p.skins.owned[skinId] = true
	end)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local mem = PlayerData.get(player)
	if mem then
		mem.skins.owned[skinId] = true
	end
	local s = Skins.get(skinId)
	local sku = if s then s.robuxKey else skinId
	if CommerceService.onSkin then
		task.spawn(CommerceService.onSkin, player, skinId, now)
	end
	track(player, "purchase", sku)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "robux_spent", tonumber(info.CurrencySpent) or 0, { sku = sku })
	end)
	push(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Produto da campanha num perfil (gravado ou em memória). Estrelas e reforços se juntam por máximo
-- entre servidores (ProfileSchema.mergeCampaign): aplicar no gravado e na memória não dá em dobro.
-- Créditos só no gravado (a memória anda junto pelo PlayerData.bump).
function CommerceService.applyCampaignGrant(p: any, cp: Commerce.CampaignProduct, now: number)
	local c = p.campaign
	if cp.grants == "season_skip" then
		c.season.stars += Temporada.skipStars(c.season.stars)
	elseif cp.grants == "boost_xp" then
		Reforcos.extend(c.boosts, "xp", cp.amount or 0, now)
	elseif cp.grants == "boost_cr" then
		Reforcos.extend(c.boosts, "cr", cp.amount or 0, now)
	elseif cp.grants == "credits" then
		p.credits = math.min(p.credits + (cp.amount or 0), 1000000000)
	end
end

-- Recibo de produto da campanha: uma única vez por PurchaseId (gravação atômica), como os outros.
local function campaignReceipt(
	player: Player,
	info: { [string]: any },
	cp: Commerce.CampaignProduct
): Enum.ProductPurchaseDecision
	local now = os.time()
	local ok, applied = PlayerData.applyReceipt(player, tostring(info.PurchaseId), function(p)
		CommerceService.applyCampaignGrant(p, cp, now)
	end)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if applied then
		if cp.grants == "credits" then
			PlayerData.bump(player, "credits", cp.amount or 0)
		else
			local mem = PlayerData.get(player)
			if mem then
				CommerceService.applyCampaignGrant(mem, cp, now)
			end
		end
	end
	if CommerceService.onCampaign then
		task.spawn(CommerceService.onCampaign, player, cp.key, applied)
	end
	track(player, "purchase", cp.key)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "robux_spent", tonumber(info.CurrencySpent) or 0, { sku = cp.key })
	end)
	push(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Recibo do veículo ao nascer (D-103), uma única vez por PurchaseId como os outros. O prompt só abriu
-- com o lugar achado e reservado: se a reserva ainda vale, o recibo vira o veículo (nada no perfil
-- além do PurchaseId); se não (morreu, a reserva venceu, recibo repetido noutro servidor), vira CI no
-- perfil na mesma gravação atômica. Recibo repetido não entrega nada (nem veículo nem CI).
local function vehicleReceipt(
	player: Player,
	info: { [string]: any },
	vp: Commerce.VehicleProduct
): Enum.ProductPurchaseDecision
	local ready = CommerceService.vehicleReady
	local deliver = ready ~= nil and ready(player, vp.spec)
	local credits = if deliver then 0 else CompraVeiculo.refundCredits(vp.spec, tonumber(info.CurrencySpent))
	local ok, applied = PlayerData.applyReceipt(player, tostring(info.PurchaseId), function(p)
		if credits > 0 then
			p.credits = math.min(p.credits + credits, 1000000000)
		end
	end)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if applied then
		if credits > 0 then
			PlayerData.bump(player, "credits", credits)
		end
		if CommerceService.vehicleGrant then
			task.spawn(CommerceService.vehicleGrant, player, vp.spec, deliver, credits)
		end
	end
	track(player, "purchase", vp.key)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "robux_spent", tonumber(info.CurrencySpent) or 0, { sku = vp.key })
	end)
	push(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player or not PlayerData.get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = Commerce.productKeyById(info.ProductId)
	local cp = if key then Commerce.campaignProduct(key) else nil
	if cp then
		return campaignReceipt(player, info, cp)
	end
	local vp = if key then Commerce.vehicleProduct(key) else nil
	if vp then
		return vehicleReceipt(player, info, vp)
	end
	if not key then
		local skinId = Skins.skinByProductId(info.ProductId)
		if skinId then
			return skinReceipt(player, info, skinId)
		end
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
		boughtPasses[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local key = Commerce.passKeyById(passId) or Skins.passKeyById(passId)
			track(player, "purchase", key or "pass")
			if key then
				local b = boughtPasses[player] or {}
				b[key] = true
				boughtPasses[player] = b
			end
			CommerceService.refresh(player)
			local skinId = Skins.skinByPassId(passId)
			if skinId and CommerceService.onSkin then
				task.spawn(CommerceService.onSkin, player, skinId, true)
			end
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
