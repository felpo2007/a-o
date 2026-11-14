--!strict
-- Eventos da partida no cliente (Modules/EventosService: barragem naval, ataque aéreo, inserção de
-- helicóptero, morteiro do VC, medevac, depósito, contra-ataque). O servidor põe um Configuration por
-- evento em ReplicatedStorage.VT65Eventos (sempre replicado), com os atributos Evento, Nome, Lado,
-- Alvo, Setor, Grade, X, Z, RaioM, Fase (aviso/ativo/armado/janela/fim), Inicio e Fim
-- (workspace:GetServerTimeNow) e o apaga 5 s depois do fim.
-- Este módulo junta o que as telas precisam (faixa do EventosHud, círculo na CartaView, anel e
-- marcador no mundo do Marcadores): a lista viva, o ícone e a cor por fase. Muda só por evento
-- (ChildAdded/ChildRemoved/AttributeChanged): nada por quadro.
-- Studio: EventosVisual.dev(seg) põe eventos de exemplo locais (um em cada fase), sem o servidor.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local UiKit = require(script.Parent.UiKit)

local EventosVisual = {}

export type Ev = {
	key: string, -- nome do Configuration (único)
	id: string, -- "naval" | "air" | "heli" | "mortar" | "medevac" | "depot" | "counter"
	name: string,
	side: string, -- quem o evento favorece
	target: string,
	sector: number?,
	grade: string,
	x: number,
	z: number,
	raioM: number,
	fase: string,
	inicio: number,
	fim: number,
}

-- ícone por evento (emoji/símbolo que o Roblox desenha; o texto ao lado diz o nome)
EventosVisual.ICON = {
	naval = "⚓",
	air = "✈",
	heli = "🚁",
	mortar = "💥",
	medevac = "✚",
	depot = "📦",
	counter = "⚔",
} :: { [string]: string }

-- cor por fase: aviso (cáqui), em curso (vermelho), carga armada (vermelho forte), janela de
-- assalto (oliva claro), fim (apagado)
local V = UiKit.V
EventosVisual.PHASE_COLOR = {
	aviso = V.KHAKI,
	ativo = V.RED_HI,
	armado = V.RED,
	janela = V.OLIVE_HI,
	fim = V.MUTED,
} :: { [string]: Color3 }

-- rótulo curto da fase (frase inteira: o dicionário traduz)
EventosVisual.PHASE_TEXT = {
	aviso = "AVISO",
	ativo = "EM CURSO",
	armado = "CARGA ARMADA",
	janela = "JANELA",
	fim = "ENCERRADO",
} :: { [string]: string }

function EventosVisual.icon(id: string): string
	return EventosVisual.ICON[id] or "!"
end

function EventosVisual.color(fase: string): Color3
	return EventosVisual.PHASE_COLOR[fase] or V.KHAKI
end

-- raio em studs (os atributos vêm em metros)
function EventosVisual.radiusStuds(ev: Ev): number
	return ev.raioM / MapConfig.STUD_M
end

function EventosVisual.now(): number
	return workspace:GetServerTimeNow()
end

-- segundos até o fim (o relógio da faixa)
function EventosVisual.left(ev: Ev): number
	return math.max(0, ev.fim - EventosVisual.now())
end

-- ===== lista viva =====
local live: { [Instance]: Ev } = {}
local devList: { Ev } = {}
local devUntil = 0
local changed = Instance.new("BindableEvent")
-- (sem argumentos): algo mudou; quem desenha relê list()
EventosVisual.Changed = changed.Event

local function num(v: any, d: number): number
	return if type(v) == "number" then v else d
end

local function read(c: Instance): Ev
	local setor = c:GetAttribute("Setor")
	return {
		key = c.Name,
		id = tostring(c:GetAttribute("Evento") or ""),
		name = tostring(c:GetAttribute("Nome") or ""),
		side = tostring(c:GetAttribute("Lado") or ""),
		target = tostring(c:GetAttribute("Alvo") or ""),
		sector = if type(setor) == "number" and setor > 0 then setor else nil,
		grade = tostring(c:GetAttribute("Grade") or ""),
		x = num(c:GetAttribute("X"), 0),
		z = num(c:GetAttribute("Z"), 0),
		raioM = num(c:GetAttribute("RaioM"), 0),
		fase = tostring(c:GetAttribute("Fase") or "aviso"),
		inicio = num(c:GetAttribute("Inicio"), 0),
		fim = num(c:GetAttribute("Fim"), 0),
	}
end

-- eventos de agora, do que acaba antes ao que acaba depois
function EventosVisual.list(): { Ev }
	local out: { Ev } = {}
	for _, ev in live do
		table.insert(out, ev)
	end
	if os.clock() < devUntil then
		for _, ev in devList do
			table.insert(out, ev)
		end
	end
	table.sort(out, function(a: Ev, b: Ev): boolean
		if a.fim ~= b.fim then
			return a.fim < b.fim
		end
		return a.key < b.key
	end)
	return out
end

local function watch(c: Instance)
	if not c:IsA("Configuration") then
		return
	end
	live[c] = read(c)
	c.AttributeChanged:Connect(function()
		if c.Parent then
			live[c] = read(c)
			changed:Fire()
		end
	end)
	changed:Fire()
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("VT65Eventos")
	for _, c in folder:GetChildren() do
		watch(c)
	end
	folder.ChildAdded:Connect(watch)
	folder.ChildRemoved:Connect(function(c: Instance)
		if live[c] then
			live[c] = nil
			changed:Fire()
		end
	end)
end)

-- ===== exemplo local (gancho de Studio) =====
-- um evento em cada fase, perto do jogador (ou no meio da carta), por `seg` segundos
function EventosVisual.dev(seg: number)
	local Players = game:GetService("Players")
	local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local B = MapConfig.Bounds
	local cx = if root and root:IsA("BasePart") then root.Position.X else (B.minX + B.maxX) / 2
	local cz = if root and root:IsA("BasePart") then root.Position.Z else (B.minZ + B.maxZ) / 2
	local t = EventosVisual.now()
	type Sample = { id: string, name: string, fase: string, raioM: number, extra: number }
	local samples: { Sample } = {
		{ id = "naval", name = "Apoio naval", fase = "aviso", raioM = 60, extra = 5 },
		{ id = "mortar", name = "Morteiro do VC", fase = "ativo", raioM = 40, extra = -2 },
		{ id = "depot", name = "Depósito de munição do VC", fase = "armado", raioM = 15, extra = -8 },
		{ id = "heli", name = "Inserção de helicóptero", fase = "janela", raioM = 50, extra = 10 },
	}
	table.clear(devList)
	for i, s in samples do
		local a = (i - 1) * math.pi / 2
		table.insert(devList, {
			key = string.format("exemplo_%d", i),
			id = s.id,
			name = s.name,
			side = "US",
			target = "VC",
			sector = i,
			grade = "BS 693 928",
			x = cx + math.cos(a) * 160,
			z = cz + math.sin(a) * 160,
			raioM = s.raioM,
			fase = s.fase,
			inicio = t,
			fim = t + seg + s.extra,
		})
	end
	devUntil = os.clock() + seg
	changed:Fire()
	task.delay(seg + 0.1, function()
		changed:Fire()
	end)
end

return EventosVisual
