--!strict
-- D-200 (prompt de jogabilidade, item 19): o lançador do antitanque a pé (RPG-2 do VC; a bazuca M20
-- dos EUA pelo mesmo caminho). Antes o foguete saía pelo Vehicle_Fire com 6 s entre tiros e nenhum
-- estado de carregado. Agora o servidor confere tudo (Shared/Lancador):
-- - tiro ("Lancador_Acao" { op = "fogo", dir, alca }): vivo, de pé (fora de veículo), papel
--   antitanque, o lançador na mão (atributo "ArmaMao" do ArmaNaMao), tubo carregado, intervalo mínimo
--   e direção válida. A alça levanta a direção e a dispersão sai daqui, não do cliente;
-- - voo: simulado aqui a cada Heartbeat (gravidade, sem arrasto). Bate em veículo: penetração e dano
--   do VehicleService; em qualquer coisa: a explosão do ExplosionService. Antes de armar (armM), o
--   projétil falha e não explode. Um muro colado na cara também conta como falha;
-- - recarga ({ op = "recarga" }): tubo vazio e reserva; leva recargaS e só põe no tubo se o
--   lançador continuar na mão ({ op = "cancelar" } ou largar o lançador cancela). "RocketReloadUntil"
--   diz até quando (relógio do servidor) para a tela e o corpo;
-- - os clientes desenham o projétil e o fim dele (LancadorFx): Fire_Launch com a velocidade e
--   Lancador_Fim no ponto onde parou.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Lancador = require(ReplicatedStorage.Shared.Lancador)
local Net = require(ReplicatedStorage.Shared.Net)
local ExplosionService = require(script.Parent.ExplosionService)
local VehicleService = require(script.Parent.VehicleService)

local LancadorService = {}
local M = 0.28

type Voo = {
	n: number,
	pos: Vector3, -- studs
	vel: Vector3, -- studs/s
	t: number,
	origem: Vector3,
	ficha: Lancador.Ficha,
	params: RaycastParams,
	from: string?,
	por: Player?, -- quem atirou: o abate e o XP são dele
}

local voos: { Voo } = {}
local seq = 0
local ultimo: { [Player]: number } = {}
local recargaTok: { [Player]: number } = {}
local tokN = 0
local rng = Random.new()

LancadorService.stats = { tiros = 0, explodiu = 0, falhou = 0, veiculos = 0, recusas = 0 }

local function vivo(p: Player): Model?
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if c and h and h.Health > 0 and h.SeatPart == nil and p:GetAttribute("Downed") ~= true then
		return c
	end
	return nil
end

local function naMao(p: Player, c: Model): boolean
	return p:GetAttribute("Role") == "anti_tank" and c:GetAttribute("ArmaMao") == "launcher"
end

local function cancelar(p: Player)
	recargaTok[p] = nil
	if p:GetAttribute("RocketReloadUntil") ~= nil then
		p:SetAttribute("RocketReloadUntil", nil)
	end
end

local function fim(v: Voo, pos: Vector3, falhou: boolean)
	Net.unreliable("Lancador_Fim"):FireAllClients({ n = v.n, x = pos.X, y = pos.Y, z = pos.Z, falhou = falhou })
end

local function valido(d: any): boolean
	if typeof(d) ~= "Vector3" then
		return false
	end
	local m = (d :: Vector3).Magnitude
	return m == m and m > 0.5 and m < 2
end

function LancadorService.disparar(p: Player, mira: Vector3, alca: number?): boolean
	local c = vivo(p)
	if not (c and naMao(p, c)) or not valido(mira) then
		LancadorService.stats.recusas += 1
		return false
	end
	local now = os.clock()
	if now - (ultimo[p] or -math.huge) < Lancador.INTERVALO_MIN_S then
		LancadorService.stats.recusas += 1
		return false
	end
	local total, carregado = p:GetAttribute("Rockets"), p:GetAttribute("RocketLoaded")
	if not Lancador.podeAtirar(total :: number?, carregado :: boolean?) then
		LancadorService.stats.recusas += 1
		return false
	end
	local head = c:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return false
	end
	local fac = p:GetAttribute("Faction")
	local f = Lancador.de(if type(fac) == "string" then fac else nil)
	local a = if alca and table.find(f.alcas, alca) then alca else Lancador.ALCA_PADRAO
	local dir = Lancador.direcao(mira.Unit, f, a, rng:NextNumber(), rng:NextNumber())
	ultimo[p] = now
	p:SetAttribute("Rockets", (total :: number) - 1)
	p:SetAttribute("RocketLoaded", false)
	cancelar(p)
	LancadorService.stats.tiros += 1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c }
	local saida = Lancador.SAIDA_M / M
	local start = head.Position + dir * saida
	seq += 1
	local v: Voo = {
		n = seq,
		pos = start,
		vel = dir * f.v0 / M,
		t = 0,
		origem = head.Position,
		ficha = f,
		params = params,
		from = if type(fac) == "string" then fac else nil,
		por = p,
	}
	Net.unreliable("Fire_Launch"):FireAllClients({
		kind = f.id,
		x = start.X,
		y = start.Y,
		z = start.Z,
		vx = v.vel.X,
		vy = v.vel.Y,
		vz = v.vel.Z,
		n = seq,
		by = p.UserId,
	})
	-- muro colado na cara: o projétil não arma
	local colado = workspace:Raycast(head.Position, dir * saida, params)
	if colado then
		LancadorService.stats.falhou += 1
		fim(v, colado.Position, true)
		return true
	end
	table.insert(voos, v)
	return true
end

function LancadorService.recarregar(p: Player): boolean
	local c = vivo(p)
	if not (c and naMao(p, c)) or recargaTok[p] ~= nil then
		return false
	end
	if
		not Lancador.podeRecarregar(p:GetAttribute("Rockets") :: number?, p:GetAttribute("RocketLoaded") :: boolean?)
	then
		return false
	end
	local fac = p:GetAttribute("Faction")
	local f = Lancador.de(if type(fac) == "string" then fac else nil)
	tokN += 1
	local tok = tokN
	recargaTok[p] = tok
	p:SetAttribute("RocketReloadUntil", workspace:GetServerTimeNow() + f.recargaS)
	task.delay(f.recargaS, function()
		if recargaTok[p] ~= tok then
			return
		end
		recargaTok[p] = nil
		p:SetAttribute("RocketReloadUntil", nil)
		local c2 = vivo(p)
		if
			c2
			and naMao(p, c2)
			and Lancador.podeRecarregar(
				p:GetAttribute("Rockets") :: number?,
				p:GetAttribute("RocketLoaded") :: boolean?
			)
		then
			p:SetAttribute("RocketLoaded", true)
		end
	end)
	return true
end

local function passo(dt: number)
	local g = Lancador.G / M
	for i = #voos, 1, -1 do
		local v = voos[i]
		v.t += dt
		local nv = v.vel - Vector3.new(0, g * dt, 0)
		local step = (v.vel + nv) * 0.5 * dt
		local hit = workspace:Raycast(v.pos, step, v.params)
		if hit then
			table.remove(voos, i)
			local distM = (hit.Position - v.origem).Magnitude * M
			local armado = distM >= v.ficha.armM
			if armado then
				if VehicleService.projectileHit(hit.Instance, v.ficha.pen, step) then
					LancadorService.stats.veiculos += 1
				end
				ExplosionService.detonate(
					v.ficha.explosive,
					hit.Position,
					if v.por and v.por.Parent then v.por else nil,
					v.from
				)
				LancadorService.stats.explodiu += 1
			else
				LancadorService.stats.falhou += 1
			end
			fim(v, hit.Position, not armado)
		elseif v.t >= v.ficha.maxVooS then
			table.remove(voos, i)
			fim(v, v.pos + step, true)
		else
			v.pos += step
			v.vel = nv
		end
	end
end

function LancadorService.start()
	Net.event("Lancador_Acao").OnServerEvent:Connect(function(p: Player, req: any)
		if type(req) ~= "table" then
			return
		end
		if req.op == "fogo" then
			LancadorService.disparar(p, req.dir, tonumber(req.alca))
		elseif req.op == "recarga" then
			LancadorService.recarregar(p)
		elseif req.op == "cancelar" then
			cancelar(p)
		end
	end)
	local function porSoldado(p: Player)
		p.CharacterAdded:Connect(function(c: Model)
			cancelar(p)
			-- largou o lançador no meio da recarga: ela para
			c:GetAttributeChangedSignal("ArmaMao"):Connect(function()
				if c:GetAttribute("ArmaMao") ~= "launcher" then
					cancelar(p)
				end
			end)
		end)
	end
	for _, p in Players:GetPlayers() do
		porSoldado(p)
	end
	Players.PlayerAdded:Connect(porSoldado)
	Players.PlayerRemoving:Connect(function(p: Player)
		ultimo[p] = nil
		recargaTok[p] = nil
	end)
	RunService.Heartbeat:Connect(passo)
end

return LancadorService
