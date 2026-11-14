--!strict
-- Toca os sons das armas (Shared/SomArmas, D-107): só o trecho de um disparo do arquivo
-- (PlaybackRegion), tom, equalização, cauda pelo lugar (eco ou reverberação) e 3D num ponto do mundo.
-- Os ids de fora (Front 44 / Pro Sound Effects) são conferidos uma vez no começo; o que não carregar
-- toca o som do jogo da chave `alt` (AssetIds.Sounds). Usado pelo AudioController e pelo Acerto.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local SomArmas = require(ReplicatedStorage.Shared.SomArmas)

local Som = {}

local failed: { [number]: boolean } = {}
task.spawn(function()
	local ids: { string } = {}
	local function add(def: SomArmas.Def)
		table.insert(ids, "rbxassetid://" .. def.id)
	end
	for _, def in SomArmas.LIB do
		add(def)
	end
	for _, def in SomArmas.CARNE do
		add(def)
	end
	pcall(function()
		ContentProvider:PreloadAsync(ids, function(content: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success then
				local n = tonumber(string.match(content, "(%d+)$"))
				if n then
					failed[n] = true
				end
			end
		end)
	end)
end)

local function group(): SoundGroup?
	local g = SoundService:FindFirstChild("VT65Efeitos")
	return if g and g:IsA("SoundGroup") then g else nil
end

export type Opts = {
	pos: Vector3?, -- 3D nesse ponto; sem: 2D
	vol: number?, -- multiplica o volume do som
	pitch: number?, -- multiplica o tom
	delay: number?, -- s
	minDist: number?, -- studs (3D)
	maxDist: number?, -- studs (3D)
	low: number?, -- dB (equalizador)
	mid: number?,
	high: number?,
	cauda: SomArmas.Cauda?,
}

local function go(def: SomArmas.Def, o: Opts)
	local id, start, len, pitch = def.id, def.start, def.len, def.pitch or 1
	if failed[id] then
		local alt = def.alt and AssetIds.Sounds[def.alt]
		if type(alt) ~= "number" or alt == 0 then
			return
		end
		id, start, len, pitch = alt, nil, nil, 1 -- o som do jogo inteiro, no tom dele
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = def.vol * (o.vol or 1)
	s.PlaybackSpeed = pitch * (o.pitch or 1)
	s.SoundGroup = group()
	if len then
		pcall(function()
			s.PlaybackRegionsEnabled = true
			s.PlaybackRegion = NumberRange.new(start or 0, (start or 0) + len)
		end)
	end
	if o.low or o.mid or o.high then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain, eq.MidGain, eq.HighGain = o.low or 0, o.mid or 0, o.high or 0
		eq.Priority = 1
		eq.Parent = s
	end
	local c = o.cauda
	if c then
		if c.eco then
			local e = Instance.new("EchoSoundEffect")
			e.Delay = c.delay
			e.Feedback = c.feedback
			e.WetLevel = c.wet
			e.DryLevel = 0
			e.Priority = 2
			e.Parent = s
		else
			local r = Instance.new("ReverbSoundEffect")
			r.DecayTime = c.decay
			r.Density = 1
			r.Diffusion = 1
			r.WetLevel = c.wet
			r.DryLevel = 0
			r.Priority = 2
			r.Parent = s
		end
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
	s:Play()
	-- a cauda (eco) toca depois do fim do trecho: some 2 s depois (som inteiro: até 6 s)
	local life = (len or 6) / math.max(s.PlaybackSpeed, 0.1) + 2
	task.delay(life, function()
		s:Destroy()
		if att then
			att:Destroy()
		end
	end)
end

-- Toca um som (Def ou chave de SomArmas.LIB)
function Som.play(what: SomArmas.Def | string, opts: Opts?)
	local def: SomArmas.Def? = if type(what) == "string" then SomArmas.LIB[what] else what
	if not def then
		return
	end
	local o: Opts = opts or {}
	local d = o.delay
	if d and d > 0 then
		task.delay(d, go, def, o)
	else
		go(def, o)
	end
end

-- O id carregou? (false = toca o alt)
function Som.ok(def: SomArmas.Def): boolean
	return not failed[def.id]
end

return Som
