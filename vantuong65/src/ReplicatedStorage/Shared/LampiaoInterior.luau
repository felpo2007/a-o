--!strict
-- D-241 (dono: "traga essa questão epica para dentro das casas"): o lampião aceso de cada casa. Módulo
-- puro (Lune e Roblox): onde ele fica e como a chama respira. Quem monta é o Modules/InteriorLuz;
-- quem anima e põe a poeira na luz é o Controllers/InteriorVivo.
local LampiaoInterior = {}

LampiaoInterior.TAG = "VT65Lampiao"
-- O globo é Neon, que multiplica a cor: com tom claro ele estourava em amarelo-esverdeado (Studio)
LampiaoInterior.COR_GLOBO = { 214, 96, 26 }
-- A luz de dia é suave: com 1,0 e laranja forte, a telha vermelha do teto parecia acesa
LampiaoInterior.COR = { 255, 196, 140 }
LampiaoInterior.BRILHO = 0.7
LampiaoInterior.ALCANCE = 26 -- studs: enche um cômodo sem vazar para a rua
LampiaoInterior.CABECA = 9.4 -- studs acima do piso: passa do capacete do soldado (8,1 medidos)
LampiaoInterior.FOLGA_TETO = 1.6
LampiaoInterior.PE_DIREITO_MIN = 11 -- abaixo disso não é um cômodo
LampiaoInterior.LADO_LIVRE = 2.5 -- studs livres em volta do globo (não nasce dentro de parede)

-- A chama muda com a hora: a correção de cor da noite puxa tudo para o azul, e o lampião com a cor do
-- dia saía cinza (visto no Studio). À noite ele fica mais laranja e mais forte.
LampiaoInterior.HORA = {
	tarde = { cor = { 255, 170, 110 }, brilho = 0.9 },
	noite = { cor = { 255, 140, 70 }, brilho = 1.6 },
} :: { [string]: { cor: { number }, brilho: number } }

function LampiaoInterior.daHora(id: any): ({ number }, number)
	local h = if type(id) == "string" then LampiaoInterior.HORA[id] else nil
	if h then
		return h.cor, h.brilho
	end
	return LampiaoInterior.COR, LampiaoInterior.BRILHO
end

-- Altura do globo acima do piso, para um pé-direito `teto`. nil: não cabe.
function LampiaoInterior.alturaGlobo(teto: number): number?
	if teto < LampiaoInterior.PE_DIREITO_MIN then
		return nil
	end
	return math.clamp(teto * 0.7, LampiaoInterior.CABECA, teto - LampiaoInterior.FOLGA_TETO)
end

-- Pontos a tentar em volta do centro da casa, do mais perto ao mais longe: { dx, dz } em studs.
function LampiaoInterior.candidatos(passo: number, aneis: number): { { number } }
	local out: { { number } } = { { 0, 0 } }
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
	for r = 1, aneis do
		for _, d in dirs do
			table.insert(out, { d[1] * r * passo, d[2] * r * passo })
		end
	end
	return out
end

-- A chama respira: fator do brilho em 0,86 a 1,06, sem repetir igual entre lampiões (`semente`).
function LampiaoInterior.chama(t: number, semente: number): number
	local a = math.sin(t * 2.3 + semente)
	local b = math.sin(t * 5.7 + semente * 1.7)
	local c = math.sin(t * 11.1 + semente * 2.9)
	return 0.96 + 0.05 * a + 0.03 * b + 0.02 * c
end

return LampiaoInterior
