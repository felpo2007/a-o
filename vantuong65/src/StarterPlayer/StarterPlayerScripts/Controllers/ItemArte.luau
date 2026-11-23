--!strict
-- Desenho de um item cosmético (D-175), comum às telas das CAIXAS e do ARQUIVO MILITAR (e à roleta
-- do lote 61). Tudo a partir dos dados do jogo, sem imagem inventada:
--   - emblema, plaqueta e moldura: o desenho 2D do cartão (cores e sigla do Shared/Cosmeticos);
--   - prêmio de saldo (créditos, Fragmentos): ficha redonda com a quantidade;
--   - acabamento de arma: o modelo 3D da arma com o acabamento (ViewportFrame; a mesma arte e o
--     mesmo Skins.applyWeapon da Intendência), de lado;
--   - uniforme: o pano da farda (cores e padrão do Shared/Skins). O soldado vestido fica no retrato
--     grande do detalhe (ItemArte.soldado): SoldierPreview não descarta retratos, então não dá para
--     criar um por cartão.
-- `item`: o id ou uma tabela com `id` (o itemView do servidor serve); o resto vem do Shared.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Caixas = require(ReplicatedStorage.Shared.Caixas) :: any
local Conjuntos = require(ReplicatedStorage.Shared.Conjuntos) :: any
local Cosmeticos = require(ReplicatedStorage.Shared.Cosmeticos) :: any
local GunModel = require(ReplicatedStorage.Shared.GunModel) :: any
local Skins = require(ReplicatedStorage.Shared.Skins) :: any
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local ArteCatalogo = require(script.Parent.ArteCatalogo)
local EmblemaImagem = require(script.Parent.EmblemaImagem)
local SoldierPreview = require(script.Parent.SoldierPreview) :: any
local UiKit = require(script.Parent.UiKit)

local ItemArte = {}
local V, F = UiKit.V, UiKit.F
local player = Players.LocalPlayer

local function rgb(t: any, def: Color3): Color3
	return if type(t) == "table" and #t >= 3 then Color3.fromRGB(t[1], t[2], t[3]) else def
end
ItemArte.rgb = rgb

-- raridade (a tabela do Shared/Caixas)
function ItemArte.raridade(id: string?): any
	return (id and Caixas.raridade(id)) or { id = "comum", nome = "Comum", cor = { 158, 158, 150 } }
end

function ItemArte.corRaridade(id: string?): Color3
	return rgb(ItemArte.raridade(id).cor, V.DIM)
end

-- dados completos do item: o que veio na tabela, completado pelo Shared
function ItemArte.info(item: any): any
	local id = if type(item) == "string" then item elseif type(item) == "table" then item.id else nil
	local base = (id and Cosmeticos.info(id)) or {}
	local out = table.clone(base)
	if type(item) == "table" then
		for k, v in item do
			out[k] = v
		end
	end
	out.id = id
	-- D-176: título de conjunto (tit_*): o texto do título é o próprio item
	if id and string.sub(id, 1, 4) == "tit_" and Conjuntos.TITULOS[id] then
		out.kind = "titulo"
		out.nome = out.nome or Conjuntos.TITULOS[id]
		out.raridade = out.raridade or "lendario"
		out.desc = out.desc or "Título do cartão do jogador."
	end
	local s = id and Skins.get(id)
	if s then
		out.skin = s
	end
	return out
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

-- D-178: degradê cor -> cor3 (a cor de baixo fica branca e o UIGradient pinta). Só no próprio
-- objeto: o texto e os filhos ficam com a cor deles.
local function degrade(obj: Instance, c1: Color3, c3: Color3?)
	if not c3 then
		return
	end
	if obj:IsA("UIStroke") then
		obj.Color = Color3.new(1, 1, 1)
	else
		(obj :: any).BackgroundColor3 = Color3.new(1, 1, 1)
	end
	local g = Instance.new("UIGradient")
	g.Name = "Degrade"
	g.Color = ColorSequence.new(c1, c3)
	g.Rotation = 45
	g.Parent = obj
end

local function label(parent: Instance, s: string, size: number, color: Color3, font: any): TextLabel
	local t = UiKit.rotulo(parent, size, color, font)
	t.Text = s
	t.TextWrapped = true
	return t
end

-- ===== arma com o acabamento (ViewportFrame) =====
local function arma(box: Frame, s: any, aspecto: number?, qual: string?)
	-- D-229: a imagem de estúdio do acabamento; o modelo 3D fica de reserva
	local foto = ArteCatalogo.acabamento(s, qual)
	if foto ~= "" then
		local im = Instance.new("ImageLabel")
		im.Name = "Arma"
		im.BackgroundTransparency = 1
		im.Image = foto
		im.ScaleType = Enum.ScaleType.Fit
		im.AnchorPoint = Vector2.new(0.5, 0.5)
		im.Position = UDim2.fromScale(0.5, 0.5)
		im.Size = UDim2.fromScale(0.98, 0.98)
		im.Parent = box
		return
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Arma"
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(172, 168, 158) -- D-229: mais luz, para o acabamento aparecer
	vp.LightColor = Color3.fromRGB(255, 246, 232)
	vp.LightDirection = Vector3.new(-0.5, -1, -0.65)
	vp.Parent = box
	local cam = Instance.new("Camera")
	cam.FieldOfView = 24
	cam.Parent = vp
	vp.CurrentCamera = cam
	-- D-179: o acabamento universal aparece na arma de vitrine dele
	local wid = s.weapon or qual or s.vitrine or ""
	local folder = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
	local art = if folder then folder:FindFirstChild(wid) else nil
	local m: Model
	if art and art:IsA("Model") then
		m = art:Clone()
	else
		local wp = Weapons.get(wid)
		m = GunModel.build(wid, if wp then wp.kind else nil)
	end
	Skins.applyWeapon(m, s.id, wid)
	m:PivotTo(CFrame.identity)
	m.Parent = vp
	-- de lado (a Intendência enquadra igual), com folga para o cano não sair do quadro
	local cf, size = m:GetBoundingBox()
	-- D-229: num cartão largo a arma ocupa a largura (o FOV da câmera é o vertical)
	local dist = size.Magnitude / 2 / (math.tan(math.rad(cam.FieldOfView / 2)) * math.max(1, aspecto or 1)) * 1.05
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist, dist * 0.18, dist * 0.12), cf.Position)
end

-- ===== pano do uniforme =====
local function pano(box: Frame, s: any)
	local cols = s.swatch or {}
	local p = frame(box, UDim2.fromScale(0.78, 0.78), rgb(cols[1], V.PANEL), 0)
	p.Name = "Pano"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.5)
	p.ClipsDescendants = true
	UiKit.corner(p, 4)
	local rng = Random.new(#s.id * 7919)
	local function peca(c: any, x: number, y: number, w: number, h: number, rot: number)
		local f = frame(p, UDim2.fromScale(w, h), rgb(c, V.PANEL), 0)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Rotation = rot
		local k = Instance.new("UICorner")
		k.CornerRadius = UDim.new(0.5, 0)
		k.Parent = f
	end
	if #cols < 2 or s.pattern == "plain" then
		return
	end
	local function cor(): any
		return cols[rng:NextInteger(2, #cols)]
	end
	if s.pattern == "tiger" or string.find(s.id, "tiger", 1, true) then
		for _ = 1, 16 do
			peca(
				cor(),
				rng:NextNumber(0, 1),
				rng:NextNumber(0, 1),
				rng:NextNumber(0.3, 0.7),
				0.05,
				rng:NextNumber(-8, 8)
			)
		end
	elseif s.pattern == "tadpole" then
		for _ = 1, 22 do
			peca(
				cor(),
				rng:NextNumber(0, 1),
				rng:NextNumber(0, 1),
				rng:NextNumber(0.12, 0.3),
				0.03,
				rng:NextNumber(-6, 6)
			)
		end
	elseif s.pattern == "lizard" then
		for _ = 1, 30 do
			peca(
				cor(),
				rng:NextNumber(0, 1),
				rng:NextNumber(0, 1),
				0.035,
				rng:NextNumber(0.12, 0.26),
				rng:NextNumber(-6, 6)
			)
		end
	else
		for _ = 1, 14 do
			local d = rng:NextNumber(0.12, 0.26)
			peca(cor(), rng:NextNumber(0, 1), rng:NextNumber(0, 1), d, d * 1.5, rng:NextNumber(0, 180))
		end
	end
end

-- ===== soldado vestido =====
-- O manequim do lobby (VT65Preview, vestido pelo servidor) com o molde da skin: o id de IMAGEM que o
-- servidor resolveu ("Molde_<chave>", ImagensUi.moldes; o cliente não abre decal). Sem ele, a farda
-- sai pintada nas cores da skin, como a prévia da Intendência.
local SHIRT = { "UpperTorso", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }
local PANTS = { "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }
local retrato: any = nil

local function manequim(lado: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("VT65Preview")
	local m = if folder then folder:FindFirstChild(lado) else nil
	if not (m and m:IsA("Model")) then
		return nil
	end
	local want = m:GetAttribute("Parts")
	if type(want) == "number" then
		local n = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		if n < want then
			return nil -- ainda chegando do servidor
		end
	end
	return m
end

-- clone do manequim do lado da skin, já com a farda (ou nil se o manequim não chegou)
local function vestido(s: any): Model?
	local src = manequim(if s.side == "VC" then "VC" else "US")
	if not src then
		return nil
	end
	local m = src:Clone()
	local camisa = s.shirt and ReplicatedStorage:GetAttribute("Molde_" .. s.shirt)
	local calca = s.pants and ReplicatedStorage:GetAttribute("Molde_" .. s.pants)
	if type(camisa) == "number" and type(calca) == "number" then
		local sh = m:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
		sh.ShirtTemplate = "rbxassetid://" .. camisa
		sh.Parent = m
		local pa = m:FindFirstChildOfClass("Pants") or Instance.new("Pants")
		pa.PantsTemplate = "rbxassetid://" .. calca
		pa.Parent = m
		return m
	end
	local shirt, pants
	if s.rgb then
		shirt, pants = rgb(s.rgb.shirt, V.PANEL), rgb(s.rgb.pants, V.PANEL)
	else
		shirt = rgb(s.swatch[1], V.PANEL)
		pants = rgb(s.swatch[2] or s.swatch[1], V.PANEL)
	end
	for _, d in m:GetChildren() do
		if d:IsA("Shirt") or d:IsA("Pants") then
			d:Destroy()
		end
	end
	for _, name in SHIRT do
		local part = m:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = shirt
		end
	end
	for _, name in PANTS do
		local part = m:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = pants
		end
	end
	return m
end

-- o soldado num cartão (ViewportFrame parado, de três quartos, corpo inteiro). false = sem manequim
local function soldadoCartao(box: Frame, s: any): boolean
	local m = vestido(s)
	if not m then
		return false
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Soldado"
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(128, 124, 114)
	vp.LightColor = Color3.fromRGB(255, 240, 220)
	vp.LightDirection = Vector3.new(-0.5, -0.8, -1)
	vp.Parent = box
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	m:PivotTo(CFrame.identity)
	m.Parent = vp
	local cf, size = m:GetBoundingBox()
	local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	local frente = if root and root:IsA("BasePart") then root.CFrame.LookVector else Vector3.new(0, 0, -1)
	local dir = (CFrame.fromAxisAngle(Vector3.yAxis, math.rad(25)) * frente).Unit
	local d = size.Y / 2 / math.tan(math.rad(cam.FieldOfView / 2)) * 1.1
	cam.CFrame = CFrame.lookAt(cf.Position + dir * d + Vector3.new(0, size.Y * 0.04, 0), cf.Position)
	return true
end

-- Desenho do item num quadrado de lado `s`, com fundo e borda da raridade. Devolve o quadro.
-- opts.soldado: o uniforme vestido no soldado (ViewportFrame; mais pesado que o pano).
export type Opcoes = { soldado: boolean?, aspecto: number?, arma: string? }
function ItemArte.desenha(parent: Instance, item: any, s: number, opts: Opcoes?): Frame
	local it = ItemArte.info(item)
	local box = frame(parent, UDim2.fromOffset(s, s), Color3.new(1, 1, 1), 0)
	box.Name = "Item"
	UiKit.corner(box, 6)
	local rc = ItemArte.corRaridade(it.raridade)
	UiKit.edge(box, rc, 2, 0)
	local fundo = Instance.new("UIGradient")
	fundo.Color = ColorSequence.new(rc:Lerp(V.PANEL_2, 0.62), V.PANEL_2)
	fundo.Rotation = 90
	fundo.Parent = box
	local c1, c2 = rgb(it.cor, rc), rgb(it.cor2, V.TEXT)
	local c3: Color3? = if type(it.cor3) == "table" then rgb(it.cor3, c1) else nil
	if it.kind == "emblema" then
		local e = frame(box, UDim2.fromScale(0.7, 0.7), c1, 0)
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.Position = UDim2.fromScale(0.5, 0.5)
		UiKit.corner(e, math.floor(s * 0.12))
		UiKit.edge(e, c2, 2, 0.2)
		degrade(e, c1, c3)
		local t = label(e, it.sigla or "★", math.floor(s * 0.3), c2, F.TITLE)
		t.Size = UDim2.fromScale(1, 1)
		t.TextXAlignment = Enum.TextXAlignment.Center
		-- D-218: a insígnia por cima; a sigla colorida fica só enquanto a imagem não chega
		local arte = EmblemaImagem.nova(box)
		arte.AnchorPoint = Vector2.new(0.5, 0.5)
		arte.Position = UDim2.fromScale(0.5, 0.5)
		arte.Size = UDim2.fromScale(0.94, 0.94)
		EmblemaImagem.mostra(arte, it.id, function(tem: boolean)
			e.Visible = not tem
		end)
	elseif it.kind == "plaqueta" then
		local tag = frame(box, UDim2.fromScale(0.82, 0.48), c1, 0)
		tag.AnchorPoint = Vector2.new(0.5, 0.5)
		tag.Position = UDim2.fromScale(0.5, 0.5)
		UiKit.corner(tag, math.floor(s * 0.1))
		UiKit.edge(tag, c2, 3, 0)
		degrade(tag, c1, c3)
		local hole = frame(tag, UDim2.fromOffset(math.floor(s * 0.08), math.floor(s * 0.08)), V.BG, 0)
		hole.AnchorPoint = Vector2.new(0, 0.5)
		hole.Position = UDim2.new(0, math.floor(s * 0.05), 0.5, 0)
		UiKit.corner(hole, 99)
		local t = label(tag, UiKit.upper(player.DisplayName), math.floor(s * 0.1), V.BG, F.TITLE_MED)
		t.Position = UDim2.fromScale(0.2, 0)
		t.Size = UDim2.fromScale(0.78, 1)
		t.TextTruncate = Enum.TextTruncate.AtEnd
	elseif it.kind == "moldura" then
		local m = frame(box, UDim2.fromScale(0.78, 0.56), V.PANEL, 0)
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Position = UDim2.fromScale(0.5, 0.5)
		UiKit.corner(m, 4)
		degrade(UiKit.edge(m, c1, 4, 0), c1, c3)
		local bar = frame(m, UDim2.new(0, math.floor(s * 0.06), 1, 0), c2, 0)
		bar.Name = "Faixa"
	elseif it.kind == "creditos" or it.kind == "fragmentos" then
		-- prêmio de saldo (D-174): ficha redonda com a quantidade e a moeda
		local cor = if it.kind == "creditos" then V.KHAKI else V.BRASS
		local m = frame(box, UDim2.fromScale(0.72, 0.72), cor:Lerp(V.PANEL, 0.6), 0)
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Position = UDim2.fromScale(0.5, 0.5)
		UiKit.corner(m, 999)
		UiKit.edge(m, cor, 3, 0)
		local q = label(m, tostring(it.quantidade or ""), math.floor(s * 0.2), V.TEXT, F.TITLE)
		q.Size = UDim2.fromScale(1, 0.62)
		q.TextXAlignment = Enum.TextXAlignment.Center
		q.TextYAlignment = Enum.TextYAlignment.Bottom
		local u = label(
			m,
			if it.kind == "creditos" then "CRÉDITOS" else "FRAGMENTOS",
			math.floor(s * 0.07),
			cor,
			F.TITLE_MED
		)
		u.Position = UDim2.fromScale(0, 0.62)
		u.Size = UDim2.fromScale(1, 0.24)
		u.TextXAlignment = Enum.TextXAlignment.Center
	elseif it.kind == "titulo" then
		-- faixa de papel com o título datilografado (o título é texto por natureza)
		local fx = frame(box, UDim2.fromScale(0.86, 0.34), Color3.fromRGB(214, 202, 168), 0)
		fx.AnchorPoint = Vector2.new(0.5, 0.5)
		fx.Position = UDim2.fromScale(0.5, 0.5)
		fx.Rotation = -4
		UiKit.corner(fx, 2)
		local t = label(
			fx,
			UiKit.upper(it.nome or ""),
			math.floor(s * 0.1),
			Color3.fromRGB(46, 40, 30),
			Font.fromEnum(UiKit.TYPE_OLD)
		)
		t.Size = UDim2.fromScale(0.92, 1)
		t.Position = UDim2.fromScale(0.04, 0)
		t.TextXAlignment = Enum.TextXAlignment.Center
	elseif it.skin and it.skin.kind == "weapon" then
		arma(box, it.skin, opts and opts.aspecto, opts and opts.arma)
	elseif it.skin and it.skin.kind == "uniform" then
		if not (opts and opts.soldado and soldadoCartao(box, it.skin)) then
			pano(box, it.skin)
		end
	elseif it.skin and it.skin.kind == "camo" then
		-- D-239: o soldado com os feixes de folha (tools/blender/visuais_catalogo.py)
		local img = ArteCatalogo.visual(it.skin.id)
		if img ~= "" then
			local foto = Instance.new("ImageLabel")
			foto.Name = "Camuflagem"
			foto.BackgroundTransparency = 1
			foto.AnchorPoint = Vector2.new(0.5, 0.5)
			foto.Position = UDim2.fromScale(0.5, 0.5)
			foto.Size = UDim2.fromScale(0.98, 0.98)
			foto.ScaleType = Enum.ScaleType.Fit
			foto.Image = img
			foto.Parent = box
		else
			pano(box, it.skin)
		end
	else
		-- sem cadastro: o quadro fica só com a cor da raridade (nada de texto no lugar da imagem)
		box.Name = "ItemSemArte"
	end
	return box
end

-- ===== recompensas do passe (D-208; prompt de interface §11: "Imagem de cada recompensa") =====
-- O passe (Shared/Temporada) tinha um emoji por tipo. Agora cada recompensa tem um desenho:
--   - acabamento de arma (camo) e uniforme: o item de verdade (a arma em 3D com o acabamento, o pano da
--     farda), pelo ItemArte.desenha;
--   - créditos, título e emblema: a ficha, a faixa de papel e a insígnia do ItemArte.desenha;
--   - cartão de abate: a moldura com a caveira; música: o disco; gesto: o soldado em silhueta fazendo o
--     gesto; reforço: o selo "2×". Desenhados com quadros (nada de imagem inventada).
local SIGLA: { [string]: { s: string, c1: { number }, c3: { number } } } = {
	emb_s1 = { s = "S1", c1 = { 214, 172, 72 }, c3 = { 150, 96, 10 } },
	emb_capacete = { s = "M1", c1 = { 104, 124, 64 }, c3 = { 46, 56, 30 } },
	emb_bambu = { s = "B", c1 = { 120, 150, 60 }, c3 = { 40, 70, 30 } },
	emb_estrela = { s = "★", c1 = { 196, 122, 56 }, c3 = { 110, 60, 24 } },
	emb_veterano_ouro = { s = "★", c1 = { 255, 206, 64 }, c3 = { 170, 110, 10 } },
}
local function caixaDe(parent: Instance, s: number, rc: Color3): Frame
	local box = frame(parent, UDim2.fromOffset(s, s), Color3.new(1, 1, 1), 0)
	box.Name = "Item"
	UiKit.corner(box, 6)
	UiKit.edge(box, rc, 2, 0)
	local fundo = Instance.new("UIGradient")
	fundo.Color = ColorSequence.new(rc:Lerp(V.PANEL_2, 0.62), V.PANEL_2)
	fundo.Rotation = 90
	fundo.Parent = box
	return box
end
local function circulo(parent: Instance, d: number, cor: Color3, cx: number?, cy: number?): Frame
	local f = frame(parent, UDim2.fromScale(d, d), cor, 0)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx or 0.5, cy or 0.5)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.Parent = f
	UiKit.corner(f, 999)
	return f
end
local function barra(parent: Instance, x: number, y: number, w: number, h: number, rot: number, cor: Color3): Frame
	local f = frame(parent, UDim2.fromScale(w, h), cor, 0)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Rotation = rot
	UiKit.corner(f, 3)
	return f
end

function ItemArte.recompensa(parent: Instance, r: any, s: number): Frame
	local kind = if type(r) == "table" then r.kind else nil
	local id = if type(r) == "table" then (r.id or (type(r.ids) == "table" and r.ids[1]) or nil) else nil
	-- D-226: o prêmio que não é um item de verdade usa a imagem renderizada; sem ela, o desenho abaixo
	local imagem = ArteCatalogo.premio(kind)
	if imagem ~= "" then
		local caixa = caixaDe(parent, s, ItemArte.corRaridade(if kind == "credits" then "comum" else "epico"))
		caixa.Name = "Recompensa"
		local im = Instance.new("ImageLabel")
		im.Name = "Imagem"
		im.BackgroundTransparency = 1
		im.Image = imagem
		im.ScaleType = Enum.ScaleType.Fit
		im.AnchorPoint = Vector2.new(0.5, 0.5)
		im.Position = UDim2.fromScale(0.5, 0.5)
		im.Size = UDim2.fromScale(0.92, 0.92)
		im.Parent = caixa
		return caixa
	end
	if (kind == "camo" or kind == "uniform") and id and Skins.get(id) then
		return ItemArte.desenha(parent, { id = id, raridade = if kind == "camo" then "raro" else "epico" }, s)
	elseif kind == "credits" then
		return ItemArte.desenha(
			parent,
			{ id = "creditos", kind = "creditos", quantidade = r.amount, raridade = "comum" },
			s
		)
	elseif kind == "title" then
		return ItemArte.desenha(parent, { id = id, kind = "titulo", nome = r.name, raridade = "epico" }, s)
	elseif kind == "emblem" then
		local sg = SIGLA[id or ""] or { s = "★", c1 = { 214, 172, 72 }, c3 = { 120, 80, 20 } }
		return ItemArte.desenha(parent, {
			id = id,
			kind = "emblema",
			sigla = sg.s,
			cor = sg.c1,
			cor2 = { 240, 234, 220 },
			cor3 = sg.c3,
			raridade = if id == "emb_veterano_ouro" then "lendario" else "raro",
		}, s)
	end
	local rc = ItemArte.corRaridade(if kind == "boost" then "incomum" else "epico")
	local box = caixaDe(parent, s, rc)
	box.Name = "Recompensa"
	if kind == "killcard" then
		-- cartão de abate: a moldura escura com a faixa vermelha e a caveira desenhada
		local m = frame(box, UDim2.fromScale(0.74, 0.56), V.PANEL, 0)
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Position = UDim2.fromScale(0.5, 0.5)
		UiKit.corner(m, 4)
		UiKit.edge(m, V.RED_HI, 3, 0)
		frame(m, UDim2.new(0, math.max(3, math.floor(s * 0.05)), 1, 0), V.RED, 0)
		local cran = circulo(m, 0.5, V.TEXT, 0.56, 0.42)
		circulo(cran, 0.26, V.PANEL, 0.32, 0.5)
		circulo(cran, 0.26, V.PANEL, 0.68, 0.5)
		barra(m, 0.56, 0.78, 0.2, 0.14, 0, V.TEXT)
	elseif kind == "music" then
		-- disco de vinil: o preto com os sulcos e o selo no meio
		local d = circulo(box, 0.74, Color3.fromRGB(18, 18, 16))
		for _, k in { 0.86, 0.68 } do
			local g = circulo(d, k, Color3.fromRGB(18, 18, 16))
			UiKit.edge(g, Color3.fromRGB(60, 60, 56), 1, 0.2)
		end
		local selo = circulo(d, 0.36, Color3.fromRGB(80, 120, 170))
		UiKit.edge(selo, V.TEXT, 1, 0.5)
		circulo(selo, 0.2, V.BG)
	elseif kind == "gesture" then
		-- o soldado em silhueta fazendo o gesto (a mão erguida até a testa ou o mapa nas mãos)
		local cor = Color3.fromRGB(200, 196, 176)
		circulo(box, 0.2, cor, 0.5, 0.26)
		barra(box, 0.5, 0.56, 0.22, 0.36, 0, cor)
		barra(box, 0.42, 0.88, 0.08, 0.26, 0, cor)
		barra(box, 0.58, 0.88, 0.08, 0.26, 0, cor)
		if id == "ges_mapa" then
			barra(box, 0.5, 0.56, 0.4, 0.2, 0, Color3.fromRGB(214, 203, 170))
		elseif id == "ges_cantil" then
			barra(box, 0.68, 0.36, 0.08, 0.3, -30, cor)
			circulo(box, 0.12, V.OLIVE, 0.66, 0.2)
		else
			barra(box, 0.66, 0.38, 0.08, 0.32, 40, cor)
		end
	elseif kind == "boost" then
		-- selo do reforço: "2×" grande em âmbar
		local selo = circulo(box, 0.74, V.AMBAR)
		UiKit.edge(selo, V.AMBAR_TEXTO, 3, 0.3)
		local t = label(selo, "2×", math.floor(s * 0.28), V.AMBAR_TEXTO, F.TITLE)
		t.Size = UDim2.fromScale(1, 0.7)
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.TextYAlignment = Enum.TextYAlignment.Bottom
		local x = label(selo, if id == "xp" then "XP" else "", math.floor(s * 0.11), V.AMBAR_TEXTO, F.TITLE_MED)
		x.Position = UDim2.fromScale(0, 0.66)
		x.Size = UDim2.fromScale(1, 0.2)
		x.TextXAlignment = Enum.TextXAlignment.Center
	else
		local t = label(box, "★", math.floor(s * 0.4), V.BRASS, F.BODY_B)
		t.Size = UDim2.fromScale(1, 1)
		t.TextXAlignment = Enum.TextXAlignment.Center
	end
	return box
end

-- Põe o soldado com a farda do uniforme `item` em `parent` (tamanho cheio), no retrato grande que
-- gira de leve (SoldierPreview: um só, reaproveitado; ele não descarta retratos). false = sem
-- manequim (quem chama desenha o pano no lugar).
function ItemArte.soldado(parent: Instance, item: any): boolean
	local it = ItemArte.info(item)
	local s = it.skin
	if not (s and s.kind == "uniform") then
		return false
	end
	local m = vestido(s)
	if not m then
		return false
	end
	if not retrato then
		retrato = SoldierPreview.newStill(-0.45)
	end
	SoldierPreview.setModel(retrato, m)
	local f = retrato.frame :: Frame
	f.Position = UDim2.fromScale(0, 0)
	f.Size = UDim2.fromScale(1, 1)
	f.Visible = true
	f.Parent = parent
	return true
end

-- tira o retrato da tela que fechou (ele volta na próxima chamada)
function ItemArte.soltaSoldado()
	if retrato then
		(retrato.frame :: Frame).Parent = nil
	end
end

return ItemArte
