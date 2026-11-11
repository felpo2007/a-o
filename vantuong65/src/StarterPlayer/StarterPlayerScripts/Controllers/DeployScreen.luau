--!strict
-- Tela de deslocamento (lobby; Partes 4 e 12.5), em tela cheia, com identidade própria de dossiê de
-- operações de 1965: pasta parda, fichas de arquivo pautadas, carimbos, texto de máquina de escrever
-- (SpecialElite) e títulos condensados (Oswald). Sem bandeiras nem símbolos (LANCAMENTO.md).
-- Passos: 1 LADO → 2 SQUAD → 3 PAPEL → 4 INSERÇÃO (o mapa de spawn do GameUI fica à direita).
-- Construída uma vez: render() só troca textos, cores e visibilidade. Os cartões ficam num
-- reservatório por chave, então o foco do controle não pula quando chega um Squad_State.
-- Só dados reais: Roles (unidades, papéis e armas), Weapons (nome e cartucho), MapConfig (QG e grade
-- de 1965) e o efetivo contado pelo atributo "Faction" dos jogadores (a mesma conta do TeamService).
-- Remotes (os mesmos de antes): Team_Choose, Squad_Action {op = create/join/leave} e Role_Choose.
-- Controle: A escolhe (navegação do Roblox), B volta (ui_back, ligado no GameUI): squad → lado,
-- papel → cancela a troca de papel ou sai do squad. Mouse e toque: botão "VOLTAR" no rodapé.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Input = require(script.Parent.Input)
local SoldierPreview = require(script.Parent.SoldierPreview)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local DeployScreen = {}

-- ===== estilo =====
local HEAD = Enum.Font.Oswald -- títulos condensados
local TYPE = Enum.Font.SpecialElite -- máquina de escrever
local INK, CARD, MANILA, DRAB, KHAKI, STAMP = UiKit.INK, UiKit.CARD, UiKit.MANILA, UiKit.DRAB, UiKit.KHAKI, UiKit.STAMP
local CARD_HOT = Color3.fromRGB(250, 244, 226) -- ficha em foco / sob o mouse
local CARD_OFF = Color3.fromRGB(196, 188, 164) -- ficha cheia ou trancada
local NEW_CARD = Color3.fromRGB(222, 206, 162) -- "formar squad"
local MANILA_HOT = Color3.fromRGB(206, 184, 136)
local OLIVE_INK = Color3.fromRGB(58, 82, 44) -- carimbo verde ("ABERTO", "ATUAL")
local NOTICE = Color3.fromRGB(238, 132, 104)

local UNIT_ORDER = { "infantry", "command", "recon", "sapper", "mortar", "armor", "helicopter" }
local UNIT_NAME: { [string]: string } = {
	command = "Comando",
	infantry = "Infantaria",
	recon = "Reconhecimento",
	sapper = "Sapadores",
	mortar = "Morteiro",
	armor = "Blindado",
	helicopter = "Helicóptero",
}
local ROLE_ORDER = {
	"squad_leader",
	"rifleman",
	"grenadier",
	"machine_gunner",
	"anti_tank",
	"engineer",
	"medic",
	"radio_operator",
	"commander",
	"observer",
	"sniper",
	"sapper",
	"mortar",
	"tank_crew",
	"pilot",
	"door_gunner",
}

-- textos das facções: nomes e unidades de Starlite (research/F0_FONTES.md: RLT-7 com 3/3, 2/4 e 3/7;
-- o 1º Regimento VC, força principal); uniforme como o Characters veste por padrão
type FactionInfo = { stamp: string, stampSize: number, title: string, unit: string, short: string, kit: string }
local FACTION: { [string]: FactionInfo } = {
	US = {
		stamp = "USMC",
		stampSize = 34,
		title = "FUZILEIROS NAVAIS DOS EUA",
		unit = "RLT-7 · batalhões 3/3, 2/4 e 3/7",
		short = "EUA",
		kit = "Uniforme OG-107 · capacete M1 · colete M1955",
	},
	VC = {
		stamp = "QUÂN GIẢI PHÓNG",
		stampSize = 22,
		title = "1º REGIMENTO VIET CONG",
		unit = "Força principal",
		short = "VC",
		kit = "Uniforme cáqui",
	},
}

local function ordered(keys: { [string]: any }, pref: { string }): { string }
	local out = {}
	for _, k in pref do
		if keys[k] ~= nil then
			table.insert(out, k)
		end
	end
	local extra = {}
	for k in keys do
		if not table.find(pref, k) then
			table.insert(extra, k)
		end
	end
	table.sort(extra)
	for _, k in extra do
		table.insert(out, k)
	end
	return out
end
local UNITS_OF: { [string]: { string } } = {
	US = ordered(Roles.units.US, UNIT_ORDER),
	VC = ordered(Roles.units.VC, UNIT_ORDER),
}
local ROLE_IDS = ordered(Roles.roles, ROLE_ORDER)

-- grade de 1965 (6 algarismos) de um ponto do mapa, pela origem do MapConfig
local function gridRef(x: number, z: number): string
	local g = MapConfig.GridOrigin1965
	local e = g.e + x * MapConfig.STUD_M
	local n = g.n - z * MapConfig.STUD_M
	return string.format("BS %03d%03d", math.floor((e % 100000) / 100), math.floor((n % 100000) / 100))
end

local function weaponLine(id: string): string
	local w = Weapons.get(id)
	return if w then w.name else id
end

local function weaponNames(list: { string }?): string
	if not list then
		return "—"
	end
	local names = {}
	for _, id in list do
		table.insert(names, weaponLine(id))
	end
	return table.concat(names, " + ")
end

local function keyName(code: string): string
	return (string.gsub(code, "^Button", ""))
end

-- ===== tamanho de texto (projeto 1280 x 720; na TV, nunca abaixo de 24 px na tela) =====
local scale = 1
local texts: { { o: any, s: number } } = {}
local function reg(o: any, s: number)
	table.insert(texts, { o = o, s = s })
	o.TextSize = UiKit.textAt(s, scale)
end

function DeployScreen.setScale(k: number)
	scale = k
	for _, e in texts do
		e.o.TextSize = UiKit.textAt(e.s, k)
	end
end

-- ===== peças =====
local function box(parent: Instance?, color: Color3, x: number, y: number, w: number, h: number, tr: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = tr or 0
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Parent = parent
	return f
end

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thick: number, tr: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.Transparency = tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function txt(
	parent: Instance,
	font: Enum.Font,
	size: number,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	align: Enum.TextXAlignment?
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = font
	t.TextColor3 = color
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Text = ""
	t.Parent = parent
	reg(t, size)
	return t
end

-- carimbo de borracha: texto e moldura na mesma tinta, um pouco torto
local function stamp(parent: Instance, size: number, x: number, y: number, w: number, h: number, rot: number): TextLabel
	local t = txt(parent, HEAD, size, STAMP, x, y, w, h, Enum.TextXAlignment.Center)
	t.Rotation = rot
	t.TextTransparency = 0.12
	t.ZIndex = 3
	stroke(t, STAMP, 3, 0.18)
	return t
end

local function inkStamp(t: TextLabel, color: Color3)
	t.TextColor3 = color
	local s = t:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = color
	end
end

local function hline(parent: Instance, color: Color3, x: number, y: number, w: number, tr: number?)
	box(parent, color, x, y, w, 2, tr)
end

-- papel com luz de cima (o UIGradient só pinta o próprio objeto, não os filhos)
local function paper(parent: Instance, rot: number)
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(212, 206, 192))
	g.Parent = parent
end

local function cardButton(parent: Instance?, w: number, h: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(w, h)
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = parent
	return b
end

-- realce do mouse e do foco do controle (o foco também ganha a moldura amarela UiKit.FOCUS)
local function hover(b: GuiButton, fn: (on: boolean) -> ())
	local over, sel = false, false
	local function apply()
		fn(over or sel)
	end
	b.MouseEnter:Connect(function()
		over = true
		apply()
	end)
	b.MouseLeave:Connect(function()
		over = false
		apply()
	end)
	b.SelectionGained:Connect(function()
		sel = true
		apply()
	end)
	b.SelectionLost:Connect(function()
		sel = false
		apply()
	end)
end

local function scroller(parent: Instance, x: number, y: number, w: number, h: number): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Position = UDim2.fromOffset(x, y)
	s.Size = UDim2.fromOffset(w, h)
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = INK
	s.Selectable = false -- o foco vai nos cartões, nunca na rolagem
	s.Parent = parent
	return s
end

-- pasta parda com aba datilografada; devolve a pasta e a linha de informação à direita da aba
local function folder(parent: Instance, tab: string, w: number): (Frame, TextLabel)
	local f = box(parent, MANILA, 0, 0, w, 536)
	corner(f, 4)
	paper(f, 80)
	stroke(f, INK, 1, 0.75)
	local t = box(f, DRAB, 16, 12, 250, 32)
	corner(t, 2)
	local tt = txt(t, TYPE, 16, KHAKI, 12, 0, 226, 32)
	tt.Text = tab
	local info = txt(f, TYPE, 16, INK, 280, 12, w - 296, 32, Enum.TextXAlignment.Right)
	return f, info
end

-- ===== raiz =====
local root = Instance.new("Frame")
root.Name = "Deploy"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Visible = false
DeployScreen.root = root
DeployScreen.changed = function() end -- o GameUI troca pelo refresh()

-- cabeçalho
local title = txt(root, HEAD, 40, CARD, 40, 8, 600, 48)
title.Text = "VẠN TƯỜNG '65"
local subtitle = txt(root, TYPE, 16, KHAKI, 40, 54, 700, 22)
subtitle.Text = "OPERAÇÃO STARLITE · 18–24 AGO 1965 · ORDEM DE DESLOCAMENTO"
local posLine = txt(root, TYPE, 16, KHAKI, 700, 14, 540, 22, Enum.TextXAlignment.Right)
local teamLine = txt(root, TYPE, 16, KHAKI, 700, 40, 540, 22, Enum.TextXAlignment.Right)
box(root, KHAKI, 40, 80, 1200, 1, 0.55)

-- passos
local STEPS = { "LADO", "SQUAD", "PAPEL", "INSERÇÃO" }
local STEP_INDEX: { [string]: number } = { faction = 1, squad = 2, role = 3, insert = 4 }
local stepBoxes: { { f: Frame, t: TextLabel, s: UIStroke } } = {}
for i, name in STEPS do
	local x = 40 + (i - 1) * 165
	local f = box(root, DRAB, x, 88, 150, 30)
	local s = stroke(f, KHAKI, 1, 0.5)
	local t = txt(f, HEAD, 17, KHAKI, 0, 0, 150, 30, Enum.TextXAlignment.Center)
	t.Text = string.format("%d · %s", i, name)
	if i < #STEPS then
		box(root, KHAKI, x + 152, 102, 11, 2, 0.4)
	end
	stepBoxes[i] = { f = f, t = t, s = s }
end

-- aviso curto (recusa prevista, vaga ocupada); some sozinho
local notice = txt(root, TYPE, 16, NOTICE, 700, 106, 540, 20, Enum.TextXAlignment.Right)
local noticeToken = 0
local function notify(msg: string)
	noticeToken += 1
	local my = noticeToken
	notice.Text = msg
	task.delay(6, function()
		if noticeToken == my then
			notice.Text = ""
		end
	end)
end

-- páginas (só a ativa fica na árvore: o foco automático nunca cai numa página escondida)
local function page(): Frame
	local p = Instance.new("Frame")
	p.BackgroundTransparency = 1
	p.Position = UDim2.fromOffset(40, 128)
	p.Size = UDim2.fromOffset(1200, 536)
	return p
end
local pages: { [string]: Frame } = {
	faction = page(),
	squad = page(),
	role = page(),
	insert = page(),
}

-- ===== estado =====
-- B no passo do squad volta a mostrar os lados; vale só enquanto o lado não muda (sem depender da
-- ordem dos sinais de atributo)
local browsing = false
local browsingFaction: string? = nil
local lastRole: string? = nil -- último papel confirmado pelo servidor (para cancelar a troca)
local lastRoleSquad: any = nil
local previewRole: string? = nil
local shownStep = ""

local function myFaction(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" and FACTION[f] then f else nil
end

local function isBrowsing(): boolean
	return browsing and browsingFaction ~= nil and browsingFaction == myFaction()
end

local function currentStep(): string
	if not myFaction() or isBrowsing() then
		return "faction"
	elseif not player:GetAttribute("SquadId") then
		return "squad"
	elseif not player:GetAttribute("Role") then
		return "role"
	end
	return "insert"
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

-- ===== passo 1: lado =====
type FCard = {
	btn: TextButton,
	preview: SoldierPreview.Preview,
	count: TextLabel,
	avail: TextLabel,
	cta: Frame,
	ctaText: TextLabel,
}
local fcards: { [string]: FCard } = {}

local function chooseFaction(f: string)
	if myFaction() == f then
		browsing = false -- o mesmo lado: só volta ao squad
		DeployScreen.changed()
		return
	end
	local why = joinBlocked(f)
	if why then
		notify("Este lado está " .. string.lower(why) .. ": o servidor deve recusar.")
	end
	Net.event("Team_Choose"):FireServer(f)
end

local function unitsText(f: string): string
	local lines = {}
	local heavy = false
	for _, unit in UNITS_OF[f] do
		local def = Roles.units[f][unit]
		local name = UNIT_NAME[unit] or unit
		local line = if def.size == 1
			then string.format("%s: 1 vaga", name)
			elseif def.count > 1 then string.format("%s: %d squads de %d", name, def.count, def.size)
			else string.format("%s: 1 squad de %d", name, def.size)
		if def.heavy then
			line ..= " *"
			heavy = true
		end
		table.insert(lines, line)
	end
	if heavy then
		table.insert(lines, string.format("* abre com %d no time", Roles.HEAVY_UNLOCK))
	end
	return table.concat(lines, "\n")
end

local function factionCard(f: string, x: number, tab: string): FCard
	local info = FACTION[f]
	local hq = MapConfig.HQ[f]
	local b = cardButton(pages.faction, 590, 536, MANILA)
	b.Position = UDim2.fromOffset(x, 0)
	corner(b, 4)
	paper(b, 75)
	local tabT = txt(b, TYPE, 16, INK, 24, 12, 300, 26)
	tabT.Text = tab
	tabT.TextTransparency = 0.25
	stamp(b, info.stampSize, 330, 10, 236, 42, -5).Text = info.stamp
	-- retrato (cópia fotográfica com margem)
	local photo = box(b, CARD, 24, 56, 236, 300)
	stroke(photo, INK, 1, 0.7)
	local pv = SoldierPreview.new(0.2, if f == "US" then -0.5 else 0.5)
	pv.frame.Position = UDim2.fromOffset(10, 10)
	pv.frame.Size = UDim2.fromOffset(216, 240)
	pv.frame.Parent = photo
	reg(pv.note, 16)
	SoldierPreview.set(pv, f, nil)
	local cap = txt(photo, TYPE, 16, INK, 10, 252, 216, 44, Enum.TextXAlignment.Center)
	cap.Text = string.format("%s · %s", Roles.roles.rifleman.name, weaponLine(Roles.loadout[f].rifleman[1]))
	local kit = txt(b, TYPE, 16, INK, 24, 362, 236, 46)
	kit.TextYAlignment = Enum.TextYAlignment.Top
	kit.Text = info.kit
	local count = txt(b, HEAD, 30, INK, 24, 414, 236, 44)
	local avail = stamp(b, 20, 136, 300, 140, 38, -8)
	-- coluna da direita
	local t = txt(b, HEAD, 30, INK, 280, 62, 286, 80)
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Text = info.title
	local u = txt(b, TYPE, 16, INK, 280, 144, 286, 42)
	u.TextYAlignment = Enum.TextYAlignment.Top
	u.Text = info.unit
	hline(b, UiKit.RULE_RED, 280, 188, 286)
	local qg = txt(b, TYPE, 16, INK, 280, 196, 286, 60)
	qg.TextYAlignment = Enum.TextYAlignment.Top
	qg.Text = string.format("QG %s · %s", gridRef(hq.x, hq.z), hq.note)
	local uh = txt(b, HEAD, 18, INK, 280, 258, 286, 22)
	uh.Text = "UNIDADES"
	local units = txt(b, TYPE, 16, INK, 280, 282, 286, 150)
	units.TextYAlignment = Enum.TextYAlignment.Top
	units.Text = unitsText(f)
	for i = 1, 6 do -- pauta azul da ficha
		hline(b, UiKit.RULE_BLUE, 280, 280 + i * 19, 286, 0.8)
	end
	local cta = box(b, DRAB, 0, 476, 590, 60)
	local ctaText = txt(cta, HEAD, 26, KHAKI, 0, 0, 590, 60, Enum.TextXAlignment.Center)
	local c: FCard = { btn = b, preview = pv, count = count, avail = avail, cta = cta, ctaText = ctaText }
	hover(b, function(on: boolean)
		b.BackgroundColor3 = if on then MANILA_HOT else MANILA
		cta.BackgroundColor3 = if on then STAMP else DRAB
	end)
	b.Activated:Connect(function()
		chooseFaction(f)
	end)
	return c
end
fcards.US = factionCard("US", 0, "FICHA 1-A · LADO")
fcards.VC = factionCard("VC", 610, "FICHA 1-B · LADO")

local function renderFaction()
	local us, vc = counts()
	local mine = myFaction()
	for f, c in fcards do
		-- jogadores (os bots não contam no equilíbrio do TeamService)
		c.count.Text = string.format("JOGADORES %d/%d", if f == "US" then us else vc, Roles.TEAM_MAX)
		local why = joinBlocked(f)
		if mine == f then
			c.avail.Text = "SEU LADO"
			inkStamp(c.avail, OLIVE_INK)
			c.ctaText.Text = "CONTINUAR ►"
		elseif why then
			c.avail.Text = why
			inkStamp(c.avail, STAMP)
			c.ctaText.Text = "ALISTAR-SE ►"
		else
			c.avail.Text = "ABERTO"
			inkStamp(c.avail, OLIVE_INK)
			c.ctaText.Text = "ALISTAR-SE ►"
		end
	end
end

-- ===== retrato grande (passos 2 e 3) =====
local photoCol = box(root, CARD, 920, 128, 320, 536)
photoCol.Visible = false
stroke(photoCol, INK, 1, 0.6)
paper(photoCol, 90)
local photoSlot = box(photoCol, INK, 14, 14, 292, 350)
local capTitle = txt(photoCol, HEAD, 26, INK, 14, 370, 292, 36)
hline(photoCol, UiKit.RULE_RED, 14, 408, 292)
local capLines = txt(photoCol, TYPE, 16, INK, 14, 414, 292, 116)
capLines.TextYAlignment = Enum.TextYAlignment.Top
for i = 1, 5 do
	hline(photoCol, UiKit.RULE_BLUE, 14, 412 + i * 20, 292, 0.82)
end
local main = SoldierPreview.new(0.24, -0.45)
reg(main.note, 16)
main.frame.Parent = photoSlot

local function caption(f: string, roleId: string?, extra: string?)
	local rid = roleId or "rifleman"
	local r = Roles.roles[rid]
	local lo = Roles.loadout[f][rid]
	capTitle.Text = string.upper(if r then r.name else rid)
	local lines = {}
	if lo then
		for _, id in lo do
			local w = Weapons.get(id)
			table.insert(lines, if w then string.format("%s — %s", w.name, w.cartridge) else id)
		end
	end
	table.insert(lines, FACTION[f].kit)
	if extra then
		table.insert(lines, extra)
	end
	capLines.Text = table.concat(lines, "\n")
end

-- ===== passo 2: squad =====
type SCard = {
	btn: TextButton,
	top: TextLabel,
	mid: TextLabel,
	bottom: TextLabel,
	base: Color3,
	hot: boolean, -- sob o mouse ou com o foco
	action: (() -> ())?,
}
type Row = { frame: Frame, name: TextLabel, detail: TextLabel, holder: Frame, newCard: SCard }

local sFolder, sInfo = folder(pages.squad, "FICHA 2 · SQUAD", 860)
local sScroll = scroller(sFolder, 16, 56, 828, 464)
local sList = Instance.new("UIListLayout")
sList.Padding = UDim.new(0, 10)
sList.SortOrder = Enum.SortOrder.LayoutOrder
sList.Parent = sScroll

local function squadCard(parent: Instance, isNew: boolean): SCard
	local b = cardButton(parent, 116, 96, if isNew then NEW_CARD else CARD)
	corner(b, 3)
	local top = txt(b, HEAD, 20, INK, 8, 2, 100, 28)
	hline(b, UiKit.RULE_RED, 8, 31, 100)
	local mid = if isNew then txt(b, TYPE, 16, INK, 8, 36, 100, 30) else txt(b, HEAD, 30, INK, 8, 34, 100, 34)
	local bottom = txt(b, TYPE, 16, INK, 8, 68, 100, 24)
	if isNew then
		stroke(b, INK, 1, 0.45)
	end
	local c: SCard =
		{ btn = b, top = top, mid = mid, bottom = bottom, base = b.BackgroundColor3, hot = false, action = nil }
	hover(b, function(on: boolean)
		c.hot = on
		b.BackgroundColor3 = if on then CARD_HOT else c.base
	end)
	b.Activated:Connect(function()
		local fn = c.action
		if fn then
			fn()
		end
	end)
	return c
end

local rows: { [string]: Row } = {}
local squadCards: { [string]: SCard } = {}

local function unitRow(): Row
	local fr = Instance.new("Frame")
	fr.BackgroundTransparency = 1
	fr.Size = UDim2.fromOffset(828, 96)
	fr.Parent = sScroll
	local label = box(fr, CARD, 0, 0, 196, 96, 0.12)
	corner(label, 3)
	local name = txt(label, HEAD, 22, INK, 10, 2, 180, 28)
	hline(label, UiKit.RULE_RED, 10, 31, 176)
	local detail = txt(label, TYPE, 16, INK, 10, 36, 180, 58)
	detail.TextYAlignment = Enum.TextYAlignment.Top
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(206, 0)
	holder.Size = UDim2.fromOffset(622, 96)
	holder.Parent = fr
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.Padding = UDim.new(0, 8)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = holder
	local nc = squadCard(holder, true)
	nc.btn.LayoutOrder = 99
	return { frame = fr, name = name, detail = detail, holder = holder, newCard = nc }
end

-- devolve o cartão preferido para o foco (o 1º squad com vaga ou o "formar" da infantaria)
local function renderSquad(f: string, st: any): GuiObject?
	local size: number? = if st and type(st.size) == "number" then st.size else nil
	local squads: { any } = if st and type(st.squads) == "table" then st.squads else {}
	sInfo.Text = if size
		then string.format(
			"Jogadores %s %d/%d · pesados abrem com %d",
			FACTION[f].short,
			size,
			Roles.TEAM_MAX,
			Roles.HEAVY_UNLOCK
		)
		else "Recebendo os squads do servidor…"
	for _, r in rows do
		r.frame.Visible = false
	end
	for _, c in squadCards do
		c.btn.Visible = false
	end
	local preferred: GuiObject? = nil
	local fallback: GuiObject? = nil
	for order, unit in UNITS_OF[f] do
		local def = Roles.units[f][unit]
		local key = f .. ":" .. unit
		local row = rows[key]
		if not row then
			row = unitRow()
			rows[key] = row
		end
		row.frame.Visible = true
		row.frame.LayoutOrder = order
		row.name.Text = string.upper(UNIT_NAME[unit] or unit)
		local locked = def.heavy and (size == nil or size < Roles.HEAVY_UNLOCK)
		local detail = if def.size == 1 then "1 vaga" else string.format("Squads de %d · até %d", def.size, def.count)
		if def.heavy then
			detail ..= if locked
				then string.format(
					"\nAbre com %d no time%s",
					Roles.HEAVY_UNLOCK,
					if size then string.format(" (agora %d)", size) else ""
				)
				else "\nLiberado"
		end
		row.detail.Text = detail
		local used: { [string]: boolean } = {}
		for _, s in squads do
			if s.unit == unit and type(s.id) == "string" then
				used[s.name] = true
				local c = squadCards[s.id]
				if not c then
					c = squadCard(row.holder, false)
					squadCards[s.id] = c
				end
				local card = c :: SCard
				local n = if type(s.members) == "table" then #s.members else 0
				local full = n >= def.size
				card.btn.Visible = true
				card.btn.LayoutOrder = table.find(def.names, s.name) or 50
				card.top.Text = tostring(s.name)
				card.mid.Text = string.format("%d/%d", n, def.size)
				card.bottom.Text = if full then "CHEIO" else "ENTRAR"
				card.base = if full then CARD_OFF else CARD
				card.btn.BackgroundColor3 = if card.hot then CARD_HOT else card.base
				local id = s.id
				card.action = function()
					if full then
						notify("Squad cheio: o servidor deve recusar.")
					end
					Net.event("Squad_Action"):FireServer({ op = "join", id = id })
				end
				if not full and not preferred then
					preferred = card.btn
				end
			end
		end
		local nextName: string? = nil
		for _, nm in def.names do
			if not used[nm] then
				nextName = nm
				break
			end
		end
		local nc = row.newCard
		nc.btn.Visible = nextName ~= nil
		if nextName then
			nc.top.Text = "+ NOVO"
			nc.mid.Text = nextName
			nc.bottom.Text = if locked then "TRANCADO" else "FORMAR"
			nc.base = if locked then CARD_OFF else NEW_CARD
			nc.btn.BackgroundColor3 = if nc.hot then CARD_HOT else nc.base
			nc.btn.Selectable = not locked
			nc.action = function()
				if locked then
					notify(string.format("Unidade pesada: abre com %d no time.", Roles.HEAVY_UNLOCK))
					return
				end
				Net.event("Squad_Action"):FireServer({ op = "create", unit = unit })
			end
			if not locked and not fallback then
				fallback = nc.btn
			end
		end
	end
	caption(f, nil, "Retrato padrão do lado")
	return preferred or fallback
end

-- ===== passo 3: papel =====
type RCard = {
	btn: TextButton,
	name: TextLabel,
	weapons: TextLabel,
	slots: TextLabel,
	mark: TextLabel,
	base: Color3,
	hot: boolean,
	blocked: string?,
}
local rFolder, rInfo = folder(pages.role, "FICHA 3 · PAPEL", 860)
local rScroll = scroller(rFolder, 16, 56, 828, 464)
local rGrid = Instance.new("UIGridLayout")
rGrid.CellSize = UDim2.fromOffset(196, 150)
rGrid.CellPadding = UDim2.fromOffset(10, 10)
rGrid.SortOrder = Enum.SortOrder.LayoutOrder
rGrid.Parent = rScroll
local roleCards: { [string]: RCard } = {}

local function showRole(id: string?)
	local f = myFaction()
	if not f then
		return
	end
	previewRole = id
	local lo = if id then Roles.loadout[f][id] else nil
	SoldierPreview.set(main, f, if lo then lo[1] else nil)
	local sid = player:GetAttribute("SquadId")
	local squadName = if type(sid) == "string" then string.match(sid, ":(.+)$") else nil
	caption(f, id, if squadName then "Squad " .. squadName else nil)
end

local function chooseRole(id: string)
	local c = roleCards[id]
	if c and c.blocked then
		notify(c.blocked .. ": o servidor deve recusar.")
	end
	local sid = player:GetAttribute("SquadId")
	if id == lastRole and sid == lastRoleSquad and player:GetAttribute("Role") == nil then
		-- o mesmo papel de antes da troca: o servidor ainda o tem e não mandaria mudança de atributo;
		-- só desfaz a troca local (sem os +15 s)
		player:SetAttribute("Role", id)
		return
	end
	Net.event("Role_Choose"):FireServer(id)
end

local function roleCard(id: string): RCard
	local b = cardButton(rScroll, 196, 150, CARD)
	corner(b, 3)
	for i = 1, 3 do -- pauta azul
		hline(b, UiKit.RULE_BLUE, 10, 82 + i * 22, 176, 0.8)
	end
	local name = txt(b, HEAD, 20, INK, 10, 4, 176, 48)
	name.TextYAlignment = Enum.TextYAlignment.Top
	hline(b, UiKit.RULE_RED, 10, 54, 176)
	local weapons = txt(b, TYPE, 16, INK, 10, 60, 176, 52)
	weapons.TextYAlignment = Enum.TextYAlignment.Top
	local slots = txt(b, TYPE, 16, INK, 10, 118, 176, 26, Enum.TextXAlignment.Right)
	local mark = stamp(b, 18, 24, 56, 148, 36, -9)
	mark.Visible = false
	local c: RCard =
		{ btn = b, name = name, weapons = weapons, slots = slots, mark = mark, base = CARD, hot = false, blocked = nil }
	hover(b, function(on: boolean)
		c.hot = on
		b.BackgroundColor3 = if on then CARD_HOT else c.base
		if on then
			showRole(id)
		end
	end)
	b.Activated:Connect(function()
		chooseRole(id)
	end)
	return c
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

-- unidade pelo nome do squad no id ("US:Alfa"), enquanto o Squad_State não chega
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

local function renderRole(f: string, st: any, sid: string): GuiObject?
	local sq = findSquad(st, sid)
	local unit: string? = if sq then sq.unit else unitOfSquad(f, sid)
	local def = if unit then Roles.units[f][unit] else nil
	local me = player.UserId
	local leaderText = ""
	if sq and sq.leader then
		local lp = Players:GetPlayerByUserId(sq.leader)
		leaderText = if sq.leader == me then " · líder: você" elseif lp then " · líder: " .. lp.DisplayName else ""
	end
	local squadName = string.match(sid, ":(.+)$") or sid
	rInfo.Text = string.format(
		"Squad %s · %s%s%s",
		squadName,
		if unit then UNIT_NAME[unit] or unit else "?",
		if sq and def then string.format(" · %d de %d", #sq.members, def.size) else "",
		leaderText
	)
	local restoring = lastRole ~= nil and lastRoleSquad == sid
	local preferred: GuiObject? = nil
	local firstFree: GuiObject? = nil
	local firstId: string? = nil
	for order, id in ROLE_IDS do
		local r = Roles.roles[id]
		local lo = Roles.loadout[f][id]
		local show = unit ~= nil and r.unit == unit and lo ~= nil
		local c = roleCards[id]
		if show and not c then
			c = roleCard(id)
			roleCards[id] = c
		end
		if c then
			local card = c :: RCard
			card.btn.Visible = show
			if show then
				card.btn.LayoutOrder = order
				card.name.Text = string.upper(r.name)
				card.weapons.Text = weaponNames(lo)
				local max = r.maxPerSquad
				local free: number? = nil
				if max then
					local taken = 0
					if sq and type(sq.roles) == "table" then
						for uid, rr in sq.roles do
							if rr == id and tostring(uid) ~= tostring(me) then
								taken += 1
							end
						end
					end
					free = max - taken
					card.slots.Text = if sq
						then string.format("VAGA %d/%d", math.max(free or 0, 0), max)
						else "VAGA ?/" .. max
				else
					card.slots.Text = "LIVRE"
				end
				local blocked: string? = nil
				if id == "squad_leader" and sq and sq.leader ~= me then
					blocked = "SÓ O LÍDER"
				elseif free ~= nil and sq and free <= 0 then
					blocked = "OCUPADO"
				end
				card.blocked = blocked
				local current = restoring and lastRole == id
				card.mark.Visible = blocked ~= nil or current
				if blocked then
					card.mark.Text = blocked
					inkStamp(card.mark, STAMP)
				elseif current then
					card.mark.Text = "ATUAL"
					inkStamp(card.mark, OLIVE_INK)
				end
				card.base = if blocked then CARD_OFF else CARD
				card.btn.BackgroundColor3 = if card.hot then CARD_HOT else card.base
				if not firstId then
					firstId = id
				end
				if current then
					preferred = card.btn
				end
				if not blocked and not firstFree then
					firstFree = card.btn
				end
			end
		end
	end
	local pick = preferred or firstFree
	-- retrato: o papel em foco; ao entrar no passo, o atual (troca) ou o primeiro livre
	if not (previewRole and roleCards[previewRole] and roleCards[previewRole].btn.Visible) then
		local id: string? = nil
		for rid, c in roleCards do
			if c.btn == pick then
				id = rid
			end
		end
		previewRole = id or firstId
	end
	showRole(previewRole)
	return pick
end

-- ===== passo 4: inserção (o mapa do GameUI fica à direita) =====
local iFolder, iInfo = folder(pages.insert, "FICHA 4 · INSERÇÃO", 370)
iInfo.Visible = false
local iPhoto = box(iFolder, CARD, 16, 52, 338, 268)
stroke(iPhoto, INK, 1, 0.7)
local iSlot = box(iPhoto, INK, 10, 10, 318, 212)
local iCaption = txt(iPhoto, HEAD, 22, INK, 10, 226, 318, 36, Enum.TextXAlignment.Center)
local iLines = txt(iFolder, TYPE, 16, INK, 16, 332, 338, 196)
iLines.TextYAlignment = Enum.TextYAlignment.Top

local function renderInsert(f: string)
	local role = player:GetAttribute("Role")
	local rid = if type(role) == "string" then role else "rifleman"
	local r = Roles.roles[rid]
	local lo: { string }? = nil
	local loAttr = player:GetAttribute("Loadout")
	if type(loAttr) == "string" and loAttr ~= "" then
		lo = string.split(loAttr, ",")
	else
		lo = Roles.loadout[f][rid]
	end
	SoldierPreview.set(main, f, if lo then lo[1] else nil)
	local sid = player:GetAttribute("SquadId")
	local squadName = if type(sid) == "string" then (string.match(sid, ":(.+)$") or sid) else "—"
	local unit = if type(sid) == "string" then unitOfSquad(f, sid) else nil
	local hq = MapConfig.HQ[f]
	iCaption.Text = string.upper(if r then r.name else rid)
	local _, padText = Input.glyph("map_role", "map")
	iLines.Text = table.concat({
		"SQUAD  " .. squadName .. (if unit then " (" .. (UNIT_NAME[unit] or unit) .. ")" else ""),
		"ARMAS  " .. weaponNames(lo),
		"QG     " .. gridRef(hq.x, hq.z),
		"",
		"Escolha na carta um ponto PRONTO.",
		string.format("Trocar de papel: %s (+15 s)", keyName(padText)),
	}, "\n")
end

-- ===== rodapé: dicas de botão e "VOLTAR" para mouse e toque =====
local hints = Instance.new("Frame")
hints.BackgroundTransparency = 1
hints.Position = UDim2.fromOffset(40, 676)
hints.Size = UDim2.fromOffset(900, 36)
hints.Parent = root
local hl = Instance.new("UIListLayout")
hl.FillDirection = Enum.FillDirection.Horizontal
hl.Padding = UDim.new(0, 22)
hl.VerticalAlignment = Enum.VerticalAlignment.Center
hl.SortOrder = Enum.SortOrder.LayoutOrder
hl.Parent = hints
type Chip = { f: Frame, img: ImageLabel, t: TextLabel }
local chips: { Chip } = {}
for i = 1, 5 do
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 36)
	f.LayoutOrder = i
	f.Visible = false
	f.Parent = hints
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromOffset(30, 30)
	img.LayoutOrder = 1
	img.Parent = f
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, 36)
	t.Font = TYPE
	t.TextColor3 = KHAKI
	t.LayoutOrder = 2
	t.Parent = f
	reg(t, 16)
	table.insert(chips, { f = f, img = img, t = t })
end

local function padImage(code: Enum.KeyCode): string?
	local img: string? = nil
	pcall(function()
		local v = UserInputService:GetImageForKeyCode(code) :: any
		if type(v) == "string" and v ~= "" then
			img = v
		end
	end)
	return img
end

local hintCount = 0
local function chip(img: string?, key: string, label: string)
	hintCount += 1
	local c = chips[hintCount]
	if not c then
		return
	end
	c.f.Visible = true
	c.img.Visible = img ~= nil
	c.img.Image = img or ""
	c.t.Text = if img then label else string.format("[%s] %s", key, label)
end

local function actionChip(actionId: string, ctx: string, label: string)
	local img, text = Input.glyph(actionId, ctx)
	chip(img, keyName(text), label)
end

local backBtn = Instance.new("TextButton")
backBtn.AnchorPoint = Vector2.new(1, 0)
backBtn.Position = UDim2.fromOffset(1240, 674)
backBtn.Size = UDim2.fromOffset(280, 40)
backBtn.BackgroundColor3 = DRAB
backBtn.TextColor3 = KHAKI
backBtn.Font = HEAD
backBtn.AutoButtonColor = true
backBtn.Selectable = false -- no controle, B volta
backBtn.Visible = false
backBtn.Parent = root
reg(backBtn, 18)
stroke(backBtn, KHAKI, 1, 0.4)
local backAction: (() -> ())? = nil
backBtn.Activated:Connect(function()
	local fn = backAction
	if fn then
		fn()
	end
end)

local function backLabel(step: string): string?
	if step == "faction" then
		return if isBrowsing() then "Voltar ao squad" else nil
	elseif step == "squad" then
		return "Trocar de lado"
	elseif step == "role" then
		local sid = player:GetAttribute("SquadId")
		return if lastRole and lastRoleSquad == sid then "Cancelar a troca" else "Sair do squad"
	end
	return nil
end

local function renderFooter(step: string)
	hintCount = 0
	local dev = Input.device()
	local back = backLabel(step)
	if step == "insert" then
		if dev == "gamepad" then
			actionChip("map_next", "map", "Próximo ponto")
			actionChip("map_select", "map", "Inserir")
			actionChip("map_mark", "map", "Marcar")
			actionChip("map_role", "map", "Trocar de papel")
		elseif dev == "touch" then
			chip(nil, "Toque", "no ponto de inserção")
		else
			chip(nil, "Clique", "no ponto de inserção")
			actionChip("map_next", "map", "Próximo ponto")
			actionChip("map_select", "map", "Inserir")
			actionChip("map_role", "map", "Trocar de papel")
		end
	elseif dev == "gamepad" then
		chip(padImage(Enum.KeyCode.ButtonA), "A", "Escolher")
		if back then
			actionChip("ui_back", "menu", back)
		end
	else
		chip(nil, if dev == "touch" then "Toque" else "Clique", "Escolher")
		if back and dev ~= "touch" then
			actionChip("ui_back", "menu", back)
		end
	end
	for i = hintCount + 1, #chips do
		chips[i].f.Visible = false
	end
	-- botão para mouse e toque (no controle, os botões do próprio controle)
	if dev == "gamepad" then
		backBtn.Visible = false
		backAction = nil
	elseif step == "insert" then
		backBtn.Visible = true
		backBtn.Text = "TROCAR DE PAPEL (+15 s)"
		backAction = function()
			player:SetAttribute("Role", nil) -- como o Y do mapa: só o menu; o servidor confirma ao escolher
			DeployScreen.changed()
		end
	else
		backBtn.Visible = back ~= nil
		backBtn.Text = "◄ " .. string.upper(back or "")
		backAction = if back
			then function()
				DeployScreen.back()
			end
			else nil
	end
end

-- ===== render =====
local function updateHeader(f: string?)
	local us, vc = counts()
	teamLine.Text = string.format("JOGADORES  EUA %d/%d · VC %d/%d", us, Roles.TEAM_MAX, vc, Roles.TEAM_MAX)
	if f then
		local hq = MapConfig.HQ[f]
		posLine.Text = string.format("QG %s · %s", FACTION[f].short, gridRef(hq.x, hq.z))
	else
		for _, sp in MapConfig.Strongpoints do
			if sp.name == "An Cường (2)" then
				posLine.Text = string.format("%s · %s", string.upper(sp.name), gridRef(sp.x, sp.z))
			end
		end
	end
end

local function setPreviews(step: string)
	local onFaction = step == "faction"
	SoldierPreview.setActive(fcards.US.preview, onFaction)
	SoldierPreview.setActive(fcards.VC.preview, onFaction)
	SoldierPreview.setActive(main, step == "squad" or step == "role" or step == "insert")
	local slot = if step == "insert" then iSlot else photoSlot
	if main.frame.Parent ~= slot then
		main.frame.Parent = slot
	end
end

local function deactivate()
	SoldierPreview.setActive(fcards.US.preview, false)
	SoldierPreview.setActive(fcards.VC.preview, false)
	SoldierPreview.setActive(main, false)
end

-- st: último Squad_State (ou nil). Só desenha com a tela visível (o GameUI controla Visible).
function DeployScreen.render(st: any)
	if not root.Visible then
		deactivate()
		shownStep = ""
		return
	end
	local step = currentStep()
	local f = myFaction()
	if st and st.faction ~= f then
		st = nil -- estado do lado antigo (troca de lado): espera o do lado novo
	end
	for name, p in pages do
		local want = if name == step then root else nil
		if p.Parent ~= want then
			p.Parent = want
		end
	end
	photoCol.Visible = step == "squad" or step == "role"
	local idx = STEP_INDEX[step]
	for i, s in stepBoxes do
		if i < idx then
			s.f.BackgroundColor3, s.f.BackgroundTransparency = UiKit.OLIVE, 0
			s.t.TextColor3, s.t.TextTransparency = KHAKI, 0
		elseif i == idx then
			s.f.BackgroundColor3, s.f.BackgroundTransparency = STAMP, 0
			s.t.TextColor3, s.t.TextTransparency = CARD, 0
		else
			s.f.BackgroundColor3, s.f.BackgroundTransparency = DRAB, 0.6
			s.t.TextColor3, s.t.TextTransparency = KHAKI, 0.45
		end
	end
	updateHeader(f)
	local preferred: GuiObject? = nil
	if step == "faction" then
		renderFaction()
		preferred = if f then fcards[f].btn else fcards.US.btn
	elseif f and step == "squad" then
		previewRole = nil
		SoldierPreview.set(main, f, nil)
		preferred = renderSquad(f, st)
	elseif f and step == "role" then
		local sid = player:GetAttribute("SquadId")
		preferred = renderRole(f, st, tostring(sid))
	elseif f then
		renderInsert(f)
	end
	setPreviews(step)
	renderFooter(step)
	-- foco do controle: ao trocar de passo, ou se o item focado sumiu (cartão escondido/trancado)
	if Input.isGamepad() and step ~= "insert" then
		local cur = GuiService.SelectedObject
		local lost = cur == nil or not cur:IsDescendantOf(root) or not cur.Visible or not cur.Selectable
		if (step ~= shownStep or lost) and preferred then
			GuiService.SelectedObject = preferred
		end
	end
	shownStep = step
end

-- B / VOLTAR: devolve true se tratou
function DeployScreen.back(): boolean
	if not root.Visible then
		return false
	end
	local step = currentStep()
	if step == "faction" then
		if isBrowsing() then
			browsing = false
			DeployScreen.changed()
			return true
		end
		return false
	elseif step == "squad" then
		browsing, browsingFaction = true, myFaction()
		DeployScreen.changed()
		return true
	elseif step == "role" then
		local sid = player:GetAttribute("SquadId")
		if lastRole and lastRoleSquad == sid then
			player:SetAttribute("Role", lastRole) -- cancela a troca: o servidor ainda tem este papel
		else
			Net.event("Squad_Action"):FireServer({ op = "leave" })
		end
		return true
	end
	return false
end

-- ===== atributos =====
local function trackRole()
	local r = player:GetAttribute("Role")
	if type(r) == "string" then
		lastRole = r
		lastRoleSquad = player:GetAttribute("SquadId")
	end
end
trackRole()
player:GetAttributeChangedSignal("Role"):Connect(trackRole)
player:GetAttributeChangedSignal("SquadId"):Connect(function()
	-- o servidor só limpa o papel trocando de squad: papel antigo de outro squad não volta
	if player:GetAttribute("SquadId") ~= lastRoleSquad then
		lastRole, lastRoleSquad = nil, nil
	end
	previewRole = nil
end)
player:GetAttributeChangedSignal("Faction"):Connect(function()
	browsing, browsingFaction = false, nil
	lastRole, lastRoleSquad = nil, nil
end)

-- efetivo dos lados (entra e sai gente): só textos, uma vez por segundo com a tela aberta
task.spawn(function()
	while true do
		task.wait(1)
		if root.Visible then
			updateHeader(myFaction())
			if shownStep == "faction" then
				renderFaction()
			end
		end
	end
end)

return DeployScreen
