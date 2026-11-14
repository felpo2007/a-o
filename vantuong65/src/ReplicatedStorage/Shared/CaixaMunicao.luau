--!strict
-- Caixa de munição do Suporte (D-108; pedido do dono, 2026-11-13: "coloque o suporte que possui uma
-- caixa de munição que ele pode colocar no chão e ao passar perto você pega munição e 1 granada",
-- "faça a caixa de munições bonita e que seja possível ver onde ele coloca no chão").
-- Módulo PURO (tests/luau/classes.luau). Servidor: Modules/CaixaMunicaoService (posta, estoque,
-- entrega, bots). Cliente: Controllers/CaixaMunicao.client (prévia verde/vermelha, ícone do time,
-- botão PÔR CAIXA no toque) e a carta (CartaView.drawCaixas).
-- Regras:
--   - só o Suporte põe; uma caixa por suporte (pôr outra tira a anterior); depois de pôr, a próxima
--     só depois de RECARGA_S;
--   - no chão firme, perto (até POR_MAX_M do soldado), sem água, sem rampa forte e com espaço livre;
--   - quem é do mesmo lado e passa a ALCANCE_M pega, sem tecla: os carregadores da arma até o cheio
--     da dotação (Weapons.magsFor) e 1 granada (até as do nascimento); o antitanque, 1 foguete;
--   - cada pessoa pega de novo só depois de INTERVALO_S (não fica parado em cima);
--   - ESTOQUE pegadas; some vazia ou depois de DURACAO_S;
--   - quem pôs ganha "Reabastecimento" (Progression.REWARDS.resupply) quando outro pega.
-- Números de jogo, PLACEHOLDER até o playtest.
local CaixaMunicao = {}

CaixaMunicao.ALCANCE_M = 3 -- passa a até 3 m do centro da caixa
CaixaMunicao.ALTURA_M = 2 -- e a até 2 m de altura (não pega do andar de cima nem do túnel)
CaixaMunicao.INTERVALO_S = 20 -- por pessoa
CaixaMunicao.ESTOQUE = 8 -- pegadas por caixa
CaixaMunicao.DURACAO_S = 240 -- some depois de 4 min
CaixaMunicao.RECARGA_S = 30 -- o suporte põe outra depois de 30 s
CaixaMunicao.POR_MAX_M = 4 -- até 4 m do soldado
CaixaMunicao.INCLINACAO_MAX = 35 -- graus
CaixaMunicao.GRANADAS = 1 -- por pegada
CaixaMunicao.FOGUETES_MAX = 3 -- antitanque: o mesmo 3 do nascimento (VehicleService, "Rockets")
-- medidas do modelo do Blender (assets/blender/caixa_municao_*/metricas.json): largura, altura e
-- fundo (m); pegada no chão (studs, x e z) e o ponto do ícone acima da base (studs). A frente é −Z.
CaixaMunicao.TAMANHO_M = {
	US = { 0.75, 0.54, 0.45 },
	VC = { 0.71, 0.43, 0.46 },
} :: { [string]: { number } }
CaixaMunicao.PEGADA_STUDS = {
	US = { 2.5, 1.58 },
	VC = { 2.35, 1.94 },
} :: { [string]: { number } }
CaixaMunicao.ICONE_STUDS = {
	US = { 0, 2.772, -0.19 },
	VC = { 0, 2.851, -0.203 },
} :: { [string]: { number } }

-- largura, altura e fundo da caixa do lado (m)
function CaixaMunicao.size(faction: string?): (number, number, number)
	local t = CaixaMunicao.TAMANHO_M[faction or "US"] or CaixaMunicao.TAMANHO_M.US
	return t[1], t[2], t[3]
end
-- bots (BotService): sem munição, vão à caixa do lado a até BOT_BUSCA_M; o bot suporte põe a caixa
-- quando o squad chega ao lugar e a dele está a mais de BOT_LONGE_M
CaixaMunicao.BOT_BUSCA_M = 80
CaixaMunicao.BOT_LONGE_M = 60
CaixaMunicao.BOT_CATAR_S = 30 -- bot sem munição e sem caixa perto acha 1 carregador (dos caídos)

export type Box = {
	id: string,
	owner: string, -- "p:<UserId>" ou "b:<id do bot>"
	faction: string,
	x: number,
	y: number,
	z: number, -- studs (centro da base)
	stock: number,
	untilT: number, -- os.clock em que some
	taken: { [string]: number }, -- quem pegou -> quando
}

function CaixaMunicao.new(id: string, owner: string, faction: string, x: number, y: number, z: number, now: number): Box
	return {
		id = id,
		owner = owner,
		faction = faction,
		x = x,
		y = y,
		z = z,
		stock = CaixaMunicao.ESTOQUE,
		untilT = now + CaixaMunicao.DURACAO_S,
		taken = {},
	}
end

-- ===== pôr =====
export type PlaceIn = {
	role: string?,
	alive: boolean,
	seated: boolean,
	distM: number, -- do soldado até o lugar
	dyM: number, -- desnível do lugar em relação aos pés
	slopeDeg: number,
	water: boolean,
	blocked: boolean, -- algo sólido no volume da caixa
	ground: boolean, -- achou chão
	sinceLastS: number, -- desde a última caixa deste suporte
}

-- Pode pôr aqui? (true) ou (false, motivo em texto de tela)
function CaixaMunicao.canPlace(i: PlaceIn): (boolean, string?)
	if i.role ~= "support" then
		return false, "só o Suporte põe a caixa"
	end
	if not i.alive or i.seated then
		return false, "agora não"
	end
	if i.sinceLastS < CaixaMunicao.RECARGA_S then
		return false, string.format("caixa nova em %d s", math.ceil(CaixaMunicao.RECARGA_S - i.sinceLastS))
	end
	if not i.ground then
		return false, "sem chão aqui"
	end
	if i.distM > CaixaMunicao.POR_MAX_M + 0.5 or math.abs(i.dyM) > 2.5 then
		return false, "longe demais"
	end
	if i.water then
		return false, "na água não"
	end
	if i.slopeDeg > CaixaMunicao.INCLINACAO_MAX then
		return false, "chão inclinado demais"
	end
	if i.blocked then
		return false, "sem espaço"
	end
	return true, nil
end

-- Inclinação (graus) pela normal do chão
function CaixaMunicao.slope(nx: number, ny: number, nz: number): number
	local len = math.sqrt(nx * nx + ny * ny + nz * nz)
	if len < 1e-6 then
		return 90
	end
	return math.deg(math.acos(math.clamp(ny / len, -1, 1)))
end

-- Caixa que sai quando este dono põe outra (uma por suporte): o id da anterior, ou nil
function CaixaMunicao.replaced(boxes: { Box }, owner: string): Box?
	for _, b in boxes do
		if b.owner == owner then
			return b
		end
	end
	return nil
end

-- ===== pegar =====
-- Está ao alcance? (distâncias em metros: horizontal e vertical)
function CaixaMunicao.inReach(flatM: number, dyM: number): boolean
	return flatM <= CaixaMunicao.ALCANCE_M and math.abs(dyM) <= CaixaMunicao.ALTURA_M
end

export type Need = {
	spare: number, -- reserva da arma principal agora
	spareFull: number, -- reserva cheia da dotação
	frags: number,
	fragsMax: number,
	rockets: number?, -- antitanque
	others: boolean?, -- outra arma do equipamento (pistola) abaixo da dotação
}

-- Precisa de alguma coisa? (cheio de tudo não gasta a caixa)
function CaixaMunicao.needs(n: Need): boolean
	if n.spare < n.spareFull or n.frags < n.fragsMax or n.others == true then
		return true
	end
	return n.rockets ~= nil and n.rockets < CaixaMunicao.FOGUETES_MAX
end

-- Pode pegar agora? (mesmo lado, vivo, ao alcance, intervalo, estoque, precisa)
function CaixaMunicao.canTake(
	b: Box,
	who: string,
	faction: string?,
	alive: boolean,
	reach: boolean,
	needs: boolean,
	now: number
): boolean
	if faction ~= b.faction or not alive or not reach or not needs then
		return false
	end
	if b.stock <= 0 or now >= b.untilT then
		return false
	end
	local last = b.taken[who]
	return last == nil or now - last >= CaixaMunicao.INTERVALO_S
end

-- Registra a pegada: gasta 1 do estoque. Devolve o estoque que sobrou.
function CaixaMunicao.take(b: Box, who: string, now: number): number
	b.stock = math.max(b.stock - 1, 0)
	b.taken[who] = now
	return b.stock
end

-- Granadas depois da pegada (até as do nascimento)
function CaixaMunicao.grenadesAfter(frags: number, fragsMax: number): number
	if frags >= fragsMax then
		return frags
	end
	return math.min(frags + CaixaMunicao.GRANADAS, fragsMax)
end

function CaixaMunicao.rocketsAfter(rockets: number): number
	return math.min(rockets + 1, math.max(rockets, CaixaMunicao.FOGUETES_MAX))
end

-- A caixa acabou? (vazia ou passou do tempo)
function CaixaMunicao.gone(b: Box, now: number): boolean
	return b.stock <= 0 or now >= b.untilT
end

-- Quem pôs ganha XP? (outro soldado do mesmo lado, jogador)
function CaixaMunicao.rewards(owner: string, who: string): boolean
	return owner ~= who and string.sub(owner, 1, 2) == "p:"
end

-- Reserva cheia da dotação: carregadores de sobra; na arma de depósito tubular (espingarda), em
-- cartuchos soltos (cargas de sobra x capacidade). mags = carregadores por vida (Weapons.magsFor).
function CaixaMunicao.spareFull(mags: number, magazine: number, tube: boolean): number
	local extra = math.max(math.floor(mags) - 1, 0)
	return if tube then extra * magazine else extra
end

-- ===== bots =====
-- O bot precisa ir à caixa? (sem carregador de sobra e com o da arma abaixo da metade)
function CaixaMunicao.botWants(spare: number, mag: number, magazine: number): boolean
	return spare <= 0 and mag < magazine * 0.5
end

-- Caixa do lado mais perto (studs; maxM em metros), ou nil
function CaixaMunicao.nearest(
	boxes: { Box },
	faction: string,
	x: number,
	z: number,
	maxM: number,
	studM: number,
	now: number
): Box?
	local best: Box? = nil
	local bestD = maxM / studM
	for _, b in boxes do
		if b.faction == faction and not CaixaMunicao.gone(b, now) then
			local d = math.sqrt((b.x - x) ^ 2 + (b.z - z) ^ 2)
			if d <= bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

return CaixaMunicao
