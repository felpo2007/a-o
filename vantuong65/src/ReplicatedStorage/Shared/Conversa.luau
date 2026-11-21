--!strict
-- Conversa no campo (pedido do dono, 2026-11-12: "permita falar pelo jogo com quem está perto e com o
-- seu batalhão"). Regras puras, testadas no Lune (tests/luau/comunicacao.luau). O servidor
-- (Modules/Comunicacao) monta os canais de texto e a lista de quem pode ouvir cada voz; o cliente
-- (Controllers/Voz.client) liga o som.
--   Texto: perto (40 m, só em campo), squad, lado (o time inteiro) e o geral do Roblox só fora do campo.
--   Voz: perto (posicional, some aos 40 m) e o rádio do squad (segurar o botão; som de rádio). O
--   inimigo nunca recebe o rádio; perto, ouve a voz, como no real.
-- Distâncias em metros. Todos os números são PLACEHOLDER de design (calibrar em playtest).
local Conversa = {}

Conversa.C = {
	textNearM = 40, -- chat de perto: só quem está a até 40 m de quem escreveu lê
	voiceNearM = 40, -- voz de perto: some aos 40 m (curva NEAR_CURVE_M)
	voiceStreamM = 50, -- o servidor libera o som até 50 m: folga para 0,5 s de corrida entre as contas
	syncS = 0.5, -- membros dos canais e listas da voz: 2 Hz
	radioMaxS = 60, -- rádio aberto direto por mais que isto fecha sozinho (botão preso)
	radioMinGapS = 0.1, -- abrir e fechar mais rápido que isto é ignorado (anti-spam do remote)
	speakRms = 0.02, -- nível RMS (AudioAnalyzer) acima do qual o HUD mostra que a pessoa fala
	speakHoldS = 0.4, -- o ícone fica mais isto depois da última sílaba
	-- som de rádio de campanha: passa-banda (passa-alta + passa-baixa) e distorção leve
	radioLowHz = 350,
	radioHighHz = 3000,
	radioDistortion = 0.25,
	radioVolume = 1.3,
	squelchVolume = 0.45,
}

-- Curva da voz de perto: { metros, volume 0..1 }. O motor interpola em linha reta entre os pontos e
-- mantém o último valor depois do fim (0 a partir de 40 m).
Conversa.NEAR_CURVE_M = {
	{ 0, 1 },
	{ 3, 1 },
	{ 10, 0.55 },
	{ 20, 0.25 },
	{ 30, 0.08 },
	{ 40, 0 },
} :: { { number } }

-- A mesma curva em studs, no formato de AudioEmitter:SetDistanceAttenuation.
function Conversa.attenuationStuds(studM: number): { [number]: number }
	local out: { [number]: number } = {}
	for _, p in Conversa.NEAR_CURVE_M do
		out[p[1] / studM] = p[2]
	end
	return out
end

-- Volume da curva a d metros (interpolação linear, como o motor faz). Para os testes e o HUD.
function Conversa.nearVolume(d: number): number
	local pts = Conversa.NEAR_CURVE_M
	if d <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if d <= b[1] then
			return a[2] + (b[2] - a[2]) * (d - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- Quem é quem para as contas (um por jogador no servidor). x, z em metros.
export type Who = {
	userId: number,
	faction: string?,
	squad: string?,
	inField: boolean, -- com corpo vivo no campo (caído conta)
	downed: boolean,
	x: number,
	z: number,
	radio: boolean, -- segurando o rádio agora (validado)
}

local function dist(a: Who, b: Who): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end
Conversa.dist = dist

-- Chat de perto: os dois em campo e a até textNearM. Quem está no lobby não fala para o campo.
function Conversa.nearText(sender: Who?, recipient: Who?): boolean
	if not (sender and recipient) then
		return false
	end
	return sender.inField and recipient.inField and dist(sender, recipient) <= Conversa.C.textNearM
end

-- Geral do Roblox (RBXGeneral): só entre quem está fora do campo (lobby, escolhas, espera para nascer).
function Conversa.generalText(sender: Who?, recipient: Who?): boolean
	if not (sender and recipient) then
		return false
	end
	return not sender.inField and not recipient.inField
end

export type Members = {
	near: { [number]: boolean }, -- canal de perto: quem está em campo
	squads: { [string]: { [number]: boolean } }, -- por squad (em campo ou não)
	sides: { [string]: { [number]: boolean } }, -- por lado
}

-- Membros que cada canal deve ter agora.
function Conversa.members(all: { Who }): Members
	local out: Members = { near = {}, squads = {}, sides = {} }
	for _, w in all do
		if w.inField then
			out.near[w.userId] = true
		end
		if w.squad then
			out.squads[w.squad] = out.squads[w.squad] or {}
			out.squads[w.squad][w.userId] = true
		end
		if w.faction then
			out.sides[w.faction] = out.sides[w.faction] or {}
			out.sides[w.faction][w.userId] = true
		end
	end
	return out
end

-- Pode abrir o rádio do squad? (nil = pode)
function Conversa.radioCheck(inField: boolean, downed: boolean, squad: string?): string?
	if not inField then
		return "fora de campo"
	elseif downed then
		return "caído"
	elseif not squad then
		return "sem squad"
	end
	return nil
end

-- Quem pode receber o som da voz de `sp` (UserIds em ordem): quem está em campo a até voiceStreamM
-- (de qualquer lado: perto, o inimigo ouve) e, só enquanto sp segura o rádio, o próprio squad
-- (em campo ou esperando para nascer). Fora do campo, ninguém.
function Conversa.voiceAllow(sp: Who, all: { Who }): { number }
	local out: { number } = {}
	if not sp.inField then
		return out
	end
	for _, o in all do
		if o.userId == sp.userId then
			continue
		end
		local near = o.inField and dist(sp, o) <= Conversa.C.voiceStreamM
		local radio = sp.radio
			and sp.squad ~= nil
			and o.squad == sp.squad
			and o.faction ~= nil
			and o.faction == sp.faction
		if near or radio then
			table.insert(out, o.userId)
		end
	end
	table.sort(out)
	return out
end

function Conversa.sameIds(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- Nome do canal de texto do squad ("US:Alfa" -> "VT65Squad_US_Alfa").
function Conversa.squadChannel(sid: string): string
	return "VT65Squad_" .. (string.gsub(sid, "[^%w]", "_"))
end

-- Quem fala (para o ícone do HUD): devolve (falando, instante da última sílaba).
function Conversa.speaking(rms: number, now: number, lastLoudAt: number?): (boolean, number?)
	local C = Conversa.C
	if rms >= C.speakRms then
		return true, now
	end
	if lastLoudAt and now - lastLoudAt <= C.speakHoldS then
		return true, lastLoudAt
	end
	return false, lastLoudAt
end

return Conversa
