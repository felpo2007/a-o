--!strict
-- D-202 (prompt de jogabilidade, §21): a cena da comemoração num ViewportFrame.
-- - Palco: três caixotes de madeira (o 1º no meio e mais alto, com a faixa cor de latão; o 2º com a
--   de aço; o 3º com a de bronze), sacos de areia dos lados, o mastro de bambu com o pano da cor do
--   lado que venceu (dois mastros, um de cada cor, no empate), caixas de munição e coqueiros ao fundo,
--   no fim da tarde. Nada na frente dos soldados.
-- - Soldados: a cópia do personagem (aparência, uniforme, capacete e a arma da partida) ou o manequim
--   do lado. Os gestos são do Shared/Comemoracao, por cinemática direta sobre peças ancoradas (o
--   ViewportFrame não simula). As juntas do soldado são AnimationConstraint (R15 do
--   HumanoidDescription); cada uma volta aos anexos de rig dela, então o personagem copiado deitado,
--   agachado, mirando ou caído fica de pé. Acessórios e armas seguem as soldas.
-- - Câmera: os três sempre no quadro, com um balanço lento.
-- - D-221 (dono: "sem trabalho nenhum sem animações fodas efeitos especiais"): palco de noite que acende
--   a cada pouso, caixotes com filete de luz e o número do lugar, bandeira de pano com dobras, câmera
--   que treme no impacto. Os efeitos em volta da cena estão no Controllers/PodioEfeitos.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comemoracao = require(ReplicatedStorage.Shared.Comemoracao)
local UiEfeitos = require(script.Parent.UiEfeitos)

local Cena = {}
Cena.__index = Cena

type Lig = {
	a: BasePart,
	b: BasePart,
	tipo: string, -- "motor" | "solda" | "rel"
	junta: string?,
	c0: CFrame,
	c1: CFrame,
	c0rot: CFrame,
	c0rotInv: CFrame,
	rel: CFrame,
}
type Elo = { peca: BasePart, pai: BasePart, lig: Lig, direto: boolean }
type Boneco = { modelo: Model, raiz: BasePart, ordem: { Elo }, pes: { BasePart }, lugar: number }

local RAD = math.rad
Cena.TIRAS = 10
Cena.LARGURA_TIRA = 0.68
-- Enquadramento (soldado de ~8,1 studs com o capacete; braços no alto até ~15 studs acima do chão):
-- do chão a ~16 studs na vertical, com folga, e os três com os caixotes na horizontal. D-214: o
-- roteiro da câmera (aberta, depois perto do 1º) está no Shared/Comemoracao.camera.
local CAM_FOV = 34

local function peca(
	pai: Instance,
	nome: string,
	tam: Vector3,
	cf: CFrame,
	cor: Color3,
	mat: Enum.Material,
	forma: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = nome
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if forma then
		p.Shape = forma
	end
	p.Size = tam
	p.CFrame = cf
	p.Color = cor
	p.Material = mat
	p.Parent = pai
	return p
end

-- D-221: o número do lugar na frente do caixote, em barras de luz
local SEGMENTOS = {
	[1] = { "b", "c" },
	[2] = { "a", "b", "g", "e", "d" },
	[3] = { "a", "b", "g", "c", "d" },
} :: { [number]: { string } }

local function numeral(pai: Instance, n: number, centro: Vector3, h: number, cor: Color3)
	local w, e = h * 0.58, h * 0.16
	local X, Y = w / 2 - e / 2, h / 2 - e / 2
	local barra = {
		a = { 0, Y, w, e },
		d = { 0, -Y, w, e },
		g = { 0, 0, w, e },
		b = { X, Y / 2, e, h / 2 },
		c = { X, -Y / 2, e, h / 2 },
		e = { -X, -Y / 2, e, h / 2 },
		f = { -X, Y / 2, e, h / 2 },
	} :: { [string]: { number } }
	for _, s in SEGMENTOS[n] do
		local b = barra[s]
		peca(
			pai,
			"Numero",
			Vector3.new(b[3], b[4], 0.08),
			CFrame.new(centro + Vector3.new(b[1], b[2], 0)),
			cor,
			Enum.Material.Neon
		)
	end
end

-- Cena nova dentro de `pai` (o quadro do pódio): o céu (gradiente) e o ViewportFrame por cima.
function Cena.nova(pai: GuiObject)
	local self = setmetatable({}, Cena) :: any
	local ceu = Instance.new("Frame")
	ceu.Name = "Ceu"
	ceu.BorderSizePixel = 0
	ceu.Size = UDim2.fromScale(1, 1)
	ceu.BackgroundColor3 = Color3.new(1, 1, 1)
	ceu.Parent = pai
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		-- D-221: o fim do crepúsculo: noite em cima e a última faixa de fogo no horizonte
		ColorSequenceKeypoint.new(0, Color3.fromRGB(9, 13, 30)),
		ColorSequenceKeypoint.new(0.42, Color3.fromRGB(32, 32, 62)),
		ColorSequenceKeypoint.new(0.68, Color3.fromRGB(122, 58, 58)),
		ColorSequenceKeypoint.new(0.82, Color3.fromRGB(236, 126, 56)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(116, 54, 38)),
	})
	g.Parent = ceu
	-- D-221: o cenário pintado (tools/podio_fundo.py) por cima do degradê; um pouco maior que o quadro,
	-- para acompanhar o giro da câmera
	local cenario = Instance.new("ImageLabel")
	cenario.Name = "Cenario"
	cenario.BackgroundTransparency = 1
	cenario.AnchorPoint = Vector2.new(0.5, 0.5)
	cenario.Position = UDim2.fromScale(0.5, 0.5)
	cenario.Size = UDim2.fromScale(1.1, 1.1)
	cenario.ScaleType = Enum.ScaleType.Crop
	cenario.Parent = pai
	local function poeCenario()
		local v = ReplicatedStorage:GetAttribute("Img_podio_fundo")
		cenario.Image = if type(v) == "number" and v ~= 0 then string.format("rbxassetid://%d", v) else ""
	end
	local conexao = ReplicatedStorage:GetAttributeChangedSignal("Img_podio_fundo"):Connect(poeCenario)
	cenario.Destroying:Once(function()
		conexao:Disconnect()
	end)
	poeCenario()
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Cena"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(152, 140, 126)
	vp.LightColor = Color3.fromRGB(255, 218, 176)
	vp.LightDirection = Vector3.new(0.45, -0.7, -0.55)
	vp.ZIndex = 3 -- entre os efeitos de trás e os da frente (Controllers/PodioEfeitos)
	vp.Parent = pai
	local cam = Instance.new("Camera")
	cam.FieldOfView = CAM_FOV
	cam.Parent = vp
	vp.CurrentCamera = cam
	self.ceu, self.vp, self.cam, self.cenario = ceu, vp, cam, cenario
	self.t = 0
	self.tremor = 0 -- D-221: o tranco da câmera no pouso
	self.acesa = 0 -- D-221: o palco acendendo (soma nos pousos)
	self.aoPousar = nil :: ((number) -> ())? -- D-221: avisa os efeitos que o soldado tocou o tampo
	self.com = {} :: { [number]: string } -- D-214: a comemoração de cada lugar
	self.soloId = nil :: string? -- D-214: a prévia do ARMÁRIO (não "solo": é o nome do método)
	self.bonecos = {} :: { [number]: Boneco }
	self.panos = {} :: { { Part } }
	self.topos = {} :: { Vector3 }
	self.corPano = {} :: { Color3 }
	self.palco = Instance.new("Model")
	self.palco.Name = "Palco"
	self.palco.Parent = vp
	self:_palco()
	return self
end

function Cena._palco(self: any)
	local P = self.palco
	local madeira = Color3.fromRGB(162, 116, 70)
	-- D-221: a clareira de terra; atrás dela, o cenário pintado. O mato baixo esconde a borda do chão
	peca(P, "Chao", Vector3.new(170, 1, 64), CFrame.new(0, -0.5, 18), Color3.fromRGB(66, 52, 40), Enum.Material.Ground)
	local mato = Random.new(65)
	for k = -30, 30 do
		local d = mato:NextNumber(1.8, 3.2)
		peca(
			P,
			"Mato",
			Vector3.new(d * 1.5, d * 0.62, d),
			CFrame.new(k * 2.7 + mato:NextNumber(-0.8, 0.8), mato:NextNumber(-0.1, 0.25), -14 - mato:NextNumber(0, 1.2)),
			Color3.fromRGB(18, 17, 24),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
	end
	-- caixotes do pódio, com a faixa do lugar
	local faixa = {
		[1] = Color3.fromRGB(181, 148, 74),
		[2] = Color3.fromRGB(152, 154, 150),
		[3] = Color3.fromRGB(150, 98, 60),
	}
	local C = Comemoracao.CAIXOTE
	for i, l in Comemoracao.LUGARES do
		local cx = peca(
			P,
			string.format("Caixote%d", i),
			Vector3.new(C.largura, l.alto, C.fundo),
			CFrame.new(l.x, l.alto / 2, 0),
			madeira,
			Enum.Material.WoodPlanks
		)
		cx.Color = madeira:Lerp(Color3.new(0, 0, 0), 0.05 * (i - 1))
		peca(
			P,
			string.format("Faixa%d", i),
			Vector3.new(C.largura + 0.1, 0.4, C.fundo + 0.1),
			CFrame.new(l.x, l.alto - 0.55, 0),
			faixa[i],
			Enum.Material.Metal
		)
		peca(
			P,
			"Tampa",
			Vector3.new(C.largura + 0.3, 0.25, C.fundo + 0.3),
			CFrame.new(l.x, l.alto + 0.12, 0),
			Color3.fromRGB(122, 88, 54),
			Enum.Material.WoodPlanks
		)
		-- D-221: o filete de luz em volta do tampo e o número do lugar na frente
		local luz = ({
			Color3.fromRGB(255, 206, 96),
			Color3.fromRGB(196, 216, 240),
			Color3.fromRGB(236, 150, 88),
		})[i]
		local frente = C.fundo / 2 + 0.2
		peca(
			P,
			"Filete",
			Vector3.new(C.largura + 0.4, 0.13, 0.13),
			CFrame.new(l.x, l.alto + 0.02, frente),
			luz,
			Enum.Material.Neon
		)
		for _, s in { -1, 1 } do
			peca(
				P,
				"Filete",
				Vector3.new(0.13, 0.13, C.fundo + 0.4),
				CFrame.new(l.x + s * (C.largura / 2 + 0.2), l.alto + 0.02, 0),
				luz,
				Enum.Material.Neon
			)
		end
		local h = math.min(l.alto * 0.6, 2.7)
		numeral(P, i, Vector3.new(l.x, (l.alto - 0.55) / 2, C.fundo / 2 + 0.06), h, luz)
	end
	-- sacos de areia em meia-lua atrás, dos dois lados
	local saco = Color3.fromRGB(150, 134, 100)
	for _, lado in { -1, 1 } do
		for fila = 0, 2 do
			for k = 0, 4 do
				local x = lado * (17.5 + k * 2.5 + (fila % 2) * 1.2)
				local z = -8 - k * 0.9
				peca(
					P,
					"Saco",
					Vector3.new(2.4, 0.95, 1.4),
					CFrame.new(x, 0.48 + fila * 0.9, z) * CFrame.Angles(0, RAD(lado * (10 + k * 6)), 0),
					saco:Lerp(Color3.new(0, 0, 0), 0.05 * ((k + fila) % 3)),
					Enum.Material.Fabric
				)
			end
		end
	end
	-- caixas de munição junto do 3º
	for k, pos in { Vector3.new(17.2, 0.7, 3.5), Vector3.new(19.3, 0.7, 2.6), Vector3.new(18.2, 2.1, 3.1) } do
		peca(
			P,
			string.format("Municao%d", k),
			Vector3.new(2.2, 1.4, 1.2),
			CFrame.new(pos) * CFrame.Angles(0, RAD(8 * k), 0),
			Color3.fromRGB(84, 90, 58),
			Enum.Material.WoodPlanks
		)
	end
end

-- O pano do lado que venceu no mastro (dois no empate). vencedor: "US" | "VC" | "draw".
-- D-221: `imagens` são as chaves da bandeira de verdade ("bandeira_eua"...), repartida nas tiras.
function Cena.bandeira(self: any, cores: { Color3 }, imagens: { string }?)
	for _, m in self.panos do
		for _, p in m do
			p:Destroy()
		end
	end
	table.clear(self.panos)
	table.clear(self.topos)
	local old = self.palco:FindFirstChild("Mastros")
	if old then
		old:Destroy()
	end
	local M = Instance.new("Model")
	M.Name = "Mastros"
	M.Parent = self.palco
	local n = #cores
	for i, c in cores do
		-- entre o 1º e o 3º (um mastro) ou um de cada lado do 1º (empate), atrás deles e baixo o
		-- bastante para o pano caber no quadro
		local x = if n == 1 then 6 else (i - 1.5) * 15
		local topo = Vector3.new(x, 14.6, -12)
		local cor = c:Lerp(Color3.new(1, 1, 1), 0.12)
		peca(
			M,
			"Mastro",
			Vector3.new(15.2, 0.45, 0.45),
			CFrame.new(x, 7.6, -12) * CFrame.Angles(0, 0, RAD(90)),
			Color3.fromRGB(170, 150, 100),
			Enum.Material.Wood,
			Enum.PartType.Cylinder
		)
		-- D-221: dez tiras estreitas; a cor de cada uma muda com a dobra (no `passo`)
		local chave = imagens and imagens[i]
		local v = if chave then ReplicatedStorage:GetAttribute("Img_" .. chave) else nil
		local segs = {}
		for k = 1, Cena.TIRAS do
			local tira = peca(
				M,
				"Pano",
				Vector3.new(Cena.LARGURA_TIRA + 0.03, 4.2, 0.08),
				CFrame.new(topo + Vector3.new((k - 0.5) * Cena.LARGURA_TIRA, -2.1, 0)),
				if type(v) == "number" then Color3.new(1, 1, 1) else cor,
				Enum.Material.Fabric
			)
			if type(v) == "number" and v ~= 0 then
				-- a mesma imagem nas duas faces, cada tira mostrando a sua fatia
				for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
					local tx = Instance.new("Texture")
					tx.Face = face
					tx.Texture = string.format("rbxassetid://%d", v)
					tx.StudsPerTileU = Cena.TIRAS * Cena.LARGURA_TIRA
					tx.StudsPerTileV = 4.2
					tx.OffsetStudsU = if face == Enum.NormalId.Back
						then (k - 1) * Cena.LARGURA_TIRA
						else (Cena.TIRAS - k) * Cena.LARGURA_TIRA
					tx.Parent = tira
				end
			end
			table.insert(segs, tira)
		end
		self.panos[i] = segs
		self.topos[i] = topo
		self.corPano[i] = if type(v) == "number" then Color3.new(1, 1, 1) else cor
	end
end

local function rigAtt(p: Instance, nome: string): Attachment?
	local a = p:FindFirstChild(nome .. "RigAttachment")
	return if a and a:IsA("Attachment") then a else nil
end

-- Prepara a cópia do soldado: limpa o que não desenha ou mexe sozinho, ancora e monta o esqueleto a
-- partir da HumanoidRootPart. Nil se não for um R15 inteiro (o chamador põe o manequim).
local function montar(m: Model, lugar: number): Boneco?
	local raiz = m:FindFirstChild("HumanoidRootPart")
	if not (raiz and raiz:IsA("BasePart")) then
		return nil
	end
	local ligs: { [BasePart]: { Lig } } = {}
	local function add(l: Lig)
		ligs[l.a] = ligs[l.a] or {}
		ligs[l.b] = ligs[l.b] or {}
		table.insert(ligs[l.a], l)
		table.insert(ligs[l.b], l)
	end
	local juntas = 0
	local function junta(nome: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame)
		local rot = c0 - c0.Position
		add({
			a = p0,
			b = p1,
			tipo = "motor",
			junta = nome,
			c0 = c0,
			c1 = c1,
			c0rot = rot,
			c0rotInv = rot:Inverse(),
			rel = CFrame.identity,
		})
		if table.find(Comemoracao.JUNTAS, nome) then
			juntas += 1
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			-- o rig do jogo (R15 do HumanoidDescription): a junta é a AnimationConstraint entre os dois
			-- anexos de rig; vale mesmo com o corpo caído (ela desligada, os anexos no lugar)
			local a0, a1 = d.Attachment0, d.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if a0 and a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				junta(d.Name, p0, p1, a0.CFrame, a1.CFrame)
			end
		elseif d:IsA("Motor6D") and d.Part0 and d.Part1 then
			local c0, c1 = d.C0, d.C1
			local a0, a1 = rigAtt(d.Part0, d.Name), rigAtt(d.Part1, d.Name)
			if a0 and a1 then
				c0, c1 = a0.CFrame, a1.CFrame
			end
			junta(d.Name, d.Part0, d.Part1, c0, c1)
		elseif d:IsA("JointInstance") and d.Part0 and d.Part1 then
			local j = d :: any
			add({
				a = d.Part0,
				b = d.Part1,
				tipo = "solda",
				c0 = j.C0,
				c1 = j.C1,
				c0rot = CFrame.identity,
				c0rotInv = CFrame.identity,
				rel = CFrame.identity,
			})
		elseif d:IsA("WeldConstraint") and d.Part0 and d.Part1 then
			local p0, p1 = d.Part0 :: BasePart, d.Part1 :: BasePart
			add({
				a = p0,
				b = p1,
				tipo = "rel",
				c0 = CFrame.identity,
				c1 = CFrame.identity,
				c0rot = CFrame.identity,
				c0rotInv = CFrame.identity,
				rel = p0.CFrame:ToObjectSpace(p1.CFrame),
			})
		end
	end
	-- braços, pernas, tronco e cabeça: sem eles o gesto não tem onde agir
	if juntas < 10 then
		return nil
	end
	-- o que não desenha ou mexe sozinho sai; as peças ficam ancoradas (as juntas e restrições que
	-- sobram não fazem nada no ViewportFrame)
	for _, d in m:GetDescendants() do
		if
			d:IsA("BaseScript")
			or d:IsA("Sound")
			or d:IsA("ProximityPrompt")
			or d:IsA("BillboardGui")
			or d:IsA("ParticleEmitter")
			or d:IsA("Trail")
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			-- a cópia do personagem local em 1ª pessoa vem com a cabeça e o capacete escondidos
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	local ordem: { Elo } = {}
	local visto: { [BasePart]: boolean } = { [raiz] = true }
	local fila: { BasePart } = { raiz }
	local i = 1
	while i <= #fila do
		local p = fila[i]
		i += 1
		local lista = ligs[p]
		if lista then
			for _, l in lista do
				local outro = if l.a == p then l.b else l.a
				if not visto[outro] and outro:IsDescendantOf(m) then
					visto[outro] = true
					table.insert(ordem, { peca = outro, pai = p, lig = l, direto = l.a == p })
					table.insert(fila, outro)
				end
			end
		end
	end
	-- peça solta (sem solda): fica onde estava em relação à raiz
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and not visto[d] then
			table.insert(ordem, {
				peca = d,
				pai = raiz,
				lig = {
					a = raiz,
					b = d,
					tipo = "rel",
					c0 = CFrame.identity,
					c1 = CFrame.identity,
					c0rot = CFrame.identity,
					c0rotInv = CFrame.identity,
					rel = raiz.CFrame:ToObjectSpace(d.CFrame),
				},
				direto = true,
			})
		end
	end
	local pes: { BasePart } = {}
	for _, n in { "LeftFoot", "RightFoot" } do
		local p = m:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			table.insert(pes, p)
		end
	end
	return { modelo = m, raiz = raiz, ordem = ordem, pes = pes, lugar = lugar }
end

local function elo(l: Lig, direto: boolean, ang: { number }?): CFrame
	if l.tipo == "rel" then
		return if direto then l.rel else l.rel:Inverse()
	end
	local t = CFrame.identity
	if ang then
		-- o giro no quadro da peça de cima (o do Shared/Comemoracao), levado ao quadro do C0
		t = l.c0rotInv * CFrame.Angles(RAD(ang[1]), RAD(ang[2]), RAD(ang[3])) * l.c0rot
	end
	if direto then
		return l.c0 * t * l.c1:Inverse()
	end
	return l.c1 * t:Inverse() * l.c0:Inverse()
end

local function posar(b: Boneco, base: CFrame, pose: Comemoracao.Pose)
	local cfs: { [BasePart]: CFrame } = { [b.raiz] = base }
	for _, e in b.ordem do
		local ang = if e.lig.tipo == "motor" and e.lig.junta then pose.juntas[e.lig.junta] else nil
		cfs[e.peca] = cfs[e.pai] * elo(e.lig, e.direto, ang)
	end
	-- os pés no tampo do caixote (ou no ar, no pulo): a sola mais baixa manda
	local sola = math.huge
	for _, p in b.pes do
		local cf = cfs[p]
		if cf then
			sola = math.min(sola, cf.Position.Y - p.Size.Y / 2)
		end
	end
	local l = Comemoracao.LUGARES[b.lugar]
	local dy = if sola < math.huge then (l.alto + 0.25 + math.max(0, pose.sobe)) - sola else 0
	local sobe = CFrame.new(0, dy, 0)
	b.raiz.CFrame = sobe * base
	for _, e in b.ordem do
		e.peca.CFrame = sobe * cfs[e.peca]
	end
end

-- Põe (ou tira, com nil) o soldado do lugar. Devolve false se o modelo não serve (o chamador tenta
-- o manequim).
function Cena.por(self: any, lugar: number, m: Model?): boolean
	local velho = self.bonecos[lugar]
	if velho then
		velho.modelo:Destroy()
		self.bonecos[lugar] = nil
	end
	if not m then
		return true
	end
	local b = montar(m, lugar)
	if not b then
		m:Destroy()
		return false
	end
	m.Parent = self.vp
	self.bonecos[lugar] = b
	self:_posar(b)
	return true
end

function Cena._posar(self: any, b: Boneco)
	local l = Comemoracao.LUGARES[b.lugar]
	-- de frente para a câmera (+Z), virado um pouco para o meio
	local base = CFrame.new(l.x, l.alto + 4, 0) * CFrame.Angles(0, RAD(180 + (if self.soloId then 0 else l.giro)), 0)
	if self.soloId then
		-- D-214: a prévia do ARMÁRIO: só a comemoração escolhida, em laço
		local p = Comemoracao.celebracao(self.soloId, self.t)
		posar(b, if p.gira then base * CFrame.Angles(0, RAD(p.gira), 0) else base, p)
		return
	end
	-- D-214: cada um chega no caixote na vez dele (3º, 2º, 1º); antes, fica fora de vista
	local visivel, dy = Comemoracao.entrada(b.lugar, self.t)
	if not visivel then
		-- de lado e longe (a altura o `posar` refaz pelos pés)
		base = CFrame.new(600, 0, 0) * base
	end
	local pose = Comemoracao.poseNoPodio(b.lugar, self.t, self.com[b.lugar])
	if dy > 0 then
		pose = { juntas = pose.juntas, sobe = math.max(0, pose.sobe) + dy, gira = pose.gira }
	end
	-- D-221: a volta do corpo no próprio eixo
	if pose.gira and pose.gira ~= 0 then
		base = base * CFrame.Angles(0, RAD(pose.gira), 0)
	end
	posar(b, base, pose)
end

-- D-214: a comemoração do lugar (o 1º faz a dele quando a câmera chega perto)
function Cena.comemoracao(self: any, lugar: number, id: string?)
	self.com[lugar] = Comemoracao.valida(id)
end

-- D-214: a prévia do ARMÁRIO: um soldado só no caixote do meio, fazendo a comemoração `id` em laço,
-- com a câmera de corpo inteiro (nil volta ao pódio)
function Cena.solo(self: any, id: string?)
	self.soloId = if id then Comemoracao.valida(id) else nil
	self.t = 0
end

function Cena.passo(self: any, dt: number)
	local antes = self.t
	self.t += dt
	for _, b in self.bonecos do
		self:_posar(b)
	end
	-- D-221: o soldado tocou o tampo: a câmera dá o tranco, o palco acende e os efeitos disparam
	if not self.soloId then
		local P = Comemoracao.PODIO
		for lugar in self.bonecos do
			local pouso = P.entrada[lugar] + P.queda
			if antes < pouso and self.t >= pouso then
				local forte = lugar == 1
				self.tremor = math.max(self.tremor, if forte then 1 else 0.5)
				self.acesa = math.min(1, self.acesa + (if forte then 0.6 else 0.2))
				if self.aoPousar then
					self.aoPousar(lugar)
				end
			end
		end
	end
	local luz = if self.soloId then 1 else 0.24 + 0.76 * self.acesa
	self.vp.Ambient = Color3.fromRGB(46, 46, 66):Lerp(Color3.fromRGB(150, 138, 128), luz)
	self.vp.LightColor = Color3.fromRGB(150, 146, 176):Lerp(Color3.fromRGB(255, 222, 180), luz)
	-- o pano: tiras estreitas com a onda correndo do mastro para a ponta; a dobra escurece
	for i, segs in self.panos do
		local cf = CFrame.new(self.topos[i])
		for k, p in segs do
			local onda = math.sin(2 * math.pi * 0.85 * self.t - k * 0.62)
			local a = RAD((6 + k * 1.5) * onda + 2)
			cf = cf * CFrame.Angles(0, a, 0)
			p.CFrame = cf * CFrame.new(Cena.LARGURA_TIRA / 2, -2.1 + 0.05 * k * onda, 0)
			local dobra = self.corPano[i]:Lerp(Color3.new(0, 0, 0), 0.05 + 0.2 * (0.5 + 0.5 * onda))
			p.Color = dobra
			for _, tx in p:GetChildren() do
				if tx:IsA("Texture") then
					tx.Color3 = dobra
				end
			end
			cf = cf * CFrame.new(Cena.LARGURA_TIRA, 0, 0)
		end
	end
	-- câmera (D-214, Shared/Comemoracao.camera): aberta nos três com o balanço lento; depois vai até o
	-- 1º (sem pódio, fica aberta); na prévia, o soldado de corpo inteiro
	local c = Comemoracao.camera(if self.bonecos[1] or self.soloId then self.t else 0, self.soloId ~= nil)
	local a = RAD(c.giro)
	local alvo = Vector3.new(c.ax, c.ay, c.az)
	-- D-221: em tela mais estreita que 16:9, recua no plano aberto para os três caberem
	local tam = self.vp.AbsoluteSize
	local aspecto = if tam.Y > 0 then tam.X / tam.Y else 16 / 9
	local abre = if self.soloId then 0 else math.clamp((c.dist - 20) / 15, 0, 1)
	local dist = c.dist * (1 + (math.max(1, 1.75 / aspecto) - 1) * abre)
	local pos = alvo + Vector3.new(math.sin(a) * dist, c.alto - c.ay, math.cos(a) * dist)
	-- o cenário anda um pouco com o giro e cresce no close
	self.cenario.Position = UDim2.fromScale(0.5 - c.giro * 0.0016, 0.5)
	local zoom = 1.1 + 0.12 * (1 - abre)
	self.cenario.Size = UDim2.fromScale(zoom, zoom)
	self.cam.FieldOfView = c.fov
	local cf = CFrame.lookAt(pos, alvo)
	self.tremor *= math.exp(-dt * 8)
	if self.tremor > 0.01 and not UiEfeitos.calmo() then
		local f = 0.42 * self.tremor
		cf = cf
			* CFrame.new(f * math.sin(self.t * 67), f * math.sin(self.t * 83 + 1), 0)
			* CFrame.Angles(0, 0, RAD(0.9 * self.tremor * math.sin(self.t * 59)))
	end
	self.cam.CFrame = cf
end

-- D-214: o instante da cena (s desde o começo da comemoração), para a tela acompanhar o roteiro
function Cena.tempo(self: any): number
	return self.t
end

-- Onde (fração da largura da cena) fica o pé do soldado do lugar: os cartões vão embaixo dele.
function Cena.telaX(self: any, lugar: number): number
	local l = Comemoracao.LUGARES[lugar]
	local p = self.cam.CFrame:PointToObjectSpace(Vector3.new(l.x, l.alto, 0))
	local size = self.vp.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	local ndc = (p.X / math.max(-p.Z, 1e-3)) / (math.tan(RAD(self.cam.FieldOfView / 2)) * aspect)
	return 0.5 + ndc / 2
end

-- D-221: onde (frações da cena) fica um ponto `h` studs acima do tampo do lugar
function Cena.tela(self: any, lugar: number, h: number): (number, number)
	local l = Comemoracao.LUGARES[lugar]
	return self:telaPonto(Vector3.new(l.x, l.alto + h, 0))
end

-- D-221: um ponto qualquer da cena em frações da tela
function Cena.telaPonto(self: any, v: Vector3): (number, number)
	local p = self.cam.CFrame:PointToObjectSpace(v)
	local size = self.vp.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	local prof = math.max(-p.Z, 1e-3)
	local tanV = math.tan(RAD(self.cam.FieldOfView / 2))
	return 0.5 + (p.X / prof) / (tanV * aspect) / 2, 0.5 - (p.Y / prof) / tanV / 2
end

function Cena.reiniciar(self: any)
	self.t = 0
	self.tremor = 0
	self.acesa = 0
	for lugar in self.bonecos do
		self:por(lugar, nil)
	end
end

return Cena
