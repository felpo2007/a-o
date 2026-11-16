--!strict
-- Caixas de suprimentos no servidor (D-173). Regras em Shared/Caixas e Modules/CaixaRegras.
--   - o sorteio é daqui (Random do servidor), dentro da transação atômica (PlayerData.transact): o
--     resultado é gravado ANTES de ir para o cliente, e a animação só mostra o que já foi gravado;
--   - caixa paga: Developer Product. Só oferece o prompt com Caixas.PAGAS_LIGADAS, o produto criado e
--     o PolicyService dizendo que o jogador pode (ArePaidRandomItemsRestricted falso). Se a consulta
--     falha, bloqueia. O recibo (ProcessReceipt, via CommerceService.crateReceipt) é idempotente pelo
--     PurchaseId; jogador restrito que chegou a um recibo (prompt do próprio cliente) recebe
--     Fragmentos fixos, sem sorteio;
--   - caixa gratuita: só com Bilhetes de Recompensa (missão cumprida e boas-vindas), nunca à venda;
--   - pedidos do cliente: um por vez por jogador e no máximo 1 a cada 0,4 s.
-- Studio (ganchos, só no Studio):
--   workspace:SetAttribute("VT65DevCaixa", "bilhetes")  -> +5 bilhetes
--   workspace:SetAttribute("VT65DevCaixa", "fragmentos") -> +1000 fragmentos
--   workspace:SetAttribute("VT65DevCaixa", "pagas")     -> liga a venda paga NESTA sessão (teste)
--   workspace:SetAttribute("VT65DevCaixa", "restrito")  -> simula ArePaidRandomItemsRestricted
--   workspace:SetAttribute("VT65DevCaixa", "falha")     -> simula falha da consulta ao PolicyService
--   workspace:SetAttribute("VT65DevCaixa", "recibo:<caixa>") -> recibo simulado (sem Robux)
local AnalyticsService = game:GetService("AnalyticsService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Caixas = require(ReplicatedStorage.Shared.Caixas) :: any
local Calendario = require(ReplicatedStorage.Shared.Calendario) :: any
local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Cosmeticos = require(ReplicatedStorage.Shared.Cosmeticos) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Temporada = require(ReplicatedStorage.Shared.Temporada)
local AssetLoader = require(script.Parent.AssetLoader) :: any
local CaixaRegras = require(script.Parent.CaixaRegras) :: any
local CommerceService = require(script.Parent.CommerceService)
local PlayerData = require(script.Parent.PlayerData)

local CaixaService = {}

local rng = Random.new()
local busy: { [Player]: boolean } = {}
local last: { [Player]: number } = {}
local policy: { [Player]: { at: number, ok: boolean, restricted: boolean } } = {}
local dev = { pagas = false, restrito = false, falha = false }
-- tabela que não passou na validação (Caixas.validar) na partida: não abre, não vende
local invalidas: { [string]: boolean } = {}
CaixaService.MIN_GAP = 0.4
-- item ou cosmético novo no perfil: o CampanhaService reenvia o estado da campanha (emblemas do cartão)
CaixaService.onGrant = nil :: ((player: Player) -> ())?
CaixaService.POLICY_TTL = 600

local function sorteio(): number
	return rng:NextInteger(0, Caixas.ESCALA - 1)
end

local function passes(player: Player): { [string]: boolean }
	local own = CommerceService.ownership(player)
	return if own and type(own.passes) == "table" then own.passes else {}
end

-- ===== PolicyService =====
-- (restrito, respondeu). Falha na consulta: restrito (bloqueia o pago até responder).
function CaixaService.politica(player: Player): (boolean, boolean)
	if RunService:IsStudio() then
		if dev.falha then
			return true, false
		end
		if dev.restrito then
			return true, true
		end
	end
	local c = policy[player]
	if c and c.ok and os.clock() - c.at < CaixaService.POLICY_TTL then
		return c.restricted, true
	end
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and type(info) == "table" and type(info.ArePaidRandomItemsRestricted) == "boolean" then
		policy[player] = { at = os.clock(), ok = true, restricted = info.ArePaidRandomItemsRestricted }
		return info.ArePaidRandomItemsRestricted, true
	end
	policy[player] = { at = os.clock(), ok = false, restricted = true }
	warn("[Caixas] PolicyService não respondeu; caixas pagas bloqueadas para", player.UserId)
	return true, false
end

local function pagasLigadas(): boolean
	return Caixas.PAGAS_LIGADAS or (RunService:IsStudio() and dev.pagas)
end

local function produtoId(c: any): number
	local id = c.produto and (Commerce.IDS :: any)[c.produto]
	return if type(id) == "number" then id else 0
end

-- motivo para NÃO vender esta caixa a este jogador agora (nil = pode)
function CaixaService.bloqueioPaga(player: Player, c: any): string?
	if c.tipo ~= "paga" then
		return "tipo"
	end
	if invalidas[c.id] then
		return "invalida"
	end
	if not pagasLigadas() then
		return "desligada"
	end
	if not Caixas.disponivel(c, os.time(), Temporada.SEASON) then
		return "fora_da_temporada"
	end
	local restrito, respondeu = CaixaService.politica(player)
	if not respondeu then
		return "politica_sem_resposta"
	end
	if restrito then
		return "restrito"
	end
	if produtoId(c) == 0 and not (RunService:IsStudio() and dev.pagas) then
		return "sem_produto"
	end
	return nil
end

-- ===== estado para a tela =====
local function itemView(id: string): any
	local info = Cosmeticos.info(id)
	if not info then
		return { id = id, nome = id, raridade = "comum", kind = "?" }
	end
	return {
		id = id,
		nome = info.nome,
		nomeEn = info.nomeEn,
		desc = info.desc,
		raridade = info.raridade,
		kind = info.kind,
		cor = info.cor,
		cor2 = info.cor2,
		sigla = info.sigla,
	}
end

function CaixaService.estado(player: Player): any
	local p = PlayerData.get(player)
	if not p then
		return { carregando = true }
	end
	local ps = passes(player)
	local d = p.caixas
	local caixas = {}
	for _, c in Caixas.CAIXAS do
		local odds = CaixaRegras.odds(p, c.id, ps) or {}
		local lista = {}
		for _, r in odds do
			table.insert(lista, {
				item = itemView(r.item),
				peso = r.peso,
				pct = r.pct,
				repetido = r.repetido,
				fragmentos = r.fragmentos,
			})
		end
		local bloqueio = if c.tipo == "paga"
			then CaixaService.bloqueioPaga(player, c)
			elseif invalidas[c.id] then "invalida"
			else nil
		table.insert(caixas, {
			id = c.id,
			nome = c.nome,
			nomeEn = c.nomeEn,
			desc = c.desc,
			tipo = c.tipo,
			modelo = c.modelo,
			versao = c.versao,
			sorteios = c.sorteios,
			bilhetes = c.bilhetes,
			produtoId = produtoId(c),
			robuxRef = c.robux,
			temporada = c.temporada,
			disponivel = Caixas.disponivel(c, os.time(), Temporada.SEASON),
			fim = if c.temporada then Temporada.SEASON.endsAt else nil,
			bloqueio = bloqueio,
			porRaridade = Caixas.porRaridade(c, Cosmeticos.info, nil),
			lista = lista,
			abertas = d.abertas[c.id] or 0,
			pity = if Caixas.PITY.enabled then d.pity[c.id] or 0 else nil,
		})
	end
	local troca = {}
	for _, t in CaixaRegras.troca() do
		table.insert(troca, {
			item = itemView(t.item),
			custo = t.custo,
			possui = CaixaRegras.possui(p, t.item, ps),
		})
	end
	local hist = {}
	for i = #d.hist, math.max(1, #d.hist - 19), -1 do
		local r = d.hist[i]
		table.insert(hist, {
			caixa = r.caixa,
			item = if r.item then itemView(r.item) else nil,
			repetido = r.repetido,
			fragmentos = r.fragmentos,
			origem = r.origem,
			t = r.t,
		})
	end
	local meus = { tag = {}, mol = {} }
	for _, it in Cosmeticos.ITENS do
		if p.campaign.owned[it.id] then
			if it.kind == "plaqueta" then
				table.insert(meus.tag, itemView(it.id))
			elseif it.kind == "moldura" then
				table.insert(meus.mol, itemView(it.id))
			end
		end
	end
	local restrito, respondeu = CaixaService.politica(player)
	return {
		bilhetes = d.bilhetes,
		fragmentos = d.fragmentos,
		caixas = caixas,
		troca = troca,
		hist = hist,
		meus = meus,
		on = { tag = d.on.tag, mol = d.on.mol },
		raridades = Caixas.RARIDADES,
		regras = Caixas.REGRAS,
		regrasEn = Caixas.REGRAS_EN,
		pity = Caixas.PITY,
		restrito = restrito,
		politicaOk = respondeu,
		pagasLigadas = pagasLigadas(),
		tetoDia = CaixaRegras.TETO_DIA,
		hoje = if d.dia == Calendario.dayIndex(os.time()) then d.hoje else 0,
	}
end

-- plaqueta e moldura no personagem/jogador (o cartão lê os atributos)
local function aplicarCartao(player: Player)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	player:SetAttribute("VT65Plaqueta", p.caixas.on.tag)
	player:SetAttribute("VT65Moldura", p.caixas.on.mol)
end

-- ===== pedidos do cliente =====
local function guard(player: Player): boolean
	if busy[player] then
		return false
	end
	local t = os.clock()
	if t - (last[player] or 0) < CaixaService.MIN_GAP then
		return false
	end
	last[player] = t
	busy[player] = true
	return true
end

local function release(player: Player)
	busy[player] = nil
end

-- avisa quem mostra a posse: a campanha (emblemas, plaquetas, molduras) e a intendência (skins)
local function avisar(player: Player, r: any)
	if r and r.item and not r.repetido then
		if string.sub(r.item, 1, 5) == "skin_" and CommerceService.onSkin then
			task.spawn(CommerceService.onSkin, player, r.item, false) -- só a posse (não equipa sozinho)
		end
		local g = CaixaService.onGrant
		if g then
			task.spawn(g, player)
		end
	end
end

local function logAbertura(player: Player, r: any)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "caixa_aberta", 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(r.caixa),
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = tostring(r.raridade or r.origem),
			[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = if r.repetido then "repetido" else "novo",
		})
	end)
end

function CaixaService.abrir(player: Player, caixaId: any): any
	if type(caixaId) ~= "string" then
		return { ok = false, motivo = "pedido" }
	end
	local c = Caixas.get(caixaId)
	if not c or c.tipo ~= "gratuita" or invalidas[c.id] then
		return { ok = false, motivo = "caixa" }
	end
	if not guard(player) then
		return { ok = false, motivo = "espera" }
	end
	local ps = passes(player)
	local status, r = PlayerData.transact(player, function(p)
		local res, motivo = CaixaRegras.abrirGratuita(p, caixaId, sorteio(), os.time(), ps)
		if not res then
			return nil, motivo
		end
		return res
	end)
	release(player)
	if status ~= "ok" then
		local p = PlayerData.get(player)
		local semBilhete = p and p.caixas.bilhetes < (c.bilhetes or 1)
		return { ok = false, motivo = if semBilhete then "bilhetes" else status }
	end
	logAbertura(player, r)
	avisar(player, r)
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			"Bilhetes",
			c.bilhetes or 1,
			PlayerData.get(player).caixas.bilhetes,
			Enum.AnalyticsEconomyTransactionType.Shop.Name,
			"caixa_" .. caixaId
		)
	end)
	return { ok = true, resultado = r, item = if r.item then itemView(r.item) else nil }
end

function CaixaService.trocar(player: Player, item: any): any
	if type(item) ~= "string" or #item > 48 then
		return { ok = false, motivo = "pedido" }
	end
	if not guard(player) then
		return { ok = false, motivo = "espera" }
	end
	local ps = passes(player)
	local motivoFinal: string? = nil
	local status, r = PlayerData.transact(player, function(p)
		local res, motivo = CaixaRegras.trocar(p, item, os.time(), ps)
		motivoFinal = motivo
		return res
	end)
	release(player)
	if status ~= "ok" then
		return { ok = false, motivo = motivoFinal or status }
	end
	avisar(player, r)
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			"Fragmentos",
			-(r.fragmentos :: number),
			PlayerData.get(player).caixas.fragmentos,
			Enum.AnalyticsEconomyTransactionType.Shop.Name,
			item
		)
	end)
	return { ok = true, resultado = r, item = itemView(item) }
end

function CaixaService.equipar(player: Player, req: any): any
	if type(req) ~= "table" or type(req.slot) ~= "string" or type(req.item) ~= "string" then
		return { ok = false }
	end
	if not guard(player) then
		return { ok = false, motivo = "espera" }
	end
	local status = PlayerData.transact(player, function(p)
		return if CaixaRegras.equipar(p, req.slot, req.item) then true else nil
	end)
	release(player)
	aplicarCartao(player)
	return { ok = status == "ok" }
end

function CaixaService.comprar(player: Player, caixaId: any)
	if type(caixaId) ~= "string" then
		return
	end
	local c = Caixas.get(caixaId)
	if not c then
		return
	end
	local bloqueio = CaixaService.bloqueioPaga(player, c)
	if bloqueio then
		return
	end
	local id = produtoId(c)
	if id == 0 then
		return
	end
	pcall(function()
		MarketplaceService:PromptProductPurchase(player, id)
	end)
end

-- Bilhetes ganhos jogando. Gravação atômica com teto por dia (fora da missão: o que não coube fica de
-- fora, e o jogador vê o teto na tela).
function CaixaService.ganhar(player: Player, n: number, motivo: string)
	task.spawn(function()
		local dia = Calendario.dayIndex(os.time())
		local status, dado = PlayerData.transact(player, function(p)
			local d = CaixaRegras.ganhar(p, n, dia, motivo)
			return if d > 0 then d else nil
		end)
		if status == "ok" then
			pcall(function()
				AnalyticsService:LogEconomyEvent(
					player,
					Enum.AnalyticsEconomyFlowType.Source,
					"Bilhetes",
					dado,
					PlayerData.get(player).caixas.bilhetes,
					Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
					motivo
				)
			end)
		end
	end)
end

-- ===== recibo da caixa paga (chamado pelo CommerceService.ProcessReceipt) =====
function CaixaService.recibo(player: Player, info: { [string]: any }, c: any): Enum.ProductPurchaseDecision
	local purchaseId = tostring(info.PurchaseId)
	-- a política na hora do recibo: restrito ou sem resposta -> Fragmentos fixos (sem sorteio). Venda
	-- paga desligada (o prompt só abre com ela ligada; um recibo agora veio de prompt do próprio
	-- cliente) também: nada de item aleatório pago antes do dono ligar
	local restrito, respondeu = CaixaService.politica(player)
	local semSorteio = restrito or not respondeu or invalidas[c.id] == true or not pagasLigadas()
	local ps = passes(player)
	local novo = false
	local status, r = PlayerData.transact(player, function(p)
		local res, agora = CaixaRegras.recibo(p, c.id, purchaseId, sorteio(), os.time(), semSorteio, ps)
		novo = agora
		p.purchases[purchaseId] = p.purchases[purchaseId] or os.time()
		return res
	end)
	if status ~= "ok" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not novo then
		-- recibo repetido: já entregue e já mostrado (nada de nova abertura nem novo registro)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	logAbertura(player, r)
	avisar(player, r)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "robux_spent", tonumber(info.CurrencySpent) or 0, { sku = c.produto })
	end)
	Net.event("Suprimento_Resultado"):FireClient(player, {
		resultado = r,
		item = if r.item then itemView(r.item) else nil,
	})
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ===== Studio =====
local function devHook()
	local v = Workspace:GetAttribute("VT65DevCaixa")
	if not RunService:IsStudio() or type(v) ~= "string" then
		return
	end
	Workspace:SetAttribute("VT65DevCaixa", nil)
	for _, player in Players:GetPlayers() do
		if v == "bilhetes" or v == "fragmentos" then
			PlayerData.transact(player, function(p)
				if v == "bilhetes" then
					p.caixas.bilhetes += 5
				else
					p.caixas.fragmentos += 1000
				end
				return true
			end)
		elseif v == "pagas" then
			dev.pagas = true
		elseif v == "restrito" then
			dev.restrito = true
		elseif v == "falha" then
			dev.falha = true
		elseif v == "normal" then
			dev.pagas, dev.restrito, dev.falha = false, false, false
		elseif string.sub(v, 1, 7) == "recibo:" then
			local c = Caixas.get(string.sub(v, 8))
			if c and c.tipo == "paga" then
				local fake =
					{ PurchaseId = "dev-" .. tostring(os.clock()), PlayerId = player.UserId, CurrencySpent = 0 }
				local d = CaixaService.recibo(player, fake, c)
				print("[VT65 CAIXA] recibo simulado", c.id, d.Name)
				-- o mesmo recibo de novo devolve o mesmo resultado (sem novo sorteio)
				local again = CaixaService.recibo(player, fake, c)
				print("[VT65 CAIXA] recibo repetido", c.id, again.Name, #PlayerData.get(player).caixas.hist)
			end
		end
	end
	print("[VT65 CAIXA] gancho", v, "pagas", dev.pagas, "restrito", dev.restrito, "falha", dev.falha)
end

function CaixaService.start()
	CommerceService.crateReceipt = function(player: Player, info: { [string]: any }, c: any)
		return CaixaService.recibo(player, info, c)
	end
	Net.func("Suprimento_Get").OnServerInvoke = function(player: Player)
		return CaixaService.estado(player)
	end
	Net.func("Suprimento_Abrir").OnServerInvoke = function(player: Player, caixaId: any)
		local r = CaixaService.abrir(player, caixaId)
		r.estado = CaixaService.estado(player)
		return r
	end
	Net.func("Suprimento_Trocar").OnServerInvoke = function(player: Player, item: any)
		local r = CaixaService.trocar(player, item)
		r.estado = CaixaService.estado(player)
		return r
	end
	Net.func("Suprimento_Equipar").OnServerInvoke = function(player: Player, req: any)
		local r = CaixaService.equipar(player, req)
		r.estado = CaixaService.estado(player)
		return r
	end
	Net.event("Suprimento_Comprar").OnServerEvent:Connect(function(player: Player, caixaId: any)
		CaixaService.comprar(player, caixaId)
	end)
	PlayerData.Loaded:Connect(function(player: Player)
		aplicarCartao(player)
		-- boas-vindas: 2 bilhetes uma vez por conta, para conhecer a caixa gratuita
		CaixaService.ganhar(player, 2, "boas_vindas")
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		last[player] = nil
		policy[player] = nil
	end)
	Workspace:GetAttributeChangedSignal("VT65DevCaixa"):Connect(devHook)
	-- a arte das caixas para a tela do cliente (ViewportFrame): cópia do modelo publicado
	task.spawn(function()
		local folder = Instance.new("Folder")
		folder.Name = "VT65CaixasArte"
		local feitos: { [string]: boolean } = {}
		for _, c in Caixas.CAIXAS do
			if not feitos[c.modelo] then
				feitos[c.modelo] = true
				local tpl = AssetLoader.template(c.modelo)
				if tpl then
					local copy = tpl:Clone()
					copy.Name = c.modelo
					for _, d in copy:GetDescendants() do
						if d:IsA("BasePart") and string.sub(d.Name, 1, 8) == "Colisao_" then
							d:Destroy()
						end
					end
					copy.Parent = folder
				end
			end
		end
		folder.Parent = ReplicatedStorage
	end)
	-- confere as tabelas na partida: tabela inválida desliga a caixa (não abre, não vende)
	for _, c in Caixas.CAIXAS do
		local erros = Caixas.validar(c, Cosmeticos.info)
		if #erros > 0 then
			warn("[Caixas] tabela inválida:", table.concat(erros, "; "))
			invalidas[c.id] = true
		end
	end
end

return CaixaService
