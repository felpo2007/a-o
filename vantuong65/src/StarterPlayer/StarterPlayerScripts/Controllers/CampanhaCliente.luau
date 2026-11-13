--!strict
-- Estado da campanha no cliente (missões, passe, mercado, reforços, medalhas, cartão, vantagens;
-- plano de volta diária, 2026-11-12). Uma cópia só para todas as telas: chega pelo Campanha_State
-- (o servidor manda ao entrar e a cada mudança) ou pelo Campanha_Get na primeira vez. As telas leem
-- get() e ouvem Changed; nunca esperam o servidor sem mostrar "carregando".
-- O formato está no contrato da campanha (Modules/CampanhaService no servidor).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local CampanhaCliente = {}

local state: { [string]: any }? = nil
local changed = Instance.new("BindableEvent")
-- (estado novo, result do último pedido ou nil)
CampanhaCliente.Changed = changed.Event

function CampanhaCliente.get(): { [string]: any }?
	return state
end

local recvAt = 0
local function set(s: any)
	if type(s) ~= "table" then
		return
	end
	state = s
	recvAt = os.clock()
	changed:Fire(s, s.result)
end

task.spawn(function()
	Net.event("Campanha_State").OnClientEvent:Connect(set)
end)

-- pede o estado ao servidor (uma vez por chamada; quem chama já mostra "carregando")
local asking = false
function CampanhaCliente.refresh()
	if asking then
		return
	end
	asking = true
	task.spawn(function()
		local ok, s = pcall(function()
			return Net.func("Campanha_Get"):InvokeServer()
		end)
		asking = false
		if ok then
			set(s)
		end
	end)
end

-- pedido ao servidor ({ op = ..., ... }); a resposta chega como Campanha_State com result
function CampanhaCliente.action(op: string, args: { [string]: any }?)
	local msg: { [string]: any } = if args then table.clone(args) else {}
	msg.op = op
	task.spawn(function()
		Net.event("Campanha_Action"):FireServer(msg)
	end)
end

-- segundos que faltam até t (relógio do servidor: o `now` do último estado mais o tempo desde que chegou)
function CampanhaCliente.left(t: number?): number
	local s = state
	if not (s and t and type(s.now) == "number") then
		return 0
	end
	return math.max(0, t - (s.now + (os.clock() - recvAt)))
end

CampanhaCliente.refresh()

return CampanhaCliente
