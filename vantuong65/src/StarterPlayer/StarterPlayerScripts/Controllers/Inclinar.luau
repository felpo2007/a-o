--!strict
-- Inclinar (D-99). Pedido do dono: "os botões de se inclinar não estão funcionando" e "utilize o mesmo
-- modelo de movimentação e inclinação que uso no Front 44". Chamado pelo Movement.client a cada quadro.
-- Por que não funcionava: Q/E e L3/R3 existiam só na camada de mira (sem mirar a tecla nem chegava),
-- a máquina de estados zerava o inclinar fora da mira, a câmera só ia 0,4 m de lado sem girar, nada
-- impedia de espiar através da parede e soltar a mira mandava lean = 0 ao servidor.
-- Agora, como no Front 44:
-- - segurar Q/E (teclado, a qualquer hora a pé) ou L3/R3 (controle, mirando: fora da mira L3 corre e
--   R3 é o corpo a corpo, D-69). As duas teclas contam juntas (soltar uma volta para a outra);
-- - o valor anda para o alvo a 8/s; correndo, deitado, nadando, transpondo ou sentado o alvo é 0;
-- - a câmera vai para o lado (Movement.LEAN.offsetM) e gira 14°; a arma de 1ª pessoa vai junto
--   (WeaponVisuals, VT65ViewModelSeat); em 3ª pessoa o tronco do próprio soldado usa este valor;
-- - colisão: um raio e uma esfera do olho para o lado medem o espaço; a parede limita câmera, arma e
--   tronco (o que vai ao servidor também);
-- - o atributo "Lean" do personagem (PostureService, em quartos) é o que os outros veem
--   (PostureController); este módulo o manda a cada mudança e de novo se algo o zerar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)

local Inclinar = {}
local camera = workspace.CurrentCamera
local M = Movement.STUD_M
local L = Movement.LEAN

export type State = {
	lean: number, -- −1..1, suavizado (esquerda < 0)
	roll: number, -- rad, giro da câmera neste quadro (> 0 = cabeça para a esquerda)
	room: number, -- 0..1, quanto cabe do lado do inclinar
	left: boolean,
	right: boolean,
	sent: number,
	sentAt: number,
}
local S: State = { lean = 0, roll = 0, room = 1, left = false, right = false, sent = 0, sentAt = -10 }
Inclinar.state = S

-- teclas seguradas (as duas camadas, teclado e controle, chamam o mesmo id)
Input.on("lean_left", "press", function()
	S.left = true
end)
Input.on("lean_left", "release", function()
	S.left = false
end)
Input.on("lean_right", "press", function()
	S.right = true
end)
Input.on("lean_right", "release", function()
	S.right = false
end)
-- menu, mapa, morte, veículo: a máquina de estados cancela o inclinar; aqui também
Input.StateChanged:Connect(function(cancelled: { string })
	if table.find(cancelled, "lean") then
		S.left, S.right = false, false
	end
end)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true
params.IgnoreWater = true

-- espaço do olho para o lado (0..1): raio fino (parede encostada) e esfera (quinas e frestas)
local function roomToward(char: Model, origin: Vector3, dir: Vector3): number
	params.FilterDescendantsInstances = { char, camera }
	local reach = (L.offsetM + L.wallM) / M
	local hitM: number? = nil
	local r = workspace:Raycast(origin, dir * reach, params)
	if r then
		hitM = r.Distance * M
	end
	local ok, s = pcall(function()
		return workspace:Spherecast(origin, L.wallM / M, dir * reach, params)
	end)
	if ok and s then
		local d = (s :: RaycastResult).Distance * M + L.wallM
		hitM = if hitM then math.min(hitM, d) else d
	end
	return Movement.leanRoom(hitM)
end

local function intent(): number
	local st = Input.state
	if not InputMap.acceptsGame(st) or st.downed or st.vehicle ~= nil then
		return 0
	end
	return (if S.right then 1 else 0) - (if S.left then 1 else 0)
end

-- Um quadro. busy: nadando ou transpondo. eyeLocal: o olho sem inclinar, no espaço da
-- HumanoidRootPart. Devolve o deslocamento lateral da câmera (studs, direita > 0).
function Inclinar.step(
	dt: number,
	char: Model,
	hum: Humanoid,
	root: BasePart,
	stance: string,
	busy: boolean,
	eyeLocal: Vector3
): number
	local blocked = busy
		or stance == "prone"
		or hum.SeatPart ~= nil
		or Input.state.sprinting
		or char:GetAttribute("Sprinting") == true
		or char:GetAttribute("Downed") == true
	local target = Movement.leanTarget(intent(), blocked)
	local side = if target > 0 then 1 elseif target < 0 then -1 elseif S.lean > 0 then 1 else -1
	if target ~= 0 or math.abs(S.lean) > 1e-3 then
		S.room = roomToward(char, root.CFrame:PointToWorldSpace(eyeLocal), root.CFrame.RightVector * side)
	else
		S.room = 1
	end
	target = math.clamp(target, -S.room, S.room)
	S.lean = math.clamp(Movement.leanStep(S.lean, target, dt), -S.room, S.room) -- a parede empurra já
	if math.abs(S.lean) < 1e-4 then
		S.lean = 0
	end
	S.roll = -S.lean * math.rad(L.rollDeg)
	-- servidor: o alvo em quartos; de novo se o atributo ficou diferente (soltar a mira zera)
	local q = Movement.leanQuant(target)
	local now = os.clock()
	local attr = char:GetAttribute("Lean")
	local cur = if type(attr) == "number" then attr else 0
	local gap = if q ~= S.sent then 0.1 else 0.5
	if (q ~= S.sent or math.abs(cur - q) > 1e-3) and now - S.sentAt >= gap then
		S.sent, S.sentAt = q, now
		Net.event("Posture_Set"):FireServer({ lean = q })
	end
	return S.lean * L.offsetM / M
end

-- sem corpo ou no veículo: tudo a zero (o servidor zera o atributo ao sentar e ao deitar)
function Inclinar.reset()
	S.lean, S.roll, S.room = 0, 0, 1
end

-- Lido pelo PostureController para o próprio soldado (sem esperar a volta do servidor).
function Inclinar.value(): number
	return S.lean
end

-- só no Studio: workspace "VT65DevLean" = −1/0/1 inclina sem tecla (teste do espiar na quina)
if game:GetService("RunService"):IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevLean"):Connect(function()
		local v = workspace:GetAttribute("VT65DevLean")
		S.left = type(v) == "number" and v < 0
		S.right = type(v) == "number" and v > 0
	end)
end

return Inclinar
