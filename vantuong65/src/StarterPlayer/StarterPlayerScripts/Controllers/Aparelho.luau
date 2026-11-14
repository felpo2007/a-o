--!strict
-- Decisões puras por aparelho (Parte 13, T3), testadas no Lune (tests/luau/toque_veiculo.luau).
-- Sem `game` nem `script`:
--   - perfil de gráficos do celular e a economia de bateria (o Graficos.client aplica);
--   - vibração no celular (o Haptics toca com HapticEffect);
--   - rede móvel: sinal fraco e quando tentar voltar para a mesma partida (o Reconexao.client).
local Aparelho = {}

-- ===== gráficos =====
-- O que NUNCA muda por aparelho nem pela economia de bateria (paridade de combate): a mata, o capim
-- e o arroz que escondem (o dossel do arrozal continua no detalhe mínimo), a Atmosphere (névoa e
-- alcance de visão), a grama animada do terreno, os soldados (modelo e distância), a fumaça de
-- granada e de explosão, o clarão do tiro e o traçante, e a correção de cor (contraste) na escolha do
-- jogador, igual à do PC. O perfil só mexe nas chaves abaixo (o teste confere).
Aparelho.PROFILE_KEYS = {
	shadows = true, -- sombra do sol (Lighting.GlobalShadows)
	plantShadows = true, -- sombra das copas (CastShadow das plantas marcadas)
	bloom = true,
	sunRays = true,
	colorCorrection = true,
	detail = true, -- atributo local GfxDetail (poeira, folhas, fumaça do horizonte, faixas, arroz de perto)
	hapticFire = true, -- pulso do disparo no celular
} :: { [string]: boolean }

Aparelho.DETAIL = { high = 1, medium = 0.6, low = 0.3 } :: { [string]: number }
Aparelho.MOBILE_DETAIL_MAX = 0.6 -- celular: no máximo o médio
Aparelho.DETAIL_MIN = 0.3 -- economia de bateria: o baixo (o menor que as telas conhecem)

export type Hardware = { touch: boolean, keyboard: boolean, mouse: boolean, tenFoot: boolean }

-- celular ou tablet: toque sem teclado nem mouse e fora da TV (um tablet com teclado é PC)
function Aparelho.isMobile(h: Hardware): boolean
	return h.touch and not h.keyboard and not h.mouse and not h.tenFoot
end

export type GfxIn = {
	gfxShadows: boolean,
	gfxPlantShadows: boolean,
	gfxPost: string, -- "full" | "light" | "off"
	gfxDetail: string, -- "high" | "medium" | "low"
	batterySaver: boolean,
}
export type Profile = {
	shadows: boolean,
	plantShadows: boolean,
	bloom: boolean,
	sunRays: boolean,
	colorCorrection: boolean,
	detail: number,
	hapticFire: boolean,
}

-- Escolhas do jogador → o que vale neste aparelho. O celular nunca SOBE nada que o jogador
-- desligou; só desce o que pesa na GPU de celular e não muda o combate.
function Aparelho.profile(s: GfxIn, mobile: boolean): Profile
	local detail = Aparelho.DETAIL[s.gfxDetail] or 1
	local post = s.gfxPost
	local p: Profile = {
		shadows = s.gfxShadows == true,
		plantShadows = s.gfxPlantShadows == true,
		bloom = post == "full",
		sunRays = post ~= "off",
		colorCorrection = post ~= "off", -- igual em todo aparelho: é contraste, não enfeite
		detail = detail,
		hapticFire = true,
	}
	if mobile then
		-- celular: sem a sombra das copas (cada copa redesenhada em cada faixa da sombra), sem brilho
		-- e sem raios de sol (passes de tela cheia) e detalhe no máximo médio
		p.plantShadows = false
		p.bloom = false
		p.sunRays = false
		p.detail = math.min(detail, Aparelho.MOBILE_DETAIL_MAX)
	end
	if s.batterySaver then
		-- escolha do jogador (nunca padrão), vale em qualquer aparelho: o mínimo de tudo que é enfeite.
		-- A sombra do sol sai também (o PC tem a mesma opção nos gráficos: não é vantagem do celular).
		p.shadows = false
		p.plantShadows = false
		p.bloom = false
		p.sunRays = false
		p.detail = Aparelho.DETAIL_MIN
		p.hapticFire = false
	end
	return p
end

-- ===== vibração no celular (HapticEffect) =====
-- Celular: só pulsos (disparo leve, ser atingido forte, explosão forte e caindo com a distância).
-- Nada contínuo (motor, rotor, batimento): gasta bateria e o motor de vibração do celular não faz
-- "ronco". No controle continua tudo como antes (Haptics, motores).
Aparelho.HAPTIC_LEVEL = { off = 0, low = 0.45, normal = 1 } :: { [string]: number }
Aparelho.HAPTIC_MIN = 0.1 -- abaixo disso alguns celulares não vibram (documentação do HapticEffect)
Aparelho.HAPTIC_FLOOR = 0.12 -- piso de quem está ligado (o "baixo" ainda se sente)
Aparelho.HAPTIC_GAP = { fire = 0.1, hit = 0.15, explosion = 0.3 } :: { [string]: number }
Aparelho.EXPLOSION_RANGE_M = 120

export type Pulse = { amp: number, ms: number, preset: string }

-- kind: "fire" (x = coice em graus), "hit" (x ignorado), "explosion" (x = distância em m).
-- level: hapticFire (disparo) ou hapticDamage (atingido, explosão). nil = não vibra.
function Aparelho.pulse(kind: string, level: string, x: number, battery: boolean): Pulse?
	local lv = Aparelho.HAPTIC_LEVEL[level] or 1
	if lv <= 0 then
		return nil
	end
	local amp, ms, preset
	if kind == "fire" then
		if battery then
			return nil -- economia de bateria: o disparo não vibra (atingido e explosão continuam)
		end
		amp = math.clamp(x / 1.6, 0.15, 1) * 0.35 * lv
		ms = 35
		preset = "UIClick"
	elseif kind == "hit" then
		amp = 0.85 * lv
		ms = 120
		preset = "GameplayCollision"
	elseif kind == "explosion" then
		local k = math.clamp(1 - x / Aparelho.EXPLOSION_RANGE_M, 0, 1) ^ 1.5
		if k * lv < 0.04 then
			return nil -- longe demais para sentir
		end
		amp = k * lv
		ms = math.floor(150 + 250 * k)
		preset = "GameplayExplosion"
	else
		return nil
	end
	return { amp = math.clamp(math.max(amp, Aparelho.HAPTIC_FLOOR), 0, 1), ms = ms, preset = preset }
end

-- Intervalo mínimo por tipo (fogo automático a 550 tiros/min não vira um zumbido contínuo).
-- Devolve true e marca a hora se pode vibrar agora.
function Aparelho.gate(last: { [string]: number }, kind: string, now: number): boolean
	local gap = Aparelho.HAPTIC_GAP[kind] or 0.1
	local t = last[kind]
	if t and now - t < gap then
		return false
	end
	last[kind] = now
	return true
end

-- vibração contínua (motor do veículo, rotor, batimento) só no controle
function Aparelho.continuousHaptics(device: string): boolean
	return device == "gamepad"
end

-- ===== rede móvel =====
-- Sinal fraco: quase nada chegando do servidor por 2 s, ou latência alta por 3 s. Volta ao normal
-- com 1 s bom. É só aviso: quem segura a ligação é o Roblox.
Aparelho.NET_RECV_MIN = 0.05 -- kB/s (Stats.DataReceiveKbps): partida de 50 x 50 nunca fica abaixo
Aparelho.NET_PING_MAX = 0.45 -- s (Player:GetNetworkPing)
Aparelho.NET_WEAK_RECV_S = 2
Aparelho.NET_WEAK_PING_S = 3
Aparelho.NET_OK_S = 1

export type Net = { quietT: number, slowT: number, goodT: number, weak: boolean }

function Aparelho.newNet(): Net
	return { quietT = 0, slowT = 0, goodT = 0, weak = false }
end

-- recv/ping nil = não deu para ler (conta como bom: nunca acusa sem medida)
function Aparelho.netStep(st: Net, dt: number, recvKbps: number?, pingS: number?): boolean
	local quiet = recvKbps ~= nil and recvKbps < Aparelho.NET_RECV_MIN
	local slow = pingS ~= nil and pingS > Aparelho.NET_PING_MAX
	st.quietT = if quiet then st.quietT + dt else 0
	st.slowT = if slow then st.slowT + dt else 0
	if st.quietT >= Aparelho.NET_WEAK_RECV_S or st.slowT >= Aparelho.NET_WEAK_PING_S then
		st.weak = true
		st.goodT = 0
	elseif st.weak then
		st.goodT = if quiet or slow then 0 else st.goodT + dt
		if st.goodT >= Aparelho.NET_OK_S then
			st.weak = false
		end
	end
	return st.weak
end

-- Erros do Roblox (Enum.ConnectionError) que são queda de rede: só nesses o jogo tenta voltar
-- sozinho. Expulsão, ociosidade, manutenção, servidor fechado e duplicado nunca.
Aparelho.REJOIN_NAMES = {
	DisconnectConnectionLost = true, -- 277
	DisconnectTimeout = true, -- 266
	DisconnectRaknetErrors = true, -- 279
	DisconnectReceivePacketError = true, -- 260
	DisconnectReceivePacketStreamError = true, -- 261
	DisconnectSendPacketError = true, -- 262
} :: { [string]: boolean }
Aparelho.REJOIN_VALUES = { [277] = true, [266] = true, [279] = true, [260] = true, [261] = true, [262] = true } :: {
	[number]: boolean,
}

function Aparelho.shouldRejoin(name: string?, value: number?): boolean
	if name ~= nil and Aparelho.REJOIN_NAMES[name] then
		return true
	end
	return value ~= nil and Aparelho.REJOIN_VALUES[value] == true
end

-- Plano das tentativas: espera (s) antes de cada uma e se vai para o mesmo servidor (JobId) ou para
-- qualquer um. A troca Wi-Fi ↔ dados leva alguns segundos; voltar rápido demais falha.
Aparelho.REJOIN_PLAN = {
	{ wait = 3, same = true },
	{ wait = 8, same = true },
	{ wait = 15, same = false },
}

function Aparelho.rejoinStep(attempt: number): (number?, boolean)
	local p = Aparelho.REJOIN_PLAN[attempt]
	if not p then
		return nil, false
	end
	return p.wait, p.same
end

return Aparelho
