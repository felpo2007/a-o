--!strict
-- Morte e corpos (D-107). Módulo PURO (Lune e Roblox): números e regras que o servidor
-- (Modules/CorposService) e os clientes (Controllers/MorteFx) usam. Pedido do dono: "os mortos não
-- somem do mapa e nem ficam deitados também", "faça animação para quando ele morrer".
-- - Queda: o corpo vira boneco de pano no servidor (a física replica para todos), com as juntas do
--   R15 limitadas (JUNTAS); parado, ou em ASSENTAR_MAX_S, congela deitado.
-- - Corpo: fica no chão VIDA_S e some em SUMIR_S; com mais de TETO corpos, o mais velho some antes,
--   em SUMIR_RAPIDO_S (até 100 bots no mapa). Números de jogo, PLACEHOLDER até o playtest.
local Corpos = {}

Corpos.VIDA_S = 25 -- s no chão até começar a sumir
Corpos.SUMIR_S = 2.5 -- s apagando (cada cliente apaga devagar)
Corpos.SUMIR_RAPIDO_S = 1.0 -- s apagando quando o teto manda o mais velho embora
Corpos.TETO = 24 -- corpos no mapa ao mesmo tempo (caindo + no chão)
Corpos.ASSENTAR_MAX_S = 4 -- s de queda no máximo; depois congela onde estiver
Corpos.PARADO_V = 1.2 -- studs/s: abaixo disso a peça conta como parada
Corpos.PARADO_S = 0.6 -- s com todas as peças paradas para congelar antes
Corpos.VOO_MAX = 50 -- studs/s (14 m/s): acima disso a peça é freada (boneco não sai voando)
Corpos.GIRO_MAX = 20 -- rad/s
Corpos.EMPURRAO = 6 -- studs/s no tronco ao morrer em pé (cai para trás, um pouco de lado)
Corpos.ERGUER_MAX = 4 -- studs: o quanto um corpo deitado sobe antes de ganhar colisão
Corpos.EM_PE_Y = 0.75 -- componente vertical do eixo do tronco acima da qual o corpo "está de pé"
Corpos.GRUPO = "VT65Corpo" -- grupo de colisão do boneco (não colide com ele mesmo nem com veículo)

-- As 15 peças do corpo R15 (sem a HumanoidRootPart)
Corpos.PECAS = {
	"LowerTorso",
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

export type Junta = {
	tipo: string, -- "bola" (BallSocket: cone e giro) | "dobra" (Hinge no eixo X da junta)
	eixo: string?, -- bola: "cima" (pescoço, cintura) ou "baixo" (membros), o eixo do cone
	cone: number?, -- graus
	giro: number?, -- graus para cada lado em volta do eixo
	min: number?, -- dobra: graus (no repouso = 0)
	max: number?,
}

-- Juntas do boneco (graus). No R15 os Attachments das juntas não têm rotação (tools/anim/r15.py):
-- X para a direita, Y para cima, o soldado olha para −Z. Dobrar o cotovelo é girar +X (o antebraço
-- vai para a frente); dobrar o joelho é −X (o calcanhar vai para trás), como o agachado do
-- PostureController (joelho −115°, quadril +75°). O cone da bola é medido do repouso (braço e perna
-- caídos, tronco e cabeça em pé). Números do Front 44 (Characters.Ragdoll) abertos para o agachado,
-- o deitado e a pega do fuzil, que precisam caber no cone na hora da morte.
Corpos.JUNTAS = {
	Waist = { tipo = "bola", eixo = "cima", cone = 30, giro = 20 },
	Neck = { tipo = "bola", eixo = "cima", cone = 45, giro = 45 },
	LeftShoulder = { tipo = "bola", eixo = "baixo", cone = 110, giro = 60 },
	RightShoulder = { tipo = "bola", eixo = "baixo", cone = 110, giro = 60 },
	LeftElbow = { tipo = "dobra", min = -3, max = 140 },
	RightElbow = { tipo = "dobra", min = -3, max = 140 },
	LeftWrist = { tipo = "bola", eixo = "baixo", cone = 35, giro = 20 },
	RightWrist = { tipo = "bola", eixo = "baixo", cone = 35, giro = 20 },
	LeftHip = { tipo = "bola", eixo = "baixo", cone = 85, giro = 25 },
	RightHip = { tipo = "bola", eixo = "baixo", cone = 85, giro = 25 },
	LeftKnee = { tipo = "dobra", min = -140, max = 3 },
	RightKnee = { tipo = "dobra", min = -140, max = 3 },
	LeftAnkle = { tipo = "bola", eixo = "baixo", cone = 40, giro = 10 },
	RightAnkle = { tipo = "bola", eixo = "baixo", cone = 40, giro = 10 },
} :: { [string]: Junta }

-- Eixos do Attachment da junta (primário, secundário) no referencial de repouso: o cone da bola fica
-- em volta do osso; a dobra gira no eixo X (de lado).
function Corpos.eixos(j: Junta): ({ number }, { number })
	if j.tipo == "dobra" then
		return { 1, 0, 0 }, { 0, 1, 0 }
	elseif j.eixo == "cima" then
		return { 0, 1, 0 }, { -1, 0, 0 }
	end
	return { 0, -1, 0 }, { 1, 0, 0 }
end

-- Fila de corpos: { nasceu = instante da morte (s), sumindo = já some } do mais velho ao mais novo.
-- Devolve os índices que começam a sumir agora e em quanto tempo: os vencidos (VIDA_S) devagar; e,
-- se ainda passar do TETO (contando os que estão caindo), os mais velhos depressa.
export type Fila = { { nasceu: number, sumindo: boolean } }
function Corpos.paraSumir(fila: Fila, caindo: number, agora: number): { { i: number, s: number } }
	local out: { { i: number, s: number } } = {}
	local vivos = caindo
	for _, c in fila do
		if not c.sumindo then
			vivos += 1
		end
	end
	for i, c in fila do
		if not c.sumindo then
			if agora - c.nasceu >= Corpos.VIDA_S then
				table.insert(out, { i = i, s = Corpos.SUMIR_S })
				vivos -= 1
			elseif vivos > Corpos.TETO then
				table.insert(out, { i = i, s = Corpos.SUMIR_RAPIDO_S })
				vivos -= 1
			end
		end
	end
	return out
end

-- Quanto do corpo já sumiu (0 = inteiro, 1 = apagado), pelo relógio do servidor.
function Corpos.apagado(agora: number, inicio: number?, dur: number?): number
	if type(inicio) ~= "number" then
		return 0
	end
	local d = if type(dur) == "number" and dur > 0 then dur else Corpos.SUMIR_S
	return math.clamp((agora - inicio) / d, 0, 1)
end

-- Um passo do assentar: segundos parado (a maior velocidade das peças abaixo de PARADO_V) e se
-- congela agora (parado PARADO_S ou queda de ASSENTAR_MAX_S).
function Corpos.assentar(parado: number, maxV: number, dt: number, idade: number): (number, boolean)
	local p = if maxV < Corpos.PARADO_V then parado + dt else 0
	return p, p >= Corpos.PARADO_S or idade >= Corpos.ASSENTAR_MAX_S
end

-- Quanto erguer (studs) um corpo para nenhuma peça ficar enterrada: lista de { fundo da peça, chão
-- embaixo dela }. Folga de 0,1 stud, no máximo ERGUER_MAX.
function Corpos.erguer(pecas: { { number } }): number
	local need = 0
	for _, p in pecas do
		need = math.max(need, p[2] - p[1])
	end
	return if need > 0 then math.min(need + 0.1, Corpos.ERGUER_MAX) else 0
end

return Corpos
