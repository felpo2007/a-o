--!strict
-- D-243 (prompt, seção 11): liga os conjuntos de nascer dos mapas retangulares ao SpawnService. O plano vem do
-- Data/Layout; a regra é do Shared/NascerRet. Conjunto com inimigo perto ou à vista sai da lista de pontos livres e
-- aparece bloqueado com o motivo; o QG é a reserva e vale sempre. Ninguém vivo é movido quando a lista muda.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MapaAtivo = require(ReplicatedStorage.Shared.MapaAtivo)
local MapasRet = require(ReplicatedStorage.Shared.MapasRet) :: any
local NascerRet = require(ReplicatedStorage.Shared.NascerRet)
local Combatants = require(script.Parent.Combatants)

local NascerRetService = {}

local M = MapasRet.M_POR_STUD
local CACHE_S = 1
local ESPERA_ARTE_S = 25 -- a arte fixa e os objetos do mapa chegam depois do terreno

local lista: { NascerRet.Conjunto } = {}
local porLugar: { [string]: NascerRet.Conjunto } = {}
local nomes: { [string]: string } = {}
local turno: { [string]: number } = {}
local cache: { [string]: { t: number, why: string? } } = {}

local function chave(x: number, z: number): string
	return string.format("%.1f;%.1f", x, z)
end

local function chao(x: number, z: number): number
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { workspace.Terrain }
	rp.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -3000, 0), rp)
	return if hit then hit.Position.Y else 60
end

-- Linha livre do peito de quem nasce até o inimigo (paredes e terreno cortam; folha sem colisão, não).
local function vistaDe(c: NascerRet.Conjunto): (ex: number, ez: number) -> boolean
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ignora: { Instance } = {}
	for _, e in Combatants.list() do
		table.insert(ignora, e.model)
	end
	rp.FilterDescendantsInstances = ignora
	rp.RespectCanCollide = true
	rp.IgnoreWater = true
	local origem = Vector3.new(c.x, chao(c.x, c.z) + 1.4 / M, c.z)
	return function(ex: number, ez: number): boolean
		local alvo = Vector3.new(ex, chao(ex, ez) + 1.4 / M, ez)
		return workspace:Raycast(origem, alvo - origem, rp) == nil
	end
end

local function motivo(c: NascerRet.Conjunto, faction: string): string?
	local k = faction .. ":" .. c.id
	local agora = os.clock()
	local q = cache[k]
	if q and agora - q.t < CACHE_S then
		return q.why
	end
	local inimigos: { number } = {}
	for _, e in Combatants.list() do
		local r = Combatants.root(e)
		if e.faction ~= faction and r and Combatants.active(e) then
			table.insert(inimigos, r.Position.X * M)
			table.insert(inimigos, r.Position.Z * M)
		end
	end
	local why = NascerRet.comprometido(c, inimigos, M, vistaDe(c))
	cache[k] = { t = agora, why = why }
	return why
end

local function nomeDe(c: NascerRet.Conjunto): string
	local n = nomes[c.id]
	if n then
		return n
	end
	local p = MapaAtivo.projeto()
	local melhor, nome = math.huge, ""
	for _, st in p.setores do
		local wx, wz = MapaAtivo.mundo(p, st.x, st.y)
		local d = (wx - c.x) ^ 2 + (wz - c.z) ^ 2
		if d < melhor then
			melhor, nome = d, st.nome
		end
	end
	local texto = string.format("Reforço — %s", nome)
	nomes[c.id] = texto
	return texto
end

-- Os conjuntos deste lado agora, já no formato de ponto do SpawnService.
local function pontos(ms: any, comboio: any, faction: string): { any }
	local validos: { NascerRet.Conjunto } = {}
	if ms.mode == "LinhaFrente" then
		local f = ms.frente
		local sp = f and ms.points[f.ativo]
		if sp then
			validos = NascerRet.frente(lista, sp.x, sp.z, faction == "VC", M)
		end
	elseif ms.mode == "Comboio" then
		local s, escolta = comboio.situacao(faction)
		if s then
			validos = NascerRet.comboio(lista, s, escolta)
		end
	end
	local out = {}
	for _, c in validos do
		table.insert(out, {
			id = "conj:" .. c.id,
			name = nomeDe(c),
			x = c.x,
			z = c.z,
			kind = "rally",
			blockM = NascerRet.C.inimigoPertoM,
			vaga = function(): CFrame
				local n = (turno[c.id] or 0) + 1
				turno[c.id] = n
				local x, z, sx, sz = NascerRet.vaga(c, n, M)
				local p = Vector3.new(x, chao(x, z) + 4.5, z)
				return CFrame.lookAt(p, Vector3.new(sx, p.Y, sz))
			end,
		})
	end
	return out
end

-- O gerador não conhece as miudezas postas em tempo de jogo (meda de palha, cerca): com o cenário pronto, cada
-- saída é varrida com o corpo do soldado. Saída bloqueada troca por outra direção livre, longe da outra saída.
local function revalidaSaidas()
	while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
		ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
	end
	task.wait(ESPERA_ARTE_S)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.RespectCanCollide = true
	rp.IgnoreWater = true
	local ignora: { Instance } = { workspace.Terrain }
	local caminhoes = workspace:FindFirstChild("Comboio")
	if caminhoes then
		table.insert(ignora, caminhoes)
	end
	for _, e in Combatants.list() do
		table.insert(ignora, e.model)
	end
	rp.FilterDescendantsInstances = ignora
	local function livre(c: NascerRet.Conjunto, sx: number, sz: number): boolean
		local a = Vector3.new(c.x, chao(c.x, c.z) + 4.2, c.z)
		local b = Vector3.new(sx, chao(sx, sz) + 4.2, sz)
		return workspace:Spherecast(a, 1.6, b - a, rp) == nil
	end
	local trocadas, sem = 0, 0
	for _, c in lista do
		for k = 1, 2 do
			local kx, kz = "sx" .. k, "sz" .. k
			local ox, oz = "sx" .. (3 - k), "sz" .. (3 - k)
			local q = c :: any
			if not livre(c, q[kx], q[kz]) then
				local outra = math.atan2(q[oz] - c.z, q[ox] - c.x)
				local r = math.sqrt((q[kx] - c.x) ^ 2 + (q[kz] - c.z) ^ 2)
				local achou = false
				for i = 0, 23 do
					local a = outra + math.rad(75) + i / 24 * math.rad(210)
					local sx, sz = c.x + math.cos(a) * r, c.z + math.sin(a) * r
					if livre(c, sx, sz) then
						q[kx], q[kz] = sx, sz
						achou = true
						break
					end
				end
				if achou then
					trocadas += 1
				else
					sem += 1
					warn("[VT65] nascer: conjunto " .. c.id .. " ficou sem a saída " .. k)
				end
			end
		end
		task.wait()
	end
	print(string.format("[VT65] nascer: saídas conferidas; %d trocadas, %d sem saída", trocadas, sem))
end

function NascerRetService.conjuntos(): { NascerRet.Conjunto }
	return lista
end

function NascerRetService.iniciar(SpawnService: any, ms: any, comboio: any)
	if not MapaAtivo.retangular() then
		return
	end
	local dados = ServerStorage:WaitForChild("VT65Build"):WaitForChild("Data"):FindFirstChild("Layout")
	local layout: any = if dados then (require :: any)(dados) else nil
	lista = if layout and layout.conjuntos then layout.conjuntos else {}
	for _, c in lista do
		porLugar[chave(c.x, c.z)] = c
	end
	SpawnService.addProvider(function(faction: string): { any }
		return pontos(ms, comboio, faction)
	end)
	SpawnService.addBlocker(function(x: number, z: number, faction: string): string?
		local c = porLugar[chave(x, z)]
		return if c then motivo(c, faction) else nil
	end)
	print(string.format("[VT65] nascer: %d conjuntos no mapa %s", #lista, MapaAtivo.id()))
	task.spawn(revalidaSaidas)
end

return NascerRetService
