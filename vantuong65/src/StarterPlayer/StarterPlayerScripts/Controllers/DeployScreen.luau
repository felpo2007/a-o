--!strict
-- Preparação para entrar em campo (Partes 4 e 12.5). D-223 (dono: "isso está horrível, sem qualidade
-- visual, genérico, sem imagens, sem ordem"): saiu a mesa 3D com o soldado; o caminho são quatro passos
-- em tela cheia sobre o fundo do lobby: 01 TIME, 02 GRUPO, 03 CLASSE e 04 ONDE NASCER.
-- Aqui fica a LÓGICA do caminho (o que falta, os pré-requisitos, os pedidos ao servidor); quem desenha
-- é o Controllers/Preparacao (e, no passo 04, a carta do GameUI).
-- Fluxo: lado → grupo → classe → onde nascer (avança sozinho); morto com classe, abre em onde nascer.
-- VOLTAR e B voltam um passo. Só dados reais: Roles, Weapons, efetivo pelo atributo "Faction".
-- Remotes: Team_Choose, Squad_Action {op = create/join/leave}, Role_Choose, Arma_Escolher, Kit_Set.
-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevTela", "escolha" | "lado" | "squad" |
-- "papel" | "insercao"). Ver o fim do arquivo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Preparacao = require(script.Parent.Preparacao)
local Toast = require(script.Parent.Toast)

local player = Players.LocalPlayer
local DeployScreen = {}

-- ===== raiz =====
local root = Instance.new("Frame")
root.Name = "Deploy"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Visible = false
DeployScreen.root = root
DeployScreen.changed = function() end -- o GameUI troca pelo refresh()
-- definidas mais abaixo (os callbacks da tela já chamam)
DeployScreen.open = function(_name: string) end
DeployScreen.back = function(): boolean
	return false
end

function DeployScreen.setScale(k: number)
	Preparacao.setScale(k)
end

-- ===== estado =====
local panel = "squad" -- "squad" | "role" | "insert"
local browsing = false -- de volta ao passo do lado, para trocar (vale enquanto o lado não muda)
local browsingFaction: string? = nil
local wasVisible = false

local function myFaction(): string?
	local f = player:GetAttribute("Faction")
	return if f == "US" or f == "VC" then f else nil
end

local function isBrowsing(): boolean
	return browsing and browsingFaction ~= nil and browsingFaction == myFaction()
end

local function onChoose(): boolean
	return myFaction() == nil or isBrowsing()
end

local function alive(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function hasSquad(): boolean
	return type(player:GetAttribute("SquadId")) == "string"
end

local function currentRole(): string?
	local r = player:GetAttribute("Role")
	return if type(r) == "string" then r else nil
end

-- D-108: arma principal escolhida por classe (Roles.PRIMARY). A classe atual começa na do servidor
-- (atributo "Primaria"); D-211: senão, a guardada no perfil.
local primaryPref: { [string]: string } = {}
local function primaryOf(f: string, rid: string): string?
	local pref: string? = primaryPref[rid]
	if not pref and rid == currentRole() then
		local a = player:GetAttribute("Primaria")
		pref = if type(a) == "string" then a else nil
	end
	if not pref then
		pref = Roles.unpackPrefs(player:GetAttribute("ArmasPreferidas"))[Roles.chavePref(f, rid)]
	end
	return Roles.primaryFor(f, rid, pref)
end

-- o passo em que o caminho está: o primeiro que falta
local function defaultPanel(): string
	if not hasSquad() then
		return "squad"
	elseif not currentRole() then
		return "role"
	elseif not alive() then
		return "insert"
	end
	return "role"
end

local function counts(): (number, number)
	local us, vc = 0, 0
	for _, p in Players:GetPlayers() do
		local f = p:GetAttribute("Faction")
		if f == "US" then
			us += 1
		elseif f == "VC" then
			vc += 1
		end
	end
	return us, vc
end

-- mesma regra do TeamService (Team_Choose): lado cheio ou que desequilibraria é recusado
local function joinBlocked(f: string): string?
	local us, vc = counts()
	local mine = if f == "US" then us else vc
	local theirs = if f == "US" then vc else us
	local cur = myFaction()
	if cur == f then
		return nil
	elseif cur ~= nil then
		theirs -= 1
	end
	if mine >= Roles.TEAM_MAX then
		return "LOTADO"
	elseif mine > theirs then
		return "EM EXCESSO"
	end
	return nil
end

local function notify(msg: string)
	Toast.show(msg, "info", { title = "Preparação", key = "preparacao" })
end

local function chooseFaction(f: string)
	if myFaction() == f then
		browsing = false -- o mesmo lado: segue o caminho
		DeployScreen.changed()
		return
	end
	local why = joinBlocked(f)
	if why then
		notify(
			if why == "LOTADO"
				then "Este lado está lotado: o servidor deve recusar."
				else "Este lado está em excesso: o servidor deve recusar."
		)
	end
	Net.event("Team_Choose"):FireServer(f)
end

local function findSquad(st: any, sid: string): any
	if st and type(st.squads) == "table" then
		for _, s in st.squads do
			if s.id == sid then
				return s
			end
		end
	end
	return nil
end

-- unidade pelo nome do grupo no id ("US:Alfa"), enquanto o Squad_State não chega
local function unitOfSquad(f: string, sid: string): string?
	local name = string.match(sid, ":(.+)$")
	if not name then
		return nil
	end
	for unit, def in Roles.units[f] do
		if table.find(def.names, name) then
			return unit
		end
	end
	return nil
end

-- D-108/D-211: a arma principal da classe: fica no perfil e vale no próximo nascimento (a classe de
-- agora troca o equipamento no servidor, sem os +15 s)
local function swapPrimary(id: string, nextId: string)
	local f = myFaction()
	if not f or not table.find(Roles.primaries(f, id), nextId) or primaryOf(f, id) == nextId then
		return
	end
	primaryPref[id] = nextId
	Net.event("Arma_Escolher"):FireServer(f, id, nextId)
	if id == currentRole() then
		local w = Weapons.get(nextId)
		notify(string.format("%s no próximo nascimento.", if w then w.name else nextId))
	end
	DeployScreen.changed()
end

local function chooseRole(id: string)
	if id == currentRole() then
		DeployScreen.open("insert") -- a mesma classe: sem os +15 s
		return
	end
	local f = myFaction()
	Net.event("Role_Choose"):FireServer(id, if f then primaryOf(f, id) else nil)
end

-- ===== a tela =====
local view = Preparacao.novo(root, {
	lado = myFaction,
	escolherLado = chooseFaction,
	abrir = function(nome: string)
		DeployScreen.open(nome)
	end,
	voltar = function()
		DeployScreen.back()
	end,
	menu = function()
		Bus.fire("menu_principal_open") -- D-237: o botão MENU da barra de baixo
	end,
	avisar = notify,
	primaria = primaryOf,
	trocarPrimaria = swapPrimary,
	escolherPapel = chooseRole,
	papelAtual = currentRole,
	temSquad = hasSquad,
	bloqueioDoLado = joinBlocked,
	contagem = counts,
	acharSquad = findSquad,
	unidadeDoSquad = unitOfSquad,
})
DeployScreen.pe = view.pe -- a barra de baixo: no passo 04 o GameUI põe o NASCER nela
DeployScreen.resumo = view.resumo

-- st: último Squad_State (ou nil). Só desenha com a tela visível (o GameUI controla Visible).
local ultimoSt: any = nil
function DeployScreen.render(st: any)
	if not root.Visible then
		if wasVisible then
			view.resetar()
			Bus.fire("insercao_painel", false)
		end
		wasVisible = false
		return
	end
	if not wasVisible then
		wasVisible = true
		panel = defaultPanel()
		view.resetar()
	end
	local f = myFaction()
	if st and st.faction ~= f then
		st = nil -- estado do lado antigo (troca de lado): espera o do lado novo
	end
	ultimoSt = st
	-- passo que perdeu o pré-requisito (saiu do grupo, classe limpa, nasceu)
	if panel == "role" and not hasSquad() then
		panel = "squad"
	elseif panel == "insert" and not (hasSquad() and currentRole() and not alive()) then
		panel = if not hasSquad() then "squad" else "role"
	end
	local escolhendo = onChoose()
	local passo = if escolhendo then "lado" else panel
	view.render(passo, f, st, if escolhendo then isBrowsing() else true)
	Bus.fire("insercao_painel", not escolhendo and panel == "insert") -- D-103: Controllers/CompraVeiculo
end

-- passo aberto agora (o GameUI abre a carta de spawn em "insert")
function DeployScreen.panel(): string
	if not root.Visible or onChoose() then
		return "desk"
	end
	return panel
end

-- Abre um passo, com os pré-requisitos do caminho até o campo.
function DeployScreen.open(name: string)
	if name == "faction" then
		if myFaction() then
			browsing, browsingFaction = true, myFaction()
		end
		DeployScreen.changed()
		return
	end
	if not myFaction() then
		return
	end
	browsing = false
	if name == "desk" then
		name = "role" -- a carta volta para a classe
	end
	if name == "role" and not hasSquad() then
		notify("Primeiro escolha um grupo.")
		name = "squad"
	elseif name == "insert" then
		if not hasSquad() then
			notify("Primeiro escolha um grupo.")
			name = "squad"
		elseif not currentRole() then
			notify("Escolha a classe antes de nascer.")
			name = "role"
		elseif alive() then
			notify("Você já está em campo.")
			return
		end
	end
	panel = name
	DeployScreen.changed()
end

-- B / VOLTAR: um passo para trás; devolve true se tratou
function DeployScreen.back(): boolean
	if not root.Visible then
		return false
	end
	if onChoose() then
		if isBrowsing() then
			browsing = false
			DeployScreen.changed()
			return true
		end
		return false
	end
	if panel == "insert" then
		panel = "role"
	elseif panel == "role" then
		panel = "squad"
	else
		browsing, browsingFaction = true, myFaction()
	end
	DeployScreen.changed()
	return true
end

-- LB/RB (Q/E): o passo seguinte ou o anterior
local CYCLE = { "squad", "role", "insert" }
function DeployScreen.cycle(dir: number)
	if not root.Visible or onChoose() then
		return
	end
	local i = table.find(CYCLE, panel) or 1
	DeployScreen.open(CYCLE[(i - 1 + dir) % #CYCLE + 1])
end

-- ===== atributos: o caminho avança sozinho =====
player:GetAttributeChangedSignal("SquadId"):Connect(function()
	if hasSquad() then
		if panel == "squad" then
			panel = "role"
		end
	elseif panel == "role" or panel == "insert" then
		panel = "squad"
	end
	DeployScreen.changed()
end)
player:GetAttributeChangedSignal("Role"):Connect(function()
	if currentRole() and panel == "role" and not alive() then
		panel = "insert"
	end
	DeployScreen.changed()
end)
player:GetAttributeChangedSignal("Faction"):Connect(function()
	browsing, browsingFaction = false, nil
	table.clear(primaryPref)
	panel = "squad" -- lado novo: o próximo passo é o grupo
	DeployScreen.changed()
end)
player:GetAttributeChangedSignal("ArmasPreferidas"):Connect(function()
	if root.Visible and panel == "role" then
		DeployScreen.changed()
	end
end)

-- efetivo dos lados: uma vez por segundo com a tela aberta
task.spawn(function()
	while true do
		task.wait(1)
		if root.Visible and onChoose() then
			view.render("lado", myFaction(), ultimoSt, isBrowsing())
		end
	end
end)

-- ===== gancho de teste (só no Studio) =====
-- workspace:SetAttribute("VT65DevTela", x), com o jogador sem corpo em campo:
--   - "escolha": o passo que falta; "lado", "squad", "papel": aquele passo;
--   - "insercao": completa o caminho pelos remotes (EUA, grupo de infantaria, fuzileiro) e abre a carta.
-- "carregamento" é da tela de entrada (LoadingScreen) e "transicao", do SpawnTransition.
if RunService:IsStudio() then
	local function waitAttr(name: string, seconds: number): boolean
		local t0 = os.clock()
		while player:GetAttribute(name) == nil and os.clock() - t0 < seconds do
			task.wait(0.1)
		end
		return player:GetAttribute(name) ~= nil
	end
	local function devInsertion()
		if not myFaction() then
			Net.event("Team_Choose"):FireServer("US")
			if not waitAttr("Faction", 5) then
				warn("[VT65] VT65DevTela insercao: o servidor não deu lado")
				return
			end
		end
		if not hasSquad() then
			Net.event("Squad_Action"):FireServer({ op = "create", unit = "infantry" })
			if not waitAttr("SquadId", 5) then
				warn("[VT65] VT65DevTela insercao: o servidor não deu grupo")
				return
			end
		end
		if not currentRole() then
			Net.event("Role_Choose"):FireServer("rifleman")
			if not waitAttr("Role", 5) then
				warn("[VT65] VT65DevTela insercao: o servidor não deu classe")
				return
			end
		end
		task.wait(0.2) -- deixa o refresh do GameUI rodar com a classe nova
		DeployScreen.open("insert")
	end
	local DEV_PANEL: { [string]: string } = { squad = "squad", papel = "role" }
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if type(v) ~= "string" or v == "carregamento" or v == "transicao" then
			return
		end
		if v == "escolha" then
			if not myFaction() then
				DeployScreen.changed()
			elseif not hasSquad() then
				DeployScreen.open("squad")
			else
				DeployScreen.open("role")
			end
		elseif v == "lado" then
			if myFaction() then
				DeployScreen.open("faction")
			else
				DeployScreen.changed()
			end
		elseif DEV_PANEL[v] then
			DeployScreen.open(DEV_PANEL[v])
		elseif v == "insercao" then
			task.spawn(devInsertion)
		else
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil) -- local: no cliente, o mesmo valor repete
		end)
	end)
end

return DeployScreen
