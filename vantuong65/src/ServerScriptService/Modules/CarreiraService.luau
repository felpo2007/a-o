--!strict
-- D-247: a carreira no servidor (regras em Shared/Carreira). O cliente só pede; quem confere nível, pontos,
-- pré-requisito e prestígio é aqui. Os efeitos da árvore viram os atributos Vant_<chave>, junto dos passes,
-- sob o teto de combate. Prestigiar não mexe em patente, créditos nem itens.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Carreira = require(ReplicatedStorage.Shared.Carreira)
local Net = require(ReplicatedStorage.Shared.Net)
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local CaixaService = require(script.Parent.CaixaService)
local CommerceService = require(script.Parent.CommerceService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressionService = require(script.Parent.ProgressionService)

local CarreiraService = {}

local INTERVALO_S = 0.3
local ultimo: { [Player]: number } = {}

local function estado(p: Player, resultado: { [string]: any }?): { [string]: any }?
	local prof = PlayerData.get(p)
	if not prof then
		return nil
	end
	local e = prof.carreira
	local nivel, dentro, falta = Carreira.nivel(prof.xp, e.base)
	local proximas = {}
	for n = nivel + 1, math.min(nivel + 4, Carreira.NIVEL_MAX) do
		table.insert(proximas, Carreira.recompensa(n))
	end
	local pode = Carreira.podePrestigiar(e, prof.xp)
	return {
		nivel = nivel,
		nivelMax = Carreira.NIVEL_MAX,
		dentro = dentro,
		falta = falta,
		prestigio = e.prestigio,
		prestigioMax = Carreira.PRESTIGIO_MAX,
		podePrestigiar = pode,
		multXp = Carreira.multXp(e.prestigio),
		pontos = Carreira.pontosLivres(e, prof.xp),
		nos = e.nos,
		proximas = proximas,
		medalhas = Carreira.vitrine(prof.campaign.stats, prof.campaign.medals),
		resultado = resultado,
	}
end

function CarreiraService.push(p: Player, resultado: { [string]: any }?)
	local st = estado(p, resultado)
	if st then
		Net.event("Carreira_State"):FireClient(p, st)
	end
end

-- os atributos que cada sistema lê (Vantagens.mult / extra): passes + árvore
local function aplicar(p: Player)
	local prof = PlayerData.get(p)
	if not prof then
		return
	end
	local passes = (CommerceService.ownership(p).passes :: any) or {}
	local perks = Vantagens.compute(passes, nil, Carreira.efeitos(prof.carreira.nos))
	for key in Vantagens.KEYS do
		p:SetAttribute(Vantagens.attr(key), perks[key])
	end
	p:SetAttribute("Prestigio", prof.carreira.prestigio)
	p:SetAttribute("NivelSoldado", (Carreira.nivel(prof.xp, prof.carreira.base)))
end

local function salvar(p: Player)
	task.spawn(function()
		pcall(PlayerData.save, p)
	end)
end

-- o XP mudou: paga cada nível novo uma vez
local function aoGanharXp(p: Player)
	local prof = PlayerData.get(p)
	if not prof then
		return
	end
	local novos = Carreira.receber(prof.carreira, prof.xp)
	if #novos == 0 then
		return
	end
	local total = 0
	for _, r in novos do
		total += r.creditos
		if r.caixa then
			CaixaService.darCaixa(p, "servico", string.format("carreira:%d:%d", prof.carreira.prestigio, r.nivel))
		end
	end
	ProgressionService.addCredits(p, total, string.format("Nível %d", novos[#novos].nivel))
	aplicar(p)
	CarreiraService.push(p, { op = "nivel", ok = true, nivel = novos[#novos].nivel, creditos = total })
end

local function aoPedir(p: Player, msg: any)
	if type(msg) ~= "table" or type(msg.op) ~= "string" then
		return
	end
	local agora = os.clock()
	if agora - (ultimo[p] or -math.huge) < INTERVALO_S then
		return
	end
	ultimo[p] = agora
	local prof = PlayerData.get(p)
	if not prof or p:GetAttribute("DataReadOnly") == true then
		return
	end
	local e = prof.carreira
	if msg.op == "ativar" then
		local ok, motivo = Carreira.podeAtivar(e, msg.id, prof.xp)
		if ok then
			e.nos[msg.id] = true
			aplicar(p)
			salvar(p)
		end
		CarreiraService.push(p, { op = "ativar", ok = ok, motivo = motivo, id = if ok then msg.id else nil })
	elseif msg.op == "limpar" then
		Carreira.limpar(e)
		aplicar(p)
		salvar(p)
		CarreiraService.push(p, { op = "limpar", ok = true })
	elseif msg.op == "prestigiar" then
		local ok = Carreira.prestigiar(e, prof.xp)
		if ok then
			aplicar(p)
			salvar(p)
		end
		CarreiraService.push(p, { op = "prestigiar", ok = ok, prestigio = e.prestigio })
	end
end

function CarreiraService.start()
	ProgressionService.multPrestigio = function(p: Player): number
		local prof = PlayerData.get(p)
		return if prof then Carreira.multXp(prof.carreira.prestigio) else 1
	end
	ProgressionService.onXp = aoGanharXp
	Net.func("Carreira_Get").OnServerInvoke = function(p: Player)
		aplicar(p)
		return estado(p)
	end
	Net.event("Carreira_Action").OnServerEvent:Connect(aoPedir)
	Players.PlayerRemoving:Connect(function(p: Player)
		ultimo[p] = nil
	end)
	-- Studio (barra do SERVIDOR): workspace "VT65DevCarreira" = "xp:<total>" põe o XP do jogador
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevCarreira"):Connect(function()
			local v = workspace:GetAttribute("VT65DevCarreira")
			local n = if type(v) == "string" then tonumber(string.match(v, "^xp:(%d+)$")) else nil
			if not n then
				return
			end
			for _, p in Players:GetPlayers() do
				local prof = PlayerData.get(p)
				if prof then
					prof.xp = n
					aoGanharXp(p)
					ProgressionService.push(p)
					aplicar(p)
					CarreiraService.push(p)
				end
			end
			task.defer(function()
				workspace:SetAttribute("VT65DevCarreira", nil)
			end)
		end)
	end
end

return CarreiraService
