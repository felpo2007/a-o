--!strict
-- HUD de infantaria (D-210; prompt de interface §13). Puro, testado no Lune
-- (tests/luau/hud_infantaria.luau). Quem desenha é o Controllers/HudInfantaria (vida, direção do dano,
-- abates, XP e esquadrão) e o HudCampo (cartão da arma).
--   - vida com o valor real (Humanoid, que o MedicalService mantém) e os estados do corpo
--     (Medical_State: sangrando, hemorragia, braço e perna feridos);
--   - direção do dano: o ângulo do tiro que acertou em relação para onde a câmera olha (vermelho, em
--     volta da mira; o objetivo continua em latão na bússola);
--   - abates (Combat_Feed, só os creditados a jogadores) e XP discretos no alto à direita, com limite;
--   - o esquadrão (Squad_State) na lateral esquerda: quem está em campo, caído ou fora.
local HudInfantaria = {}

HudInfantaria.FEED_MAX = 4 -- linhas de abate na tela
HudInfantaria.FEED_S = 6 -- s de cada linha
HudInfantaria.XP_S = 3 -- s da linha de XP (ganhos com o mesmo rótulo somam enquanto ela está aberta)
HudInfantaria.DANO_S = 1.6 -- s do arco de dano
HudInfantaria.DANO_MAX = 4 -- arcos ao mesmo tempo
HudInfantaria.SQUAD_MAX = 8 -- linhas do esquadrão

export type Nivel = "bem" | "ferido" | "grave"

-- Vida: fração (0 a 1), o número inteiro e o nível da cor (bem > 60%, ferido > 30%, grave)
function HudInfantaria.vida(health: number?, max: number?): (number, string, Nivel)
	local m = if type(max) == "number" and max > 0 then max else 100
	local h = math.clamp(if type(health) == "number" then health else 0, 0, m)
	local f = h / m
	local nivel: Nivel = if f > 0.6 then "bem" elseif f > 0.3 then "ferido" else "grave"
	-- 0,4 não vira 0: quem está vivo nunca vê "0"
	local n = if h > 0 then math.max(1, math.floor(h + 0.5)) else 0
	return f, tostring(n), nivel
end

export type Estado = { texto: string, grave: boolean }

-- Estados do corpo (o Medical_State do servidor), do mais grave para o mais leve
function HudInfantaria.estados(med: any): { Estado }
	local out: { Estado } = {}
	if type(med) ~= "table" then
		return out
	end
	if med.arterial == true then
		table.insert(out, { texto = "HEMORRAGIA", grave = true })
	elseif type(med.bleed) == "number" and med.bleed > 0 then
		table.insert(out, { texto = "SANGRANDO", grave = false })
	end
	if med.leg == true then
		table.insert(out, { texto = "PERNA FERIDA", grave = false })
	end
	if med.arm == true then
		table.insert(out, { texto = "BRAÇO FERIDO", grave = false })
	end
	return out
end

-- Ângulo do tiro em graus: 0 = à frente, positivo à direita (o Rotation do Roblox é horário),
-- ±180 = atrás. look: para onde a câmera olha (x, z); d: da câmera até a origem do tiro (x, z).
function HudInfantaria.anguloDano(lookX: number, lookZ: number, dx: number, dz: number): number
	local frente = dx * lookX + dz * lookZ
	local direita = dx * -lookZ + dz * lookX
	if math.abs(frente) < 1e-9 and math.abs(direita) < 1e-9 then
		return 0
	end
	return math.deg(math.atan2(direita, frente))
end

-- Põe o item na frente da lista e corta no máximo (o mais novo em cima)
function HudInfantaria.empilha<T>(lista: { T }, item: T, max: number)
	table.insert(lista, 1, item)
	while #lista > max do
		table.remove(lista)
	end
end

-- Linha de abate (Combat_Feed): quem, a arma, quem caiu; `meu` acende a linha do próprio jogador
export type Abate = { quem: string, caiu: string, arma: string, ladoQuem: string?, ladoCaiu: string?, meu: boolean }
function HudInfantaria.abate(ev: any, meuId: number, arma: (id: string?, lado: string?) -> string): Abate?
	if type(ev) ~= "table" or type(ev.k) ~= "string" or type(ev.v) ~= "string" then
		return nil
	end
	local kf = if type(ev.kf) == "string" then ev.kf else nil
	return {
		quem = ev.k,
		caiu = ev.v,
		arma = arma(if type(ev.w) == "string" then ev.w else nil, kf),
		ladoQuem = kf,
		ladoCaiu = if type(ev.vf) == "string" then ev.vf else nil,
		meu = ev.ku == meuId or ev.vu == meuId,
	}
end

export type Linha = { id: number, nome: string, papel: string?, lider: boolean, estado: string }

-- O esquadrão do jogador (Squad_State) em linhas: o líder primeiro, depois a ordem de entrada; sem
-- o próprio jogador. info(userId) -> (nome ou nil se saiu do servidor, "campo" | "caido" | "fora").
-- Os papéis chegam com a chave em número ou em texto (o remote troca a chave numérica esparsa).
function HudInfantaria.esquadrao(st: any, sid: any, eu: number, info: (number) -> (string?, string)): { Linha }
	local out: { Linha } = {}
	if type(st) ~= "table" or type(st.squads) ~= "table" or type(sid) ~= "string" then
		return out
	end
	for _, s in st.squads do
		if type(s) == "table" and s.id == sid and type(s.members) == "table" then
			local roles = if type(s.roles) == "table" then s.roles else {}
			for _, uid in s.members do
				local id = tonumber(uid)
				if id and id ~= eu then
					local nome, estado = info(id)
					if nome then
						local r = roles[id] or roles[tostring(id)]
						table.insert(out, {
							id = id,
							nome = nome,
							papel = if type(r) == "string" then r else nil,
							lider = s.leader == id,
							estado = estado,
						})
					end
				end
			end
			break
		end
	end
	-- o líder primeiro, o resto na ordem de entrada (o table.sort não guarda a ordem dos iguais)
	local ord: { Linha } = {}
	for _, l in out do
		if l.lider then
			table.insert(ord, l)
		end
	end
	for _, l in out do
		if not l.lider and #ord < HudInfantaria.SQUAD_MAX then
			table.insert(ord, l)
		end
	end
	return ord
end

-- O que fazer no objetivo do time (§13: "capturar, defender e contestar conforme o modo"): em disputa,
-- contestar; senão capturar (ataque) ou defender. role: "attack" | "defend" (Front.objective).
function HudInfantaria.verbo(role: string?, disputa: boolean): string
	if disputa then
		return "contestar"
	end
	return if role == "attack" then "capturar" else "defender"
end

-- Ponto da tela perto da mira (centro)? frac: o raio em fração da altura da tela
function HudInfantaria.pertoDoCentro(x: number, y: number, w: number, h: number, frac: number): boolean
	local r = h * frac
	return (x - w / 2) ^ 2 + (y - h / 2) ^ 2 <= r * r
end

return HudInfantaria
