--!strict
-- Carta na mão (D-98, pedido do dono: "coloque o mapa como um item que ele pega e abre, e isso
-- aparece para todos"). Chamado pelo WeaponVisuals a cada quadro.
-- - Abrir o mapa tático (ação "map"; Input.state.map) pede ao servidor a carta na mão
--   (Posture_Set { carta = true }); o servidor confere (vivo, a pé, sem estar caído) e grava o
--   atributo "Carta" no personagem. O PostureController de cada cliente põe a folha nas duas mãos
--   (IK) e o fuzil a tiracolo: os outros veem, e você também em 3ª pessoa.
-- - 1ª pessoa: o fuzil some da frente, as mãos sobem com a folha e ficam na parte de baixo da tela,
--   embaixo da carta grande (CartaView, que este módulo não mexe). Fechar o mapa guarda a folha.
-- - Com a carta aberta não se atira (o contexto "map" do Input já não deixa; o WeaponController
--   confere de novo).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartaModel = require(ReplicatedStorage.Shared.CartaModel)
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)

local CartaMao = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local RAISE_S = 0.35 -- tirar a carta e abrir (s)

local S = {
	blend = 0, -- 0 guardada .. 1 aberta diante dos olhos
	sentOpen = false,
	sentAt = -10,
}
local model: Model? = nil

-- Folha no espaço da câmera (m): aberta, baixa (a parte de baixo da tela) e inclinada para os olhos;
-- guardada, abaixo da tela. Cotovelos para fora e para baixo.
local OPEN = CFrame.new(0, -0.3, -0.42) * CFrame.Angles(math.rad(-38), 0, 0)
local DOWN = CFrame.new(0.05, -0.62, -0.25) * CFrame.Angles(math.rad(-80), 0, math.rad(10))
local ELBOW_R = Vector3.new(0.26, -0.56, 0.02)
local ELBOW_L = Vector3.new(-0.26, -0.56, 0.02)

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function scaled(cf: CFrame): CFrame
	return cf.Rotation + cf.Position / M
end

local function ensure(): Model
	if model and model.Parent then
		return model
	end
	local m = CartaModel.build()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m.Parent = camera
	model = m
	return m
end

-- Mapa aberto agora, a pé (no veículo o mapa abre sem a carta na mão).
function CartaMao.wanted(): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return Input.state.map == true
		and hum ~= nil
		and hum.Health > 0
		and hum.SeatPart == nil
		and player:GetAttribute("Downed") ~= true
end

export type Out = {
	active: boolean, -- a carta está na frente (o fuzil some)
	handR: Vector3,
	handL: Vector3,
	rot: CFrame,
	wristR: Vector3,
	wristL: Vector3,
	elbowR: Vector3,
	elbowL: Vector3,
}
local out: Out = {
	active = false,
	handR = Vector3.zero,
	handL = Vector3.zero,
	rot = CFrame.identity,
	wristR = Vector3.zero,
	wristL = Vector3.zero,
	elbowR = Vector3.zero,
	elbowL = Vector3.zero,
}

-- Um quadro. firstPerson: a câmera é a de 1ª pessoa (fora disso só o pedido ao servidor anda).
function CartaMao.step(dt: number, firstPerson: boolean): Out
	local want = CartaMao.wanted()
	-- pede ao servidor quando muda (o servidor também tira a carta de quem cai ou senta)
	local now = os.clock()
	if want ~= S.sentOpen and now - S.sentAt >= 0.3 then
		S.sentOpen, S.sentAt = want, now
		Net.event("Posture_Set"):FireServer({ carta = want })
	end
	S.blend = math.clamp(S.blend + (if want then dt else -dt) / RAISE_S, 0, 1)
	out.active = S.blend > 0 and firstPerson
	if not out.active then
		if model then
			model:PivotTo(CFrame.new(0, -1e4, 0))
		end
		return out
	end
	local m = ensure()
	local e = smooth(S.blend)
	local cam = camera.CFrame
	local sway = math.sin(now * 1.3) * 0.004
	local cf = cam * scaled(DOWN:Lerp(OPEN, e)) * CFrame.new(0, sway / M, 0)
	m:PivotTo(cf)
	local main = m.PrimaryPart :: BasePart
	local r = main:FindFirstChild("MaoD") :: Attachment
	local l = main:FindFirstChild("MaoE") :: Attachment
	out.rot = cf.Rotation
	out.handR = r.WorldPosition
	out.handL = l.WorldPosition
	out.wristR = out.handR + cf:VectorToWorldSpace(Vector3.new(0.02, -0.05, 0.06) / M)
	out.wristL = out.handL + cf:VectorToWorldSpace(Vector3.new(-0.02, -0.05, 0.06) / M)
	out.elbowR = cam * (ELBOW_R / M)
	out.elbowL = cam * (ELBOW_L / M)
	return out
end

return CartaMao
