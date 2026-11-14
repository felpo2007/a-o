--!strict
-- Testes da Parte 13 (T3): veículos no toque, perfil de celular, economia de bateria, vibração e
-- rede móvel. Uso, a partir de vantuong65/:  lune run tests/luau/toque_veiculo.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
local PilotoToque = require("../../" .. C .. "PilotoToque")
local Aparelho = require("../../" .. C .. "Aparelho")
local InputMap = require("../../src/ReplicatedStorage/Shared/InputMap") :: any

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
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f", msg or "", a, b))
end

-- ===== coletivo =====
test("alavanca: pega onde o coletivo está (sem salto) e o curso inteiro vale o coletivo inteiro", function()
	local L = PilotoToque.newLever()
	PilotoToque.grab(L, 300, 0.42)
	assert(PilotoToque.command(L) == 0.42, "pegar não muda o coletivo")
	PilotoToque.drag(L, 300 - 100, 200) -- metade do curso para cima
	near(PilotoToque.command(L) :: number, 0.92, 1e-9, "meio curso = +0,5")
	PilotoToque.drag(L, 300 + 1000, 200)
	assert(PilotoToque.command(L) == 0, "não passa de 0")
	PilotoToque.drag(L, 300 - 1000, 200)
	assert(PilotoToque.command(L) == 1, "não passa de 1")
	PilotoToque.release(L)
	assert(PilotoToque.command(L) == nil, "solta: sem comando")
	PilotoToque.follow(L, 0.61)
	assert(L.value == 0.61, "solta, a alavanca mostra o coletivo real")
	PilotoToque.grab(L, 50, 0.61)
	PilotoToque.follow(L, 0.2)
	assert(L.value == 0.61, "segura, o estabilizador não mexe na mão do piloto")
end)

test("coletivo: a alavanca dá a posição; gatilho e tecla somam 0,35 por segundo", function()
	assert(PilotoToque.collectiveInput(0.3, 0, 0.8, 1 / 60) == 0.8)
	assert(PilotoToque.collectiveInput(0.3, 1, 0.1, 1 / 60) == 0.1, "a alavanca vence")
	near(PilotoToque.collectiveInput(0.5, 1, nil, 1), 0.85, 1e-9)
	near(PilotoToque.collectiveInput(0.5, -1, nil, 0.5), 0.325, 1e-9)
	assert(PilotoToque.collectiveInput(0.99, 1, nil, 1) == 1 and PilotoToque.collectiveInput(0.01, -1, nil, 1) == 0)
end)

test("coletivo: a conta nova é a mesma de antes no controle e no teclado", function()
	-- a fórmula antiga do VehicleController (antes da Parte 13), copiada aqui
	local function old(
		c: number,
		up: number,
		assist: boolean,
		pAvail: number,
		pReq: number,
		onGround: boolean,
		dt: number
	)
		c = math.clamp(c + up * 0.35 * dt, 0, 1)
		if assist and up == 0 and pAvail > 0 then
			local hover = pReq / pAvail
			if onGround then
				c = math.min(c, math.max(hover - 0.05, 0))
			else
				c += (hover - c) * math.min(1, dt * 0.8)
			end
		end
		return c
	end
	local seed = 7
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	for _ = 1, 2000 do
		local c = rnd()
		local up = ({ -1, 0, 0, 1, 0.4 })[1 + math.floor(rnd() * 5)]
		local assist = rnd() > 0.3
		local pAvail = if rnd() > 0.1 then 1000 + rnd() * 500 else 0
		local pReq = 600 + rnd() * 900
		local onGround = rnd() > 0.5
		local dt = 1 / (30 + rnd() * 90)
		local new = PilotoToque.collectiveInput(c, up, nil, dt)
		new =
			PilotoToque.collectiveAssist(new, up ~= 0, assist, if pAvail > 0 then pReq / pAvail else nil, onGround, dt)
		near(new, old(c, up, assist, pAvail, pReq, onGround, dt), 1e-12, "mesma conta")
	end
end)

-- ===== estabilização =====
test("estabilizador: no ar leva ao pairado; no chão nunca tira do chão sozinho", function()
	local c = 0.9
	for _ = 1, 180 do -- 3 s a 60 Hz
		c = PilotoToque.collectiveAssist(c, false, true, 0.6, false, 1 / 60)
	end
	near(c, 0.6, 0.05, "pairado em ~3 s")
	local g = 0.9
	for _ = 1, 600 do
		g = PilotoToque.collectiveAssist(g, false, true, 0.6, true, 1 / 60)
		assert(g <= 0.55 + 1e-9, "no chão fica abaixo do pairado")
	end
	assert(PilotoToque.collectiveAssist(0.2, false, true, 0.6, true, 1 / 60) == 0.2, "no chão não sobe")
end)

test("estabilizador: assistência, não piloto automático (o comando do piloto vence)", function()
	assert(PilotoToque.collectiveAssist(0.8, true, true, 0.6, false, 1) == 0.8, "polegar na alavanca")
	assert(PilotoToque.collectiveAssist(0.8, false, false, 0.6, false, 1) == 0.8, "desligado: fica")
	assert(PilotoToque.collectiveAssist(0.8, false, true, nil, false, 1) == 0.8, "sem medida de pairado: fica")
	-- toque: ligado ao assumir os comandos; controle e teclado guardam a escolha da sessão
	assert(PilotoToque.assistOnEnter(false, true) == true)
	assert(PilotoToque.assistOnEnter(true, true) == true)
	assert(PilotoToque.assistOnEnter(false, false) == false)
	assert(PilotoToque.assistOnEnter(true, false) == true)
	assert(PilotoToque.newLever().assist == true, "a tela começa mostrando ligado")
end)

-- ===== pedais =====
test("pedais: direito +1, esquerdo −1, os dois juntos se anulam, nenhum zero", function()
	assert(PilotoToque.pedal(false, true) == 1)
	assert(PilotoToque.pedal(true, false) == -1)
	assert(PilotoToque.pedal(true, true) == 0)
	assert(PilotoToque.pedal(false, false) == 0)
end)

test("pedais e botões: o toque só aperta ações que existem no InputMap, no contexto certo", function()
	local src = fs.readFile(C .. "ToqueVeiculo.client.luau")
	local ctxOf: { [string]: { [string]: boolean } } = {}
	for _, a in InputMap.ACTIONS do
		ctxOf[a.id] = ctxOf[a.id] or {}
		ctxOf[a.id][a.ctx] = true
	end
	local used = 0
	for id in string.gmatch(src, '"([vh]_[%a_]+)"') do
		used += 1
		local c = ctxOf[id]
		assert(c and (c.ground_vehicle or c.helicopter), id .. " não é ação de veículo no InputMap")
	end
	assert(used >= 5, "ações do toque: " .. used)
	-- v39: pedais, estabilizador, coaxial, binóculo e marca saíram da tela (automáticos ou só no
	-- controle e no teclado); continuam no InputMap
	for _, id in { "h_pedal_left", "h_pedal_right", "h_stabilize", "v_coax", "v_binoculars", "v_mark" } do
		assert(ctxOf[id], id .. " sumiu do InputMap")
		assert(not string.find(src, '"' .. id .. '"', 1, true), id .. " ainda tem botão na tela")
	end
	-- o VehicleController usa as contas testadas aqui (e não uma cópia)
	local vc = fs.readFile(C .. "VehicleController.client.luau")
	for _, f in
		{
			"PilotoToque.collectiveInput(",
			"PilotoToque.collectiveAssist(",
			"PilotoToque.pedal(",
			"PilotoToque.drive(",
			"PilotoToque.touchYaw(",
		}
	do
		assert(string.find(vc, f, 1, true), "VehicleController sem " .. f)
	end
	assert(not string.find(vc, "up * 0.35 * dt", 1, true), "sobrou a conta antiga do coletivo")
	-- o tiro do canhão e a recarga automática usam as contas daqui
	for _, f in { "PilotoToque.aimOnHold(", "PilotoToque.autoReload(", "PilotoToque.AIM_HOLD_S" } do
		assert(string.find(src, f, 1, true), "ToqueVeiculo sem " .. f)
	end
end)

-- ===== automáticos do toque (v39) =====
test("toque: devagar o analógico de lado vira o nariz; rápido, inclina; nunca os dois inteiros", function()
	local p, c = PilotoToque.touchYaw(1, 0)
	assert(p == 1 and c == 0, "pairando: pedal inteiro")
	p, c = PilotoToque.touchYaw(-0.5, PilotoToque.YAW_FULL_MS)
	assert(p == -0.5 and c == 0, "até 3 m/s: só pedal")
	p, c = PilotoToque.touchYaw(1, 30)
	assert(p == 0 and c == 1, "rápido: só cíclico (a curva coordenada vira o nariz)")
	p, c = PilotoToque.touchYaw(0.8, (PilotoToque.YAW_FULL_MS + PilotoToque.YAW_NONE_MS) / 2)
	near(p, 0.4, 1e-9, "meio do caminho")
	near(c, 0.4, 1e-9, "meio do caminho")
	for _, v in { 0, 2, 5, 7.5, 12 } do
		local a, b = PilotoToque.touchYaw(1.4, v)
		near(a + b, 1, 1e-9, "a soma é o analógico (limitado a 1)")
	end
	assert(PilotoToque.touchYaw(0, 0) == 0)
end)

test("toque: canhão mira segurando e dispara soltando; metralhadora atira no aperto", function()
	assert(PilotoToque.aimOnHold("gun_90") and PilotoToque.aimOnHold("rr_106"))
	assert(not PilotoToque.aimOnHold("m60") and not PilotoToque.aimOnHold(nil))
	assert(PilotoToque.AIM_HOLD_S > 0.1 and PilotoToque.AIM_HOLD_S < 0.3, "toque rápido não liga a ótica")
end)

test("toque: tubos do Ontos recarregam sozinhos só parado, sem repetir o pedido", function()
	assert(PilotoToque.autoReload(3, 6, 0, false, 10), "faltou tubo, parado")
	assert(not PilotoToque.autoReload(6, 6, 0, false, 10), "cheio")
	assert(not PilotoToque.autoReload(0, 6, 2, false, 10), "andando (regra do servidor: até 0,5 m/s)")
	assert(not PilotoToque.autoReload(0, 6, 0, true, 10), "já recarregando")
	assert(not PilotoToque.autoReload(0, 6, 0, false, 1), "pedido recente")
	assert(not PilotoToque.autoReload(nil, 6, 0, false, 10), "sem tubos (não é o Ontos)")
end)

-- ===== motorista =====
test("motorista: frente acelera, trás freia/ré, de lado só esterça, reto não puxa o volante", function()
	local t, s = PilotoToque.drive(0, 1, false)
	assert(t == 1 and s == 0)
	t, s = PilotoToque.drive(0, -1, false)
	assert(t == -1 and s == 0, "trás: freio e ré (como o LT)")
	t, s = PilotoToque.drive(1, 0.1, false)
	assert(t == 0 and s == 1, "quase de lado: gira a lagarta sem arrancar")
	t, s = PilotoToque.drive(-0.05, 0.9, true)
	assert(s == 0 and t == 0.9, "quase reto: sem volante")
	t, s = PilotoToque.drive(0.6, 0.6, false)
	assert(t > 0.5 and s > 0.4, "diagonal: os dois")
	local _, sTrack = PilotoToque.drive(0.4, 0.5, false)
	local _, sWheel = PilotoToque.drive(0.4, 0.5, true)
	assert(sTrack < sWheel and sTrack > 0, "lagarta mais fina no centro que o carro (curva do controle)")
	t, s = PilotoToque.drive(0, 0, false)
	assert(t == 0 and s == 0)
end)

-- ===== disposição dos botões =====
local SCREENS = {
	{ 730, 302, "Android 360 dp" },
	{ 667, 317, "iPhone SE" },
	{ 750, 311, "iPhone 14" },
	{ 932, 330, "iPhone Pro Max" },
	{ 1024, 710, "iPad" },
	{ 1180, 762, "iPad Air" },
}
local ROLES = { "driver", "gunner", "commander", "door", "pilot", "passenger" }
local FULL = { fire = true, mirror = false }

test("botões: cabem na tela, não se encostam e ficam fora da metade do analógico", function()
	for _, sc in SCREENS do
		local W, H = sc[1], sc[2]
		local function px(mm: number): number
			return PilotoToque.mmToPx(mm, math.min(W, H))
		end
		for _, role in ROLES do
			for _, mirror in { false, true } do
				local o = table.clone(FULL)
				o.mirror = mirror
				local r = PilotoToque.layout(role, W, H, o, px)
				local list = {}
				for name, rect in r do
					table.insert(list, { name = name, r = rect })
					local tag = string.format("%s %s %s%s", sc[3], role, name, if mirror then " espelhado" else "")
					assert(
						rect.x >= 0 and rect.y >= 0 and rect.x + rect.w <= W and rect.y + rect.h <= H,
						tag .. " fora da tela"
					)
					if mirror then
						assert(rect.x + rect.w <= W / 2, tag .. " na metade do analógico")
					else
						assert(rect.x >= W / 2, tag .. " na metade do analógico")
					end
				end
				for i = 1, #list do
					for j = i + 1, #list do
						assert(
							not PilotoToque.overlap(list[i].r, list[j].r),
							string.format("%s %s: %s encosta em %s", sc[3], role, list[i].name, list[j].name)
						)
					end
				end
			end
		end
	end
end)

test("botões: tamanho físico (mínimo 9 mm, tiro 16 mm) nos celulares e tablets da lista", function()
	for _, sc in SCREENS do
		local W, H = sc[1], sc[2]
		local short = math.min(W, H)
		local function px(mm: number): number
			return PilotoToque.mmToPx(mm, short)
		end
		local mmOf = function(p: number): number
			return p / PilotoToque.dpiGuess(short) * 25.4
		end
		for _, role in ROLES do
			local r = PilotoToque.layout(role, W, H, FULL, px)
			for name, rect in r do
				if name ~= "leverLabel" then
					local mm = mmOf(math.min(rect.w, rect.h))
					assert(mm >= 8.9, string.format("%s %s %s: %.1f mm", sc[3], role, name, mm))
				end
			end
			if r.fire then
				assert(mmOf(r.fire.w) >= 15.9, string.format("%s tiro: %.1f mm", sc[3], mmOf(r.fire.w)))
			end
			if r.lever then
				assert(mmOf(r.lever.h) >= 22, string.format("%s alavanca: %.1f mm de curso", sc[3], mmOf(r.lever.h)))
			end
		end
	end
	-- o que cada lugar mostra
	local px = function(mm: number): number
		return PilotoToque.mmToPx(mm, 311)
	end
	-- v39: só o essencial (dono: "deixe somente os importantes; o resto automático")
	local function names(r: { [string]: any }): string
		local l = {}
		for k in r do
			table.insert(l, k)
		end
		table.sort(l)
		return table.concat(l, ",")
	end
	local g = PilotoToque.layout("gunner", 750, 311, FULL, px)
	assert(names(g) == "exit,fire,seat", "atirador: " .. names(g))
	local p = PilotoToque.layout("pilot", 750, 311, FULL, px)
	assert(names(p) == "exit,lever,leverLabel,seat", "piloto: " .. names(p))
	local d = PilotoToque.layout("door", 750, 311, FULL, px)
	assert(names(d) == "exit,fire,seat", "porta: " .. names(d))
	local c = PilotoToque.layout("commander", 750, 311, FULL, px)
	assert(names(c) == "exit,seat", "comandante: " .. names(c))
	local m = PilotoToque.layout("driver", 750, 311, FULL, px)
	assert(names(m) == "exit,seat", "motorista: o analógico dirige; " .. names(m))
	local u = PilotoToque.layout("gunner", 750, 311, { fire = false, mirror = false }, px)
	assert(names(u) == "exit,seat", "lugar sem arma: " .. names(u))
end)

test("botões: a fileira de lugar/sair fica à esquerda do rádio do HUD de toque (T1)", function()
	local ok, Toque = pcall(function(): any
		return require("../../src/ReplicatedStorage/Shared/Toque")
	end)
	assert(ok and type(Toque) == "table", "Shared/Toque (T1) não carregou: " .. tostring(Toque))
	local T = Toque :: any
	local MM = PilotoToque.MM
	for _, sc in SCREENS do
		local W, H = sc[1], sc[2]
		local short = math.min(W, H)
		local function px(mm: number): number
			return PilotoToque.mmToPx(mm, short)
		end
		-- o mesmo cálculo do ToqueVeiculo.client (radioRect) no layout padrão do T1
		local slot = T.layout({ touchLayout = "two", touchMirror = false, touchCustom = nil }, false).radio
		local size = T.buttonPx(T.BY_ID.radio.mm, slot.scale, short, nil)
		local cx, cy = T.place(slot.x, slot.y, size, W, H)
		local radio = { x = cx - size / 2, y = cy - size / 2, w = size, h = size }
		local reserve = PilotoToque.topReserve(radio, W, px(MM.margin + MM.min + MM.gap), px(MM.gap))
		assert(reserve > 0, sc[3] .. ": o rádio do T1 não está no alto à direita (mudou o layout?)")
		for _, role in ROLES do
			local o = table.clone(FULL)
			o.avoid = radio
			local r = PilotoToque.layout(role, W, H, o, px)
			for name, rect in r do
				assert(
					not PilotoToque.overlap(rect, radio),
					string.format("%s %s: %s encosta no rádio", sc[3], role, name)
				)
				assert(rect.x >= W / 2, string.format("%s %s: %s na metade do analógico", sc[3], role, name))
				assert(rect.y + rect.h <= H, string.format("%s %s: %s fora da tela", sc[3], role, name))
			end
			if r.lever then
				local mm = r.lever.h / PilotoToque.dpiGuess(short) * 25.4
				assert(mm >= MM.leverMin, string.format("%s: alavanca com %.1f mm de curso", sc[3], mm))
			end
			local list = {}
			for _, rect in r do
				table.insert(list, rect)
			end
			for i = 1, #list do
				for j = i + 1, #list do
					assert(not PilotoToque.overlap(list[i], list[j]), sc[3] .. " " .. role .. ": botões se encostam")
				end
			end
		end
		-- e o px do T1 sem limites é o mesmo palpite da reserva daqui
		near(T.rawPx(9, short, nil), PilotoToque.mmToPx(9, short), 0.5, "rawPx do T1")
	end
	assert(PilotoToque.topReserve(nil, 800, 100, 10) == 0)
	assert(PilotoToque.topReserve({ x = 700, y = 300, w = 60, h = 60 }, 800, 100, 10) == 0, "fora da faixa de cima")
end)

test("tamanho físico: conversão mm → px da interface (ponto de celular e de tablet)", function()
	near(PilotoToque.mmToPx(25.4, 390), 160, 0.5, "1 polegada no celular")
	near(PilotoToque.mmToPx(25.4, 768), 132, 0.5, "1 polegada no tablet")
	assert(PilotoToque.mmToPx(9, 390) >= 56, "44 pt")
end)

-- ===== perfil de celular e economia de bateria =====
local function allInputs(): { Aparelho.GfxIn }
	local out = {}
	for _, sh in { true, false } do
		for _, ps in { true, false } do
			for _, post in { "full", "light", "off" } do
				for _, det in { "high", "medium", "low" } do
					for _, bat in { false, true } do
						table.insert(out, {
							gfxShadows = sh,
							gfxPlantShadows = ps,
							gfxPost = post,
							gfxDetail = det,
							batterySaver = bat,
						})
					end
				end
			end
		end
	end
	return out
end

test("perfil: o que importa no combate nunca muda (contraste igual ao do PC, só chaves de enfeite)", function()
	for _, s in allInputs() do
		for _, mobile in { false, true } do
			local p = Aparelho.profile(s, mobile)
			for k in p :: any do
				assert(Aparelho.PROFILE_KEYS[k], "chave nova no perfil: " .. tostring(k))
			end
			for _, k in { "vegetation", "atmosphere", "decoration", "characters", "smoke", "tracers", "fov" } do
				assert((p :: any)[k] == nil, "o perfil mexe em " .. k)
			end
			assert(p.colorCorrection == (s.gfxPost ~= "off"), "correção de cor na escolha do jogador")
			assert(p.detail >= Aparelho.DETAIL_MIN, "detalhe abaixo do mínimo (o dossel do arroz some)")
		end
	end
end)

test("perfil de celular: só desce o que pesa; nunca liga o que o jogador desligou", function()
	for _, s in allInputs() do
		local pc, cel = Aparelho.profile(s, false), Aparelho.profile(s, true)
		for _, k in { "shadows", "plantShadows", "bloom", "sunRays", "colorCorrection", "hapticFire" } do
			assert(not ((cel :: any)[k] and not (pc :: any)[k]), "celular ligou " .. k)
		end
		assert(cel.detail <= pc.detail and cel.detail <= Aparelho.MOBILE_DETAIL_MAX)
		assert(cel.plantShadows == false and cel.bloom == false and cel.sunRays == false)
		if not s.batterySaver then
			assert(cel.shadows == s.gfxShadows, "sombra do sol: escolha do jogador")
		end
	end
	-- do aparelho: toque sem teclado nem mouse e fora da TV
	assert(Aparelho.isMobile({ touch = true, keyboard = false, mouse = false, tenFoot = false }))
	assert(
		not Aparelho.isMobile({ touch = true, keyboard = true, mouse = false, tenFoot = false }),
		"tablet com teclado"
	)
	assert(not Aparelho.isMobile({ touch = false, keyboard = true, mouse = true, tenFoot = false }), "PC")
	assert(not Aparelho.isMobile({ touch = true, keyboard = false, mouse = false, tenFoot = true }), "TV")
end)

test("economia de bateria: escolha do jogador, nunca padrão; o mínimo de enfeite", function()
	assert(InputMap.DEFAULTS.batterySaver ~= true, "economia de bateria ligada por padrão")
	if InputMap.DEFAULTS.batterySaver ~= nil then
		assert(InputMap.validate({ batterySaver = true }).batterySaver == true, "o validate guarda a escolha")
		assert(InputMap.validate({ batterySaver = "sim" }).batterySaver == false, "lixo volta ao padrão")
	end
	for _, s in allInputs() do
		if s.batterySaver then
			for _, mobile in { false, true } do
				local p = Aparelho.profile(s, mobile)
				assert(not p.shadows and not p.plantShadows and not p.bloom and not p.sunRays)
				assert(p.detail == Aparelho.DETAIL_MIN and p.hapticFire == false)
			end
		end
	end
	local plain = Aparelho.profile({
		gfxShadows = true,
		gfxPlantShadows = false,
		gfxPost = "light",
		gfxDetail = "high",
		batterySaver = false,
	}, false)
	assert(plain.shadows and plain.sunRays and plain.detail == 1 and plain.hapticFire, "PC sem economia: como antes")
end)

-- ===== vibração =====
test("vibração: disparo leve, atingido forte, explosão forte perto e nada longe", function()
	local fire = Aparelho.pulse("fire", "normal", 1.6, false) :: Aparelho.Pulse
	local hit = Aparelho.pulse("hit", "normal", 0, false) :: Aparelho.Pulse
	local boom = Aparelho.pulse("explosion", "normal", 5, false) :: Aparelho.Pulse
	local far = Aparelho.pulse("explosion", "normal", 80, false) :: Aparelho.Pulse
	assert(fire and hit and boom and far)
	assert(fire.amp < hit.amp and hit.amp <= boom.amp, "disparo < atingido <= explosão perto")
	assert(far.amp < boom.amp and far.ms < boom.ms, "a explosão cai com a distância")
	assert(Aparelho.pulse("explosion", "normal", 130, false) == nil, "longe demais")
	assert(fire.ms < hit.ms, "o disparo é um toque curto")
	for _, p in { fire, hit, boom, far } do
		assert(p.amp >= Aparelho.HAPTIC_MIN and p.amp <= 1, "abaixo de 0,1 alguns celulares não vibram")
	end
	assert(fire.preset == "UIClick" and hit.preset == "GameplayCollision" and boom.preset == "GameplayExplosion")
end)

test("vibração: opções do jogador (desligada, baixa) e economia de bateria", function()
	for _, k in { "fire", "hit", "explosion" } do
		assert(Aparelho.pulse(k, "off", 1, false) == nil, k .. " desligado")
	end
	local low = Aparelho.pulse("hit", "low", 0, false) :: Aparelho.Pulse
	local normal = Aparelho.pulse("hit", "normal", 0, false) :: Aparelho.Pulse
	assert(low.amp < normal.amp, "baixa < normal")
	assert(Aparelho.pulse("fire", "low", 0.3, false) ~= nil, "baixa ainda se sente (piso)")
	assert(Aparelho.pulse("fire", "normal", 1, true) == nil, "bateria: o disparo não vibra")
	assert(Aparelho.pulse("hit", "normal", 0, true) ~= nil, "bateria: atingido continua")
	assert(Aparelho.pulse("explosion", "normal", 10, true) ~= nil, "bateria: explosão continua")
	assert(Aparelho.continuousHaptics("touch") == false, "nada contínuo no celular")
	assert(Aparelho.continuousHaptics("gamepad") == true, "controle como antes")
end)

test("vibração: intervalo mínimo por tipo (fogo automático não vira zumbido)", function()
	local last = {}
	assert(Aparelho.gate(last, "fire", 10))
	assert(not Aparelho.gate(last, "fire", 10.05), "550 tiros/min: um sim, outro não")
	assert(Aparelho.gate(last, "hit", 10.05), "tipos separados")
	assert(Aparelho.gate(last, "fire", 10.11))
	local n = 0
	for i = 0, 99 do -- 1 s de fogo a 100 apertos/s
		if Aparelho.gate(last, "fire", 20 + i / 100) then
			n += 1
		end
	end
	assert(n <= 10, "no máximo 10 pulsos de disparo por segundo: " .. n)
end)

-- ===== rede móvel =====
test("rede: sinal fraco só com medida (2 s sem dados ou 3 s de latência alta); volta com 1 s bom", function()
	local st = Aparelho.newNet()
	for _ = 1, 3 do
		assert(not Aparelho.netStep(st, 0.5, 0, nil))
	end
	assert(Aparelho.netStep(st, 0.5, 0, nil), "2 s sem dados")
	assert(Aparelho.netStep(st, 0.5, 30, 0.08), "um bom ainda não limpa")
	assert(not Aparelho.netStep(st, 0.5, 30, 0.08), "1 s bom limpa")
	local p = Aparelho.newNet()
	for _ = 1, 5 do
		assert(not Aparelho.netStep(p, 0.5, 30, 0.6))
	end
	assert(Aparelho.netStep(p, 0.5, 30, 0.6), "3 s de latência alta")
	local n = Aparelho.newNet()
	for _ = 1, 20 do
		assert(not Aparelho.netStep(n, 0.5, nil, nil), "sem medida nunca acusa")
	end
end)

test("rede: só volta sozinho em queda de rede (nunca expulsão, ociosidade ou manutenção)", function()
	for _, v in { 277, 266, 279, 260, 261, 262 } do
		assert(Aparelho.shouldRejoin(nil, v), tostring(v))
	end
	for _, v in { 0, 264, 267, 268, 273, 274, 275, 278, 286, 287, 292 } do
		assert(not Aparelho.shouldRejoin(nil, v), tostring(v))
	end
	assert(Aparelho.shouldRejoin("DisconnectConnectionLost", nil))
	assert(not Aparelho.shouldRejoin("DisconnectLuaKick", 267))
	assert(not Aparelho.shouldRejoin(nil, nil))
	-- plano: primeiro a mesma partida, depois qualquer uma; termina
	local w1, same1 = Aparelho.rejoinStep(1)
	local _, same3 = Aparelho.rejoinStep(#Aparelho.REJOIN_PLAN)
	assert(w1 and w1 >= 2 and same1 and not same3)
	assert(Aparelho.rejoinStep(#Aparelho.REJOIN_PLAN + 1) == nil, "para de tentar")
end)

-- ===== telas novas: texto inteiro para a tradução =====
test("telas do T3: nenhum texto montado aos pedaços com '..'", function()
	local bad = {}
	for _, f in
		{
			C .. "ToqueVeiculo.client.luau",
			C .. "Reconexao.client.luau",
			C .. "VehicleHudView.luau",
			C .. "Graficos.client.luau",
			C .. "VehicleController.client.luau",
		}
	do
		for n, l in string.split(fs.readFile(f), "\n") do
			local code = string.gsub(l, "%-%-.*$", "")
			if string.find(code, "print(", 1, true) then
				continue -- leitura do Output no Studio, não é tela
			end
			if
				string.find(code, '"[^"]*[%a\128-\255][^"]* "%s*%.%.')
				or string.find(code, '%.%.%s*" [^"]*[%a\128-\255][^"]*"')
			then
				table.insert(bad, string.format("%s:%d", f, n))
			end
		end
	end
	assert(#bad == 0, table.concat(bad, ", "))
	-- estilo novo: nada de papel datilografado nas telas do T3
	for _, f in { C .. "ToqueVeiculo.client.luau", C .. "Reconexao.client.luau" } do
		local src = fs.readFile(f)
		for _, w in { "SpecialElite", "TYPE_OLD", "TYPE_FONT", "UiKit.CARD", "UiKit.INK" } do
			assert(not string.find(src, w, 1, true), f .. " usa " .. w)
		end
		assert(string.find(src, "UiKit.V", 1, true), f .. " sem os tokens do estilo")
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
