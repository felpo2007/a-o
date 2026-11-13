--!strict
-- Itens na mão (D-99). Pedido do dono: "faça as animações perfeitas para bandagens etc." e "faça
-- animações perfeitas e realistas para todos os itens ao utilizá-los". Chamado pelo WeaponVisuals a
-- cada quadro (ItemView.step), como o CartaMao.
-- - O quê: curativo em si, torniquete, curativo no companheiro, tratamento e reanimação do médico
--   (atributo "VT65Acao" que o MedicalService grava com "VT65AcaoT"/"VT65AcaoS"), rádio (segurar o
--   botão do rádio), binóculo (atributo local "Binoculars"), pá (atributo "VT65Item" = "shovel" posto pelo
--   servidor, ou a chave "dig_start"/"dig_cancel" no Logistics_State; nunca o texto da tela, que
--   pode chegar traduzido) e cantil (só pelo gancho do Studio: o jogo ainda não tem a ação de beber).
-- - 1ª pessoa: o fuzil sai da frente (o rádio usa só a esquerda) e as mãos do Maos1P seguem o
--   caminho do Shared/ItemAnim, com o objeto na mão (modelo "VT65Item1P" na câmera).
-- - Todos veem: rádio, binóculo e cantil vão ao servidor (Posture_Set { item }); as ações médicas e
--   a pá já são do servidor. O PostureController anima o corpo de cada um (IK).
-- - 2026-11-13: granada e fumaça NA MÃO (vagas 3 e 4, Shared/Equipar; o WeaponController passa a mão
--   com ItemView.hand): a granada desenhada (Shared/GrenadeArt.hand) na direita, a esquerda tira o
--   pino (a argola cai), o braço arma e lança (ItemAnim.GRANADA). Os outros veem a granada na mão do
--   corpo (Modules/ArmaNaMao) e o arremesso do FieldService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Equipar = require(ReplicatedStorage.Shared.Equipar)
local FieldWork = require(ReplicatedStorage.Shared.FieldWork)
local GrenadeArt = require(ReplicatedStorage.Shared.GrenadeArt)
local ItemAnim = require(ReplicatedStorage.Shared.ItemAnim)
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)
-- D-108: objeto e granada do tamanho das mãos de 1ª pessoa (Maos1P.scale = Corpo.ARMA_K)
local Maos1P = require(script.Parent.Maos1P)

local ItemView = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local FAR = CFrame.new(0, -1e4, 0)
local ELBOW_R = Vector3.new(0.22, -0.44, 0.05) / M -- espaço da câmera
local ELBOW_L = Vector3.new(-0.22, -0.44, 0.05) / M

local S = {
	radio = false,
	radioT0 = nil :: number?,
	shovelT0 = -100, -- os.clock
	devName = nil :: string?,
	devT0 = 0,
	sent = nil :: string?,
	sentAt = -10,
	model = nil :: Model?,
	modelKind = "",
	blendOut = 0, -- s restantes da saída de uma ação segurada
}

export type Out = {
	active: boolean,
	full: boolean, -- as duas mãos no item (o fuzil some)
	cfR: CFrame,
	cfL: CFrame,
	poseR: string,
	poseL: string,
	wristR: Vector3,
	wristL: Vector3,
	elbowR: Vector3,
	elbowL: Vector3,
}
local out: Out = {
	active = false,
	full = false,
	cfR = CFrame.identity,
	cfL = CFrame.identity,
	poseR = "grip",
	poseL = "support",
	wristR = Vector3.zero,
	wristL = Vector3.zero,
	elbowR = Vector3.zero,
	elbowL = Vector3.zero,
}

-- rádio: o mesmo botão do Voz.client (segurar ↓ / Caps Lock)
local function radioOn()
	S.radio = true
end
local function radioOff()
	S.radio = false
end
Input.on("radio_talk", "press", radioOn)
Input.on("radio_talk", "holdStart", radioOn)
Input.on("radio_talk", "release", radioOff)
Input.on("radio_talk", "holdEnd", radioOff)
Input.StateChanged:Connect(function()
	if not Input.state.alive or Input.state.menus > 0 then
		S.radio = false
	end
end)

-- pá: por CHAVE (o texto do aviso pode chegar traduzido). O FieldWorkService manda hoje só o
-- texto; com { key = "dig_start" } ao começar e { key = "dig_cancel" } ao cancelar (ou o atributo
-- "VT65Item" = "shovel" no personagem, que o PostureController e este módulo já leem), a pá anima.
Net.event("Logistics_State").OnClientEvent:Connect(function(msg: any)
	local key = type(msg) == "table" and msg.key
	if key == "dig_start" then
		S.shovelT0 = os.clock()
	elseif key == "dig_cancel" then
		S.shovelT0 = -100
	end
end)

-- só no Studio: workspace "VT65DevItemAnim" = "bandage" | "tourniquet" | "bandage_other" | "treat" |
-- "revive" | "radio" | "binoculars" | "shovel" | "canteen" toca a animação (sem efeito de jogo)
if game:GetService("RunService"):IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevItemAnim"):Connect(function()
		local v = workspace:GetAttribute("VT65DevItemAnim")
		if type(v) == "string" and ItemAnim.ANIMS[v] then
			S.devName, S.devT0 = v, os.clock()
		else
			S.devName = nil
		end
	end)
end

-- itens que ESTE cliente pede ao servidor (os outros, como a pá, o servidor põe e tira)
local CLIENT_ITEMS = { radio = true, binoculars = true, canteen = true }

-- A ação de agora: nome, tempo desde o começo, duração (nil = segurada)
local function current(): (string?, number, number?)
	local char = player.Character
	local now = os.clock()
	if S.devName then
		local a = ItemAnim.ANIMS[S.devName]
		local t = now - S.devT0
		local D = if a.held then 4 else a.dur
		if t <= D then
			return S.devName, t, D
		end
		S.devName = nil
	end
	if char then
		local acao = char:GetAttribute("VT65Acao")
		local t0 = char:GetAttribute("VT65AcaoT")
		local secs = char:GetAttribute("VT65AcaoS")
		if type(acao) == "string" and ItemAnim.ANIMS[acao] and type(t0) == "number" then
			local D = if type(secs) == "number" then secs else (ItemAnim.duration(acao) or 4)
			local t = workspace:GetServerTimeNow() - t0
			if t >= 0 and t <= D + 0.2 then
				return acao, t, D
			end
		end
	end
	local dig = FieldWork.DIG.seconds
	if now - S.shovelT0 <= dig then
		return "shovel", now - S.shovelT0, dig
	end
	if S.radio then
		return "radio", now - (S.radioT0 or now), nil
	end
	if player:GetAttribute("Binoculars") == true then
		return "binoculars", 1, nil
	end
	-- item que o servidor pôs no personagem (a pá)
	if char then
		local it = char:GetAttribute("VT65Item")
		if type(it) == "string" and not CLIENT_ITEMS[it] then
			local name, t, D = ItemAnim.current(function(a: string): any
				return char:GetAttribute(a)
			end, workspace:GetServerTimeNow(), dig)
			if name then
				return name, t, D
			end
		end
	end
	return nil, 0, nil
end

-- objeto da mão em 1ª pessoa
local function prop(kind: string): Model
	local key = kind .. ":" .. Maos1P.scale()
	if S.model and S.model.Parent and S.modelKind == key then
		return S.model
	end
	if S.model then
		S.model:Destroy()
	end
	local def = ItemAnim.PROPS[kind]
	local m = Instance.new("Model")
	m.Name = "VT65Item1P"
	local function piece(size: { number }, cf: CFrame, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		if shape then
			p.Shape = shape
		end
		p.Size = Vector3.new(size[1], size[2], size[3]) / M
		p.Color = Color3.fromRGB(def.rgb[1], def.rgb[2], def.rgb[3])
		p.Material = if kind == "curativo" or kind == "torniquete"
			then Enum.Material.Fabric
			else Enum.Material.SmoothPlastic
		p.CFrame = cf
		p.Parent = m
		return p
	end
	local s = def.size
	local main: BasePart
	if kind == "curativo" or kind == "torniquete" then
		main = piece({ s[1], s[2], s[3] }, CFrame.identity, Enum.PartType.Cylinder)
	elseif kind == "binoculo" then
		main = piece({ s[1] * 0.3, s[2], s[3] }, CFrame.identity) -- ponte
		for _, x in { -1, 1 } do
			piece(
				{ s[3], s[2], s[2] },
				CFrame.new(x * s[1] * 0.33 / M, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
				Enum.PartType.Cylinder
			)
		end
	elseif kind == "pa" then
		main = piece(
			{ s[3], s[1], s[2] },
			CFrame.new(0, 0, -s[3] / 2 / M) * CFrame.Angles(0, math.pi / 2, 0),
			Enum.PartType.Cylinder
		)
		local b = def.blade or { 0.2, 0.15, 0.01 }
		local blade =
			piece({ b[2], b[1], b[3] }, CFrame.new(0, 0, -(s[3] + b[1] / 2) / M) * CFrame.Angles(math.pi / 2, 0, 0))
		blade.Material = Enum.Material.Metal
		piece({ 0.12, 0.03, 0.03 }, CFrame.identity, Enum.PartType.Cylinder) -- o cabo em T, na mão direita
	else
		main = piece(s, CFrame.identity)
	end
	m.PrimaryPart = main
	main.PivotOffset = main.CFrame:Inverse() -- pivô na origem do desenho (a mão)
	m:ScaleTo(Maos1P.scale())
	m.Parent = camera
	S.model, S.modelKind = m, key
	return m
end

local function hideProp()
	if S.model then
		S.model:PivotTo(FAR)
	end
end

-- ===== granada na mão (2026-11-13) =====
local G = {
	hand = nil :: Equipar.Hand?,
	model = nil :: Model?,
	key = "",
	pins = {} :: { BasePart },
	dropped = false,
}

-- O WeaponController passa a granada na mão (nil = nenhuma).
function ItemView.hand(h: Equipar.Hand?)
	G.hand = h
	G.dropped = false
end

local function grenadeModel(kind: string): Model
	local faction = player:GetAttribute("Faction")
	local key = kind .. ":" .. tostring(faction) .. ":" .. Maos1P.scale()
	if G.model and G.model.Parent and G.key == key then
		return G.model
	end
	if G.model then
		G.model:Destroy()
	end
	local m = GrenadeArt.hand(kind, if type(faction) == "string" then faction else nil)
	m:ScaleTo(m:GetScale() * Maos1P.scale())
	m.Name = "VT65Item1P" -- o WeaponVisuals leva junto no inclinar (lista FOLLOW)
	G.pins = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Pino" then
			table.insert(G.pins, d)
		end
	end
	m.Parent = camera
	G.model, G.key = m, key
	return m
end

local function hideGrenade()
	if G.model then
		G.model:PivotTo(FAR)
	end
end

-- a argola sai na mão esquerda e cai (só a de 1ª pessoa)
local function dropRing(at: Vector3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.004, 0.024, 0.024) * Maos1P.scale() / M
	ring.Color = Color3.fromRGB(150, 138, 104)
	ring.Material = Enum.Material.Metal
	ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = false, false, false, false
	ring.CFrame = CFrame.new(at)
	ring.Parent = workspace
	ring.AssemblyLinearVelocity = camera.CFrame:VectorToWorldSpace(Vector3.new(-0.4, 0.6, -0.2)) / M
	task.delay(1.2, function()
		ring:Destroy()
	end)
end

local function v3(a: { number }): Vector3
	return Vector3.new(a[1], a[2], a[3])
end

local function smoothK(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- mãos (m, espaço da câmera), pose da esquerda, granada à vista, pino à vista
local function grenadeHands(h: Equipar.Hand, now: number): (Vector3, Vector3, string, boolean, boolean)
	local GA, GE = ItemAnim.GRANADA, Equipar.GRENADE
	local t = Equipar.phaseTime(h, now)
	local hold = { r = v3(GA.hold.r), l = v3(GA.hold.l) }
	local cock = { r = v3(GA.cock.r), l = v3(GA.cock.l) }
	local breath = Vector3.new(0, math.sin(now * 1.6) * 0.004, 0)
	if h.phase == "saque" then
		local u = smoothK(t / GE.drawS)
		return v3(ItemAnim.GR_REST.r):Lerp(hold.r, u), v3(ItemAnim.GR_REST.l):Lerp(hold.l, u), "flat", true, true
	elseif h.phase == "pronta" then
		return hold.r + breath, hold.l + breath, "flat", true, true
	elseif h.phase == "armando" then
		local r = hold.r:Lerp(cock.r, smoothK((t - 0.08) / (GE.readyS - 0.08)))
		local pin = v3(GA.pin.l)
		local l: Vector3
		if t < 0.12 then
			l = hold.l:Lerp(pin, smoothK(t / 0.12))
		elseif t < GE.pinS then
			l = pin
		else
			l = pin:Lerp(cock.l, smoothK((t - GE.pinS) / math.max(GE.readyS - GE.pinS, 0.05)))
		end
		return r, l, if t < GE.pinS + 0.04 then "grip" else "flat", true, t < GE.pinS
	elseif h.phase == "armada" then
		return cock.r + breath * 0.5, cock.l + breath * 0.5, "flat", true, false
	elseif h.phase == "lancando" then
		local r, l = ItemAnim.sample(if h.under then GA.under else GA.throw, t)
		return v3(r), v3(l), "flat", t < GE.releaseS, false
	end
	return v3(ItemAnim.GR_REST.r), v3(ItemAnim.GR_REST.l), "flat", false, false
end

-- avisa o servidor do item segurado (rádio, binóculo, pá, cantil) para os outros verem
local function replicate(name: string?)
	-- a pá vai ao servidor só quando este cliente a soube pela chave "dig_start"
	local mine = os.clock() - S.shovelT0 <= FieldWork.DIG.seconds
	local ok = name and (CLIENT_ITEMS[name] or (name == "shovel" and mine)) and S.devName == nil
	local want = if ok then name else nil
	local char = player.Character
	local attr = char and char:GetAttribute("VT65Item")
	if type(attr) == "string" and not CLIENT_ITEMS[attr] and S.sent ~= attr then
		return -- item que o servidor pôs (a pá): não tira
	end
	local now = os.clock()
	local gap = if want ~= S.sent then 0.3 else 1.0
	if (want ~= S.sent or attr ~= want) and now - S.sentAt >= gap and char then
		S.sent, S.sentAt = want, now
		Net.event("Posture_Set"):FireServer({ item = want or false })
	end
end

-- Um quadro. firstPerson: a vista de 1ª pessoa com arma (fora dela só a réplica anda).
function ItemView.step(_dt: number, firstPerson: boolean): Out
	local h = G.hand
	if h and h.phase ~= "fim" then
		replicate(nil) -- rádio/binóculo saem; a granada na mão do corpo é do servidor (ArmaNaMao)
		hideProp()
		if not firstPerson then
			out.active = false
			hideGrenade()
			return out
		end
		local now = os.clock()
		local r, l, poseL, showG, showPin = grenadeHands(h, now)
		local cam = camera.CFrame
		local rot = cam.Rotation * CFrame.Angles(math.rad(8), 0, math.rad(-12))
		local pr, pl = cam * (r / M), cam * (l / M)
		out.active, out.full = true, true
		out.poseR, out.poseL = "grip", poseL
		out.cfR = rot + pr
		out.cfL = cam.Rotation * CFrame.Angles(math.rad(-10), 0, math.rad(15)) + pl
		local km = Maos1P.scale() / M
		out.wristR = pr + rot * (Vector3.new(0, -0.03, 0.05) * km)
		out.wristL = pl + cam.Rotation * (Vector3.new(0, -0.01, 0.05) * km)
		out.elbowR = cam * ELBOW_R
		out.elbowL = cam * ELBOW_L
		if showG then
			local m = grenadeModel(h.kind)
			m:PivotTo(rot + pr)
			for _, p in G.pins do
				p.LocalTransparencyModifier = if showPin then 0 else 1
			end
			if not showPin and not G.dropped then
				G.dropped = true
				dropRing(pl)
			end
		else
			hideGrenade()
		end
		return out
	end
	hideGrenade()
	local name, t, D = current()
	if name == "radio" and not S.radioT0 then
		S.radioT0 = os.clock()
		t = 0
	elseif name ~= "radio" then
		S.radioT0 = nil
	end
	replicate(name)
	local a = if name then ItemAnim.ANIMS[name] else nil
	-- binóculo em 1ª pessoa: a tela do binóculo cobre tudo (WeaponController); nada a desenhar
	if not (a and firstPerson) or name == "binoculars" then
		out.active = false
		hideProp()
		return out
	end
	local anim = a :: ItemAnim.Anim
	local tt = ItemAnim.localTime(anim, t, D)
	local r, l, tilt = ItemAnim.sample(anim.fp, tt)
	local cam = camera.CFrame
	local pr = cam * (Vector3.new(r[1], r[2], r[3]) / M)
	local pl = cam * (Vector3.new(l[1], l[2], l[3]) / M)
	local rot = cam.Rotation * CFrame.Angles(math.rad(-15), 0, 0)
	local rotR, rotL = rot, rot
	if anim.prop and anim.prop.kind == "pa" then
		-- as duas mãos no cabo: o eixo da pega acompanha o cabo (da direita para a esquerda)
		local dir = pl - pr
		if dir.Magnitude > 1e-3 then
			local up = -dir.Unit
			local right = cam.RightVector - up * cam.RightVector:Dot(up)
			if right.Magnitude > 1e-3 then
				rotR = CFrame.fromMatrix(Vector3.zero, right.Unit, up)
				rotL = rotR
			end
		end
	elseif anim.prop and anim.prop.kind == "cantil" then
		rotR = cam.Rotation * CFrame.Angles(math.rad(tilt * 0.6), 0, math.rad(-10))
	end
	out.active = true
	out.full = anim.slung
	out.poseR, out.poseL = anim.poseR, anim.poseL
	out.cfR = rotR + pr
	out.cfL = rotL + pl
	local km = Maos1P.scale() / M
	out.wristR = pr + rotR * (Vector3.new(0, -0.03, 0.05) * km)
	out.wristL = pl + rotL * (Vector3.new(0, -0.01, 0.05) * km)
	out.elbowR = cam * ELBOW_R
	out.elbowL = cam * ELBOW_L
	-- objeto na mão
	local p = anim.prop
	if p and ItemAnim.propOn(anim, tt) then
		local m = prop(p.kind)
		local at: CFrame
		if p.kind == "binoculo" then
			at = cam.Rotation + (pr + pl) / 2 + cam.LookVector * (0.02 * km)
		elseif p.kind == "pa" then
			at = CFrame.lookAt(pr, pr + (pl - pr).Unit * 2)
		elseif p.hand == "L" then
			at = rotL + (pl + rotL * (Vector3.new(0, 0.02, -0.01) * km))
		else
			at = rotR * CFrame.Angles(0, 0, math.rad(90)) + (pr + rotR * (Vector3.new(-0.005, 0.0, -0.01) * km))
		end
		m:PivotTo(at)
	else
		hideProp()
	end
	return out
end

return ItemView
