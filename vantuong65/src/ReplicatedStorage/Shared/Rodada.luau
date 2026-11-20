--!strict
-- Fim de partida e partida nova (prompt de jogabilidade, itens 21 e 22; D-193). Módulo PURO (Lune e
-- Roblox): as regras; quem roda é o servidor (Modules/RodadaService) e a tela é do cliente.
-- Ciclo: fim da partida (a tela de fim da ação, FrontHud) -> comemoração (os três melhores do time
-- que venceu) -> votação de mapa (aparece mesmo com um mapa só) -> restauração -> contagem (a do
-- MatchService, D-122) -> partida.
--   - pontuação: a oficial do modo, os pontos de cada ação que a progressão já conta (abate,
--     assistência, captura, socorro...; Progression.REWARDS), somados por partida, sem o teto por
--     minuto da XP. Congelada ao fim;
--   - desempate: pontos, abates, menos mortes, quem entrou antes na partida e o nome;
--   - empate entre os lados: a comemoração mostra o empate e os melhores dos dois lados (sem
--     inventar vencedor);
--   - menos de três elegíveis: só os que houver;
--   - votação: um voto por jogador (pode trocar até o fim); sem voto, o primeiro mapa; empate, o
--     primeiro da lista. Só mapas que existem (MAPAS); nada de opção de mentira;
--   - rodada: um número que sobe a cada partida; tarefa da rodada velha confere e para
--     (Rodada.presa, D-203);
--   - contagem: a hora do início no relógio do servidor (Rodada.contagem, D-203).
local Rodada = {}

Rodada.FASES = { "jogo", "fim", "comemoracao", "votacao", "restauracao" }
Rodada.DUR = { fim = 8, comemoracao = 12, votacao = 15, restauracao = 3 } :: { [string]: number } -- s

-- s do fim da partida até a partida nova (o "próxima partida em" da tela de fim)
function Rodada.total(): number
	local t = 0
	for _, f in Rodada.FASES do
		t += Rodada.DUR[f] or 0
	end
	return t
end
Rodada.PODIO_MAX = 3

-- Mapas que existem (um por enquanto). carta: o prefixo dos atributos das imagens da carta tática
-- (CartaService: prefixo + nw, ne, sw, se).
export type Mapa = { id: string, nome: string, carta: string }
Rodada.MAPAS = {
	{ id = "vantuong", nome = "Vạn Tường", carta = "CartaImage_" },
} :: { Mapa }

export type Linha = {
	id: string, -- UserId em texto
	nome: string,
	lado: string, -- "US" | "VC"
	pontos: number,
	abates: number,
	mortes: number,
	ordem: number, -- quando entrou na partida (menor = antes)
}

-- a < b no pódio?
function Rodada.antes(a: Linha, b: Linha): boolean
	if a.pontos ~= b.pontos then
		return a.pontos > b.pontos
	elseif a.abates ~= b.abates then
		return a.abates > b.abates
	elseif a.mortes ~= b.mortes then
		return a.mortes < b.mortes
	elseif a.ordem ~= b.ordem then
		return a.ordem < b.ordem
	end
	return a.nome < b.nome
end

-- Os até três melhores. vencedor: "US", "VC" ou "draw" (empate: os melhores dos dois lados).
function Rodada.podio(linhas: { Linha }, vencedor: string): { Linha }
	local out: { Linha } = {}
	for _, l in linhas do
		if vencedor == "draw" or l.lado == vencedor then
			table.insert(out, l)
		end
	end
	table.sort(out, Rodada.antes)
	while #out > Rodada.PODIO_MAX do
		table.remove(out)
	end
	return out
end

-- Contagem dos votos: votos[jogador] = id do mapa. Devolve o id escolhido e a contagem por mapa.
-- Voto em mapa que não existe não conta.
function Rodada.apurar(votos: { [any]: string }, mapas: { Mapa }?): (string, { [string]: number })
	local lista = mapas or Rodada.MAPAS
	local conta: { [string]: number } = {}
	for _, m in lista do
		conta[m.id] = 0
	end
	for _, id in votos do
		if conta[id] ~= nil then
			conta[id] += 1
		end
	end
	local melhor, n = lista[1].id, -1
	for _, m in lista do
		if conta[m.id] > n then
			melhor, n = m.id, conta[m.id]
		end
	end
	return melhor, conta
end

function Rodada.mapa(id: string): Mapa?
	for _, m in Rodada.MAPAS do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- A fase seguinte (depois da restauração vem o jogo, com a contagem do MatchService).
function Rodada.proxima(fase: string): string
	local i = table.find(Rodada.FASES, fase)
	if not i then
		return "jogo"
	end
	return Rodada.FASES[i % #Rodada.FASES + 1]
end

-- Tarefa da rodada `minha` ainda vale com a rodada atual `agora`?
function Rodada.vale(minha: number, agora: number): boolean
	return minha == agora
end

-- D-203 (§22): tarefa atrasada presa à partida em que nasceu. `ler` devolve (rodada atual, a partida
-- acabou?). A função devolvida só chama fn se a rodada ainda é a mesma; com paraNoFim, também não
-- depois do fim. Tiro pedido ao comandante, caixote a caminho, fogo que queima: nada disso cai na
-- partida nova (nem, com paraNoFim, na tela do fim).
function Rodada.presa<A...>(ler: () -> (number, boolean), fn: (A...) -> (), paraNoFim: boolean?): (A...) -> ()
	local minha = ler()
	return function(...: A...)
		local agora, acabou = ler()
		if Rodada.vale(minha, agora) and not (paraNoFim and acabou) then
			fn(...)
		end
	end
end

-- D-203 (§22): segundos inteiros que a tela mostra na contagem do começo. inicioEm: a hora em que a
-- partida vale, no relógio do servidor (atributo "VT65InicioEm", GetServerTimeNow); agora: o mesmo
-- relógio no cliente. Todos os clientes contam juntos (o relógio é o do servidor, não a chegada do
-- Match_State), e quem entra no meio lê o atributo. 0 = valendo.
function Rodada.contagem(inicioEm: number?, agora: number): number
	if type(inicioEm) ~= "number" or inicioEm ~= inicioEm then
		return 0
	end
	return math.max(0, math.ceil(inicioEm - agora - 1e-6))
end

return Rodada
