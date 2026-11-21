--!strict
-- Troca de arma (D-194; Shared/Equipar.Troca, prompt de jogabilidade item 10): a curva que desce e
-- sobe, a troca no meio de outra sem pular, a volta, a espera da 3ª pessoa, o texto do atributo, a
-- recarga cancelada (com os cartuchos da espingarda que já entraram) e as amarras no código.
-- Uso: lune run tests/luau/troca.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Equipar = require(S .. "Equipar") :: any
local Weapons = require(S .. "Weapons") :: any

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

-- maior salto de altura entre dois quadros de 60 Hz ao longo de [a, b]
local function maxJump(f: (number) -> number, a: number, b: number): number
	local worst, last = 0, f(a)
	local t = a
	while t < b do
		t += 1 / 60
		local v = f(t)
		worst = math.max(worst, math.abs(v - last))
		last = v
	end
	return worst
end

test("troca simples: desce no holsterS, troca embaixo, sobe no drawS e fica pronta no fim", function()
	local hold, draw = Equipar.holsterS("m14", "rifle"), Equipar.drawS("m1911", "pistol")
	local tr = Equipar.trocaNova(10, 0, hold, draw)
	near(Equipar.trocaDown(tr, 10), 0, 1e-9, "começa em uso")
	near(Equipar.trocaEmbaixo(tr), 10 + hold, 1e-9, "embaixo no holsterS")
	near(Equipar.trocaDown(tr, 10 + hold), 1, 1e-9, "embaixo")
	near(Equipar.trocaFim(tr, 10) :: number, 10 + hold + draw, 1e-9, "fim")
	assert(not Equipar.trocaPronta(tr, 10 + hold + draw - 0.01), "o dedo só chega no fim")
	assert(Equipar.trocaPronta(tr, 10 + hold + draw), "pronta no fim")
	near(Equipar.trocaDown(tr, 10 + hold + draw), 0, 1e-9, "em uso de novo")
	-- sem pulos maiores que um quadro de descida rápida
	assert(maxJump(function(t)
		return Equipar.trocaDown(tr, t)
	end, 10, 11.5) < 0.2, "curva contínua")
end)

test("troca no meio de outra continua da altura em que a arma está (não pula para cima)", function()
	local hold, draw = 0.24, 0.6
	local a = Equipar.trocaNova(0, 0, hold, draw)
	-- no meio da descida
	local t1 = 0.12
	local h1 = Equipar.trocaDown(a, t1)
	assert(h1 > 0.1 and h1 < 0.9, "meio da descida")
	local b = Equipar.trocaNova(t1, h1, hold, 0.3)
	near(Equipar.trocaDown(b, t1), h1, 1e-9, "mesma altura no começo")
	near(b.hold, hold * (1 - h1), 1e-9, "só a descida que falta")
	-- no meio da subida da arma nova
	local t2 = hold + draw * 0.5
	local h2 = Equipar.trocaDown(a, t2)
	assert(h2 > 0.1 and h2 < 0.9, "meio da subida")
	local c = Equipar.trocaNova(t2, h2, 0.15, 0.3)
	near(Equipar.trocaDown(c, t2), h2, 1e-9, "mesma altura no meio da subida")
	near(Equipar.trocaDown(c, Equipar.trocaEmbaixo(c)), 1, 1e-9, "desce até embaixo")
end)

test("volta para a arma que descia: sobe de onde está, no saque vezes a altura", function()
	local a = Equipar.trocaNova(0, 0, 0.3, 1.0)
	local h = Equipar.trocaDown(a, 0.15)
	local v = Equipar.trocaVolta(0.15, h, 1.0)
	near(Equipar.trocaDown(v, 0.15), h, 1e-9, "sem pulo")
	near(Equipar.trocaFim(v, 0.15) :: number, 0.15 + 1.0 * h, 1e-9, "subida proporcional")
	near(Equipar.trocaDown(v, 0.15 + h), 0, 1e-9, "em uso no fim")
	-- volta logo no começo: pronta na hora
	local z = Equipar.trocaVolta(5, 0, 1.0)
	assert(Equipar.trocaPronta(z, 5), "nada a subir")
end)

test("granada: a arma desce e fica embaixo até a próxima troca", function()
	local tr = Equipar.trocaNova(0, 0, 0.24, math.huge)
	near(Equipar.trocaDown(tr, 0.24), 1, 1e-9)
	near(Equipar.trocaDown(tr, 120), 1, 1e-9, "fica embaixo")
	assert(not Equipar.trocaPronta(tr, 120))
	-- vinda da granada (já embaixo): a arma só sobe
	local back = Equipar.trocaNova(120, 1, 0, 0.6)
	near(back.hold, 0, 1e-9)
	near(Equipar.trocaDown(back, 120), 1, 1e-9)
	near(Equipar.trocaFim(back, 120) :: number, 120.6, 1e-9)
end)

test("3ª pessoa: embaixo até a arma nova chegar à mão, ou até TROCA_ESPERA_S", function()
	local tr = Equipar.trocaNova(0, 0, 0.24, 0.3, true)
	near(Equipar.trocaDown(tr, 0.5), 1, 1e-9, "esperando")
	assert(Equipar.trocaFim(tr, 0.5) == nil, "sem fim antes de chegar")
	Equipar.trocaSobe(tr, 0.5)
	near(Equipar.trocaFim(tr, 0.5) :: number, 0.8, 1e-9, "sobe quando chegou")
	-- chegou antes de chegar embaixo: sobe só lá embaixo (o modelo não pula no alto)
	local early = Equipar.trocaNova(0, 0, 0.24, 0.3, true)
	Equipar.trocaSobe(early, 0.1)
	near(early.riseAt :: number, 0.24, 1e-9)
	-- nunca chegou (a mesma arma, rede perdida): sobe depois da espera
	local lost = Equipar.trocaNova(0, 0, 0.24, 0.3, true)
	local w = 0.24 + Equipar.TROCA_ESPERA_S
	near(Equipar.trocaDown(lost, w - 0.01), 1, 1e-9)
	near(Equipar.trocaFim(lost, w) :: number, w + 0.3, 1e-9)
	near(Equipar.trocaDown(lost, w + 0.3), 0, 1e-9)
end)

test("atributo: o texto ida e volta dá a mesma curva (nova e volta)", function()
	local tr = Equipar.trocaNova(0, 0.3, 0.24, 0.6)
	local s = Equipar.trocaTexto(1000.25, tr, "m1911", false)
	local v = Equipar.trocaLer(s)
	assert(v and v.alvo == "m1911" and not v.volta, s)
	Equipar.trocaSobe(v.tr, 1000.25 + tr.hold)
	for _, dt in { 0, 0.05, 0.1, tr.hold, tr.hold + 0.2, tr.hold + 0.6 } do
		near(Equipar.trocaDown(v.tr, 1000.25 + dt), Equipar.trocaDown(tr, dt), 2e-3, "nova em " .. dt)
	end
	local back = Equipar.trocaVolta(0, 0.6, 1.0)
	local vb = Equipar.trocaLer(Equipar.trocaTexto(50, back, "m14", true))
	assert(vb and vb.volta and vb.alvo == "m14")
	for _, dt in { 0, 0.2, 0.4, 0.6 } do
		near(Equipar.trocaDown(vb.tr, 50 + dt), Equipar.trocaDown(back, dt), 2e-3, "volta em " .. dt)
	end
	assert(Equipar.trocaLer("lixo") == nil and Equipar.trocaLer(12) == nil, "texto ruim não vale")
	assert(Equipar.trocaLer("1;0;0;0;m1 4;n") == nil, "alvo com espaço não vale")
end)

test("espingarda: a recarga cancelada guarda os cartuchos que já entraram", function()
	local wp = Weapons.get("win12")
	assert(wp and wp.feed == "tube", "win12 tubular")
	local start, shell = wp.reloadStartS, wp.shellS
	assert(Weapons.tubeLoaded(wp, 0, 30, start - 0.01) == 0, "nada antes de começar")
	assert(Weapons.tubeLoaded(wp, 0, 30, start + shell * 0.99) == 0, "o 1º ainda entrando")
	assert(Weapons.tubeLoaded(wp, 0, 30, start + shell) == 1, "1 no fim do tempo dele")
	assert(Weapons.tubeLoaded(wp, 0, 30, start + shell * 3.5) == 3, "3 e meio = 3")
	assert(Weapons.tubeLoaded(wp, 5, 30, 60) == wp.magazine - 5, "até encher")
	assert(Weapons.tubeLoaded(wp, 0, 2, 60) == 2, "até o que há solto")
	-- com a vantagem de recarga (0,88) o tempo encolhe junto
	assert(Weapons.tubeLoaded(wp, 0, 30, (start + shell) * 0.88, 0.88) == 1, "vantagem")
end)

test("servidor: a recarga para quando a mão muda e não completa depois de cancelada", function()
	local cs = fs.readFile("src/ServerScriptService/Modules/CombatService.luau")
	for _, t in
		{
			"local function cancelReload(player: Player, rec: Rec)",
			'if rec and type(req) == "table" and req.cancel == true then',
			"if recFor(player, rec.weapon) == rec and rec.reloadUntil == untilT then",
			"Weapons.tubeLoaded(wp, rec.mag, rec.spare, now - t0, rec.reloadK)",
			'Net.event("Posture_Set").OnServerEvent:Connect(function(player, req: any)',
		}
	do
		assert(string.find(cs, t, 1, true), "CombatService: " .. t)
	end
	local am = fs.readFile("src/ServerScriptService/Modules/ArmaNaMao.luau")
	for _, t in
		{
			'char:SetAttribute("Troca", Equipar.trocaTexto(workspace:GetServerTimeNow(), tr, alvo, t.volta == true))',
			"hold = math.clamp(hold, 0, Equipar.TROCA_MAX_HOLD)",
			"if pending[p] == nil and since >= 0.1 then",
		}
	do
		assert(string.find(am, t, 1, true), "ArmaNaMao: " .. t)
	end
end)

test("cliente: estados da troca ligados à mira, recarga, golpe, granada, veículo e 3ª pessoa", function()
	local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
	local wc = fs.readFile(C .. "WeaponController.client.luau")
	for _, t in
		{
			"setTroca(Equipar.trocaVolta(now, downNow(now), Equipar.drawS(id, kind)), handIdOf(id), true)",
			"Equipar.trocaNova(now, d0, hold, Equipar.drawS(newId, newKind))",
			"if i and tr and now >= Equipar.trocaEmbaixo(tr) then",
			"inv.aimQueued = if Input.settings.aimToggle then not inv.aimQueued else true",
			"or now < inv.busyUntil then", -- golpe
			'Net.event("Combat_Reload"):FireServer({ w = wp.id, cancel = true })',
			"local tr = Equipar.trocaNova(now, d0, hold, math.huge)", -- granada
			"if seated() or ItemView.handsBusy() then",
			"stepTroca(now)",
			'hum:GetPropertyChangedSignal("SeatPart"):Connect(function()', -- saiu do veículo: sobe
		}
	do
		assert(string.find(wc, t, 1, true), "WeaponController: " .. t)
	end
	assert(
		not string.find(wc, "task.delay(hold, function()\n\t\tif inv.token ~= my then", 1, true),
		"sem o delay antigo"
	)
	local pc = fs.readFile(C .. "PostureController.client.luau")
	-- a pose baixa sai da pega de agora (uma pega fixa ficou mais alta que a do fuzil no Studio)
	assert(
		string.find(pc, "hold = hold:Lerp(TROCA_DROP * hold * TROCA_TILT, td * (1 - 0.5 * b.prone))", 1, true),
		"3ª pessoa baixa"
	)
	assert(string.find(pc, 'char:GetAttribute(if char == player.Character then "VT65Troca" else "Troca")', 1, true))
	for _, f in
		{ "WeaponVisuals.client.luau", "Ferrolho.luau", "HudCampo.client.luau", "SoldierAnimations.client.luau" }
	do
		assert(string.find(fs.readFile(C .. f), 'Bus.on("reload_cancel"', 1, true), f .. " ouve o cancelamento")
	end
	local kv = fs.readFile(C .. "KnifeView.luau")
	assert(string.find(kv, "return Equipar.trocaDown(tr, now)", 1, true), "a 1ª pessoa usa a mesma curva")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
