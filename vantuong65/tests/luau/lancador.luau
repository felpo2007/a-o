--!strict
-- Lançador do antitanque (D-200; prompt de jogabilidade, item 19): a ficha do RPG-2 com as fontes,
-- o tubo e a reserva, a alça que acerta a distância, a dispersão, a penetração contra os veículos e
-- as amarras no servidor (validação), no cliente (tiro, recarga, cancelamento, tela, efeitos, som).
-- Uso: lune run tests/luau/lancador.luau
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
-- o Shared/Lancador usa o Vector3 do Roblox (o Lune não dá o global ao módulo): Lancador.V3 abaixo
local Vector3 = roblox.Vector3

local S = "../../src/ReplicatedStorage/Shared/"
local Lancador = require(S .. "Lancador") :: any
Lancador.V3 = roblox.Vector3
local Vehicles = require(S .. "Vehicles") :: any
local Explosive = require(S .. "Explosive") :: any
local Rng = require(S .. "Rng") :: any

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FALHA " .. name .. ": " .. tostring(err))
	end
end
local function near(a: number, b: number, tol: number, msg: string?)
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f (tol %.4f)", msg or "", a, b, tol))
end

test("ficha do RPG-2: os números das fontes e o que é equilíbrio", function()
	local f = Lancador.de("VC")
	assert(f.id == "rpg2" and f.municao == "PG-2" and f.explosive == "pg2" and f.pen == "pg2")
	assert(f.v0 == 84, "84 m/s (wiki:RPG-2; DTIC)")
	assert(table.find(f.alcas, 100) and table.find(f.alcas, 150) and f.alcas[#f.alcas] <= 150, "alça até 150 m")
	assert(f.recargaS > 0 and f.recargaS <= 10, "recarga")
	assert(f.total == 3, "3 por vida")
	for _, k in { "v0", "alcas", "recargaS", "armM", "dispersaoGraus", "total" } do
		assert(type(f.src[k]) == "string" and f.src[k] ~= "", "fonte de " .. k)
	end
	assert(Lancador.de("US").id == "m20" and Lancador.de(nil).id == "rpg2")
	assert(Explosive.TYPES.pg2 and Explosive.TYPES.rocket_35, "explosivos")
end)

test("tubo e reserva: atira só carregado; recarrega só vazio e com reserva", function()
	local t, r = Lancador.estado(3, true)
	assert(t == 1 and r == 2)
	t, r = Lancador.estado(2, false)
	assert(t == 0 and r == 2)
	t, r = Lancador.estado(0, true)
	assert(t == 0 and r == 0, "carregado sem nada: vazio")
	assert(Lancador.podeAtirar(3, true) and not Lancador.podeAtirar(3, false) and not Lancador.podeAtirar(0, true))
	assert(
		Lancador.podeRecarregar(2, false)
			and not Lancador.podeRecarregar(2, true)
			and not Lancador.podeRecarregar(0, false)
	)
end)

test("a alça acerta a distância: o voo simulado cai onde a alça diz", function()
	local f = Lancador.de("VC")
	for _, d in f.alcas do
		local th = Lancador.elevacao(d, f.v0)
		near(Lancador.alcanceNoPlano(f.v0, th), d, 1e-6, "fórmula " .. d)
		-- passo a passo a 60 quadros por segundo, como o servidor (Heartbeat)
		local pos, vel = Vector3.zero, Vector3.new(math.cos(th), math.sin(th), 0) * f.v0
		local dt = 1 / 60
		for _ = 1, 600 do
			local np, nv = Lancador.passo(pos, vel, dt)
			if np.Y < 0 then
				local k = pos.Y / (pos.Y - np.Y)
				pos = pos:Lerp(np, k)
				break
			end
			pos, vel = np, nv
		end
		near(pos.X, d, 0.05, "cai a " .. d .. " m")
	end
	-- sem alça, a 100 m o PG-2 já caiu ~7 m: por isso a alça
	local tempo = 100 / f.v0
	near(0.5 * Lancador.G * tempo * tempo, 6.95, 0.05, "queda a 100 m")
end)

test("direção: a alça levanta a mira; a dispersão tem o desvio da ficha", function()
	local f = Lancador.de("VC")
	local mira = Vector3.new(0, 0, -1)
	local d = Lancador.direcao(mira, f, 100, 0.3, 0) -- u2 = 0: sem desvio
	near(math.asin(d.Y), Lancador.elevacao(100, f.v0), 1e-6, "só a alça")
	near(d.X, 0, 1e-6, "sem desvio de lado")
	-- 3000 tiros: o desvio de cada eixo tem o desvio-padrão da ficha
	local r = Rng.new(7)
	local soma2, n = 0, 3000
	local base = Lancador.direcao(mira, f, 100, 0, 0)
	for _ = 1, n do
		local x = Lancador.direcao(mira, f, 100, r:next(), r:next())
		local ang = math.acos(math.clamp(x:Dot(base), -1, 1))
		soma2 += ang * ang
	end
	-- 2 eixos: média de ang² = 2·sigma²
	near(math.deg(math.sqrt(soma2 / n / 2)), f.dispersaoGraus, 0.03, "desvio")
	assert(Lancador.proximaAlca(f, 150, 1) == 150 and Lancador.proximaAlca(f, 50, -1) == 50, "sem dar a volta")
	assert(Lancador.proximaAlca(f, 100, 1) == 150)
end)

test("penetração: o PG-2 fura o Ontos e o LVTP-5, não a frente do M48", function()
	local pen = Vehicles.PEN.pg2
	assert(pen == 150)
	local m48, ontos, lvtp = Vehicles.SPECS.m48a3, Vehicles.SPECS.ontos, Vehicles.SPECS.lvtp5
	assert(not (Vehicles.penetrates(pen, m48.armor.front, 0, 1)), "glacis do M48 (110 mm a 60°)")
	assert(Vehicles.penetrates(pen, ontos.armor.front, 0, 0), "Ontos")
	assert(Vehicles.penetrates(pen, lvtp.armor.side, 0, 0), "LVTP-5 de lado")
	if m48.armor.side then
		assert(Vehicles.penetrates(pen, m48.armor.side, 0, 0.5), "lado do M48")
	end
end)

test("servidor: valida, simula e recarrega no tempo", function()
	local ls = fs.readFile("src/ServerScriptService/Modules/LancadorService.luau")
	for _, t in
		{
			'c:GetAttribute("ArmaMao") == "launcher"',
			'p:GetAttribute("Role") == "anti_tank"',
			"h.SeatPart == nil",
			"Lancador.INTERVALO_MIN_S",
			"Lancador.podeAtirar(",
			"Lancador.podeRecarregar(",
			"Lancador.direcao(mira.Unit, f, a, rng:NextNumber(), rng:NextNumber())",
			"VehicleService.projectileHit(hit.Instance, v.ficha.pen, step)",
			"local armado = distM >= v.ficha.armM",
			'"RocketReloadUntil"',
			"recargaTok[p] ~= tok",
		}
	do
		assert(string.find(ls, t, 1, true), "LancadorService: " .. t)
	end
	local vs = fs.readFile("src/ServerScriptService/Modules/VehicleService.luau")
	assert(not string.find(vs, 'player:SetAttribute("Rockets", left - 1)', 1, true), "o foguete saiu do Vehicle_Fire")
	assert(string.find(vs, "function VehicleService.projectileHit(", 1, true))
	assert(string.find(vs, 'player:SetAttribute("RocketLoaded"', 1, true), "nasce carregado")
	local main = fs.readFile("src/ServerScriptService/Services/Main.server.luau")
	assert(string.find(main, "LancadorService.start()", 1, true))
	local an = fs.readFile("src/ServerScriptService/Modules/ArmaNaMao.luau")
	assert(string.find(an, 'char:SetAttribute("ArmaMao", arma)', 1, true), "a mão conferida")
	local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(net, '"Lancador_Acao"', 1, true) and string.find(net, '"Lancador_Fim"', 1, true))
end)

test("cliente: tiro, recarga, cancelamento, tela, efeitos e som", function()
	local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
	local wc = fs.readFile(C .. "WeaponController.client.luau")
	for _, t in
		{
			'{ op = "fogo", dir = dir, alca = lanc.alca }',
			'{ op = "recarga" }',
			'{ op = "cancelar" }',
			"cancelLauncherReload() -- D-200",
			'Bus.fire("reload_start", f.recargaS, "launcher")',
			"Lancador.proximaAlca(",
		}
	do
		assert(string.find(wc, t, 1, true), "WeaponController: " .. t)
	end
	local fx = fs.readFile(C .. "LancadorFx.client.luau")
	assert(string.find(fx, 'e.kind ~= "rpg2"', 1, true) and string.find(fx, "Lancador_Fim", 1, true))
	assert(string.find(fx, "local MAX_VOOS = 12", 1, true), "limite de projéteis")
	local wv = fs.readFile(C .. "WeaponVisuals.client.luau")
	assert(string.find(wv, 'if viewKind == "launcher" then', 1, true) and string.find(wv, "GranadaPG2", 1, true))
	local hud = fs.readFile(C .. "HudCampo.client.luau")
	assert(string.find(hud, "local function renderLauncher(): boolean", 1, true))
	local pc = fs.readFile(C .. "PostureController.client.luau")
	assert(string.find(pc, 'dono:GetAttribute("RocketReloadUntil")', 1, true), "recarga em 3ª pessoa")
	local au = fs.readFile(C .. "AudioController.client.luau")
	assert(string.find(au, '"rpg2_disparo"', 1, true))
	local ids = fs.readFile("src/ReplicatedStorage/Shared/AssetIds.luau")
	for _, k in { "rpg2_disparo", "rpg2_voo", "rpg2_recarga" } do
		local v = string.match(ids, k .. " = (%d+)")
		assert(v and tonumber(v) and (tonumber(v) :: number) > 0, "som publicado: " .. k)
	end
	assert(fs.isFile("assets/rpg_sons/rpg2_disparo.ogg"), "som do disparo")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
