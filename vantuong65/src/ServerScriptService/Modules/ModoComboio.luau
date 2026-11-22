--!strict
-- D-243: o Comboio na partida. As regras são do Shared/Comboio; aqui ficam a estrada no mundo, os dois caminhões
-- (imagem de uma unidade lógica), quem escolta, contesta e repara, o dano, os conjuntos de reforço e as duas
-- rodadas com troca de lado. O servidor manda em tudo; o cliente só recebe o que ModoComboio.publica devolve.
-- Presença: vivo, apto, a pé e a até escoltaM / contestaM em distância horizontal do ponto médio, com limite de
-- altura (alturaPresencaM). Quem está dentro de veículo não conta (como na captura).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Comboio = require(ReplicatedStorage.Shared.Comboio)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local MapaAtivo = require(ReplicatedStorage.Shared.MapaAtivo)
local MapasRet = require(ReplicatedStorage.Shared.MapasRet) :: any
local Trajeto = require(ReplicatedStorage.Shared.Trajeto)
local Combatants = require(script.Parent.Combatants)

local ModoComboio = {}

local P = MapasRet.COMBOIO
local R = P.regras
local M = MapasRet.M_POR_STUD
local PASSO_S = 0.1
local ALCANCE_REPARO_M = 5 -- PROVISÓRIO: distância do reparador à caixa do caminhão
local INTERVALO_S = 12 -- PROVISÓRIO: entre as duas rodadas
local ARTE_GIRO = -90 -- a frente da arte do M35 (Vehicles.ART.m35.artYawDeg)

type Caminhao = { modelo: Model, caixa: BasePart, prompt: ProximityPrompt }

local ms: any = nil
local T: Trajeto.Trajeto? = nil
local cps: { number } = {}
local caminhoes: { Caminhao } = {}
local candidatos: { { s: number, x: number, z: number } } = {}
local corridas: { Comboio.Corrida } = {}
local rodada = 1
local escolta = "US"
local vencedor: string? = nil
local trocando = false
local presenca: Comboio.Presenca = { escolta = 0, defesa = 0, reparadores = 0 }
local reparando: { [Player]: boolean } = {}
local contadorEvento = 0

local function outro(f: string): string
	return if f == "US" then "VC" else "US"
end

local function corrida(): Comboio.Corrida?
	return corridas[rodada]
end

local function mundo(x: number, y: number, h: number): Vector3
	local wx, wz = MapaAtivo.mundo(P, x, y)
	return Vector3.new(wx, h / M, wz)
end

-- A estrada com o relevo real: um raio por amostra, no terreno e no tabuleiro das pontes.
local function garanteTrajeto(): Trajeto.Trajeto
	if T then
		return T
	end
	while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
		ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
	end
	local map = workspace:WaitForChild("Map")
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	local alvos: { Instance } = { workspace.Terrain }
	local pontes = map:FindFirstChild("Pontes")
	if pontes then
		table.insert(alvos, pontes)
	end
	rp.FilterDescendantsInstances = alvos
	rp.IgnoreWater = true
	local t = Trajeto.novo(P.nos, R.extensaoM, function(x: number, y: number): number
		local wx, wz = MapaAtivo.mundo(P, x, y)
		local hit = workspace:Raycast(Vector3.new(wx, 1500, wz), Vector3.new(0, -3000, 0), rp)
		return if hit then hit.Position.Y * M else 16
	end)
	Trajeto.suaviza(t, 2.5)
	T = t
	cps = {}
	for i, cp in P.checkpoints do
		cps[i] = t.sNos[cp.no]
	end
	-- candidatos de reforço a cada 75 m, dos dois lados da estrada e fora de construções
	candidatos = {}
	local sv = 0
	while sv <= t.comprimento do
		local x, y = Trajeto.pos(t, sv)
		local dx, dy = Trajeto.dir(t, sv)
		for _, lado in { -1, 1 } do
			for _, afasta in { 30, 38, 24 } do
				local qx, qy = x - dy * lado * afasta, y + dx * lado * afasta
				if qx > 6 and qx < P.compM - 6 and qy > 6 and qy < P.profM - 6 then
					local wx, wz = MapaAtivo.mundo(P, qx, qy)
					local hit = workspace:Raycast(Vector3.new(wx, 1500, wz), Vector3.new(0, -3000, 0), rp)
					local solo = hit and hit.Material ~= Enum.Material.Water
					local livre = #workspace:GetPartBoundsInRadius(
						Vector3.new(wx, (hit and hit.Position.Y or 0) + 4, wz),
						7
					) == 0
					if solo and livre then
						table.insert(candidatos, { s = sv, x = wx, z = wz })
						break
					end
				end
			end
		end
		sv += 75
	end
	print(
		string.format(
			"[VT65] comboio: estrada de %.2f m com o relevo, raio mínimo %.1f m, %d conjuntos de reforço",
			t.comprimento,
			Trajeto.raioMinimo(t),
			#candidatos
		)
	)
	return t
end

local function posicionar()
	local t, c = T, corrida()
	if not (t and c) then
		return
	end
	local atras, frente = Comboio.centros(c.s)
	for i, s in { atras, frente } do
		local cam = caminhoes[i]
		if cam then
			local x, y, z = Trajeto.pos(t, s)
			local x1, y1, z1 = Trajeto.pos(t, s + 2)
			local x0, y0, z0 = Trajeto.pos(t, s - 2)
			local p = mundo(x, y, z)
			local eixo = mundo(x1, y1, z1) - mundo(x0, y0, z0)
			local cf = CFrame.lookAt(p, p + eixo)
			cam.modelo:PivotTo(cf * CFrame.Angles(0, math.rad(ARTE_GIRO), 0))
			cam.caixa.CFrame = cf * CFrame.new(0, 1.4 / M, 0)
		end
	end
end

local function montaCaminhoes()
	if #caminhoes > 0 then
		return
	end
	local AssetLoader = require(script.Parent.AssetLoader) :: any
	local pasta = Instance.new("Folder")
	pasta.Name = "Comboio"
	for i = 1, 2 do
		local molde = AssetLoader.template("m35")
		local modelo: Model
		if molde then
			modelo = molde:Clone()
		else
			modelo = Instance.new("Model")
			local b = Instance.new("Part")
			b.Size = Vector3.new(7 / M, 2.8 / M, 2.4 / M)
			b.Color = Color3.fromRGB(70, 78, 52)
			b.Parent = modelo
			modelo.PrimaryPart = b
		end
		modelo.Name = "Caminhao" .. i
		for _, d in modelo:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			elseif d:IsA("Seat") then
				d:Destroy()
			end
		end
		local caixa = Instance.new("Part")
		caixa.Name = "Caixa"
		caixa.Size = Vector3.new(2.4 / M, 2.8 / M, 7 / M)
		caixa.Transparency = 1
		caixa.Anchored = true
		caixa.CanTouch = false
		caixa.Parent = modelo
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Reparar"
		prompt.ObjectText = "Comboio"
		prompt.HoldDuration = R.reparoPessoaS
		prompt.MaxActivationDistance = ALCANCE_REPARO_M / M
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = caixa
		prompt.PromptButtonHoldBegan:Connect(function(pl: Player)
			reparando[pl] = true
		end)
		prompt.PromptButtonHoldEnded:Connect(function(pl: Player)
			reparando[pl] = nil
		end)
		modelo.Parent = pasta
		caminhoes[i] = { modelo = modelo, caixa = caixa, prompt = prompt }
	end
	pasta.Parent = workspace
end

-- Lados da rodada: quem escolta nasce na base de origem (oeste) e a defesa na do destino (leste).
local function aplicaLados()
	local ox, oz = MapaAtivo.mundo(P, P.baseOeste.x, P.baseOeste.y)
	local lx, lz = MapaAtivo.mundo(P, P.baseLeste.x, P.baseLeste.y)
	MapConfig.HQ[escolta] = { x = ox, z = oz, note = "origem do comboio" }
	MapConfig.HQ[outro(escolta)] = { x = lx, z = lz, note = "defesa do destino" }
	ReplicatedStorage:SetAttribute("VT65ComboioEscolta", escolta)
end

local function novaCorrida()
	local t = garanteTrajeto()
	corridas[rodada] = Comboio.nova(table.clone(cps), t.comprimento)
	table.clear(reparando)
	montaCaminhoes()
	posicionar()
end

local function medePresenca(c: Comboio.Corrida): Comboio.Presenca
	local t = T :: Trajeto.Trajeto
	local x, y, z = Trajeto.pos(t, c.s)
	local ref = mundo(x, y, z)
	local e2, d2 = (R.escoltaM / M) ^ 2, (R.contestaM / M) ^ 2
	local hMax = R.alturaPresencaM / M
	local nE, nD = 0, 0
	for _, e in Combatants.list() do
		local root = Combatants.root(e)
		local hum = Combatants.humanoid(e)
		if root and hum and Combatants.active(e) and not hum.SeatPart and math.abs(root.Position.Y - ref.Y) <= hMax then
			local dx, dz = root.Position.X - ref.X, root.Position.Z - ref.Z
			local q = dx * dx + dz * dz
			if e.faction == escolta and q <= e2 then
				nE += 1
			elseif e.faction == outro(escolta) and q <= d2 then
				nD += 1
			end
		end
	end
	-- reparador: do lado da escolta, vivo, a pé e perto de um caminhão; se sair disso, para de contar
	local nR = 0
	for pl in reparando do
		local char = pl.Character
		local en = char and Combatants.get(char)
		local root = en and Combatants.root(en)
		local hum = en and Combatants.humanoid(en)
		local ok = en ~= nil and root ~= nil and hum ~= nil and en.faction == escolta and Combatants.active(en)
		ok = ok and hum ~= nil and not hum.SeatPart
		if ok and root then
			local perto = false
			for _, cam in caminhoes do
				local l = cam.caixa.CFrame:PointToObjectSpace(root.Position)
				local h = cam.caixa.Size / 2 + Vector3.one * (ALCANCE_REPARO_M / M)
				if math.abs(l.X) <= h.X and math.abs(l.Z) <= h.Z and math.abs(l.Y) <= h.Y then
					perto = true
				end
			end
			ok = perto
		end
		if ok then
			nR += 1
		else
			reparando[pl] = nil
		end
	end
	return { escolta = nE, defesa = nD, reparadores = nR }
end

local function fimDaPartida()
	local a, b = corridas[1], corridas[2]
	local q = Comboio.resultado(a, b)
	-- a 1ª rodada foi escoltada pelos EUA e a 2ª pelo VC
	vencedor = if q == 1 then "US" elseif q == 2 then "VC" else "draw"
end

local function trocaRodada()
	trocando = true
	rodada = 2
	escolta = outro(escolta)
	aplicaLados()
	novaCorrida()
	-- a mesma contagem do começo da partida; todos voltam às bases com as condições iniciais
	ms.prepUntil = os.clock() + INTERVALO_S
	ms.startedAt = ms.prepUntil
	ms.waveEpoch = ms.startedAt
	local RodadaService = require(script.Parent.RodadaService) :: any
	for _, r in RodadaService.restaurar do
		local ok, err = pcall(r.fn :: any)
		if not ok then
			warn(string.format("[VT65] comboio: restauração %s falhou: %s", r.nome, tostring(err)))
		end
	end
	trocando = false
end

local function passo(dt: number)
	local c = corrida()
	if not (c and T) or vencedor or trocando or not ms or ms.ended or ms.inPrep() then
		return
	end
	presenca = medePresenca(c)
	Comboio.passo(c, dt, presenca)
	posicionar()
	for _, cam in caminhoes do
		local on = c.imobilizadoAte ~= nil
		if cam.prompt.Enabled ~= on then
			cam.prompt.Enabled = on
		end
	end
	if ms.points[1] then
		local x, y = Trajeto.pos(T :: Trajeto.Trajeto, c.s)
		local wx, wz = MapaAtivo.mundo(P, x, y)
		ms.points[1].x, ms.points[1].z = wx, wz
	end
	if c.entregue or c.t >= R.rodadaS then
		if rodada == 1 then
			task.spawn(trocaRodada)
		else
			fimDaPartida()
		end
	end
end

-- ===== interface com o MatchService =====
function ModoComboio.iniciar(matchService: any)
	ms = matchService
	local acumulado = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acumulado += dt
		if acumulado >= PASSO_S then
			local d = math.min(acumulado, 0.5) -- um engasgo do servidor não dá salto no comboio
			acumulado = 0
			passo(d)
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		reparando[p] = nil
	end)
	local SpawnService = require(script.Parent.SpawnService) :: any
	SpawnService.addProvider(ModoComboio.conjuntos)
	local ExplosionService = require(script.Parent.ExplosionService) :: any
	local antes = ExplosionService.onVehicles
	ExplosionService.onVehicles = function(pos: Vector3, id: string)
		if antes then
			antes(pos, id)
		end
		ModoComboio.sopro(pos, id)
	end
end

function ModoComboio.novaPartida()
	rodada, escolta, vencedor = 1, "US", nil
	table.clear(corridas)
	aplicaLados()
	task.spawn(novaCorrida)
end

function ModoComboio.vencedor(): string?
	return vencedor
end

-- Segundos de partida em que a rodada atual acaba (o relógio do HUD).
function ModoComboio.limite(decorrido: number): number
	local c = corrida()
	return decorrido + (if c then math.max(0, R.rodadaS - c.t) else R.rodadaS)
end

-- Conjuntos de reforço: a escolta nasce 60-120 m atrás da referência, a defesa à frente dela, com a lateral.
function ModoComboio.conjuntos(faction: string): { any }
	local out = {}
	local c = corrida()
	if not c or MapaAtivo.id() ~= "comboio" then
		return out
	end
	local souEscolta = faction == escolta
	for i, q in candidatos do
		local d = q.s - c.s
		if (souEscolta and d <= -60 and d >= -120) or (not souEscolta and d >= 45 and d <= 150) then
			table.insert(out, {
				id = "comboio:" .. i,
				name = if souEscolta then "Reforço da escolta" else "Reforço da defesa",
				x = q.x,
				z = q.z,
				kind = "rally",
			})
		end
	end
	return out
end

-- Sopro de explosão: um evento só, mesmo pegando os dois caminhões.
function ModoComboio.sopro(pos: Vector3, id: string)
	local c = corrida()
	if not c then
		return
	end
	local big = id == "naval_5in" or id == "bomb_250lb"
	local alcance = if big then 8 else 4
	local melhor = math.huge
	for _, cam in caminhoes do
		melhor = math.min(melhor, (cam.caixa.Position - pos).Magnitude * M)
	end
	if melhor < alcance then
		contadorEvento += 1
		Comboio.dano(c, "sopro" .. contadorEvento, (if big then 60 else 30) * (1 - melhor / alcance))
	end
end

-- Projétil no caminhão (lançador): devolve true se a peça é do comboio.
function ModoComboio.impacto(inst: Instance): boolean
	for _, cam in caminhoes do
		if inst == cam.caixa or inst:IsDescendantOf(cam.modelo) then
			local c = corrida()
			if c then
				contadorEvento += 1
				Comboio.dano(c, "proj" .. contadorEvento, 40)
			end
			return true
		end
	end
	return false
end

function ModoComboio.publica(): any
	local c = corrida()
	if not c then
		return nil
	end
	local est = Comboio.estado(c, presenca)
	local marcos = {}
	for i, s in c.cps do
		marcos[i] = s / c.comprimento
	end
	return {
		rodada = rodada,
		escolta = escolta,
		s = c.s,
		fracao = c.s / c.comprimento,
		marcos = marcos,
		cp = c.cp,
		cpProg = c.cpProg,
		cpTotal = R.checkpointS,
		estado = est,
		texto = Comboio.TEXTOS[est],
		integridade = c.integridade,
		imobS = if c.imobilizadoAte then math.max(0, c.imobilizadoAte - c.t) else 0,
		reparo = c.reparo / R.reparoPessoaS,
		restaS = math.max(0, R.rodadaS - c.t),
		entregue = c.entregue,
	}
end

return ModoComboio
