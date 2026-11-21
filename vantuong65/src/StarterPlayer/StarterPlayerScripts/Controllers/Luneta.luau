--!strict
-- Tela da luneta (2026-11-12, "faça sniper"): o WeaponController chama Luneta.update a cada quadro.
-- - círculo da ocular, preto em volta e uma sombra macia na borda (anéis cada vez mais claros);
-- - retículo da época desenhado no TAMANHO ANGULAR (escala com o FOV da câmera):
--   - Unertl 8x (USMC): cruz fina de lado a lado com um ponto pequeno no centro (anúncios de leilão
--     de lunetas "USMC-SNIPER": "cross with a very small dot in the center");
--   - PU 3,5x (Mosin 91/30): poste grosso subindo de baixo até o centro, com a ponta em cunha, e duas
--     barras horizontais vindo dos lados sem chegar ao centro ("heavy post reticle"; barras: confiança
--     média). Espessuras e a folga das barras: PLACEHOLDER;
-- - o círculo desloca um pouco com o balanço e o coice (o olho fora do eixo escurece a borda);
-- - ao encostar o olho, um piscar preto de 0,15 s esconde a troca de FOV.
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Luneta = {}

local BLACK = Color3.new(0, 0, 0)
local CIRCLE = 0.9 -- diâmetro do círculo em fração da altura da tela

local gui = Instance.new("ScreenGui")
gui.Name = "VT65Luneta"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 12 -- abaixo do HUD de campo (13) e dos avisos
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function frame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = BLACK
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Parent = parent
	return f
end

local function round(f: Frame)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
end

-- círculo: borda preta enorme (escurece tudo fora) + anéis de sombra por dentro
local port = frame(gui, "Ocular")
port.BackgroundTransparency = 1
round(port)
local outer = Instance.new("UIStroke")
outer.Thickness = 4000
outer.Color = BLACK
outer.Parent = port
local rings: { Frame } = {}
for i = 1, 6 do
	local r = frame(port, "Sombra" .. i)
	r.BackgroundTransparency = 1
	r.Position = UDim2.fromScale(0.5, 0.5)
	r.Size = UDim2.fromScale(1 - (i - 1) * 0.022, 1 - (i - 1) * 0.022)
	round(r)
	local s = Instance.new("UIStroke")
	s.Color = BLACK
	s.Thickness = 0
	s.Transparency = 0.25 + i * 0.12
	s.Parent = r
	table.insert(rings, r)
end

-- retículo (centro do círculo)
local ret = frame(port, "Reticulo")
ret.BackgroundTransparency = 1
ret.Position = UDim2.fromScale(0.5, 0.5)
ret.Size = UDim2.fromOffset(0, 0)
local U = {
	h = frame(ret, "CruzH"),
	v = frame(ret, "CruzV"),
	dot = frame(ret, "Ponto"),
	post = frame(ret, "Poste"),
	tip = frame(ret, "Ponta"),
	barL = frame(ret, "BarraE"),
	barR = frame(ret, "BarraD"),
}
round(U.dot)
U.tip.Rotation = 45
local ALL: { Frame } = { U.h, U.v, U.dot, U.post, U.tip, U.barL, U.barR }

local blink = Instance.new("Frame")
blink.Name = "Piscar"
blink.BorderSizePixel = 0
blink.BackgroundColor3 = BLACK
blink.Size = UDim2.fromScale(1, 1)
blink.BackgroundTransparency = 1
blink.Parent = gui

local state = { kind = "", shownAt = 0 }

local function px(deg: number, ppd: number, min: number): number
	return math.max(min, math.floor(deg * ppd + 0.5))
end

local function layout(kind: string, ppd: number, diam: number)
	for _, f in ALL do
		f.Visible = false
	end
	if kind == "unertl" then
		local t = px(0.012, ppd, 1) -- cruz média (PLACEHOLDER)
		U.h.Visible, U.v.Visible, U.dot.Visible = true, true, true
		U.h.Size = UDim2.fromOffset(diam, t)
		U.v.Size = UDim2.fromOffset(t, diam)
		local d = px(0.05, ppd, 3) -- ponto do centro (PLACEHOLDER)
		U.dot.Size = UDim2.fromOffset(d, d)
		for _, f in { U.h, U.v, U.dot } do
			f.Position = UDim2.fromOffset(0, 0)
		end
	elseif kind == "pu" then
		local w = px(0.09, ppd, 2) -- poste (PLACEHOLDER)
		local len = diam / 2
		U.post.Visible, U.tip.Visible, U.barL.Visible, U.barR.Visible = true, true, true, true
		-- ponta em cunha: quadrado girado 45° com o canto de cima no centro (o ponto de pontaria)
		local s = math.max(2, math.floor(w * 0.72 + 0.5))
		local drop = s * 0.7071
		U.tip.Size = UDim2.fromOffset(s, s)
		U.tip.Position = UDim2.fromOffset(0, drop)
		U.post.AnchorPoint = Vector2.new(0.5, 0)
		U.post.Size = UDim2.fromOffset(w, len)
		U.post.Position = UDim2.fromOffset(0, drop)
		local gap = 0.9 * ppd -- folga das barras até o centro (PLACEHOLDER)
		local bt = px(0.05, ppd, 1)
		local bl = math.max(len - gap, 0)
		for _, side in { -1, 1 } do
			local b = if side < 0 then U.barL else U.barR
			b.AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5)
			b.Size = UDim2.fromOffset(bl, bt)
			b.Position = UDim2.fromOffset(side * gap, 0)
		end
	end
end

-- kind: retículo ("unertl" | "pu") ou nil (desliga); fov: FOV vertical da câmera (graus);
-- offset: deslocamento do círculo em fração da altura da tela (olho fora do eixo)
function Luneta.update(kind: string?, fovDeg: number, offset: Vector2)
	if not kind then
		if gui.Enabled then
			gui.Enabled = false
			state.kind = ""
		end
		return
	end
	local vp = camera.ViewportSize
	local h = math.max(vp.Y, 1)
	local diam = math.floor(h * CIRCLE)
	local ppd = h / math.max(fovDeg, 0.5)
	if not gui.Enabled then
		gui.Enabled = true
		state.shownAt = os.clock()
	end
	if kind ~= state.kind then
		state.kind = kind
	end
	layout(kind, ppd, diam)
	port.Size = UDim2.fromOffset(diam, diam)
	port.Position = UDim2.new(0.5, offset.X * h, 0.5, offset.Y * h)
	for i, r in rings do
		local st = r:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = math.max(1, math.floor(diam * 0.011 * (1 + i * 0.15)))
		end
	end
	local since = os.clock() - state.shownAt
	blink.BackgroundTransparency = math.clamp(since / 0.15, 0, 1)
end

function Luneta.active(): boolean
	return gui.Enabled
end

return Luneta
