--!strict
-- D-193 (prompt de jogabilidade, itens 21 e 22): o ciclo do fim de partida no MESMO servidor. Regras
-- em Shared/Rodada (testadas no Lune); a tela é do cliente (Controllers/FimDeRodada.client).
--   fim da partida (MatchService.afterEnd; o pódio congela aqui)
--   -> fim (Rodada.DUR.fim): a tela de fim da ação de sempre (FrontHud);
--   -> comemoração (Rodada.DUR.comemoracao): o pódio dos três melhores do time que venceu, pelos
--      pontos da partida (MatchService.placar), CONGELADO no atributo "VT65Podio" (JSON; quem sai
--      depois do fim continua nele);
--   -> votação (Rodada.DUR.votacao): os mapas que existem ("VT65Mapas"), um voto por jogador (pode
--      trocar até o fim; remote Rodada_Votar), a contagem em "VT65Votos"; sem voto, o primeiro;
--   -> restauração (Rodada.DUR.restauracao): cada serviço registra a sua (RodadaService.restaurar:
--      corpos, granadas e fumaça, buracos da pá, veículos, jogadores de volta ao QG);
--   -> MatchService.newMatch: a contagem de sempre (D-122) e a partida.
-- Fase e fim de cada fase no relógio do servidor: "VT65Fase" e "VT65FaseAte" (GetServerTimeNow) em
-- ReplicatedStorage; quem entra no meio recebe o estado pelos atributos. Partida nova feita por fora
-- (gancho do Studio) muda MatchService.rodada e a tarefa velha para.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rodada = require(ReplicatedStorage.Shared.Rodada)
local MatchService = require(script.Parent.MatchService)

local RodadaService = {}

-- restauração: (nome, função); cada uma roda protegida e na ordem em que entrou
RodadaService.restaurar = {} :: { { nome: string, fn: () -> () } }
function RodadaService.aoRestaurar(nome: string, fn: () -> ())
	table.insert(RodadaService.restaurar, { nome = nome, fn = fn })
end

local fase = "jogo"
local votos: { [Player]: string } = {}

local function setFase(f: string, dur: number?)
	fase = f
	ReplicatedStorage:SetAttribute("VT65Fase", f)
	ReplicatedStorage:SetAttribute("VT65FaseAte", if dur then workspace:GetServerTimeNow() + dur else nil)
end

local function votosPorId(): { [string]: string }
	local out: { [string]: string } = {}
	for p, id in votos do
		out[tostring(p.UserId)] = id
	end
	return out
end

local function publicarVotos()
	local _, conta = Rodada.apurar(votosPorId())
	ReplicatedStorage:SetAttribute("VT65Votos", HttpService:JSONEncode(conta))
end

function RodadaService.fase(): string
	return fase
end

-- D-202 (§21): a cópia do soldado de cada lugar do pódio, congelada no fim da partida, em
-- ReplicatedStorage.VT65PodioModelos.<UserId>: a cena da comemoração (Controllers/CenaComemoracao)
-- mostra a aparência e o equipamento da partida, mesmo que ele saia depois. Sem personagem agora, a
-- cena usa o manequim do lado.
local function pastaModelos(): Folder
	local f = ReplicatedStorage:FindFirstChild("VT65PodioModelos")
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = "VT65PodioModelos"
		f.Parent = ReplicatedStorage
	end
	return f :: Folder
end

local function congelarModelos(podio: { any })
	local pasta = pastaModelos()
	pasta:ClearAllChildren()
	for _, l in podio do
		local p = Players:GetPlayerByUserId(tonumber(l.id) or 0)
		local c = p and p.Character
		if c and c:FindFirstChild("HumanoidRootPart") then
			local was = c.Archivable
			c.Archivable = true
			local ok, m = pcall(function(): Model
				return c:Clone()
			end)
			c.Archivable = was
			if ok and m then
				for _, d in m:GetDescendants() do
					if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("ProximityPrompt") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
					end
				end
				m.Name = tostring(l.id)
				m.Parent = pasta
			end
		end
	end
end

-- O ciclo depois do fim da partida (MatchService.afterEnd).
function RodadaService.fim(winner: string)
	local minha = MatchService.rodada
	local function vale(): boolean
		return Rodada.vale(minha, MatchService.rodada) and MatchService.ended
	end
	-- o resultado congela agora (quem sair daqui em diante continua no pódio)
	local podio = Rodada.podio(MatchService.linhas() :: any, winner)
	ReplicatedStorage:SetAttribute("VT65Podio", HttpService:JSONEncode({ vencedor = winner, linhas = podio }))
	pcall(congelarModelos, podio)
	-- 0. a tela de fim da ação (FrontHud: vitória, setores, reforços, baixas)
	setFase("fim", Rodada.DUR.fim)
	task.wait(Rodada.DUR.fim)
	if not vale() then
		return
	end
	-- 1. comemoração
	setFase("comemoracao", Rodada.DUR.comemoracao)
	task.wait(Rodada.DUR.comemoracao)
	if not vale() then
		return
	end
	-- 2. votação (aparece com um mapa só)
	table.clear(votos)
	local mapas = {}
	for _, m in Rodada.MAPAS do
		table.insert(mapas, { id = m.id, nome = m.nome, carta = m.carta })
	end
	ReplicatedStorage:SetAttribute("VT65Mapas", HttpService:JSONEncode(mapas))
	publicarVotos()
	setFase("votacao", Rodada.DUR.votacao)
	task.wait(Rodada.DUR.votacao)
	if not vale() then
		return
	end
	local escolhido = Rodada.apurar(votosPorId())
	ReplicatedStorage:SetAttribute("VT65MapaEscolhido", escolhido)
	-- 3. restauração (o mapa é o mesmo: só há um; com mais mapas, a troca entra aqui)
	setFase("restauracao", Rodada.DUR.restauracao)
	for _, r in RodadaService.restaurar do
		local ok, err = pcall(r.fn :: any)
		if not ok then
			warn(string.format("[VT65] restauração %s falhou: %s", r.nome, tostring(err)))
		end
	end
	task.wait(Rodada.DUR.restauracao)
	if not vale() then
		return
	end
	pastaModelos():ClearAllChildren()
	-- 4. a partida nova, com a contagem de sempre
	MatchService.newMatch()
	setFase("jogo", nil)
end

-- O que cada sistema devolve na partida nova (D-193), na ordem: o que está solto no mapa, o terreno,
-- os veículos (tira quem está sentado) e por último os jogadores, de volta ao QG com corpo novo.
-- require aqui dentro: estes módulos dependem do MatchService. Não volta: a grama queimada pelo
-- napalm (ReplaceMaterial), as construções da logística e os tiros já marcados (morteiro, barragem).
local function registrar()
	local S = script.Parent
	local CorposService = require(S:WaitForChild("CorposService")) :: any
	local TrapService = require(S:WaitForChild("TrapService")) :: any
	local FieldWorkService = require(S:WaitForChild("FieldWorkService")) :: any
	local ExplosionService = require(S:WaitForChild("ExplosionService")) :: any
	local VehicleService = require(S:WaitForChild("VehicleService")) :: any
	local SpawnService = require(S:WaitForChild("SpawnService")) :: any
	local function relato(nome: string, n: any)
		print(string.format("[VT65] partida nova: %s %s", nome, tostring(n)))
	end
	RodadaService.aoRestaurar("corpos", function()
		relato("corpos", CorposService.limpar())
	end)
	RodadaService.aoRestaurar("soltos", function()
		local n = 0
		for _, nome in { "Granadas", "Smoke", "DroppedWeapons" } do
			local f = workspace:FindFirstChild(nome)
			if f then
				for _, d in f:GetChildren() do
					d:Destroy()
					n += 1
				end
			end
		end
		for _, d in workspace:GetChildren() do
			if d.Name == "Napalm" then
				d:Destroy()
				n += 1
			end
		end
		relato("granadas, fumaça, armas no chão e napalm", n)
	end)
	RodadaService.aoRestaurar("armadilhas", function()
		relato("armadilhas", TrapService.limpar())
	end)
	RodadaService.aoRestaurar("buracos", function()
		relato("buracos da pá", FieldWorkService.restaurar())
	end)
	RodadaService.aoRestaurar("crateras", function()
		relato("crateras", ExplosionService.restaurar())
	end)
	RodadaService.aoRestaurar("veiculos", function()
		relato("veículos de volta", VehicleService.restaurar())
	end)
	RodadaService.aoRestaurar("jogadores", function()
		relato("jogadores de volta ao QG", SpawnService.restaurar())
	end)
end

function RodadaService.start()
	setFase("jogo", nil)
	MatchService.afterEnd = RodadaService.fim
	MatchService.NEXT_MATCH_S = Rodada.total() -- o "próxima partida em" da tela de fim
	task.spawn(registrar)
	Net.event("Rodada_Votar").OnServerEvent:Connect(function(p: Player, id: any)
		if fase ~= "votacao" or type(id) ~= "string" or not Rodada.mapa(id) then
			return
		end
		votos[p] = id
		publicarVotos()
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		if votos[p] then
			votos[p] = nil
			if fase == "votacao" then
				publicarVotos()
			end
		end
	end)
end

return RodadaService
