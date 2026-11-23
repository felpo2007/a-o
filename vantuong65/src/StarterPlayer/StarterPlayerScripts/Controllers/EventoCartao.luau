--!strict
-- D-185 (dono: "os eventos n estao acontecendo" e "melhore eles"): o cartão do começo de cada evento da
-- partida, no lugar do aviso de texto. Numa partida no Studio os eventos aconteciam, mas a 300-390 m
-- do soldado e só com um aviso curto, fácil de perder. Vai pelo Toast.custom (a mesma faixa dos
-- avisos, que empilha e tem a zona do celular) e mostra:
--   - o ícone grande do evento num selo da cor do que ele é para quem vê (Eventos.stance: verde a seu
--     favor, vermelho contra você, âmbar quando pega todo mundo) e esse rótulo;
--   - o nome do evento, o que fazer (o texto do servidor) e onde: o setor, a distância e o rumo de quem
--     vê (Eventos.whereFrom);
--   - numa barragem que pode ferir quem vê, dentro da área (Eventos.inside), a linha vermelha
--     "VOCÊ ESTÁ NA ÁREA: SAIA AGORA";
--   - o estalo do rádio (radio_squelch) ao chegar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Eventos = require(ReplicatedStorage.Shared.Eventos)
local Front = require(ReplicatedStorage.Shared.Front)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local EventosVisual = require(script.Parent.EventosVisual)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local EventoCartao = {}

local M = MapConfig.STUD_M
local player = Players.LocalPlayer
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

type Look = { accent: Color3, text: Color3, kind: string }
local LOOK: { [string]: Look } = {
	favor = { accent = Color3.fromRGB(122, 158, 84), text = Color3.fromRGB(172, 206, 126), kind = "sucesso" },
	contra = { accent = Color3.fromRGB(200, 70, 54), text = Color3.fromRGB(240, 124, 104), kind = "erro" },
	todos = { accent = Color3.fromRGB(226, 148, 52), text = Color3.fromRGB(244, 184, 96), kind = "alerta" },
}
local DIM = Color3.fromRGB(184, 178, 150)
local DANGER = Color3.fromRGB(255, 96, 76)

local function label(parent: Instance, name: string, text: string, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = UiKit.BODY_FONT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Parent = parent
	return l
end

local function squelch()
	local id = AssetIds.Sounds.radio_squelch
	if type(id) ~= "number" or id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "VT65EventoRadio"
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = 0.7
	local g = SoundService:FindFirstChild("VT65Efeitos")
	s.SoundGroup = if g and g:IsA("SoundGroup") then g else nil
	s.Parent = SoundService
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

-- O marcador do evento (ReplicatedStorage.VT65Eventos, "<id>_<uid>"), pela chave "evento:<uid>".
local function markerOf(id: string, chave: string?): Instance?
	local uid = if chave then string.match(chave, "^evento:(%d+)$") else nil
	local folder = ReplicatedStorage:FindFirstChild("VT65Eventos")
	if not (uid and folder) then
		return nil
	end
	return folder:FindFirstChild(string.format("%s_%s", id, uid))
end

-- O cartão do começo do evento. msg: o Evento_Aviso { evento, texto, tipo, titulo, chave, duracao }.
-- Devolve false quando não sabe montar (o chamador mostra o aviso de texto).
function EventoCartao.show(msg: any): boolean
	local id = if type(msg) == "table" then msg.evento else nil
	local def = if type(id) == "string" then Eventos.DEFS[id] else nil
	if not def or type(msg.texto) ~= "string" then
		return false
	end
	local marker = markerOf(id, msg.chave)
	local faction = player:GetAttribute("Faction")
	local side = marker and marker:GetAttribute("Lado")
	local stance = if type(side) == "string"
		then Eventos.stance(id, side, if type(faction) == "string" then faction else nil)
		elseif msg.tipo == "info" then "favor"
		else "contra"
	local look = LOOK[stance]
	-- onde: o setor, a distância e o rumo de quem vê
	local where = ""
	local danger = false
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local x, z = marker and marker:GetAttribute("X"), marker and marker:GetAttribute("Z")
	local setor = marker and marker:GetAttribute("Setor")
	local letra = if type(setor) == "number" and setor > 0 then Front.letra(setor) else nil
	if root and root:IsA("BasePart") and type(x) == "number" and type(z) == "number" then
		local dx, dz = (x - root.Position.X) * M, (z - root.Position.Z) * M
		local d, dir = Eventos.whereFrom(dx, dz)
		if d == 0 then
			where = if letra then string.format("%s · aqui perto", letra) else "aqui perto"
		else
			where = if letra
				then string.format("%s · ~%d m a %s", letra, d, dir)
				else string.format("~%d m a %s", d, dir)
		end
		local raio = marker and marker:GetAttribute("RaioM")
		danger = def.kind == "barrage" and stance ~= "favor" and type(raio) == "number" and Eventos.inside(dx, dz, raio)
	elseif letra then
		where = letra
	end
	local title = if type(msg.titulo) == "string" then msg.titulo else def.name
	local body = UiKit.capitalize(msg.texto)
	Toast.custom(function(card: Frame, L: Toast.Layout): number
		local S = px(46, 66) -- selo do ícone
		local gap = px(8, 12)
		local y = L.pad
		local badge = Instance.new("Frame")
		badge.Name = "EvSelo"
		badge.Position = UDim2.fromOffset(L.x, y)
		badge.Size = UDim2.fromOffset(S, S)
		badge.BackgroundColor3 = look.accent
		badge.BorderSizePixel = 0
		badge.Parent = card
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = badge
		local glyph = label(badge, "EvIcone", EventosVisual.icon(id), math.floor(S * 0.6), Color3.new(1, 1, 1))
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.TextYAlignment = Enum.TextYAlignment.Center
		local tx = L.x + S + gap
		local tw = L.w - S - gap
		local tagSize = px(13, 19)
		local tag = label(card, "EvLado", Eventos.STANCE_TEXT[stance] or "", tagSize, look.text)
		tag.FontFace = UiKit.HEAD_FONT
		tag.Position = UDim2.fromOffset(tx, y)
		tag.Size = UDim2.fromOffset(tw, tagSize + 2)
		local nameSize = px(22, 32)
		local name = label(card, "EvNome", UiKit.upper(title), nameSize, UiKit.CARD)
		name.FontFace = UiKit.headFont(title)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(tx, y + tagSize + 2)
		name.Size = UDim2.fromOffset(tw, nameSize + 4)
		y += S + gap
		local bodySize = UiKit.text(15)
		local bh = math.ceil(TextService:GetTextSize(body, bodySize, UiKit.BODY_FONT, Vector2.new(L.w, 10000)).Y)
		local b = label(card, "EvTexto", body, bodySize, UiKit.CARD)
		b.TextWrapped = true
		b.Position = UDim2.fromOffset(L.x, y)
		b.Size = UDim2.fromOffset(L.w, bh + 2)
		y += bh + 2
		if where ~= "" then
			local ws = UiKit.text(14)
			local w = label(card, "EvOnde", where, ws, DIM)
			w.Position = UDim2.fromOffset(L.x, y + px(4, 6))
			w.Size = UDim2.fromOffset(L.w, ws + 4)
			y += px(4, 6) + ws + 4
		end
		if danger then
			local ds = px(16, 23)
			local dl = label(card, "EvPerigo", "VOCÊ ESTÁ NA ÁREA: SAIA AGORA", ds, DANGER)
			dl.FontFace = UiKit.HEAD_FONT
			dl.Position = UDim2.fromOffset(L.x, y + px(4, 6))
			dl.Size = UDim2.fromOffset(L.w, ds + 4)
			y += px(4, 6) + ds + 4
		end
		return y
	end, {
		kind = look.kind,
		key = if type(msg.chave) == "string" then msg.chave else nil,
		duration = math.max(if type(msg.duracao) == "number" then msg.duracao else 0, 7),
	})
	squelch()
	return true
end

return EventoCartao
