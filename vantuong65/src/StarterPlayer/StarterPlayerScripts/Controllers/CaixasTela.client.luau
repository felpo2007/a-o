--!strict
-- Caixas de suprimentos (D-173): a aba CAIXAS da loja (ShopController manda "caixas_show" com a área
-- dela) e as telas por cima: ITENS E PROBABILIDADES (antes de qualquer compra ou abertura), a
-- ABERTURA, a TROCA de Fragmentos, o HISTÓRICO e o CARTÃO (plaqueta e moldura).
-- Regras da tela (política "Paid Random Items" do Roblox e o pedido do dono):
--   - o resultado vem do servidor JÁ GRAVADO; a animação só mostra o que saiu (nada de "quase");
--   - a lista de itens com a chance exata de cada um está sempre a um botão com texto, antes do
--     botão de comprar/abrir, e mostra o que o jogador já tem (vira Fragmentos);
--   - caixa paga só aparece para quem o servidor libera (venda ligada, PolicyService ok); sem pressa
--     artificial, sem contador falso, sem preço inventado (o preço vem do GetProductInfoAsync);
--   - animação: completa, curta ou sem (botão no alto), e PULAR a qualquer momento.
-- D-177 (pedido do dono: roleta estilo Counter-Strike, com identidade própria): a galeria de
-- imagens com a chance real de cada item (sem nome no cartão; o nome fica na descrição), a
-- ROLETA horizontal que para no item que o servidor já gravou (Shared/Roleta) e a RECOMPENSA com
-- EQUIPAR e VOLTAR. Nada de sorteio aqui: a faixa só enfeita, com os pesos da própria lista.
-- D-174: as caixas grátis dos marcos (Recruta, Serviço, Batalhão, Campanha, Veterano) ficam
-- guardadas até o jogador abrir, cada uma com o "como ganhar"; a COMPRA DIRETA troca créditos
-- de intendência ($, ganhos jogando) pelo cosmético escolhido, sem sorteio.
-- Controle: tudo é botão selecionável (A escolhe, B volta). Studio: VT65DevTela = "caixas".
local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Caixas = require(ReplicatedStorage.Shared.Caixas) :: any
local Efeitos = require(ReplicatedStorage.Shared.Efeitos)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression) :: any
local Roleta = require(ReplicatedStorage.Shared.Roleta) :: any
local Bus = require(script.Parent.Bus)
local CaixaImagem = require(script.Parent.CaixaImagem)
local Input = require(script.Parent.Input)
local ItemArte = require(script.Parent.ItemArte)
local Toast = require(script.Parent.Toast)
local UiEfeitos = require(script.Parent.UiEfeitos)
local UiKit = require(script.Parent.UiKit)

local V, F, px = UiKit.V, UiKit.F, UiKit.px

local state: any = nil
local host: Frame? = nil
local root: Frame? = nil
local prices: { [number]: number } = {}
local anim = "completa" -- "completa" | "curta" | "sem"
local ANIM_NEXT = { completa = "curta", curta = "sem", sem = "completa" }
local ANIM_LABEL = { completa = "EFEITOS: COMPLETOS", curta = "EFEITOS: CURTOS", sem = "EFEITOS: DESLIGADOS" }
local MOTIVO = {
	desligada = "A venda em Robux ainda não foi liberada.",
	restrito = "Indisponível na sua conta pela regra do Roblox para itens aleatórios pagos.",
	politica_sem_resposta = "Não deu para confirmar sua conta agora. Tente mais tarde.",
	fora_da_temporada = "Fora da temporada.",
	sem_produto = "Ainda não está à venda.",
	invalida = "Caixa em manutenção.",
}

-- ===== ajudas =====
local function rgb(t: any, def: Color3): Color3
	return if type(t) == "table" and #t >= 3 then Color3.fromRGB(t[1], t[2], t[3]) else def
end

local function rar(id: string?): any
	if state and id then
		for _, r in state.raridades do
			if r.id == id then
				return r
			end
		end
	end
	return { id = "comum", nome = "Comum", cor = { 158, 158, 150 }, fragmentos = 0 }
end

local function frame(parent: Instance, size: UDim2, color: Color3?, tr: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.BackgroundColor3 = color or V.PANEL
	f.BackgroundTransparency = if color then tr or 0 else 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function text(parent: Instance, s: string, size: number, color: Color3?, font: any?): TextLabel
	local t = UiKit.rotulo(parent, size, color or V.TEXT, font)
	t.Text = s
	t.TextWrapped = true
	return t
end

local function kindName(kind: string): string
	return if kind == "emblema"
		then "Emblema do cartão"
		elseif kind == "plaqueta" then "Plaqueta do cartão"
		elseif kind == "moldura" then "Moldura do cartão"
		elseif kind == "creditos" then "Créditos ($)"
		elseif kind == "fragmentos" then "Fragmentos de Arsenal"
		else "Acabamento ou uniforme"
end

local function ehSaldo(item: any): boolean
	return item ~= nil and (item.kind == "creditos" or item.kind == "fragmentos")
end

-- desenho do item (emblema, plaqueta, moldura, arma em 3D, pano do uniforme ou prêmio de saldo),
-- quadrado de lado `s`: Controllers/ItemArte (D-175, o mesmo do ARQUIVO MILITAR)
local function desenhaItem(parent: Instance, item: any, s: number): Frame
	return ItemArte.desenha(parent, item, s)
end

-- (D-212: o caixote 3D de reserva foi para o Controllers/CaixaImagem, que mostra a imagem nova)

-- ===== estado =====
local function fetch(): any
	local ok, s = pcall(function()
		return Net.func("Suprimento_Get"):InvokeServer()
	end)
	if ok and type(s) == "table" and not s.carregando then
		state = s
	end
	return state
end

local function priceOf(id: number): number?
	if id == 0 then
		return nil
	end
	if prices[id] then
		return prices[id]
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Product)
	end)
	if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
		prices[id] = info.PriceInRobux
		return info.PriceInRobux
	end
	return nil
end

-- ===== telas por cima =====
local overlays: { [string]: ScreenGui } = {}
local function closeOverlay(name: string)
	local g = overlays[name]
	if g then
		overlays[name] = nil
		UiKit.closed(name)
		UiKit.release(g)
		g:Destroy()
		if root then
			UiKit.focus(root)
		end
	end
end

local function overlay(name: string, order: number, w: number, h: number): (ScreenGui, Frame)
	closeOverlay(name)
	local g = UiKit.screen("VT65" .. name, order)
	local back = frame(g, UDim2.fromScale(1, 1), V.BG, 0.25)
	back.Active = true
	local panel = frame(g, UDim2.fromOffset(w, h), V.PANEL, 0.02)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Active = true
	UiKit.corner(panel, 4)
	UiKit.edge(panel, V.LINE, 1, 0.3)
	UiKit.fit(g, panel, w, h, 12)
	overlays[name] = g
	UiKit.opened(name, order)
	return g, panel
end

local function closeButton(parent: Instance, name: string)
	local a = UiKit.action(parent, "FECHAR ×", "secondary", function()
		closeOverlay(name)
	end, { h = px(38, 52) })
	a.button.AnchorPoint = Vector2.new(1, 0)
	a.button.Position = UDim2.new(1, -px(14, 20), 0, px(12, 16))
	a.button.Size = UDim2.fromOffset(px(118, 160), px(38, 52))
end

Input.on("ui_back", "press", function()
	for _, name in { "CaixaAbertura", "CaixaOdds", "CaixaTroca", "CaixaLoja", "CaixaHist", "CaixaCartao" } do
		if overlays[name] and UiKit.backFor(name) then
			closeOverlay(name)
			return
		end
	end
end)

local refresh: () -> () = function() end
-- D-212: a caixa clicada na vitrine da loja (o próximo desenho da lista vai até ela)
local focoPendente: string? = nil
Bus.on("caixa_foco", function(id: string)
	focoPendente = id
end)
local abrirGratis: (c: any) -> () = function(_c: any) end
local comprar: (c: any) -> () = function(_c: any) end

-- botão de ação da caixa (abrir com bilhete, abrir uma guardada ou comprar), ou nil se não há o que
-- fazer
local function botaoAcao(parent: Instance, c: any): any
	if c.tipo == "gratuita" and c.fonte == "marco" then
		local g = c.guardadas or 0
		local a = UiKit.action(
			parent,
			if g == 1
				then "ABRIR · 1 GUARDADA"
				elseif g > 1 then string.format("ABRIR · %d GUARDADAS", g)
				else "NENHUMA GUARDADA",
			"premio",
			function()
				abrirGratis(c)
			end,
			{ h = px(46, 62) }
		)
		a.enabled(g >= 1 and c.bloqueio == nil)
		return a
	end
	if c.tipo == "gratuita" then
		local n = c.bilhetes or 1
		local a = UiKit.action(
			parent,
			string.format("ABRIR · %d BILHETE%s", n, if n > 1 then "S" else ""),
			"premio",
			function()
				abrirGratis(c)
			end,
			{ h = px(46, 62) }
		)
		a.enabled(state.bilhetes >= n and c.bloqueio == nil)
		return a
	end
	if c.bloqueio then
		return nil
	end
	local p = priceOf(c.produtoId)
	local label = if p then string.format("COMPRAR · R$ %d", p) else "COMPRAR"
	local a = UiKit.action(parent, label, "robux", function()
		comprar(c)
	end, { h = px(46, 62) })
	return a
end

-- ===== sons (D-177, tools/sons_roleta.py) =====
local sonsCarregados = false
local function carregaSons()
	if sonsCarregados then
		return
	end
	sonsCarregados = true
	task.spawn(function()
		local lista = {}
		for _, k in
			{
				"roleta_tique",
				"roleta_parada",
				"roleta_revela",
				"roleta_raro",
				"roleta_lendario",
				"caixa_pouso",
				"caixa_tremor",
				"caixa_estouro",
			}
		do
			local id = AssetIds.Sounds and AssetIds.Sounds[k]
			if type(id) == "number" and id ~= 0 then
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://" .. id
				table.insert(lista, s)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(lista)
		end)
		for _, s in lista do
			s:Destroy()
		end
	end)
end

local function tocar(chave: string, vol: number, tom: number?)
	local id = AssetIds.Sounds and AssetIds.Sounds[chave]
	if type(id) ~= "number" or id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = vol
	s.PlaybackSpeed = tom or 1
	local g = SoundService:FindFirstChild("VT65Efeitos")
	if g and g:IsA("SoundGroup") then
		s.SoundGroup = g
	end
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- D-213: as camadas da caixa aberta e as texturas dos efeitos baixam no ABRIR (antes da resposta do
-- servidor), para estarem prontas no estouro. Só a caixa que vai abrir: cada camada pesa ~2 MB de
-- textura.
local preCarregadas: { [string]: boolean } = {}
local function preCaixa(id: string)
	if preCarregadas[id] then
		return
	end
	preCarregadas[id] = true
	local lista: { string } = {}
	for _, camada in { "corpo", "tampa" } do
		local img = CaixaImagem.id(id, camada)
		if img then
			table.insert(lista, string.format("rbxassetid://%d", img))
		end
	end
	for _, nome in { "faisca", "brilho", "raio", "anel", "cintila" } do
		local img = UiEfeitos.imagem(nome)
		if img then
			table.insert(lista, img)
		end
	end
	if #lista > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(lista)
			end)
		end)
	end
end

local SOM_RARIDADE = {
	comum = "roleta_revela",
	incomum = "roleta_revela",
	raro = "roleta_raro",
	epico = "roleta_lendario",
	lendario = "roleta_lendario",
}

local function equipar(it: any)
	local ok = pcall(function()
		if it.kind == "plaqueta" or it.kind == "moldura" then
			Net.func("Suprimento_Equipar")
				:InvokeServer({ slot = if it.kind == "plaqueta" then "tag" else "mol", item = it.id })
		elseif it.kind == "emblema" then
			Net.event("Campanha_Action"):FireServer({ op = "card_set", emblem = it.id })
		elseif it.kind == "skin" then
			Net.event("Gear_Equip"):FireServer(it.id, true)
		end
	end)
	Toast.show(if ok then "Equipado." else "Não deu para equipar agora.")
end

local function equipavel(it: any): boolean
	return it ~= nil and (it.kind == "plaqueta" or it.kind == "moldura" or it.kind == "emblema" or it.kind == "skin")
end

-- texto acessível de um item (o cartão não tem nome; a descrição mostra)
local function descricao(e: any): string
	local it = ItemArte.info(e.item)
	local r = rar(it.raridade)
	local base =
		string.format("%s · %s · %s · %s", it.nome or it.id, UiKit.upper(r.nome), kindName(it.kind or ""), e.pct)
	if e.repetido then
		base ..= string.format(" · Você já tem: vira +%d Fragmentos", e.fragmentos)
	end
	return base
end

-- ITENS E PROBABILIDADES (antes de comprar ou abrir): galeria de imagens com a chance real de
-- cada uma. Sem nome no cartão (o pedido); o nome e os detalhes aparecem na descrição embaixo ao
-- passar o cursor, focar com o controle ou tocar.
local function abrirOdds(c: any)
	carregaSons()
	local cam = workspace.CurrentCamera
	local W = math.min(px(780, 1040), math.floor(cam.ViewportSize.X - 24))
	local H = px(600, 800)
	local _, panel = overlay("CaixaOdds", 42, W, H)
	closeButton(panel, "CaixaOdds")
	local t = text(panel, UiKit.upper(c.nome), px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local custo = if c.fonte == "marco"
		then string.format("Grátis, não se compra. Como ganhar: %s", c.ganha or "jogando.")
		elseif c.tipo == "gratuita" then string.format(
			"Custo: %d Bilhete de Recompensa (ganho jogando; não se compra).",
			c.bilhetes or 1
		)
		else (function(): string
			local p = priceOf(c.produtoId)
			return if p
				then string.format("Preço: R$ %d (Robux), cobrado pelo Roblox na confirmação.", p)
				else "Preço: confirmado pelo Roblox na compra."
		end)()
	local sub =
		text(panel, custo .. " · 1 resultado por abertura. Chances exatas: a soma é 100%.", px(14, 19), V.DIM, F.BODY)
	sub.Position = UDim2.fromOffset(px(18, 24), px(48, 62))
	sub.Size = UDim2.new(1, -px(36, 48), 0, px(36, 48))
	-- por raridade
	local chips = frame(panel, UDim2.new(1, -px(36, 48), 0, px(26, 34)))
	chips.Position = UDim2.fromOffset(px(18, 24), px(88, 116))
	UiKit.list(chips, true, px(10, 14))
	for _, r in state.raridades do
		local w = c.porRaridade[r.id] or 0
		if w > 0 then
			local chip = UiKit.tag(
				chips,
				string.format("%s %s", UiKit.upper(r.nome), Caixas.pct(w)),
				rgb(r.cor, V.DIM),
				px(13, 18)
			)
			chip.AutomaticSize = Enum.AutomaticSize.X
		end
	end
	-- a galeria (todas as imagens do mesmo tamanho)
	local topo = px(122, 162)
	local baixo = px(160, 214) -- descrição + regras + botão
	local list = Instance.new("ScrollingFrame")
	list.Name = "Galeria"
	list.Position = UDim2.fromOffset(px(18, 24), topo)
	list.Size = UDim2.new(1, -px(36, 48), 1, -topo - baixo)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = panel
	local s = px(104, 138)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(s + px(8, 10), s + px(34, 44))
	grid.CellPadding = UDim2.fromOffset(px(8, 10), px(8, 10))
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	-- descrição (acessível) e as regras embaixo
	local desc = text(panel, "Toque ou passe o cursor num item para ver o nome.", px(14, 19), V.TEXT, F.BODY_B)
	desc.Name = "Descricao"
	desc.AnchorPoint = Vector2.new(0, 1)
	desc.Position = UDim2.new(0, px(18, 24), 1, -baixo + px(40, 54))
	desc.Size = UDim2.new(1, -px(36, 48), 0, px(36, 48))
	desc.TextYAlignment = Enum.TextYAlignment.Top
	local regras = text(panel, "• " .. table.concat(state.regras, "\n• "), px(11, 14), V.DIM, F.BODY)
	regras.AnchorPoint = Vector2.new(0, 1)
	regras.Position = UDim2.new(0, px(18, 24), 1, -px(64, 86))
	regras.Size = UDim2.new(1, -px(36, 48), 0, px(66, 88))
	regras.TextYAlignment = Enum.TextYAlignment.Top
	for i, e in c.lista do
		local it = ItemArte.info(e.item)
		local rc = ItemArte.corRaridade(it.raridade)
		local cel = Instance.new("TextButton")
		cel.Name = "Cel_" .. tostring(it.id)
		cel.Text = ""
		cel.AutoButtonColor = false
		cel.LayoutOrder = i
		cel.BackgroundColor3 = rc:Lerp(V.BG, 0.72)
		cel.BorderSizePixel = 0
		cel.Selectable = true
		cel.Parent = list
		UiKit.corner(cel, 6)
		local borda = UiKit.edge(cel, rc, 2, 0.15)
		local box = ItemArte.desenha(cel, e.item, s, { soldado = true })
		box.Position = UDim2.fromOffset(px(4, 5), px(4, 5))
		local pc = text(cel, e.pct, px(16, 22), V.TEXT, F.TITLE)
		pc.AnchorPoint = Vector2.new(0, 1)
		pc.Position = UDim2.new(0, 0, 1, -px(4, 5))
		pc.Size = UDim2.new(1, 0, 0, px(24, 32))
		pc.TextXAlignment = Enum.TextXAlignment.Center
		if e.repetido then
			-- já tem: selo no canto (vira Fragmentos; a descrição diz quantos)
			local selo = frame(cel, UDim2.fromOffset(px(22, 28), px(22, 28)), V.KHAKI, 0)
			selo.Name = "JaTem"
			selo.AnchorPoint = Vector2.new(1, 0)
			selo.Position = UDim2.new(1, -px(3, 4), 0, px(3, 4))
			selo.ZIndex = 6
			UiKit.corner(selo, 99)
			local v = text(selo, "✓", px(14, 18), V.BG, F.TITLE)
			v.Size = UDim2.fromScale(1, 1)
			v.TextXAlignment = Enum.TextXAlignment.Center
			v.ZIndex = 7
		end
		local function mostra()
			desc.Text = descricao(e)
			borda.Thickness = 3
		end
		local function some()
			borda.Thickness = 2
		end
		cel.MouseEnter:Connect(mostra)
		cel.MouseLeave:Connect(some)
		cel.SelectionGained:Connect(mostra)
		cel.SelectionLost:Connect(some)
		UiKit.bind(cel, mostra)
	end
	local row = frame(panel, UDim2.new(1, -px(36, 48), 0, px(46, 62)))
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0, px(18, 24), 1, -px(12, 16))
	local a = botaoAcao(row, c)
	if a then
		a.button.Size = UDim2.new(0.6, 0, 1, 0)
	end
	UiKit.focus(panel)
end

-- RECOMPENSA: o cartão ampliado, a raridade com a luz dela, EQUIPAR e VOLTAR. O item já está no
-- inventário (gravado pelo servidor antes de qualquer animação).
local function recompensa(panel: Frame, g: ScreenGui, res: any, item: any)
	local r = rar(res.raridade)
	local rc = rgb(r.cor, V.KHAKI)
	local alto = res.raridade == "epico" or res.raridade == "lendario"
	local card = frame(panel, UDim2.fromScale(1, 1))
	card.Name = "Recompensa"
	card.ClipsDescendants = true -- a luz não vaza do painel
	-- D-213: a luz da raridade com os efeitos (Controllers/UiEfeitos): o halo macio respirando atrás do
	-- cartão e os raios girando (do raro para cima). Com os efeitos desligados (ou movimento
	-- reduzido), só o halo parado.
	local S = px(230, 300)
	local Wp = panel.Size.X.Offset
	local cy = px(40, 54) + S / 2
	local forca = Efeitos.FORCA[res.raridade or "comum"] or Efeitos.FORCA.comum
	local vivo = anim ~= "sem"
	local raro = alto or res.raridade == "raro"
	UiEfeitos.halo(
		card,
		UDim2.fromOffset(Wp / 2, cy),
		rc,
		math.floor(S * (1.5 + forca)),
		math.clamp(0.62 - forca * 0.3, 0.1, 0.8),
		if vivo then 2.4 else nil,
		1
	)
	if vivo and raro then
		UiEfeitos.raios(
			card,
			Vector2.new(Wp / 2, cy),
			rc,
			math.floor(S * (2.2 + forca)),
			if alto then 6 else 4,
			if alto then 11 else 7,
			1
		)
	end
	local ampliado = Instance.new("Frame")
	ampliado.Name = "Ampliado"
	ampliado.BackgroundTransparency = 1
	ampliado.AnchorPoint = Vector2.new(0.5, 0)
	ampliado.Position = UDim2.new(0.5, 0, 0, px(40, 54))
	ampliado.Size = UDim2.fromOffset(S, S)
	ampliado.ZIndex = 3
	ampliado.Parent = card
	local escala = Instance.new("UIScale")
	escala.Scale = 0.6
	escala.Parent = ampliado
	if item then
		local box = ItemArte.desenha(ampliado, item, S, { soldado = true })
		box.Position = UDim2.fromScale(0, 0)
		local st = box:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = if alto then 5 else 3
		end
	else
		-- só Fragmentos (conta restrita): a ficha de saldo
		local box = ItemArte.desenha(
			ampliado,
			{ id = "frag", kind = "fragmentos", quantidade = res.fragmentos, raridade = "comum" },
			S
		)
		box.Position = UDim2.fromScale(0, 0)
	end
	TweenService:Create(escala, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	-- D-213: o item aparece com faíscas e a onda na cor da raridade, cintilas no cartão, o brilho
	-- passando por ele e, no épico e no lendário, brasas subindo
	if vivo then
		local centro = Vector2.new(Wp / 2, cy)
		UiEfeitos.faiscas(card, centro, rc, Efeitos.quantas(res.raridade, anim), {
			vmin = 240,
			vmax = 620 + 200 * forca,
			gravidade = 420,
			z = 30,
		})
		UiEfeitos.onda(card, centro, rc, S * 0.95, 0.6, 29)
		UiEfeitos.cintilas(ampliado, rc, if alto then 4 elseif raro then 3 else 1, nil, 32)
		local vidro = Instance.new("Frame")
		vidro.Name = "Vidro"
		vidro.BackgroundTransparency = 1
		vidro.Size = UDim2.fromScale(1, 1)
		vidro.ClipsDescendants = true
		vidro.ZIndex = 10
		vidro.Parent = ampliado
		UiEfeitos.varre(vidro, 3.2, nil, 11, 0.4)
		if alto then
			UiEfeitos.brasas(card, rc, 12, 77, 2)
		end
	end
	local col = frame(card, UDim2.new(1, 0, 0, px(150, 200)))
	col.AnchorPoint = Vector2.new(0, 1)
	col.Position = UDim2.new(0, 0, 1, -px(10, 14))
	UiKit.list(col, false, px(6, 8), Enum.HorizontalAlignment.Center)
	if res.raridade then
		local tag = UiKit.tag(col, UiKit.upper(r.nome), rc, px(16, 22))
		tag.LayoutOrder = 1
		tag.AutomaticSize = Enum.AutomaticSize.X
	end
	local nome = text(col, if item then item.nome else "Fragmentos de Arsenal", px(24, 32), V.TEXT, F.TITLE)
	nome.LayoutOrder = 2
	nome.Size = UDim2.new(1, -px(24, 32), 0, px(32, 42))
	nome.TextXAlignment = Enum.TextXAlignment.Center
	local linha = if res.origem == "restrito"
		then string.format(
			"Itens aleatórios pagos indisponíveis para a sua conta agora: +%d Fragmentos de Arsenal, sem sorteio.",
			res.fragmentos
		)
		elseif res.repetido then string.format(
			"Você já tinha este item: virou +%d Fragmentos de Arsenal.",
			res.fragmentos
		)
		elseif ehSaldo(item) then "Entrou no seu saldo."
		elseif res.origem == "compra" then "Comprado com créditos: já é seu."
		else "Novo no seu arsenal."
	local l = text(col, linha, px(15, 20), if res.repetido then V.BRASS else V.KHAKI, F.BODY)
	l.LayoutOrder = 3
	l.Size = UDim2.new(1, -px(24, 32), 0, px(22, 30))
	l.TextXAlignment = Enum.TextXAlignment.Center
	local row = frame(col, UDim2.new(1, 0, 0, px(46, 62)))
	row.LayoutOrder = 4
	UiKit.list(row, true, px(12, 16), Enum.HorizontalAlignment.Center)
	if item and not ehSaldo(item) and equipavel(item) then
		local eq = UiKit.action(row, "EQUIPAR", "primary", function()
			equipar(item)
			closeOverlay("CaixaAbertura")
			refresh()
		end, { h = px(46, 62) })
		eq.button.Name = "Equipar"
		eq.button.Size = UDim2.fromOffset(px(180, 240), px(46, 62))
	end
	local volta = UiKit.action(row, "VOLTAR", "secondary", function()
		closeOverlay("CaixaAbertura")
	end, { h = px(46, 62) })
	volta.button.Name = "Voltar"
	volta.button.Size = UDim2.fromOffset(px(150, 200), px(46, 62))
	if overlays.CaixaAbertura == g then
		UiKit.focus(row)
	end
end

-- D-213 (dono: "animação perfeita e realista com efeitos visuais ... para a abertura das caixas"): a
-- caixa antes da roleta, no roteiro do Shared/Efeitos: cai do alto (baque, poeira, tranco), sacode
-- cada vez mais (faíscas escapando pela fresta), estoura (clarão, a tampa voa, faíscas, onda e raios)
-- e some na luz enquanto a roleta entra. A luz é a da CAIXA: o item só aparece na roleta. As duas
-- camadas da caixa aberta (corpo e tampa) são renders do Blender no enquadramento da fechada; sem
-- elas, a fechada some no clarão. `pulou()` corta para o fim. Devolve o palco (os raios ficam
-- atrás da roleta até ela parar) e marca o atributo "Intro" ("feita") quando acaba.
local function introCaixa(panel: Frame, W: number, H: number, c: any, modo: string, pulou: () -> boolean): Frame
	local R = Efeitos.ROTEIRO[modo] or Efeitos.ROTEIRO.completa
	local acento = CaixaImagem.ACENTO[tostring(c.id)] or V.AMBAR
	local palco = frame(panel, UDim2.fromScale(1, 1))
	palco.Name = "Palco"
	palco.ClipsDescendants = true -- a caixa cai de dentro do painel
	palco:SetAttribute("Intro", "rodando")
	local S = math.floor(math.min(H * 0.66, W * 0.42))
	local cx, cy = W / 2, H * 0.54
	-- sombra no chão (cresce com a queda) e o halo da caixa
	local sombra = UiEfeitos.halo(palco, UDim2.fromOffset(cx, cy + S * 0.34), Color3.new(0, 0, 0), S, 0.4, nil, 1)
	sombra.Name = "Sombra"
	sombra.Size = UDim2.fromOffset(math.floor(S * 0.95), math.floor(S * 0.24))
	local halo = UiEfeitos.halo(palco, UDim2.fromOffset(cx, cy), acento, math.floor(S * 1.9), 0.8, 1.4, 1)
	halo:SetAttribute("Tr", 0.8)
	local caixa = frame(palco, UDim2.fromOffset(S, S))
	caixa.Name = "Caixa"
	caixa.AnchorPoint = Vector2.new(0.5, 0.5)
	caixa.Position = UDim2.fromOffset(cx, cy)
	caixa.ZIndex = 3
	local esc = Instance.new("UIScale")
	esc.Parent = caixa
	local function camada(nome: string, id: number?, z: number): ImageLabel?
		if not id then
			return nil
		end
		local im = Instance.new("ImageLabel")
		im.Name = nome
		im.BackgroundTransparency = 1
		im.AnchorPoint = Vector2.new(0.5, 0.5)
		im.Position = UDim2.fromScale(0.5, 0.5)
		im.Size = UDim2.fromScale(1, 1)
		im.ScaleType = Enum.ScaleType.Fit
		im.Image = string.format("rbxassetid://%d", id)
		im.ZIndex = z
		im.Parent = caixa
		return im
	end
	local fechada: GuiObject = camada("Fechada", CaixaImagem.id(c.id), 2)
		or CaixaImagem.desenha(caixa, c.id, c.modelo or "caixa_municao_us")
	local corpo = camada("Corpo", CaixaImagem.id(c.id, "corpo"), 2)
	local tampa = camada("Tampa", CaixaImagem.id(c.id, "tampa"), 4)
	local aberta = corpo ~= nil and tampa ~= nil
	-- as camadas ficam à vista e quase transparentes: escondida (ou com 1), a imagem não é desenhada e
	-- não baixa (no Studio, a caixa sumia no estouro, e depois o IsLoaded nunca virava); o
	-- pré-carregamento começou no ABRIR (preCaixa)
	for _, im in { corpo, tampa } do
		if im then
			im.ImageTransparency = 0.98
		end
	end
	local function pinta(tr: number)
		if fechada:IsA("ImageLabel") then
			fechada.ImageTransparency = tr
		else
			fechada.Visible = tr < 0.5
		end
		if not aberta or fechada.Visible then
			return -- antes do estouro as camadas abertas seguem transparentes
		end
		if corpo then
			corpo.ImageTransparency = tr
		end
		if tampa then
			tampa.ImageTransparency = math.max(tr, tampa.ImageTransparency)
		end
	end
	local t = 0
	local feito: { [string]: boolean } = {}
	local proxFaisca = 0
	local piorQuadro = 0
	local tTroca: number? = nil -- quando a fechada deu lugar às camadas abertas
	local espera = 0 -- quanto o estouro esperou as camadas baixarem
	-- cada fase acontece uma vez; o instante fica no painel ("Abertura_<fase>", s) para o teste no Studio
	local function uma(nome: string): boolean
		if feito[nome] then
			return false
		end
		feito[nome] = true
		panel:SetAttribute("Abertura_" .. nome, math.floor(t * 1000 + 0.5) / 1000)
		return true
	end
	UiEfeitos.roda(function(dt: number): boolean
		if not palco.Parent then
			return false
		end
		-- um quadro travado conta no máximo 0,1 s: a abertura fica mais lenta, mas não pula fase (no
		-- Studio, um quadro de 0,8 s passava direto do estouro para a saída)
		t += math.min(dt, 0.1)
		piorQuadro = math.max(piorQuadro, dt)
		-- as camadas abertas ainda baixando: a caixa sacode mais um pouco (até 1,2 s) antes de estourar
		if
			aberta
			and not feito.estouro
			and t >= R.estouro
			and espera < 1.2
			and not (corpo and tampa and corpo.IsLoaded and tampa.IsLoaded)
		then
			espera += math.min(dt, 0.1)
			t = R.estouro - 0.001
		end
		if pulou() then
			t = math.max(t, R.fim)
		end
		-- queda e pouso
		local dy = Efeitos.queda(t, R.pouso) * S
		local sx, sy = 1, 1
		if t >= R.pouso then
			if uma("pouso") and R.pouso > 0 and not pulou() then
				tocar("caixa_pouso", 0.8)
				UiEfeitos.tremer(panel, 0.25, px(6, 8))
				local chao = Vector2.new(cx, cy + S * 0.3)
				local po = Color3.fromRGB(176, 160, 124)
				for _, lado in { 0, math.pi } do
					UiEfeitos.faiscas(palco, chao, po, 7, {
						cone = lado - (if lado == 0 then 0.25 else -0.25),
						abertura = 0.7,
						vmin = 60,
						vmax = 220,
						gravidade = -60, -- a poeira sobe devagar
						arrasto = 3.2,
						tam = px(30, 40),
						z = 5,
					})
				end
			end
			sx, sy = Efeitos.amasso(t - R.pouso)
		end
		-- tremor (a luz da caixa cresce; faíscas escapam pela fresta)
		local tx, ty, giro = 0, 0, 0
		if t >= R.tremor and t < R.estouro then
			if uma("tremor") and not pulou() then
				tocar("caixa_tremor", 0.7)
			end
			local dur = R.estouro - R.tremor
			tx, ty, giro = Efeitos.tremor(t - R.tremor, dur, 1)
			local u = (t - R.tremor) / dur
			halo:SetAttribute("Tr", 0.8 - 0.45 * u)
			if t >= proxFaisca then
				proxFaisca = t + 0.16 - 0.1 * u
				UiEfeitos.faiscas(
					palco,
					-- o ponto da fresta anda pelo tempo (nada de sorteio nesta tela)
					Vector2.new(cx + math.sin(t * 37.1) * S * 0.3, cy - S * 0.1),
					acento,
					1 + math.floor(u * 3),
					{ abertura = 0.9, vmin = 120, vmax = 320, gravidade = 380, tam = px(16, 22), z = 6 }
				)
			end
		end
		-- estouro
		if t >= R.estouro then
			if uma("estouro") then
				if not pulou() then
					tocar("caixa_estouro", 0.85)
					-- clarão curto (no Studio, 0,7 de branco apagava a caixa abrindo)
					UiEfeitos.clarao(panel, Color3.new(1, 1, 1), 0.35, 0.22, 40)
					UiEfeitos.clarao(panel, acento, 0.25, 0.6, 39)
					local boca = Vector2.new(cx, cy - S * 0.12)
					UiEfeitos.faiscas(palco, boca, acento, Efeitos.quantas("caixa", modo), {
						cone = -math.pi / 2,
						abertura = math.pi * 1.3,
						vmin = 300,
						vmax = 880,
						gravidade = 520,
						z = 8,
					})
					UiEfeitos.onda(palco, boca, acento, S * 1.05, 0.55, 7)
					UiEfeitos.tremer(panel, 0.35, px(10, 14))
				end
				UiEfeitos.raios(palco, Vector2.new(cx, cy - S * 0.15), acento, math.floor(S * 2.6), 5, 14, 2)
				halo:SetAttribute("Tr", 0.2)
			end
			-- a fechada só sai quando as duas camadas abertas já baixaram (no Studio, a 1ª abertura
			-- de uma caixa deixava o palco vazio por ~0,3 s); até a saída, senão fica a fechada
			if aberta and fechada.Visible and corpo and tampa and corpo.IsLoaded and tampa.IsLoaded and t < R.saida then
				fechada.Visible = false
				corpo.ImageTransparency = 0
				tampa.ImageTransparency = 0
				uma("trocaCamadas")
				tTroca = t
			end
			local te = t - R.estouro
			sx, sy = Efeitos.amasso(te * 1.3)
			local tt = tTroca
			if tampa and tt then
				-- o voo conta da troca (a tampa sai do lugar dela, sem salto)
				local lx, ly, lg, ltr = Efeitos.tampa(t - tt)
				tampa.Position = UDim2.fromScale(0.5 + lx, 0.5 + ly)
				tampa.Rotation = lg * 0.25
				tampa.ImageTransparency = ltr
			end
		end
		-- saída: a caixa cresce um pouco e some na luz
		local fade = 0
		if t >= R.saida then
			fade = math.clamp((t - R.saida) / math.max(0.01, R.fim - R.saida), 0, 1)
			esc.Scale = 1 + 0.12 * fade
			halo:SetAttribute("Tr", 0.2 + 0.4 * fade)
		end
		pinta(fade)
		sombra.Visible = fade < 1
		if sombra:IsA("ImageLabel") then
			local alt = math.clamp(1 + dy / (S * 1.4), 0, 1) -- 0 no alto, 1 no chão
			sombra.ImageTransparency = math.max(1 - (0.6 * alt) * (1 - fade), 0.4)
		end
		caixa.Position = UDim2.fromOffset(cx + tx * S, cy + dy + ty * S)
		caixa.Size = UDim2.fromOffset(math.floor(S * sx), math.floor(S * sy))
		caixa.Rotation = giro
		if t >= R.fim then
			caixa:Destroy()
			sombra:Destroy()
			uma("fim")
			panel:SetAttribute("Abertura_PiorQuadroMs", math.floor(piorQuadro * 1000 + 0.5))
			panel:SetAttribute("Abertura_EsperaMs", math.floor(espera * 1000 + 0.5))
			panel:SetAttribute("Abertura_Camadas", aberta)
			palco:SetAttribute("Intro", "feita")
			return false
		end
		return true
	end)
	return palco
end

-- ABERTURA (D-177): roleta horizontal que para no item que o servidor JÁ gravou. Troca, compra
-- direta, conta restrita (só Fragmentos) e efeitos desligados vão direto à recompensa (não houve
-- sorteio para mostrar, ou o jogador não quer a animação).
local function abertura(c: any, res: any, item: any)
	carregaSons()
	local cam = workspace.CurrentCamera
	local vpW = cam.ViewportSize.X
	local W = math.floor(math.min(vpW - 24, px(1120, 1480)))
	local H = px(470, 620)
	local g, panel = overlay("CaixaAbertura", 46, W, H)
	panel.Name = "PainelRoleta"
	panel.BackgroundColor3 = V.BG
	local fundo = Instance.new("UIGradient")
	fundo.Rotation = 90
	fundo.Color = ColorSequence.new(V.BG_OLIVE, V.BG)
	fundo.Parent = panel
	local titulo = text(panel, UiKit.upper(c.nome or "Caixa"), px(16, 22), V.KHAKI, Font.fromEnum(UiKit.TYPE_OLD))
	titulo.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	titulo.Size = UDim2.new(1, -px(170, 230), 0, px(26, 34))
	local lista: { any } = {}
	for _, e in (c.lista or {}) :: { any } do
		if type(e.item) == "table" and type(e.peso) == "number" then
			table.insert(lista, { item = e.item.id, peso = e.peso })
		end
	end
	local soma = 0
	for _, e in lista do
		soma += e.peso
	end
	local podeRoleta = anim ~= "sem" and type(res.item) == "string" and soma == Caixas.ESCALA
	if not podeRoleta then
		recompensa(panel, g, res, item)
		tocar("roleta_parada", 0.6)
		tocar(SOM_RARIDADE[res.raridade or "comum"] or "roleta_revela", 0.7)
		return
	end
	-- PULAR desde o começo: apertado durante a montagem, vai direto ao vencedor
	local skip = false
	local pular = UiKit.action(panel, "PULAR", "secondary", function()
		skip = true
	end, { h = px(38, 52) })
	pular.button.Name = "Pular"
	pular.button.AnchorPoint = Vector2.new(1, 0)
	pular.button.Position = UDim2.new(1, -px(14, 20), 0, px(12, 16))
	pular.button.Size = UDim2.fromOffset(px(110, 146), px(38, 52))
	pular.button.ZIndex = 6 -- por cima do palco da caixa
	UiKit.focus(panel)
	-- D-213: a caixa estoura antes da roleta (enquanto isso a roleta é montada, escondida). Sem efeitos
	-- ou com movimento reduzido, a roleta vem direto.
	local palco: Frame? = nil
	if anim ~= "sem" and not UiEfeitos.calmo() then
		palco = introCaixa(panel, W, H, c, anim, function(): boolean
			return skip
		end)
	end
	-- a janela da faixa ocupa quase toda a largura; 5 a 7 cartões no PC, 3 no celular
	local janelaW = W - px(32, 44)
	local gap = px(8, 12)
	-- celular (só toque): até 5 cartões; PC e controle: até 7
	local soToque = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local n = Roleta.visiveis(janelaW, px(104, 140), if soToque then 5 else 7)
	local cartao = Roleta.larguraCartao(janelaW, n, gap)
	local cartaoH = cartao + px(10, 14)
	local janelaH = cartaoH + px(28, 36)
	local janela = frame(panel, UDim2.fromOffset(janelaW, janelaH), Color3.fromRGB(12, 13, 10), 0)
	janela.Name = "Janela"
	janela.AnchorPoint = Vector2.new(0.5, 0.5)
	janela.Position = UDim2.fromScale(0.5, 0.48)
	janela.ClipsDescendants = true
	janela.ZIndex = 3 -- na frente dos raios da caixa
	janela.Visible = palco == nil
	UiKit.corner(janela, 4)
	UiKit.edge(janela, V.LINE, 1, 0.3)
	local y = math.floor((janelaH - cartaoH) / 2)
	local faixa = frame(janela, UDim2.fromOffset(Roleta.TOTAL * (cartao + gap), cartaoH))
	faixa.Name = "Faixa"
	local function px0(i: number): number
		return math.floor(Roleta.posicao(i, cartao, gap, janelaW) + 0.5)
	end
	faixa.Position = UDim2.fromOffset(px0(Roleta.INICIO), y)
	local rng = Random.new()
	local ids = Roleta.faixa(lista, res.item, function(): number
		return rng:NextInteger(0, Caixas.ESCALA - 1)
	end)
	local cartoes: { Frame } = {}
	local moldes: { Instance } = {}
	local jaPre: { [string]: boolean } = {}
	for i, id in ids do
		local it = ItemArte.info(id)
		local rc = ItemArte.corRaridade(it.raridade)
		local cf = frame(faixa, UDim2.fromOffset(cartao, cartaoH), rc:Lerp(V.BG, 0.7), 0)
		cf.Name = "Cartao_" .. i
		cf.Position = UDim2.fromOffset((i - 1) * (cartao + gap), 0)
		UiKit.corner(cf, 6)
		UiKit.edge(cf, rc, 2, 0.1)
		local esc = Instance.new("UIScale")
		esc.Parent = cf
		local box = ItemArte.desenha(cf, id, cartao - px(8, 10), { soldado = true })
		box.Position = UDim2.fromOffset(px(4, 5), px(4, 5))
		-- faixa da raridade embaixo da imagem
		local barra = frame(cf, UDim2.new(1, -px(8, 10), 0, px(4, 5)), rc, 0)
		barra.AnchorPoint = Vector2.new(0.5, 1)
		barra.Position = UDim2.new(0.5, 0, 1, -px(3, 4))
		UiKit.corner(barra, 2)
		cartoes[i] = cf
		for _, d in box:GetDescendants() do
			-- o molde como imagem (pré-carregar o Shirt/Pants gera aviso de representação no Output);
			-- D-178: a textura do acabamento de arma também (sem ela a arma aparece clara no começo)
			local tpl = if d:IsA("Shirt")
				then d.ShirtTemplate
				elseif d:IsA("Pants") then d.PantsTemplate
				elseif d:IsA("MeshPart") then d.TextureID
				else nil
			if tpl and tpl ~= "" and not jaPre[tpl] then
				jaPre[tpl] = true
				local im = Instance.new("ImageLabel")
				im.Image = tpl
				table.insert(moldes, im)
			end
		end
		if i % 12 == 0 then
			task.wait() -- monta em lotes: sem travar o quadro
		end
		if overlays.CaixaAbertura ~= g then
			return -- a tela fechou enquanto montava
		end
	end
	-- marcador fixo no centro e o escurecido das pontas
	local marcador = frame(janela, UDim2.new(0, px(3, 4), 1, 0), V.BRASS, 0)
	marcador.Name = "Marcador"
	marcador.AnchorPoint = Vector2.new(0.5, 0)
	marcador.Position = UDim2.fromScale(0.5, 0)
	marcador.ZIndex = 8
	for _, cima in { true, false } do
		local seta = frame(janela, UDim2.fromOffset(px(14, 18), px(14, 18)), V.BRASS, 0)
		seta.AnchorPoint = Vector2.new(0.5, 0.5)
		seta.Position = UDim2.new(0.5, 0, if cima then 0 else 1, 0)
		seta.Rotation = 45
		seta.ZIndex = 8
	end
	for _, lado in { 0, 1 } do
		local sombra = frame(janela, UDim2.new(0.22, 0, 1, 0), Color3.fromRGB(12, 13, 10), 0)
		sombra.AnchorPoint = Vector2.new(lado, 0)
		sombra.Position = UDim2.fromScale(lado, 0)
		sombra.ZIndex = 7
		local gr = Instance.new("UIGradient")
		gr.Transparency = NumberSequence.new(if lado == 0 then 0 else 1, if lado == 0 then 1 else 0)
		gr.Parent = sombra
	end
	-- moldes de roupa e texturas de arma: carrega antes de girar (até 1,5 s), para nenhum cartão
	-- mudar no meio
	if #moldes > 0 then
		local pronto = false
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(moldes)
			end)
			for _, im in moldes do
				im:Destroy()
			end
			pronto = true
		end)
		local t0 = os.clock()
		while not pronto and not skip and os.clock() - t0 < 1.5 do
			task.wait()
		end
	end
	if overlays.CaixaAbertura ~= g then
		return
	end
	-- D-213: espera a caixa estourar e a roleta sai da luz (cresce de 90 %)
	local p0 = palco
	if p0 then
		while p0.Parent and p0:GetAttribute("Intro") ~= "feita" and not skip do
			task.wait()
			if overlays.CaixaAbertura ~= g then
				return
			end
		end
		janela.Visible = true
		if not skip then
			local ej = Instance.new("UIScale")
			ej.Scale = 0.9
			ej.Parent = janela
			TweenService:Create(ej, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
	end
	-- o marcador acende a cada cartão que passa (o brilho apaga sozinho)
	local acesa = UiEfeitos.halo(janela, UDim2.fromScale(0.5, 0.5), V.BRASS, math.floor(janelaH * 1.1), 1, nil, 7)
	acesa.Name = "MarcadorLuz"
	acesa.Size = UDim2.fromOffset(px(40, 54), math.floor(janelaH * 1.2))
	-- a rolagem: da direita para a esquerda, desacelerando até o vencedor no marcador
	local final = UDim2.fromOffset(px0(Roleta.POS_VENCEDOR), y)
	local dur = Roleta.DURACAO[anim] or Roleta.DURACAO.completa
	if skip then
		dur = 0.01 -- pulou antes de girar
	end
	local tw = TweenService:Create(faixa, TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = final,
	})
	local ultimo = Roleta.INICIO
	local ultimoTique = 0
	local luzTique = 1
	local passo = RunService.RenderStepped:Connect(function(dt: number)
		local i = Roleta.noMarcador(faixa.Position.X.Offset, cartao, gap, janelaW)
		if i ~= ultimo then
			ultimo = i
			luzTique = 0.35
			local agora = os.clock()
			if agora - ultimoTique > 0.045 then
				ultimoTique = agora
				tocar("roleta_tique", 0.28, 0.95 + rng:NextNumber() * 0.1)
			end
		end
		luzTique = math.min(1, luzTique + dt * 4)
		if acesa:IsA("ImageLabel") then
			acesa.ImageTransparency = luzTique
		else
			acesa.BackgroundTransparency = math.max(0.6, luzTique)
		end
	end)
	tw:Play()
	local t0 = os.clock()
	while os.clock() - t0 < dur + 0.05 and not skip do
		task.wait()
		if overlays.CaixaAbertura ~= g then
			passo:Disconnect()
			tw:Cancel()
			return
		end
	end
	passo:Disconnect()
	tw:Cancel()
	faixa.Position = final
	pular.button.Visible = false
	-- conferência (Studio e teste): o cartão no marcador, o item dele e o desvio do centro em px
	local noCentro = Roleta.noMarcador(final.X.Offset, cartao, gap, janelaW)
	local centro = final.X.Offset + (noCentro - 1) * (cartao + gap) + cartao / 2
	g:SetAttribute("RoletaIndice", noCentro)
	g:SetAttribute("RoletaItem", ids[noCentro])
	g:SetAttribute("RoletaServidor", res.item)
	g:SetAttribute("RoletaDesvioPx", centro - janelaW / 2)
	g:SetAttribute("RoletaVisiveis", n)
	g:SetAttribute("RoletaPulou", skip)
	-- destaque do vencedor
	local venc = cartoes[Roleta.POS_VENCEDOR]
	local esc = venc:FindFirstChildOfClass("UIScale")
	local st = venc:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 4
		st.Transparency = 0
	end
	tocar("roleta_parada", 0.6)
	if esc then
		TweenService:Create(esc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 })
			:Play()
	end
	local rc = rgb(rar(res.raridade).cor, V.KHAKI)
	local flash = frame(g, UDim2.fromScale(1, 1), rc, 1)
	flash.ZIndex = 20
	local forte = res.raridade == "epico" or res.raridade == "lendario"
	if anim == "completa" or forte then
		flash.BackgroundTransparency = if forte then 0.35 else 0.7
		TweenService:Create(flash, TweenInfo.new(if forte then 0.6 else 0.35), { BackgroundTransparency = 1 }):Play()
	end
	-- D-213: o cartão vencedor solta a onda e as faíscas na cor da raridade (o item já está gravado)
	if anim ~= "sem" and not skip then
		local meio = Vector2.new(W / 2, H * janela.Position.Y.Scale)
		UiEfeitos.onda(panel, meio, rc, cartao * 0.95, 0.5, 30)
		UiEfeitos.faiscas(panel, meio, rc, math.floor(Efeitos.quantas(res.raridade, anim) * 0.6), {
			vmin = 200,
			vmax = 640,
			gravidade = 600,
			z = 31,
		})
		UiEfeitos.cintilas(venc, rc, if forte then 3 else 1, 0.9, 12)
		if forte then
			UiEfeitos.tremer(panel, 0.3, px(8, 11))
		end
	end
	local espera = if skip then 0.25 elseif forte then 0.9 else 0.6
	local t1 = os.clock()
	while os.clock() - t1 < espera do
		task.wait()
		if overlays.CaixaAbertura ~= g then
			return
		end
	end
	tocar(SOM_RARIDADE[res.raridade or "comum"] or "roleta_revela", 0.7)
	janela:Destroy()
	if palco then
		palco:Destroy() -- os raios da caixa saem; a recompensa traz a luz da raridade
	end
	titulo.Text = UiKit.upper(c.nome or "Caixa")
	recompensa(panel, g, res, item)
end

-- TROCA de Fragmentos por item garantido
local function abrirTroca()
	local W, H = px(640, 860), px(580, 780)
	local _, panel = overlay("CaixaTroca", 42, W, H)
	closeButton(panel, "CaixaTroca")
	local t = text(panel, "TROCA DE FRAGMENTOS", px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local sub = text(
		panel,
		string.format(
			"Você tem %d Fragmentos de Arsenal. Cada troca é garantida: você escolhe o item. Fragmentos não viram Robux nem dinheiro.",
			state.fragmentos
		),
		px(14, 19),
		V.DIM,
		F.BODY
	)
	sub.Position = UDim2.fromOffset(px(18, 24), px(48, 62))
	sub.Size = UDim2.new(1, -px(36, 48), 0, px(40, 54))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(94, 124))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(106, 140))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = panel
	UiKit.list(list, false, px(6, 8))
	for i, e in state.troca do
		local row = frame(list, UDim2.new(1, -px(10, 14), 0, px(58, 78)), V.PANEL_2, 0)
		row.LayoutOrder = i
		local box = desenhaItem(row, e.item, px(50, 68))
		box.Position = UDim2.fromOffset(px(4, 5), px(4, 5))
		local r = rar(e.item.raridade)
		local nm = text(
			row,
			string.format("%s\n%s · %s", e.item.nome, UiKit.upper(r.nome), kindName(e.item.kind)),
			px(14, 18),
			V.TEXT,
			F.BODY
		)
		nm.Position = UDim2.fromOffset(px(64, 86), 0)
		nm.Size = UDim2.new(1, -px(270, 360), 1, 0)
		local label = if e.possui then "JÁ TEM" else string.format("TROCAR · %d", e.custo)
		local a = UiKit.action(row, label, "ci", function()
			local ok, rr = pcall(function()
				return Net.func("Suprimento_Trocar"):InvokeServer(e.item.id)
			end)
			if ok and type(rr) == "table" then
				if rr.estado then
					state = rr.estado
				end
				if rr.ok then
					closeOverlay("CaixaTroca")
					refresh()
					abertura({ nome = "Troca de Fragmentos" }, rr.resultado, rr.item)
				else
					Toast.show(
						if rr.motivo == "fragmentos" then "Fragmentos insuficientes." else "Não deu para trocar agora."
					)
				end
			end
		end, { h = px(40, 54) })
		a.button.AnchorPoint = Vector2.new(1, 0.5)
		a.button.Position = UDim2.new(1, -px(8, 10), 0.5, 0)
		a.button.Size = UDim2.fromOffset(px(170, 226), px(40, 54))
		a.enabled(not e.possui and state.fragmentos >= e.custo)
	end
	UiKit.focus(panel)
end

-- COMPRA DIRETA (D-174, caminho C): o cosmético escolhido por créditos ($), sem sorteio
local function abrirLoja()
	local W, H = px(640, 860), px(580, 780)
	local _, panel = overlay("CaixaLoja", 42, W, H)
	closeButton(panel, "CaixaLoja")
	local t = text(panel, "COMPRA DIRETA", px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local sub = text(
		panel,
		string.format(
			"Você tem %s em créditos (ganhos em partidas e missões). Você escolhe o item e leva ele, sem sorteio.",
			Progression.money(state.creditos or 0)
		),
		px(14, 19),
		V.DIM,
		F.BODY
	)
	sub.Position = UDim2.fromOffset(px(18, 24), px(48, 62))
	sub.Size = UDim2.new(1, -px(36, 48), 0, px(40, 54))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(94, 124))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(106, 140))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = panel
	UiKit.list(list, false, px(6, 8))
	for i, e in state.loja or {} do
		local row = frame(list, UDim2.new(1, -px(10, 14), 0, px(58, 78)), V.PANEL_2, 0)
		row.LayoutOrder = i
		local box = desenhaItem(row, e.item, px(50, 68))
		box.Position = UDim2.fromOffset(px(4, 5), px(4, 5))
		local r = rar(e.item.raridade)
		local nm = text(
			row,
			string.format("%s\n%s · %s", e.item.nome, UiKit.upper(r.nome), kindName(e.item.kind)),
			px(14, 18),
			V.TEXT,
			F.BODY
		)
		nm.Position = UDim2.fromOffset(px(64, 86), 0)
		nm.Size = UDim2.new(1, -px(270, 360), 1, 0)
		local label = if e.possui then "JÁ TEM" else string.format("LEVAR · %s", Progression.money(e.preco))
		local a = UiKit.action(row, label, "ci", function()
			local ok, rr = pcall(function()
				return Net.func("Suprimento_Loja"):InvokeServer(e.item.id)
			end)
			if ok and type(rr) == "table" then
				if rr.ok then
					closeOverlay("CaixaLoja")
					refresh()
					abertura({ nome = "Compra direta" }, rr.resultado, rr.item)
				else
					Toast.show(
						if rr.motivo == "creditos"
							then "Créditos insuficientes: jogue partidas e cumpra missões."
							elseif rr.motivo == "possui" then "Você já tem este item."
							else "Não deu para levar agora."
					)
				end
			end
		end, { h = px(40, 54) })
		a.button.AnchorPoint = Vector2.new(1, 0.5)
		a.button.Position = UDim2.new(1, -px(8, 10), 0.5, 0)
		a.button.Size = UDim2.fromOffset(px(190, 252), px(40, 54))
		a.enabled(not e.possui and (state.creditos or 0) >= e.preco)
	end
	UiKit.focus(panel)
end

-- HISTÓRICO dos últimos resultados (o servidor guarda 100; aqui os 20 mais novos)
local function abrirHist()
	local W, H = px(560, 740), px(520, 700)
	local _, panel = overlay("CaixaHist", 42, W, H)
	closeButton(panel, "CaixaHist")
	local t = text(panel, "HISTÓRICO", px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(60, 80))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(72, 96))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.Parent = panel
	UiKit.list(list, false, px(4, 6))
	if #state.hist == 0 then
		local e = text(list, "Nenhuma caixa aberta ainda.", px(15, 20), V.DIM, F.BODY)
		e.Size = UDim2.new(1, 0, 0, px(30, 40))
	end
	for i, h in state.hist do
		local quando = os.date("%d/%m %H:%M", h.t)
		local o = if h.origem == "bilhete"
			then "bilhete"
			elseif h.origem == "marco" then "caixa ganha"
			elseif h.origem == "compra" then "créditos"
			elseif h.origem == "colecao" then "coleção do Arquivo"
			elseif h.origem == "recibo" then "Robux"
			elseif h.origem == "restrito" then "Robux (sem sorteio)"
			else "troca"
		local s = if h.item
			then string.format(
				"%s · %s%s",
				h.item.nome,
				o,
				if h.repetido then string.format(" · repetido: +%d fragmentos", h.fragmentos) else ""
			)
			else string.format("+%d fragmentos · %s", h.fragmentos, o)
		local row = text(list, string.format("%s · %s", quando, s), px(14, 18), V.TEXT, F.BODY)
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, px(26, 34))
		row.TextTruncate = Enum.TextTruncate.AtEnd
	end
	UiKit.focus(panel)
end

-- CARTÃO: plaqueta e moldura escolhidas
local function abrirCartao()
	local W, H = px(560, 740), px(520, 700)
	local _, panel = overlay("CaixaCartao", 42, W, H)
	closeButton(panel, "CaixaCartao")
	local t = text(panel, "MEU CARTÃO", px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(60, 80))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(72, 96))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.Parent = panel
	UiKit.list(list, false, px(6, 8))
	local n = 0
	for _, slot in { "tag", "mol" } do
		for _, it in state.meus[slot] do
			n += 1
			local row = frame(list, UDim2.new(1, -px(10, 14), 0, px(58, 78)), V.PANEL_2, 0)
			row.LayoutOrder = n
			local box = desenhaItem(row, it, px(50, 68))
			box.Position = UDim2.fromOffset(px(4, 5), px(4, 5))
			local nm = text(row, it.nome, px(15, 20), V.TEXT, F.BODY)
			nm.Position = UDim2.fromOffset(px(64, 86), 0)
			nm.Size = UDim2.new(1, -px(230, 310), 1, 0)
			local em = state.on[slot] == it.id
			local a = UiKit.action(
				row,
				if em then "TIRAR" else "USAR",
				if em then "secondary" else "primary",
				function()
					pcall(function()
						local rr = Net.func("Suprimento_Equipar")
							:InvokeServer({ slot = slot, item = if em then "" else it.id })
						if type(rr) == "table" and rr.estado then
							state = rr.estado
						end
					end)
					abrirCartao()
				end,
				{ h = px(40, 54) }
			)
			a.button.AnchorPoint = Vector2.new(1, 0.5)
			a.button.Position = UDim2.new(1, -px(8, 10), 0.5, 0)
			a.button.Size = UDim2.fromOffset(px(130, 174), px(40, 54))
		end
	end
	if n == 0 then
		local e =
			text(list, "Plaquetas e molduras saem das caixas e da troca de Fragmentos.", px(15, 20), V.DIM, F.BODY)
		e.Size = UDim2.new(1, 0, 0, px(40, 54))
	end
	UiKit.focus(panel)
end

-- ===== a aba =====
local function build()
	local h = host
	if not h then
		return
	end
	if root then
		root:Destroy()
	end
	local r = frame(h, UDim2.fromScale(1, 1))
	r.Name = "CaixasTela"
	root = r
	if not state then
		local t = text(r, "Carregando o depósito…", px(16, 22), V.DIM, F.BODY)
		t.Size = UDim2.new(1, 0, 0, px(40, 54))
		return
	end
	-- atalhos no alto, saldos e o aviso embaixo deles
	local top = frame(r, UDim2.new(1, 0, 0, px(44, 60)))
	UiKit.list(top, true, px(10, 14))
	local function atalho(label: string, order: number, fn: () -> (), w: number?)
		local a = UiKit.action(top, label, "secondary", fn, { h = px(38, 52) })
		a.button.Size = UDim2.fromOffset(w or px(110, 146), px(38, 52))
		a.button.LayoutOrder = order
	end
	atalho("COMPRA DIRETA", 1, abrirLoja, px(150, 200))
	atalho("TROCA", 2, abrirTroca, px(96, 128))
	atalho("HISTÓRICO", 3, abrirHist, px(110, 146))
	atalho("CARTÃO", 4, abrirCartao, px(96, 128))
	atalho(ANIM_LABEL[anim], 5, function()
		anim = ANIM_NEXT[anim]
		build()
	end, px(184, 244))
	local saldo = text(
		r,
		string.format(
			"CRÉDITOS %s · BILHETES %d (hoje %d de %d) · FRAGMENTOS %d",
			Progression.money(state.creditos or 0),
			state.bilhetes,
			state.hoje or 0,
			state.tetoDia or 4,
			state.fragmentos
		),
		px(15, 20),
		V.KHAKI,
		F.TITLE_MED
	)
	saldo.Position = UDim2.fromOffset(0, px(48, 64))
	saldo.Size = UDim2.new(1, 0, 0, px(22, 30))
	-- aviso da conta restrita (sem caixas pagas) e de onde vêm os bilhetes
	local nota = if state.restrito or not state.politicaOk
		then "Caixas pagas indisponíveis na sua conta. As caixas grátis, a troca e a compra direta continuam."
		else "Caixas grátis vêm de jogar: missões (Bilhetes), treinamento, patentes, passe e partidas. Não se compram."
	local n = text(r, nota, px(13, 17), V.DIM, F.BODY)
	n.Position = UDim2.fromOffset(0, px(70, 94))
	n.Size = UDim2.new(1, 0, 0, px(22, 30))
	-- as caixas
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(0, px(96, 128))
	list.Size = UDim2.new(1, 0, 1, -px(96, 128))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = r
	UiKit.list(list, false, px(8, 10))
	local order = 0
	for _, c in state.caixas do
		-- caixa paga só para quem pode comprar agora (sem vitrine do que não dá para levar)
		if c.tipo == "paga" and c.bloqueio ~= nil then
			continue
		end
		order += 1
		local card = frame(list, UDim2.new(1, -px(10, 14), 0, px(150, 200)), V.PANEL_2, 0)
		card.Name = string.format("Caixa_%s", tostring(c.id))
		card.LayoutOrder = order
		UiKit.corner(card, 4)
		UiKit.edge(card, V.LINE, 1, 0.4)
		-- D-212: a imagem nova da caixa (Blender); o caixote 3D fica de reserva no CaixaImagem
		local arte = frame(card, UDim2.fromOffset(px(140, 186), px(140, 186)))
		arte.Name = "Arte"
		arte.Position = UDim2.fromOffset(px(6, 8), px(5, 7))
		arte.ZIndex = 2
		CaixaImagem.desenha(arte, c.id, c.modelo or "caixa_municao_us")
		-- D-213: a luz da caixa atrás da imagem
		UiEfeitos.halo(
			card,
			UDim2.fromOffset(px(6, 8) + px(70, 93), px(5, 7) + px(70, 93)),
			CaixaImagem.ACENTO[tostring(c.id)] or V.AMBAR,
			px(170, 226),
			0.7,
			nil,
			1
		)
		local x = px(154, 204)
		local nm = text(card, UiKit.upper(c.nome), px(19, 26), V.TEXT, F.TITLE)
		nm.Position = UDim2.fromOffset(x, px(8, 10))
		nm.Size = UDim2.new(1, -x - px(230, 300), 0, px(26, 34))
		local ds = text(card, c.desc, px(13, 17), V.DIM, F.BODY)
		ds.Position = UDim2.fromOffset(x, px(36, 46))
		ds.Size = UDim2.new(1, -x - px(230, 300), 0, px(36, 48))
		ds.TextYAlignment = Enum.TextYAlignment.Top
		-- barra por raridade
		local bar = frame(card, UDim2.new(1, -x - px(230, 300), 0, px(10, 14)), V.PANEL, 0)
		bar.Position = UDim2.fromOffset(x, px(80, 106))
		UiKit.list(bar, true, 0)
		local legenda = {}
		for i, rr in state.raridades do
			local w = c.porRaridade[rr.id] or 0
			if w > 0 then
				local seg = frame(bar, UDim2.new(w / Caixas.ESCALA, 0, 1, 0), rgb(rr.cor, V.DIM), 0)
				seg.LayoutOrder = i
				table.insert(legenda, string.format("%s %s", rr.nome, Caixas.pct(w)))
			end
		end
		local lg = text(card, table.concat(legenda, " · "), px(12, 16), V.DIM, F.BODY)
		lg.Position = UDim2.fromOffset(x, px(94, 124))
		lg.Size = UDim2.new(1, -x - px(230, 300), 0, px(32, 42)) -- duas linhas: as 5 raridades cabem
		if c.fonte == "marco" then
			local como = text(card, "Como ganhar: " .. (c.ganha or "jogando."), px(12, 16), V.KHAKI, F.BODY)
			como.Position = UDim2.fromOffset(x, px(126, 166))
			como.Size = UDim2.new(1, -x - px(230, 300), 0, px(22, 30))
			como.TextTruncate = Enum.TextTruncate.AtEnd
		elseif c.temporada and c.fim then
			local fim = text(
				card,
				string.format("Só nesta temporada, até %s.", os.date("%d/%m/%Y", c.fim)),
				px(12, 16),
				V.KHAKI,
				F.BODY
			)
			fim.Position = UDim2.fromOffset(x, px(126, 166))
			fim.Size = UDim2.new(1, -x - px(230, 300), 0, px(22, 30))
		end
		-- botões: itens e probabilidades sempre antes do de agir
		local col = frame(card, UDim2.new(0, px(220, 290), 1, -px(16, 20)))
		col.AnchorPoint = Vector2.new(1, 0)
		col.Position = UDim2.new(1, -px(8, 10), 0, px(8, 10))
		UiKit.list(col, false, px(8, 10))
		local ver = UiKit.action(col, "VER ITENS E PROBABILIDADES", "secondary", function()
			abrirOdds(c)
		end, { h = px(44, 60) })
		ver.button.LayoutOrder = 1
		local a = botaoAcao(col, c)
		if a then
			a.button.LayoutOrder = 2
		elseif c.bloqueio then
			local why = text(col, MOTIVO[c.bloqueio] or "Indisponível.", px(12, 16), V.DIM, F.BODY)
			why.LayoutOrder = 2
			why.Size = UDim2.new(1, 0, 0, px(44, 60))
		end
	end
	-- D-212: a caixa escolhida na vitrine da loja: a lista desce até ela e a borda acende em âmbar
	local foco = focoPendente
	if foco then
		focoPendente = nil
		local alvo = list:FindFirstChild(string.format("Caixa_%s", foco))
		if alvo and alvo:IsA("GuiObject") then
			task.defer(function()
				local y = alvo.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y
				list.CanvasPosition = Vector2.new(0, math.max(0, y - px(8, 10)))
				local st = alvo:FindFirstChildOfClass("UIStroke")
				if st then
					st.Color, st.Thickness, st.Transparency = V.AMBAR, 2, 0
				end
			end)
		end
	end
	UiKit.focus(r)
end

refresh = function()
	task.spawn(function()
		fetch()
		if host and host.Visible then
			build()
		end
	end)
end

abrirGratis = function(c: any)
	preCaixa(tostring(c.id))
	local ok, rr = pcall(function()
		return Net.func("Suprimento_Abrir"):InvokeServer(c.id)
	end)
	if not (ok and type(rr) == "table") then
		Toast.show("Não deu para abrir agora.")
		return
	end
	if rr.estado then
		state = rr.estado
	end
	if not rr.ok then
		Toast.show(
			if rr.motivo == "bilhetes"
				then "Sem Bilhetes de Recompensa: cumpra uma missão do dia."
				elseif rr.motivo == "guardada" then "Nenhuma caixa desta guardada. Veja como ganhar no cartão dela."
				else "Não deu para abrir agora."
		)
		return
	end
	closeOverlay("CaixaOdds")
	build()
	abertura(c, rr.resultado, rr.item)
end

comprar = function(c: any)
	preCaixa(tostring(c.id)) -- enquanto a janela de compra está aberta
	-- o servidor confere venda ligada, temporada e PolicyService antes de abrir o prompt
	Net.event("Suprimento_Comprar"):FireServer(c.id)
end

-- caixa paga entregue (recibo já gravado): a abertura com o resultado real
Net.event("Suprimento_Resultado").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" or type(msg.resultado) ~= "table" then
		return
	end
	local c = { modelo = "caixa_municao_us" }
	if state then
		for _, cc in state.caixas do
			if cc.id == msg.resultado.caixa then
				c = cc
			end
		end
	end
	closeOverlay("CaixaOdds")
	abertura(c, msg.resultado, msg.item)
	refresh()
end)

-- D-174: caixa grátis ganha num marco (fica guardada; a loja não abre sozinha)
Net.event("Suprimento_Ganhou").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" or type(msg.nome) ~= "string" then
		return
	end
	Toast.show(string.format("%s guardada: abra na loja, aba CAIXAS.", msg.nome))
	if host and host.Visible then
		refresh()
	else
		task.spawn(fetch)
	end
end)

Bus.on("caixas_show", function(h: Frame)
	host = h
	build()
	refresh()
end)
Bus.on("caixas_hide", function()
	for name in table.clone(overlays) do
		closeOverlay(name)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "caixas" then
			Bus.fire("shop_open", "caixas")
		end
	end)
	-- D-213: abre uma caixa grátis pelo mesmo caminho do botão ABRIR (o servidor confere bilhete ou
	-- guardada, sorteia e grava, como no clique), sem depender do foco da loja: o controle fantasma
	-- do MCP (D-149) trocava a aba no meio do teste. workspace "VT65DevAbrir" = "<id da caixa>".
	workspace:GetAttributeChangedSignal("VT65DevAbrir"):Connect(function()
		local id = workspace:GetAttribute("VT65DevAbrir")
		if type(id) ~= "string" then
			return
		end
		local s = fetch()
		for _, c in (if s then s.caixas else {}) :: { any } do
			if c.id == id and c.tipo == "gratuita" then
				abrirGratis(c)
				return
			end
		end
	end)
end
