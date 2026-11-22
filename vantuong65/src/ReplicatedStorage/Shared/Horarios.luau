--!strict
-- D-224 (dono: "coloque opções de horários do dia no mapa, que será escolhido na escolha de mapa"): a
-- hora da próxima partida é votada junto com o mapa. Módulo puro (Lune e Roblox): a lista, a luz de cada
-- horário e a apuração. Quem aplica é o LightingService; quem mostra, o FimDeRodada.
local Horarios = {}

-- luz: `cor` (RGB) entra no ambiente com a força `mistura`; `brilho` multiplica o Brightness e
-- `exposicao` soma na ExposureCompensation; `tinta` (RGB) e `saturacao` vão num ColorCorrection próprio
-- (medido no Studio: sem ele a noite ficava laranja). À noite o ambiente azulado mantém o campo jogável.
export type Luz = {
	cor: { number },
	mistura: number,
	brilho: number,
	exposicao: number,
	tinta: { number },
	saturacao: number,
	-- D-248: o que faz o fim de tarde das imagens do dono (sem estes campos, valem os do place)
	ambiente: { number }?,
	externo: { number }?,
	contraste: number?,
	atm: Atm?,
	bloom: { i: number, s: number, t: number }?,
	raios: { i: number, s: number }?,
}
export type Atm = {
	densidade: number,
	deslocamento: number,
	haze: number,
	brilho: number,
	cor: { number },
	decai: { number },
}
-- `parado`: o relógio não anda (a partida dura mais que a luz dourada, que acaba em 40 min)
export type Horario = { id: string, nome: string, desc: string, hora: number, parado: boolean?, luz: Luz }

Horarios.LISTA = {
	{
		id = "manha",
		nome = "MANHÃ",
		desc = "Sol baixo e névoa leve",
		hora = 8.5,
		luz = {
			cor = { 255, 255, 255 },
			mistura = 0,
			brilho = 1,
			exposicao = 0,
			tinta = { 255, 255, 255 },
			saturacao = 0,
		},
	},
	{
		id = "meiodia",
		nome = "MEIO-DIA",
		desc = "Sol a pino, sombras curtas",
		hora = 12.2,
		luz = {
			cor = { 255, 255, 255 },
			mistura = 0,
			brilho = 1.05,
			exposicao = -0.05,
			tinta = { 255, 255, 255 },
			saturacao = 0,
		},
	},
	{
		id = "tarde",
		nome = "FIM DE TARDE",
		desc = "Luz dourada, sombras longas",
		hora = 18.5, -- às 17h20 o sol ainda estava alto (medido no Studio); o pôr do sol é perto das 19h10
		parado = true,
		-- D-248 (dono: "quero esse estilo igual das imagens"): sol baixo, céu azul e horizonte quente,
		-- pele e madeira douradas. Valores escolhidos no Studio, olhando o key art.
		luz = {
			cor = { 168, 118, 92 },
			mistura = 0.15,
			brilho = 1.086,
			exposicao = 0.05,
			tinta = { 255, 232, 196 },
			saturacao = 0.18,
			ambiente = { 84, 62, 46 },
			externo = { 150, 116, 92 },
			contraste = 0.05,
			atm = {
				densidade = 0.3,
				deslocamento = 0.2,
				haze = 1.75,
				brilho = 0.3,
				cor = { 255, 198, 142 },
				decai = { 196, 120, 92 },
			},
			bloom = { i = 0.72, s = 34, t = 1.05 },
			raios = { i = 0.16, s = 0.8 },
		},
	},
	{
		id = "noite",
		nome = "NOITE",
		desc = "Luar e visão curta",
		hora = 20.6,
		luz = {
			cor = { 78, 96, 142 },
			mistura = 0.75,
			brilho = 0.7,
			exposicao = 0.62, -- D-241: o contraste novo fechava as sombras; o campo segue jogável de noite
			tinta = { 170, 192, 255 },
			saturacao = -0.28,
		},
	},
} :: { Horario }

Horarios.PADRAO = "tarde" -- D-248: a luz das imagens do dono

function Horarios.por(id: any): Horario?
	for _, h in Horarios.LISTA do
		if h.id == id then
			return h
		end
	end
	return nil
end

-- O horário mais votado e a contagem. Empate: o que vem primeiro na lista; sem voto, o padrão.
function Horarios.apurar(votos: { [any]: string }): (string, { [string]: number })
	local conta: { [string]: number } = {}
	for _, id in votos do
		if Horarios.por(id) then
			conta[id] = (conta[id] or 0) + 1
		end
	end
	local melhor, n = Horarios.PADRAO, 0
	for _, h in Horarios.LISTA do
		local c = conta[h.id] or 0
		if c > n then
			melhor, n = h.id, c
		end
	end
	return melhor, conta
end

return Horarios
