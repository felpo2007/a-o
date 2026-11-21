--!strict
-- Toca os kits de som (D-204; Shared/SomKits, gerado por tools/sons_armas.py): só o trecho pedido do
-- arquivo do kit (PlaybackRegion), 2D ou 3D num ponto do mundo, com atraso, tom e equalização, no
-- grupo de mixagem certo ("tiros": a arma, a cauda, a explosão; "efeitos": o resto). Usado pelo
-- AudioController, pelo Acerto e pelo Ferrolho.
-- Vagas (caudas): no máximo N tocando por vaga; a que entra apaga a mais velha em 80 ms (Tween no
-- volume), sem corte seco. A última de uma rajada toca até o fim.
-- Os arquivos são conferidos uma vez no começo (como Sound: com o id em texto o PreloadAsync pede
-- imagem e falha, D-142); kit que não carregar fica mudo e avisa uma vez.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local SomGravacoes = require(ReplicatedStorage.Shared.SomGravacoes)
local SomKits = require(ReplicatedStorage.Shared.SomKits)

local Som = {}

local failed: { [string]: boolean } = {}
-- D-220: gravação que não carregou: o trecho do kit toca no lugar dela
local gravacaoFalhou: { [number]: boolean } = {}
task.spawn(function()
	local sounds: { Sound } = {}
	local byId: { [string]: string } = {}
	for kit in SomKits do
		local id = AssetIds.Sounds[kit]
		if type(id) == "number" and id ~= 0 then
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. id
			table.insert(sounds, s)
			byId[tostring(id)] = kit
		else
			failed[kit] = true
		end
	end
	local gravacoes: { [string]: number } = {}
	for _, id in SomGravacoes.ids() do
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. id
		table.insert(sounds, s)
		gravacoes[tostring(id)] = id
	end
	pcall(function()
		ContentProvider:PreloadAsync(sounds, function(content: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success then
				local chave = string.match(content, "(%d+)$") or ""
				local g = gravacoes[chave]
				if g and not gravacaoFalhou[g] then
					gravacaoFalhou[g] = true
					warn(string.format("[VT65 SOM] gravação sem carregar: %d; fica o som do kit", g))
				end
				local kit = byId[chave]
				if kit and not failed[kit] then
					failed[kit] = true
					warn("[VT65 SOM] kit sem carregar: " .. kit)
				end
			end
		end)
	end)
	for _, s in sounds do
		s:Destroy()
	end
end)

local function group(nome: string): SoundGroup?
	local fx = SoundService:FindFirstChild("VT65Efeitos")
	if not fx then
		return nil
	end
	local g = if nome == "tiros" then fx:FindFirstChild("VT65Tiros") else fx
	return if g and g:IsA("SoundGroup") then g else (if fx:IsA("SoundGroup") then fx else nil)
end

export type Opts = {
	pos: Vector3?, -- 3D nesse ponto; sem: 2D
	vol: number?,
	pitch: number?, -- multiplica o tom (só ajuste fino: a variação vem dos trechos)
	delay: number?, -- s
	minDist: number?, -- studs (3D)
	maxDist: number?, -- studs (3D)
	low: number?, -- dB (equalizador)
	mid: number?,
	high: number?,
	grupo: string?, -- "tiros" | "efeitos" (padrão)
	vaga: string?, -- nome da vaga (caudas)
	vagas: number?, -- quantas tocam juntas na vaga
}

local vagas: { [string]: { Sound } } = {}

local function apaga(s: Sound)
	if not s.Parent then
		return
	end
	TweenService:Create(s, TweenInfo.new(0.08, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
	task.delay(0.1, function()
		s:Stop()
	end)
end

local function go(kit: string, trecho: string, o: Opts)
	local k = SomKits[kit]
	local seg = k and k.seg[trecho]
	local idKit = AssetIds.Sounds[kit]
	-- D-220: a gravação real, quando há; se ela não carregou, o trecho do kit
	local g = SomGravacoes.de(kit, trecho)
	if g and gravacaoFalhou[g.id] then
		g = nil
	end
	local inicio: number, dur: number, id: number
	if g then
		inicio, dur, id = g.ini, g.dur, g.id
	elseif seg and not failed[kit] and type(idKit) == "number" and idKit ~= 0 then
		inicio, dur, id = seg[1], seg[2], idKit
	else
		return
	end
	local s = Instance.new("Sound")
	s.Name = "VT65_" .. trecho
	s.SoundId = "rbxassetid://" .. id
	s.Volume = (o.vol or 1) * (if g then SomGravacoes.volume(g) else 1)
	s.PlaybackSpeed = (o.pitch or 1) * (if g then g.tom or 1 else 1)
	s.SoundGroup = group(o.grupo or "efeitos")
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(inicio, inicio + dur)
	if o.low or o.mid or o.high then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain, eq.MidGain, eq.HighGain = o.low or 0, o.mid or 0, o.high or 0
		eq.Parent = s
	end
	local holder: Instance = SoundService
	local att: Attachment? = nil
	if o.pos then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = o.minDist or 10
		s.RollOffMaxDistance = o.maxDist or 400
		local a = Instance.new("Attachment")
		a.WorldPosition = o.pos
		a.Parent = workspace.Terrain
		att = a
		holder = a
	end
	s.Parent = holder
	-- D-220: o tiro gravado tem cauda: na rajada, poucas vozes por arma (a mais velha apaga em 80 ms)
	local v = o.vaga
	local quantas = o.vagas or 2
	if g and not v then
		local proprio = string.sub(trecho, 1, 1) == "p"
		v = string.format("gravacao_%s_%s", kit, if proprio then "p" else "e")
		quantas = if proprio then 3 else 5
	end
	if v then
		local lista = vagas[v] or {}
		vagas[v] = lista
		for i = #lista, 1, -1 do
			if not lista[i].Parent or not lista[i].IsPlaying then
				table.remove(lista, i)
			end
		end
		while #lista >= quantas do
			apaga(table.remove(lista, 1) :: Sound)
		end
		table.insert(lista, s)
	end
	s:Play()
	local tocando = dur / math.max(s.PlaybackSpeed, 0.1)
	if g then
		-- o recorte pode acabar no meio do som (antes do tiro seguinte da rajada): sai sem estalo
		task.delay(math.max(0, tocando - 0.035), function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(0.03, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
			end
		end)
	end
	local life = tocando + 0.3
	task.delay(life, function()
		s:Destroy()
		if att then
			att:Destroy()
		end
	end)
end

-- Toca o trecho `trecho` do kit `kit` (Shared/SomKits)
function Som.kit(kit: string, trecho: string, opts: Opts?)
	local o: Opts = opts or {}
	local d = o.delay
	if d and d > 0 then
		task.delay(d, go, kit, trecho, o)
	else
		go(kit, trecho, o)
	end
end

-- Duração (s) e âncora (s) do trecho (0 se não existe)
function Som.trecho(kit: string, trecho: string): (number, number)
	local k = SomKits[kit]
	local seg = k and k.seg[trecho]
	if not seg then
		return 0, 0
	end
	return seg[2], seg[3]
end

-- O kit carregou?
function Som.ok(kit: string): boolean
	return not failed[kit]
end

return Som
