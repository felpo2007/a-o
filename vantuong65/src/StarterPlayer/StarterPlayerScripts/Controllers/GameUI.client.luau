--!strict
-- Menus de entrada e mapa tático (F2 + Parte 12.5).
-- Lobby (DeployScreen sobre a mesa 3D do LobbyScene): lado → mesa → squad → papel → inserção. No
-- controle, o analógico esquerdo move o cursor virtual (VirtualCursor) pela mesa e pelos papéis;
-- A escolhe, B volta, LB/RB pulam entre os objetos/abas. A carta de spawn abre quando a inserção é
-- escolhida na mesa (ou direto, ao morrer com papel).
-- Mapa (tocar View / M): carta topográfica de verdade (CartaView; pedido do dono, 2026-11-11), com
-- setores, frente, objetivos, pontos de inserção, squad e marcações; nunca inimigos (Parte 9.5).
-- No controle: analógico esquerdo = cursor com ímã (gruda nos pontos de spawn e nos objetivos);
-- direito = arrastar; gatilhos = zoom; direcional = passo de arrasto; L3 = você; R3 = carta inteira;
-- LB/RB pulam entre spawns liberados; A escolhe; X marca; Y troca de papel (morto) ou planta o ponto
-- de reunião do squad (líder, em campo); B/Select fecham. Mouse: roda = zoom, arrastar = mover.
-- A navegação automática do Roblox fica desligada no mapa (a nossa assume).
-- Modos: "spawn" (morto), "view" (aberto em jogo) e "target" (comandante escolhendo o alvo).
-- Tudo fica num "palco" de projeto de 1280 x 720 que escala para caber na tela (UIScale).
-- Toque (Parte 13): a carta ocupa a tela inteira; um dedo arrasta, a pinça dá zoom (CartaView);
-- tocar escolhe o ponto (raio do dedo) e o botão grande de baixo nasce, com a espera escrita
-- ("ESPERA 12 s" até ficar "NASCER", D-209); no alvo do comandante, tocar põe a mira e "CONFIRMAR ALVO"
-- manda; ✕ / ◄ MESA fecham; + e − dão zoom; ◎ volta para você. Botões no tamanho de toque
-- (ToqueUi.minPx), numa tela própria sem escala (VT65CartaToque).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Acabamento = require(game:GetService("ReplicatedFirst"):WaitForChild("Acabamento"))
local Carta = require(ReplicatedStorage.Shared.Carta)
local Front = require(ReplicatedStorage.Shared.Front)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local NascerPedido = require(ReplicatedStorage.Shared.NascerPedido)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local CartaView = require(script.Parent.CartaView)
local DeployScreen = require(script.Parent.DeployScreen)
local Input = require(script.Parent.Input)
local ArteCatalogo = require(script.Parent.ArteCatalogo)
local FundoLobby = require(script.Parent.FundoLobby)
local JogarAgora = require(script.Parent.JogarAgora)
local LobbyScene = require(script.Parent.LobbyScene)
local Marcadores = require(script.Parent.Marcadores)
local SpawnTransition = require(script.Parent.SpawnTransition)
local Toast = require(script.Parent.Toast)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiEfeitos = require(script.Parent.UiEfeitos)
local UiKit = require(script.Parent.UiKit)
local VirtualCursor = require(script.Parent.VirtualCursor)

local Roles = require(game:GetService("ReplicatedStorage").Shared.Roles)

local player = Players.LocalPlayer
local gui = UiKit.screen("VT65Menus", 20)
gui.IgnoreGuiInset = true

-- D-222: atrás da preparação, o fundo parado do lobby (em tela cheia, fora do palco)
local fundoPrep = FundoLobby.novo(gui, 0.62, 0)
fundoPrep.Visible = false

-- palco de projeto (1280 x 720), centrado e escalado para caber
local DESIGN_W, DESIGN_H = 1280, 720
local stage = Instance.new("Frame")
stage.Name = "Stage"
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
stage.BackgroundTransparency = 1
stage.Parent = gui
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage

-- tamanho de texto no palco: na TV, nunca abaixo de 24 px na tela
local function TS(size: number): number
	return UiKit.textAt(size, stageScale.Scale)
end

-- tela de deslocamento (lado / squad / papel / inserção), em tela cheia no palco
local side = DeployScreen.root
side.Parent = stage

-- Janela do mapa (estilo novo, 2026-11-11: painel escuro, sem aba datilografada). Na carta de
-- inserção (morto) ocupa o palco à direita do painel estreito de inserção da DeployScreen (x 40 a
-- 340, contrato com a tela do lobby); aberta em campo (ou no alvo do comandante) ocupa o palco, com a
-- legenda curta à direita. A folha é quadrada (1 x 1 km): a altura manda no tamanho.
local SPAWN_RECT = { x = 16, y = 72, w = 876, h = 584 } -- D-223: à esquerda; a ficha do destino vai à direita
local VIEW_RECT = { x = 24, y = 64, w = 1000, h = 620 }
local LEGEND_RECT = { x = 1036, y = 64, w = 220, h = 620 }
local mapFrame = Instance.new("Frame")
mapFrame.Name = "Carta"
mapFrame.BorderSizePixel = 0
mapFrame.ClipsDescendants = true
mapFrame.Active = true -- tapa a mesa 3D do lobby atrás da carta (o clique não atravessa)
mapFrame.Visible = false
mapFrame.ZIndex = 2 -- por cima da tela de deslocamento (passo da inserção)
mapFrame:SetAttribute("VT65SemIma", true) -- o toque na carta é da CartaView (sem o dedo gordo)
mapFrame.Parent = stage
UiKit.corner(mapFrame, 4)
local mapEdge = UiKit.stroke(mapFrame, UiKit.V.LINE, 1, 0.3)
mapEdge.Name = "Borda"
UiKit.Estilo.cantoneiras(mapFrame, UiKit.V.BRASS, 30, 12) -- D-240: a carta numa moldura de latão
-- título da carta em campo, em cima da janela (fora do mapFrame, que corta os filhos); na inserção
-- quem dá o título é o painel de inserção da DeployScreen
local mapTab = Instance.new("Frame")
mapTab.Name = "Titulo"
mapTab.BackgroundTransparency = 1
mapTab.Size = UDim2.fromOffset(VIEW_RECT.w, 30)
mapTab.Visible = false
mapTab.ZIndex = 2
mapTab.Parent = stage
local mapTitle = UiKit.title(mapTab, "", 20, UiKit.V.TEXT)
mapTitle.AutomaticSize = Enum.AutomaticSize.X
mapTitle.Size = UDim2.fromOffset(0, 30)
mapTitle.ZIndex = 2
local mapSub = UiKit.kicker(mapTab, "", 14, UiKit.V.DIM)
mapSub.AnchorPoint = Vector2.new(1, 0)
mapSub.Position = UDim2.fromScale(1, 0)
mapSub.Size = UDim2.new(0.6, 0, 0, 30)
mapSub.TextXAlignment = Enum.TextXAlignment.Right
mapSub.ZIndex = 2
-- faixa de estado no pé da carta: modo, relógio e grade do cursor à esquerda; comandos à direita
local status = Instance.new("TextLabel")
status.Name = "Estado"
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 0, 1, 0)
status.Size = UDim2.new(1, 0, 0, if UiKit.tv() then 36 else 28)
status.BackgroundColor3 = UiKit.V.PANEL
status.BackgroundTransparency = 0.1
status.BorderSizePixel = 0
status.TextColor3 = UiKit.V.TEXT
status.FontFace = UiKit.F.TITLE_MED
status.TextSize = TS(15)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextTruncate = Enum.TextTruncate.AtEnd
status.ZIndex = 9
status.Parent = mapFrame
local statusPad = Instance.new("UIPadding")
statusPad.PaddingLeft, statusPad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
statusPad.Parent = status
local hints = Instance.new("TextLabel")
hints.Name = "Comandos"
hints.BackgroundTransparency = 1
hints.Size = UDim2.fromScale(1, 1)
hints.TextColor3 = UiKit.V.DIM
hints.TextTransparency = 0
hints.Font = Enum.Font.Arimo
hints.TextSize = TS(13)
hints.TextXAlignment = Enum.TextXAlignment.Right
hints.ZIndex = 9
hints.Parent = status
local cursorUI = Instance.new("Frame")
cursorUI.Name = "Cursor"
cursorUI.AnchorPoint = Vector2.new(0.5, 0.5)
cursorUI.Size = UDim2.fromOffset(26, 26)
cursorUI.BackgroundTransparency = 1
cursorUI.ZIndex = 9
local cs = Instance.new("UIStroke")
cs.Thickness = 3
cs.Color = Color3.fromRGB(255, 214, 0)
cs.Parent = cursorUI
local cr = Instance.new("UICorner")
cr.CornerRadius = UDim.new(1, 0)
cr.Parent = cursorUI
local cross = Instance.new("Frame")
cross.AnchorPoint = Vector2.new(0.5, 0.5)
cross.Position = UDim2.fromScale(0.5, 0.5)
cross.Size = UDim2.fromOffset(4, 4)
cross.BackgroundColor3 = Color3.fromRGB(255, 214, 0)
cross.BorderSizePixel = 0
cross.Parent = cursorUI
cursorUI.Parent = mapFrame

-- tela (GetMouseLocation, com a faixa do Roblox) -> unidades de projeto da janela do mapa. O
-- AbsolutePosition não conta a faixa de cima (GetGuiInset), o mouse conta.
CartaView.mount(mapFrame, TS, function(p: Vector2): Vector2
	local abs = mapFrame.AbsoluteSize
	local k = if abs.X > 0 then mapFrame.Size.X.Offset / abs.X else 1
	local inset = GuiService:GetGuiInset()
	return (p - inset - mapFrame.AbsolutePosition) * k
end)
local legend = CartaView.buildLegend(stage, LEGEND_RECT.x, LEGEND_RECT.y, LEGEND_RECT.w, LEGEND_RECT.h)

local B = MapConfig.CartaBounds or MapConfig.Bounds
local function fromUV(u: number, v: number): (number, number)
	return Carta.fromUV(B, u, v)
end

local squadState: any = nil
local spawnList: { any } = {}
local matchState: any = nil
local mode: string = "spawn" -- "spawn" | "view" | "target"
local pinned = false
local targetAbility: string? = nil
local focusIdx: number? = nil
local mapWanted = false -- a carta pedida (a janela some depois da dobra)
local foldToken = 0

local function alive(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function readySpawns(): { any }
	local out = {}
	for _, pt in spawnList do
		if not pt.blocked then
			table.insert(out, pt)
		end
	end
	return out
end

local function spawnById(id: string): any
	for _, pt in spawnList do
		if "spawn:" .. pt.id == id then
			return pt
		end
	end
	return nil
end

-- ===== D-209 (§8): escolher o destino e confirmar no NASCER =====
-- Clique, toque, LB/RB e o 1º A só ESCOLHEM; o NASCER (botão, A ou Enter no escolhido) confirma. A
-- carta (anel âmbar), o painel e a faixa de baixo mostram o mesmo destino. O pedido leva o id do ponto
-- e a rodada; até a resposta (Spawn_Result), o corpo novo ou NascerPedido.ESPERA_S, outro pedido não
-- sai. O escolhido continua escolhido ao voltar do equipamento enquanto existir; se travar ou sumir,
-- o painel diz por quê e oferece o pronto mais perto.
local selId: string? = nil
local selInfo: { x: number?, z: number?, name: string }? = nil -- onde o escolhido estava (se sumir)
local pedidoEm: number? = nil
local pedidoId: string? = nil
local recusa: { id: string, msg: string, t: number }? = nil
local RECUSA_S = 6 -- s que o motivo da recusa fica no painel

local COR_ESTADO: { [string]: Color3 } = {
	pronto = Color3.fromRGB(124, 178, 84), -- as cores dos pontos da carta (CartaView.COR)
	espera = UiKit.V.KHAKI,
	bloqueado = UiKit.V.RED,
	pedido = UiKit.V.AMBAR,
	nenhum = UiKit.V.PANEL_3,
}

local statusH = if UiKit.tv() then 36 else 28
-- D-223 (referência do dono): a ficha do destino à direita da carta: a foto do lugar, o nome, o estado,
-- o resumo (time, grupo, classe) e, na barra de baixo, o NASCER
local PAINEL_W = 364
local painel = Instance.new("Frame")
painel.Name = "Nascer"
painel.Position = UDim2.fromOffset(900, 72)
painel.Size = UDim2.fromOffset(PAINEL_W, 584)
painel.BackgroundColor3 = UiKit.V.PANEL
painel.BackgroundTransparency = 0.04
painel.BorderSizePixel = 0
painel.Active = true -- o clique no painel não vai para a carta
painel.Visible = false
painel.ZIndex = 10
painel.ClipsDescendants = true
painel.Parent = stage
UiKit.corner(painel, 4)
local painelBorda = UiKit.stroke(painel, UiKit.V.LINE, 1, 0.2)
UiKit.Estilo.cantoneiras(painel, UiKit.V.BRASS, 26, 13)
local pFoto = Instance.new("ImageLabel")
pFoto.Name = "Foto"
pFoto.BackgroundColor3 = UiKit.V.BG
pFoto.BorderSizePixel = 0
pFoto.ScaleType = Enum.ScaleType.Crop
pFoto.Position = UDim2.fromOffset(10, 10)
pFoto.Size = UDim2.fromOffset(PAINEL_W - 20, 158)
pFoto.ZIndex = 11
pFoto.Parent = painel
UiKit.corner(pFoto, 3)
do -- D-240: a foto do lugar como um quadro de cinema, escurecendo para o nome
	local veu = Instance.new("Frame")
	veu.Name = "Veu"
	veu.BackgroundColor3 = Color3.new(0, 0, 0)
	veu.BorderSizePixel = 0
	veu.Size = UDim2.fromScale(1, 1)
	veu.ZIndex = 12
	veu.Parent = pFoto
	UiKit.corner(veu, 3)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.78),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(1, 0.22),
	})
	g.Parent = veu
end
local pFaixa = Instance.new("Frame")
pFaixa.Name = "Faixa"
pFaixa.Position = UDim2.fromOffset(10, 168)
pFaixa.Size = UDim2.fromOffset(PAINEL_W - 20, 4)
pFaixa.BorderSizePixel = 0
pFaixa.ZIndex = 11
pFaixa.Parent = painel
local INFO_W = PAINEL_W - 32
local pTipo = UiKit.kicker(painel, "", 15, UiKit.V.DIM)
pTipo.Position = UDim2.fromOffset(16, 176)
pTipo.Size = UDim2.fromOffset(INFO_W, 20)
pTipo.ZIndex = 11
local pNome = UiKit.title(painel, "", 30, UiKit.V.TEXT)
pNome.Name = "Nome"
pNome.Position = UDim2.fromOffset(16, 192)
pNome.Size = UDim2.fromOffset(INFO_W, 38)
pNome.TextTruncate = Enum.TextTruncate.AtEnd
pNome.ZIndex = 11
local pTag = UiKit.text2(painel, "", 16, UiKit.V.BG, UiKit.F.BODY_B)
pTag.Name = "Estado"
pTag.Position = UDim2.fromOffset(16, 232)
pTag.AutomaticSize = Enum.AutomaticSize.X
pTag.Size = UDim2.fromOffset(0, 26)
pTag.BackgroundTransparency = 0
pTag.TextXAlignment = Enum.TextXAlignment.Center
pTag.ZIndex = 11
UiKit.corner(pTag, 3)
UiKit.pad(pTag, 10, 10)
local pLinha = UiKit.text2(painel, "", 16, UiKit.V.TEXT, UiKit.F.TITLE_MED)
pLinha.Name = "Motivo"
pLinha.Position = UDim2.fromOffset(16, 262)
pLinha.Size = UDim2.fromOffset(INFO_W, 24)
pLinha.TextTruncate = Enum.TextTruncate.AtEnd
pLinha.ZIndex = 11
-- a alternativa (o pronto mais perto) quando o escolhido trava ou some
local pAlt = Instance.new("TextButton")
pAlt.Name = "Alternativa"
pAlt.AutoButtonColor = false
pAlt.BackgroundTransparency = 1
pAlt.Position = UDim2.fromOffset(16, 284)
pAlt.Size = UDim2.fromOffset(INFO_W, 24)
pAlt.FontFace = UiKit.F.TITLE_MED
pAlt.TextSize = 16
pAlt.TextColor3 = UiKit.V.AMBAR
pAlt.TextXAlignment = Enum.TextXAlignment.Left
pAlt.TextTruncate = Enum.TextTruncate.AtEnd
pAlt.Visible = false
pAlt.ZIndex = 11
pAlt.Parent = painel
local altPt: any = nil
-- o resumo do que foi escolhido nos passos de antes
local pResumo: { TextLabel } = {}
for i, rotulo in { "TIME", "GRUPO", "CLASSE" } do
	local y = 308 + (i - 1) * 24
	local k = UiKit.kicker(painel, rotulo, 15, UiKit.V.DIM)
	k.Position = UDim2.fromOffset(16, y)
	k.Size = UDim2.fromOffset(90, 26)
	k.ZIndex = 11
	local v = UiKit.text2(painel, "", 18, UiKit.V.TEXT, UiKit.F.TITLE_MED)
	v.Position = UDim2.fromOffset(112, y)
	v.Size = UDim2.fromOffset(INFO_W - 96, 26)
	v.TextXAlignment = Enum.TextXAlignment.Right
	v.TextTruncate = Enum.TextTruncate.AtEnd
	v.ZIndex = 11
	pResumo[i] = v
end

local pintarPainel: () -> ()
local confirmar: () -> ()
local nascerBtn = UiKit.action(DeployScreen.pe, "NASCER", "primary", function()
	confirmar()
end, { action = "map_select", ctx = "map", h = 46 })
nascerBtn.button.Name = "BotaoNascer"
nascerBtn.button.AnchorPoint = Vector2.new(1, 0.5)
nascerBtn.button.Position = UDim2.fromOffset(1256, 29)
nascerBtn.button.Size = UDim2.fromOffset(260, 46)
nascerBtn.button.Selectable = false -- na carta o controle navega pela carta (LB/RB, A)
nascerBtn.button.Visible = false
nascerBtn.button.ZIndex = 11
nascerBtn.label.TextXAlignment = Enum.TextXAlignment.Center
nascerBtn.button.ClipsDescendants = true -- o brilho não passa da borda do botão
UiEfeitos.varre(nascerBtn.button, 2.8, nil, 13) -- D-240: o brilho que corre no botão de nascer
for _, d in nascerBtn.button:GetDescendants() do
	if d:IsA("GuiObject") then
		d.ZIndex = 12
	end
end

local function pendente(): boolean
	return NascerPedido.emCurso(pedidoEm, os.clock())
end

local function selecionar(pt: any)
	if pt then
		selId = tostring(pt.id)
		selInfo = { x = pt.x, z = pt.z, name = tostring(pt.name or "") }
	else
		selId, selInfo = nil, nil
	end
	CartaView.setSelected(selId)
	pintarPainel()
end

-- o que o painel mostra agora (também a faixa de baixo e o botão do toque)
local function painelAgora(): (any, NascerPedido.Painel)
	local pt = NascerPedido.acha(spawnList, selId)
	local p = NascerPedido.painel(pt, pendente() or SpawnTransition.busy())
	if not pt and selInfo then
		-- o escolhido saiu da carta (setor tomado, reunião desfeita, companheiro caiu ou saiu)
		p = {
			estado = "bloqueado",
			botao = "INDISPONÍVEL",
			ativo = false,
			linha = NascerPedido.MOTIVO.ponto,
			tag = "× FORA DA CARTA",
		}
	end
	local r = recusa
	if r and r.id == selId and os.clock() - r.t < RECUSA_S and p.estado ~= "pedido" then
		p.linha = r.msg
	end
	return pt, p
end

function pintarPainel()
	local on = mapWanted and mode == "spawn" and side.Visible and not ToqueUi.active()
	painel.Visible = on
	nascerBtn.button.Visible = on
	if not on then
		return
	end
	local pt, p = painelAgora()
	local cor = COR_ESTADO[p.estado] or UiKit.V.PANEL_3
	pFaixa.BackgroundColor3 = cor
	if pt then
		pTipo.Text = UiKit.upper(NascerPedido.tipo(pt))
		pNome.Text = Acabamento.viet(tostring(pt.name or ""))
	elseif selInfo then
		pTipo.Text = "DESTINO"
		pNome.Text = Acabamento.viet(selInfo.name)
	else
		pTipo.Text = "DESTINO"
		pNome.Text = "—"
	end
	pNome.FontFace = UiKit.headFont(pNome.Text)
	pFoto.Image = ArteCatalogo.lugar(if pt then tostring(pt.name or "") elseif selInfo then selInfo.name else nil)
	DeployScreen.resumo.Text = string.format("DESTINO: %s", pNome.Text)
	do
		local fac = player:GetAttribute("Faction")
		local sid = player:GetAttribute("SquadId")
		local rid = player:GetAttribute("Role")
		pResumo[1].Text = if fac == "US" then "EUA" elseif fac == "VC" then "VC" else "—"
		pResumo[2].Text = if type(sid) == "string" then (string.match(sid, ":(.+)$") or sid) else "—"
		local def = if type(rid) == "string" then Roles.roles[rid] else nil
		pResumo[3].Text = if def then def.name else "—"
	end
	pTag.Visible = p.tag ~= ""
	pTag.Text = p.tag
	pTag.BackgroundColor3 = cor
	pTag.TextColor3 = if p.estado == "bloqueado" then UiKit.V.TEXT else UiKit.V.BG
	pLinha.Text = p.linha
	pLinha.TextColor3 = if p.estado == "bloqueado" then Color3.fromRGB(240, 150, 130) else UiKit.V.TEXT
	-- alternativa: só com o escolhido travado ou fora da carta
	altPt = nil
	if p.estado == "bloqueado" then
		local x = if pt then pt.x elseif selInfo then selInfo.x else nil
		local z = if pt then pt.z elseif selInfo then selInfo.z else nil
		altPt = NascerPedido.alternativa(spawnList, x, z, selId)
	end
	pAlt.Visible = altPt ~= nil
	if altPt then
		pAlt.Text = string.format("► Pronto perto: %s", Acabamento.viet(tostring(altPt.name or "")))
	end
	nascerBtn.label.Text = p.botao
	nascerBtn.label.FontFace = UiKit.headFont(p.botao)
	nascerBtn.enabled(p.ativo)
end

pAlt.Activated:Connect(function()
	if altPt then
		local pt = altPt
		selecionar(pt)
		local u, v = Carta.toUV(B, pt.x, pt.z)
		CartaView.goTo(u, v)
	end
end)

-- Confirma o escolhido: só ponto pronto, um pedido por vez. A transição carrega a área antes de
-- pedir o spawn (SpawnTransition) e mostra a recusa com o motivo.
function confirmar()
	if mode ~= "spawn" or alive() then
		return
	end
	local pt, p = painelAgora()
	if not (pt and p.ativo) then
		-- ainda não dá: a borda do painel pisca em vermelho (o motivo já está escrito nele)
		painelBorda.Color, painelBorda.Transparency = UiKit.V.RED_HI, 0
		task.delay(0.6, function()
			painelBorda.Color, painelBorda.Transparency = UiKit.V.LINE, 0.2
		end)
		return
	end
	local id = tostring(pt.id)
	pedidoEm, pedidoId = os.clock(), id
	local ok = SpawnTransition.go({ id = id, name = tostring(pt.name or ""), x = pt.x, z = pt.z }, function()
		SpawnTransition.pedir(id)
	end)
	if not ok then
		pedidoEm, pedidoId = nil, nil
	end
	pintarPainel()
end

-- alvo da missão de fogo escolhido na carta (controle: A; mouse: clique sem arrastar)
local function chooseTarget(u: number, v: number)
	local x, z = fromUV(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
	Bus.fire("target_chosen", targetAbility, x, z)
	Bus.fire("map_target_end")
end

-- Marcar na carta e ser guiado (pedido do dono): em campo, clique, A ou X marcam o ponto. Quem é
-- líder do squad marca para o squad inteiro (Squad_Mark "map"; o servidor confere e manda com
-- leader = true só para o squad); os outros põem a marca pessoal (só neste cliente). O Marcadores
-- mostra a marca no mundo com a distância e a tira quando você chega. Marcar de novo perto da sua
-- marca a apaga.
local function markAt(u: number, v: number)
	local x, z = fromUV(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
	if player:GetAttribute("Role") == "squad_leader" and player:GetAttribute("SquadId") ~= nil then
		Net.event("Squad_Mark"):FireServer({ pos = Vector3.new(x, 0, z), kind = "map" })
		return
	end
	local mine = Marcadores.waypoints().mine
	if mine and math.sqrt((mine.x - x) ^ 2 + (mine.z - z) ^ 2) * (MapConfig.STUD_M or 0.28) < 25 then
		Marcadores.clearWaypoint()
		Toast.show("Marca apagada", "info", { title = "Marca", key = "marca_pessoal" })
	else
		Marcadores.setWaypoint(x, z)
		Toast.show("Siga a marca: ela some quando você chegar", "info", { title = "Marca", key = "marca_pessoal" })
	end
end

CartaView.setCallbacks(function(pt: any)
	if mode == "spawn" then
		selecionar(pt) -- D-209: tocar só escolhe; D-246: o mouse escolhe ao passar por cima
	end
end, function(u: number, v: number)
	if mode == "target" and not Input.isGamepad() then
		chooseTarget(u, v)
	elseif mode == "view" and alive() then
		markAt(u, v)
	end
end)
-- D-246: clique do mouse no ponto escolhido: nasce ali
CartaView.setConfirma(function()
	confirmar()
end)

-- posição da carta: à direita da ficha de inserção (morto) ou no palco inteiro (em campo / alvo)
local function placeMap()
	local insertion = mode == "spawn" and side.Visible
	local r = if insertion then SPAWN_RECT else VIEW_RECT
	local touch = ToqueUi.active()
	if touch then
		-- toque: a carta cobre a tela inteira (abaixo da faixa do Roblox), em qualquer modo
		local vp = gui.AbsoluteSize
		local top = GuiService:GetGuiInset().Y
		local x, y, w, h = ToqueTelas.fullRect(vp.X, vp.Y, stageScale.Scale, DESIGN_W, DESIGN_H, top, 0)
		r = { x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) }
	end
	mapFrame.Position = UDim2.fromOffset(r.x, r.y)
	mapFrame.Size = UDim2.fromOffset(r.w, r.h)
	CartaView.resize(r.w, r.h)
	mapTab.Position = UDim2.fromOffset(r.x, r.y - 34)
	mapTab.Size = UDim2.fromOffset(r.w, 30)
	mapTab.Visible = mapWanted and not insertion and not touch
	legend.Visible = mapWanted and not insertion and not touch
	-- poucas palavras: o título e uma linha curta
	if mode == "target" then
		mapTitle.Text = "ALVO DA MISSÃO DE FOGO"
		mapSub.Text = "escolha o ponto na carta"
	elseif mode == "spawn" then
		mapTitle.Text = "INSERÇÃO"
		mapSub.Text = "escolha um ponto pronto"
	else
		mapTitle.Text = "CARTA TÁTICA"
		mapSub.Text = "sem inimigos na carta"
	end
	mapTitle.FontFace = UiKit.headFont(mapTitle.Text)
	CartaView.setMode(mode)
end

-- abre na hora; fecha dobrando a carta (0,16 s) antes de esconder
local function showMap(on: boolean)
	if on == mapWanted then
		return
	end
	mapWanted = on
	foldToken += 1
	if on then
		mapFrame.Visible = true
		CartaView.setVisible(true)
		CartaView.setMatch(matchState)
	else
		CartaView.setVisible(false)
		local my = foldToken
		CartaView.foldOut(0.16)
		task.delay(0.16, function()
			if foldToken == my then
				mapFrame.Visible = false
			end
		end)
	end
end

-- a tela de deslocamento é um "menu" (personagem parado, A confirma) enquanto não houver papel
local sideAsMenu = false
local mapOpenState = false

local function syncInput()
	local wantMenu = side.Visible and not mapWanted
	if wantMenu ~= sideAsMenu then
		sideAsMenu = wantMenu
		if wantMenu then
			Input.openMenu()
		else
			Input.closeMenu()
		end
	end
	local wantMap = mapWanted and alive()
	if wantMap ~= mapOpenState then
		mapOpenState = wantMap
		Input.event(if wantMap then "map_open" else "map_close")
	end
	-- lobby: o cursor virtual do controle manda (mesa 3D e papéis); no mapa, o cursor com ímã do
	-- mapa; fora dos dois, a navegação do Roblox
	VirtualCursor.setActive(wantMenu)
	GuiService.GuiNavigationEnabled = not mapWanted and not VirtualCursor.isActive()
	cursorUI.Visible = mapWanted and Input.isGamepad()
	if VirtualCursor.isActive() or mapWanted then
		GuiService.SelectedObject = nil
	elseif wantMenu then
		UiKit.focus(side)
	end
end

local function refresh()
	local dead = not alive()
	local hasRole = player:GetAttribute("Role") ~= nil
	-- D-117: com o menu principal aberto (Controllers/MenuPrincipal) o lobby fica escondido
	local menuPrincipal = player:GetAttribute("MenuPrincipal") == true
	side.Visible = (dead or not hasRole) and not menuPrincipal
	DeployScreen.render(squadState) -- decide o painel (a inserção abre a carta de spawn)
	local insertion = side.Visible and dead and hasRole and DeployScreen.panel() == "insert"
	local targeting = mode == "target"
	if not targeting then
		if dead and hasRole then
			mode = "spawn"
		elseif not dead then
			mode = "view"
		end
	end
	-- D-123: a carta aberta (M) também fica atrás do menu principal; ela aparecia através dele (Studio, v55)
	showMap((insertion or pinned or targeting) and not menuPrincipal)
	placeMap()
	local faction = player:GetAttribute("Faction")
	-- D-223: a mesa 3D saiu da preparação; o fundo é a imagem parada
	fundoPrep.Visible = side.Visible
	LobbyScene.update(false, if type(faction) == "string" then faction else nil)
	syncInput()
	pintarPainel()
end
DeployScreen.changed = refresh -- voltar um passo (B) e trocar de papel pelo botão mudam só o cliente

UiKit.watch(side, function()
	return side.Visible and not mapWanted
end)

-- B / Backspace na tela de deslocamento. Outro menu por cima (menu do jogo, loja, relatório) fecha
-- primeiro: os handlers de ui_back rodam todos no mesmo aperto, então olha também o quadro anterior.
local menusBefore = 0
RunService.Heartbeat:Connect(function()
	menusBefore = Input.state.menus
end)
Input.on("ui_back", "press", function()
	-- UiKit.top(): uma tela da pilha (menu, loja, relatório, fim) está por cima e trata o voltar
	if UiKit.top() ~= nil or Input.state.menus > 1 or menusBefore > 1 then
		return
	end
	if JogarAgora.busy() then
		JogarAgora.cancel() -- jogar agora contando: o voltar só cancela (fica na mesa)
		return
	end
	if side.Visible and not mapWanted then
		DeployScreen.back()
	end
end)
-- LB/RB (Q/E): objeto seguinte da mesa / aba seguinte do lobby (só com o lobby por cima de tudo)
local TAB_DIR: { [string]: number } = { ui_tab_prev = -1, ui_tab_next = 1 }
for action, dir in TAB_DIR do
	Input.on(action, "press", function()
		if UiKit.top() ~= nil or Input.state.menus > 1 or menusBefore > 1 then
			return
		end
		if side.Visible and not mapWanted then
			DeployScreen.cycle(dir)
		end
	end)
end

-- a carta de spawn aberta pela mesa: B (ou Select) volta para a mesa, não fecha o lobby
local function spawnMapBack(): boolean
	if mode == "spawn" and side.Visible and DeployScreen.panel() == "insert" then
		DeployScreen.open("desk")
		return true
	end
	return false
end

-- ===== entradas do mapa =====
local function moveCursorTo(pt: any)
	local u, v = Carta.toUV(B, pt.x, pt.z)
	CartaView.goTo(u, v)
end

Input.on("map", "tap", function()
	pinned = not pinned
	refresh()
end)
Input.on("map", "press", function() -- M no teclado
	pinned = not pinned
	refresh()
end)
local function closeMap()
	if mode == "spawn" and JogarAgora.busy() then
		JogarAgora.cancel() -- jogar agora contando: B/M só cancelam (a carta fica para escolher)
		return
	end
	if mode == "target" then
		Bus.fire("map_target_end")
	end
	pinned = false
	if not spawnMapBack() then
		refresh()
	end
end
Input.on("map_close", "press", closeMap)
Input.on("map_back", "press", closeMap)
-- LB/RB (Q/E): o próximo ponto livre (pronto ou esperando), a partir do escolhido; na inserção, ele
-- passa a ser o escolhido (D-209)
local function percorrer(dir: number)
	local list = readySpawns()
	local cur: number? = nil
	for i, pt in list do
		if tostring(pt.id) == selId then
			cur = i
		end
	end
	focusIdx = InputMap.cycle(#list, cur or focusIdx, dir)
	if focusIdx then
		local pt = list[focusIdx]
		if mode == "spawn" then
			selecionar(pt)
		end
		moveCursorTo(pt)
	end
end
Input.on("map_next", "press", function()
	percorrer(1)
end)
Input.on("map_prev", "press", function()
	percorrer(-1)
end)
Input.on("map_select", "press", function()
	local focused = CartaView.focused()
	if mode == "target" then
		local u, v = CartaView.cursorUV()
		chooseTarget(u, v)
	elseif mode == "spawn" then
		-- D-209: A no ponto sob o cursor que não é o escolhido o escolhe; no escolhido (ou fora de
		-- qualquer ponto), confirma o NASCER
		local pt = if focused then spawnById(focused.id) else nil
		if pt and tostring(pt.id) ~= selId then
			selecionar(pt)
		else
			confirmar()
		end
	elseif mode == "view" and alive() then
		local u, v = CartaView.cursorUV()
		markAt(u, v)
	end
end)
Input.on("map_mark", "press", function()
	if mode ~= "view" or not alive() then
		return
	end
	local u, v = CartaView.cursorUV()
	markAt(u, v)
end)
Input.on("map_role", "press", function()
	if mode == "spawn" and not alive() then
		DeployScreen.open("role") -- o papel da mesa; o servidor só troca ao escolher outro (+15 s)
	elseif mode == "view" and alive() then
		-- em campo, o líder planta o ponto de reunião do squad onde está (FrontService valida)
		if player:GetAttribute("Role") == "squad_leader" then
			Net.event("SquadRally_Place"):FireServer()
		else
			Toast.show("Só o líder do squad planta o ponto de reunião", "alerta", { title = "Reunião" })
		end
	end
end)

-- modo alvo (comandante / morteiro): pedido vindo do CommanderController
Bus.on("map_target", function(ability: string, label: string?)
	targetAbility = ability
	mode = "target"
	status.Text = string.format("ALVO: %s — mova o cursor e confirme", label or ability)
	refresh()
end)
Bus.on("map_target_end", function()
	if mode == "target" then
		mode = if alive() then "view" else "spawn"
		targetAbility = nil
		refresh()
	end
end)

-- comandos na faixa de estado, pelo dispositivo
local function hintText(): string
	if ToqueUi.active() then
		if mode == "spawn" then
			return "toque escolhe · NASCER confirma · pinça zoom · arraste"
		elseif mode == "target" then
			return "toque no alvo e confirme · pinça zoom · arraste"
		end
		return "toque marca · pinça zoom · arraste"
	end
	if Input.isGamepad() then
		if mode == "spawn" then
			return "LB/RB escolhe · A nascer · gatilhos zoom · Y papel · B volta"
		elseif mode == "target" then
			return "A confirma o alvo · gatilhos zoom · B cancela"
		end
		return "A marca · gatilhos zoom · R arrasta · L3 você · Y reunião do squad · B fecha"
	end
	if mode == "spawn" then
		return "clique escolhe · Enter nasce · J jogar agora · roda zoom · arraste · R papel · M volta"
	elseif mode == "target" then
		return "clique no alvo · roda zoom · arraste · M cancela"
	end
	return "clique marca · roda zoom · arraste · R reunião do squad · M fecha"
end

local function statusLine(): string
	local st = matchState
	if not st then
		return string.format("Carta · %s", CartaView.cursorGrid())
	end
	-- lista "A · B · C": cada pedaço é frase ou modelo inteiro (o Lang traduz item a item)
	local t = math.floor(st.timeLeft or 0)
	local parts = { string.format("%s %02d:%02d", UiKit.upper(st.mode), t // 60, t % 60) }
	if st.ended then
		local w = st.winner or ReplicatedStorage:GetAttribute("LastWinner")
		table.insert(parts, if w == "US" then "vitória dos EUA" elseif w == "VC" then "vitória do VC" else "empate")
	elseif st.mode == "Offensive" and st.front and st.front >= 1 then
		table.insert(parts, string.format("frente %s", Front.letra(st.front)))
	end
	table.insert(parts, string.format("cursor %s", CartaView.cursorGrid()))
	return table.concat(parts, " · ")
end

-- ===== toque (Parte 13): botões de polegar sobre a carta =====
-- Uma tela própria (sem a escala do palco): os botões ficam no tamanho físico de toque.
local T: { [string]: any } = {}
do
	-- 22: acima da carta (20) e do cartão de compra de veículo da inserção (21, CompraVeiculo, à
	-- direita); por isso o zoom fica à esquerda
	local tg = UiKit.screen("VT65CartaToque", 22)
	tg.Enabled = false
	T.gui = tg
	local m = 10
	local size = ToqueUi.minPx()
	local function square(text: string, kind: string?): TextButton
		local b = ToqueUi.bigButton(tg, text, kind, size)
		b.Size = UDim2.fromOffset(size, size)
		b.TextSize = math.floor(size * 0.5)
		return b
	end
	T.close = ToqueUi.bigButton(tg, "✕", "secondary", math.floor(size * 2.4))
	T.close.AnchorPoint = Vector2.new(1, 0)
	T.close.Position = UDim2.new(1, -m, 0, m)
	T.zin = square("+")
	T.zin.AnchorPoint = Vector2.new(0, 1)
	T.zin.Position = UDim2.new(0, m, 0.5, -4)
	T.zout = square("−")
	T.zout.AnchorPoint = Vector2.new(0, 0)
	T.zout.Position = UDim2.new(0, m, 0.5, 4)
	T.me = square("◎")
	T.me.AnchorPoint = Vector2.new(0, 0)
	T.me.Position = UDim2.new(0, m, 0.5, size + 12)
	-- confirmar: grande, embaixo ao centro (acima da faixa de estado da carta); a linha de baixo diz
	-- o ponto escolhido ou o motivo da espera
	local cw = math.floor(size * 6)
	T.cw, T.m, T.size = cw, m, size
	T.confirm = ToqueUi.bigButton(tg, "INSERIR", "primary", cw)
	T.confirm.AnchorPoint = Vector2.new(0.5, 1)
	T.confirm.Position = UDim2.new(0.5, 0, 1, -(m + 24))
	T.sub = UiKit.text2(T.confirm, "", math.max(12, math.floor(size * 0.26)), UiKit.V.TEXT, UiKit.F.TITLE_REG)
	T.sub.AnchorPoint = Vector2.new(0.5, 1)
	T.sub.Position = UDim2.new(0.5, 0, 0, -2)
	T.sub.Size = UDim2.new(1, 0, 0, math.floor(size * 0.36))
	T.sub.TextXAlignment = Enum.TextXAlignment.Center
	T.sub.TextStrokeColor3 = UiKit.V.BG
	T.sub.TextStrokeTransparency = 0.3
	T.sub.TextTruncate = Enum.TextTruncate.AtEnd
	-- à esquerda do confirmar: PAPEL (inserção) ou REUNIÃO (líder em campo)
	T.side = ToqueUi.bigButton(tg, "PAPEL", "secondary", math.floor(size * 2.6))
	T.side.AnchorPoint = Vector2.new(1, 1)
	T.side.Position = UDim2.new(0.5, -(cw / 2 + 12), 1, -(m + 24))

	T.close.Activated:Connect(function()
		closeMap()
	end)
	T.zin.Activated:Connect(function()
		CartaView.zoomBy(1.6)
	end)
	T.zout.Activated:Connect(function()
		CartaView.zoomBy(1 / 1.6)
	end)
	T.me.Activated:Connect(function()
		CartaView.centerOnMe()
	end)
	T.confirm.Activated:Connect(function()
		if mode == "spawn" then
			confirmar() -- D-209: o escolhido (o toque na carta escolhe)
			return
		end
		local f = CartaView.touchPick()
		if f and mode == "target" then
			chooseTarget(f.x, f.y)
		end
	end)
	T.side.Activated:Connect(function()
		if mode == "spawn" and not alive() then
			DeployScreen.open("role")
		elseif mode == "view" and alive() and player:GetAttribute("Role") == "squad_leader" then
			Net.event("SquadRally_Place"):FireServer()
		end
	end)
end

-- estado dos botões (10 vezes por segundo, com a carta aberta)
local function touchUpdate()
	local on = mapWanted and ToqueUi.active()
	T.gui.Enabled = on
	if not on then
		return
	end
	local spawnMode = mode == "spawn"
	T.close.Text = if spawnMode and side.Visible then "◄  VOLTAR" else "✕"
	-- D-228: na escolha de onde nascer o botão é menor e fica à esquerda do cartão do veículo; grande e
	-- no meio ele cobria a carta e o cartão
	local nascendo = spawnMode and side.Visible
	local largura = if nascendo then math.floor(T.size * 3.8) else T.cw
	local cx = if nascendo then 0.42 else 0.5
	T.confirm.Size = UDim2.fromOffset(largura, T.confirm.Size.Y.Offset)
	T.confirm.Position = UDim2.new(cx, 0, 1, -(T.m + 24))
	T.side.Position = UDim2.new(cx, -(largura / 2 + 12), 1, -(T.m + 24))
	T.me.Visible = not spawnMode
	local f = CartaView.touchPick()
	if spawnMode then
		-- D-209: o mesmo painel do mouse e do controle (NascerPedido), no botão grande
		local pt, p = painelAgora()
		T.confirm.Visible = true
		T.confirm.Text = p.botao
		T.sub.Text = if pt or selInfo
			then string.format(
				"%s · %s",
				Acabamento.viet(tostring(if pt then pt.name else (selInfo :: any).name)),
				p.linha
			)
			else p.linha
		T.confirm.BackgroundColor3 = if p.ativo then UiKit.V.AMBAR else UiKit.V.PANEL_2
		T.confirm.TextColor3 = if p.ativo then UiKit.V.AMBAR_TEXTO else UiKit.V.TEXT
		T.confirm.TextTransparency = if p.ativo then 0 else 0.3
		T.side.Visible = not alive()
		T.side.Text = "PAPEL"
	elseif mode == "target" then
		T.confirm.Visible = true
		T.confirm.Text = "CONFIRMAR ALVO"
		T.sub.Text = if f then CartaView.cursorGrid() else "toque no alvo"
		T.confirm.BackgroundColor3 = if f then UiKit.V.RED else UiKit.V.PANEL_2
		T.confirm.TextColor3 = UiKit.V.TEXT
		T.confirm.TextTransparency = if f then 0 else 0.3
		T.side.Visible = false
	else
		T.confirm.Visible = false
		T.side.Visible = alive() and player:GetAttribute("Role") == "squad_leader"
		T.side.Text = "REUNIÃO"
	end
end
CartaView.setTouchCallback(touchUpdate)

-- quadro a quadro: zoom, arrasto, cursor e ímã ficam na CartaView
local lastStatus = 0
RunService.RenderStepped:Connect(function(dt: number)
	if not mapWanted then
		if T.gui.Enabled then
			T.gui.Enabled = false
		end
		return
	end
	local pad = Input.isGamepad() and not (Input.state.disconnected or Input.state.robloxMenu)
	CartaView.step(dt, pad)
	cursorUI.Visible = pad or (ToqueUi.active() and mode == "target" and CartaView.touchPick() ~= nil)
	cursorUI.Position = UDim2.fromOffset(CartaView.cursorPx().X, CartaView.cursorPx().Y)
	local now = os.clock()
	if now - lastStatus > 0.1 then
		lastStatus = now
		-- D-209: na inserção a faixa de baixo diz o destino escolhido (o mesmo da carta e do painel)
		local spt, p = painelAgora()
		local nome = if spt then tostring(spt.name or "") elseif selInfo then selInfo.name else nil
		if mode == "spawn" and nome then
			status.Text = table.concat({ string.format("Destino: %s", Acabamento.viet(nome)), p.linha }, " · ")
		elseif mode ~= "target" or targetAbility == nil then
			status.Text = statusLine()
		else
			status.Text = string.format("ALVO %s — confirme", CartaView.cursorGrid())
		end
		hints.Text = hintText()
		-- D-228: na escolha de onde nascer, a faixa sai (o destino está na barra de baixo); as dicas ficam
		-- só para controle e toque, em que os comandos não são óbvios
		local dicas = mode ~= "spawn" or pad or ToqueUi.active()
		status.BackgroundTransparency = if dicas then 0.1 else 1
		status.TextTransparency = if mode == "spawn" then 1 else 0
		hints.TextTransparency = if dicas then 0 else 1
		if legend.Visible then
			CartaView.updateLegend()
		end
		touchUpdate()
		pintarPainel()
	end
end)

-- ===== estado do jogo =====
Net.event("Squad_State").OnClientEvent:Connect(function(st)
	squadState = st
	refresh()
end)
Net.event("Spawn_State").OnClientEvent:Connect(function(st)
	spawnList = st
	CartaView.setSpawns(st)
	-- D-209: sem destino escolhido, a carta abre com o sugerido escolhido (pronto, mais perto do
	-- objetivo do time); o jogador troca com um clique, LB/RB ou um toque
	if selId == nil and mode == "spawn" then
		local pt = NascerPedido.acha(spawnList, CartaView.preferido())
		if pt then
			selecionar(pt)
		end
	end
	pintarPainel()
end)
-- D-209: resposta do pedido de nascer (a SpawnTransition mostra a recusa na ordem; aqui o painel)
task.spawn(function()
	Net.event("Spawn_Result").OnClientEvent:Connect(function(r: any)
		if type(r) ~= "table" then
			return
		end
		local id = tostring(r.id)
		if pedidoId == id then
			pedidoEm, pedidoId = nil, nil
		end
		if r.ok == false then
			recusa = {
				id = id,
				msg = if type(r.msg) == "string" then r.msg else NascerPedido.motivo(r.cod, nil),
				t = os.clock(),
			}
			if r.cod == "rodada" then
				selecionar(nil) -- a partida mudou: os pontos são outros
			end
		end
		pintarPainel()
	end)
end)
-- partida nova: o destino e o pedido da velha não valem
ReplicatedStorage:GetAttributeChangedSignal("VT65Rodada"):Connect(function()
	pedidoEm, pedidoId, recusa = nil, nil, nil
	selecionar(nil)
end)
Net.event("Match_State").OnClientEvent:Connect(function(st)
	-- "quem está tomando" vem como lista cheia com "" = ninguém (MatchService.publish)
	if type(st) == "table" and type(st.capturing) == "table" then
		for i, v in st.capturing do
			if v == "" then
				st.capturing[i] = nil
			end
		end
	end
	matchState = st
	if mapWanted then
		CartaView.setMatch(st)
	end
end)
Net.event("Squad_Mark").OnClientEvent:Connect(function(m)
	CartaView.addMark(m)
end)
-- FrontService: pontos de inserção do lado (em campo), o squad e o ponto de reunião do squad
task.spawn(function()
	Net.event("Spawn_Points").OnClientEvent:Connect(function(list)
		CartaView.setInserts(list)
	end)
	Net.event("Squad_Positions").OnClientEvent:Connect(function(list)
		CartaView.setSquad(list)
	end)
	Net.event("SquadRally_State").OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" or type(msg.msg) ~= "string" then
			return
		end
		local kind = if msg.ok then "sucesso" elseif msg.lost then "alerta" else "erro"
		Toast.show(msg.msg, kind, { title = "Reunião do squad", key = "reuniao_squad" })
	end)
end)
for _, a in { "Faction", "SquadId", "Role", "MenuPrincipal" } do
	player:GetAttributeChangedSignal(a):Connect(refresh)
end
player.CharacterAdded:Connect(function(char)
	pinned = false
	pedidoEm, pedidoId = nil, nil -- nasceu: o pedido acabou (o destino fica para a próxima vez)
	refresh()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Died:Connect(refresh)
	refresh() -- o CharacterAdded chega antes do Humanoid: sem isto o mapa de spawn ficava na tela
end)
Input.DeviceChanged:Connect(refresh)

-- aviso enquanto o servidor gera o terreno (faixa escura à direita dos passos)
local loading = Instance.new("TextLabel")
loading.Position = UDim2.fromOffset(660, 138) -- entre as abas do lobby e os painéis
loading.Size = UDim2.fromOffset(580, 22)
loading.BackgroundColor3 = UiKit.V.PANEL
loading.BackgroundTransparency = 0.15
loading.BorderSizePixel = 0
loading.TextColor3 = UiKit.V.KHAKI
loading.TextXAlignment = Enum.TextXAlignment.Right
loading.FontFace = UiKit.F.TITLE_MED
loading.TextSize = TS(16)
UiKit.corner(loading, 3)
-- sem o tamanho do terreno no texto: o mapa muda (MapConfig.Bounds) e a frase ficava errada
loading.Text = "● Preparando o campo de batalha…"
loading.TextTruncate = Enum.TextTruncate.AtEnd
loading.ZIndex = 3
loading.Parent = stage
local loadingPad = Instance.new("UIPadding")
loadingPad.PaddingRight = UDim.new(0, 8)
loadingPad.Parent = loading
local function loadingState()
	loading.Visible = ReplicatedStorage:GetAttribute("TerrainReady") == false
end
ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Connect(loadingState)
loadingState()

-- palco: cabe na tela inteira (na TV, com margem de segurança e nunca menor que 1:1)
local function fit()
	local s = gui.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return
	end
	local k = math.min(s.X / DESIGN_W, s.Y / DESIGN_H)
	if UiKit.tv() then
		k = math.max(k * 0.92, 1)
	end
	stageScale.Scale = k
	DeployScreen.setScale(k)
	status.TextSize = TS(15)
	hints.TextSize = TS(13)
	mapTitle.TextSize = TS(20)
	mapSub.TextSize = TS(14)
	loading.TextSize = TS(16)
	if ToqueUi.active() then
		placeMap() -- toque: a carta em tela cheia acompanha a janela (girar o aparelho)
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()
refresh()

-- ===== gancho de teste (só no Studio): foto da carta =====
-- Na barra de comando do lado do cliente: workspace:SetAttribute("VT65DevCarta", "abrir") abre a carta
-- em campo; "zoom" aproxima na frente; "fechar" fecha. Volta a nil sozinho (dá para repetir).
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevCarta"):Connect(function()
		local v = workspace:GetAttribute("VT65DevCarta")
		if type(v) ~= "string" then
			return
		end
		if v == "abrir" or v == "zoom" then
			pinned = true
			refresh()
			if v == "zoom" and matchState and matchState.points then
				local f = player:GetAttribute("Faction")
				local best = nil
				for s, p in matchState.points do
					if matchState.active[s] and matchState.owner[s] ~= f then
						best = p
						break
					end
				end
				if best then
					moveCursorTo(best)
				end
			end
		elseif v == "fechar" then
			pinned = false
			refresh()
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevCarta", nil)
		end)
	end)
	-- pelo gancho comum das telas: VT65DevTela = "carta" abre (o mesmo que VT65DevCarta = "abrir")
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "carta" then
			workspace:SetAttribute("VT65DevCarta", "abrir")
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
