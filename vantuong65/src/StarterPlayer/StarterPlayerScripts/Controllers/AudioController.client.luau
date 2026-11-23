--!strict
-- Áudio da F3 (Parte 5 e 10.7): ambiências por zona com crossfade, passos por material (seus e
-- dos outros, 3D), tiros alheios em camadas por distância com atraso do som (d/349 m/s),
-- estalo supersônico quando a bala passa perto e impacto por material. Sem asset (ID 0) fica mudo.
-- D-107 (pedido do dono: "melhore o áudio das armas"): o tiro PRÓPRIO toca aqui (antes era o
-- WeaponController, um som só): disparo da arma, corpo grave, cauda pelo lugar (eco no aberto,
-- abafado na mata, reverberação na vila e no túnel), estojo e ferrolho. Os tiros dos outros ganham o
-- disparo da própria arma de perto, agudos caindo com a distância, a cauda e o zunido da bala que
-- passa rente. Dados em Shared/SomArmas; quem toca é o Controllers/Som.
-- D-204 (§9): tudo isso sai dos kits de som próprios (tools/sons_armas.py; Shared/SomKits): o tiro em
-- 1ª e 3ª pessoa de cada arma, a cauda pelo lugar, médio e longe, a bala, a recarga peça a peça, o
-- clique seco, o ciclo, o estojo, os passos (6 por chão), os impactos e as explosões. Variação sem
-- repetir a última; os tiros num grupo com limitador, e o ambiente abaixa durante o tiroteio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Accessibility = require(ReplicatedStorage.Shared.Accessibility)
local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local ExplosaoEfeito = require(ReplicatedStorage.Shared.ExplosaoEfeito)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local SomArmas = require(ReplicatedStorage.Shared.SomArmas)
local SomGravacoes = require(ReplicatedStorage.Shared.SomGravacoes)
local SonsBiblioteca = require(ReplicatedStorage.Shared.SonsBiblioteca)
local Superficie = require(ReplicatedStorage.Shared.Superficie)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Weather = require(ReplicatedStorage.Shared.Weather)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local Som = require(script.Parent.Som)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = MapConfig.STUD_M
local SND = AssetIds.Sounds

local function sid(key: string): string?
	local id = SND[key]
	return if type(id) == "number" and id ~= 0 then "rbxassetid://" .. id else nil
end

-- ===== mixagem (D-91, depois de jogar: "o barulho é insuportável, os sons estão muito altos e
-- continuam mesmo no menu") =====
-- Todo som do jogo passa por um grupo: efeitos (tiros, passos, explosões, motores), ambiente (água,
-- vila, praia, túnel) e música (só no menu). Efeitos e ambiente baixaram; no lobby e na tela de
-- inserção o ambiente some e entra a música baixa.
local function group(name: string, volume: number): SoundGroup
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = volume
	g.Parent = SoundService
	return g
end
local sfxGroup = group("VT65Efeitos", 0.5)
local ambGroup = group("VT65Ambiente", 0.6)
local musicGroup = group("VT65Musica", 0.35)
-- D-204 (§9: "tiros com presença sem esconder permanentemente informações úteis"): os tiros, as caudas
-- e as explosões num grupo dentro dos efeitos, com um limitador (muitos juntos não saturam); o
-- ambiente abaixa enquanto há tiro (compressor ligado ao grupo dos tiros) e volta em ~0,6 s. Os passos,
-- a bala passando, o rádio e os avisos ficam fora do grupo dos tiros: não abaixam.
local shotGroup = Instance.new("SoundGroup")
shotGroup.Name = "VT65Tiros"
shotGroup.Volume = 1
shotGroup.Parent = sfxGroup
do
	local lim = Instance.new("CompressorSoundEffect")
	lim.Name = "Limitador"
	lim.Threshold = -6
	lim.Ratio = 8
	lim.Attack = 0.003
	lim.Release = 0.15
	lim.GainMakeup = 0
	lim.Parent = shotGroup
	local duck = Instance.new("CompressorSoundEffect")
	duck.Name = "AbaixaNoTiro"
	duck.SideChain = shotGroup
	duck.Threshold = -30
	duck.Ratio = 3
	duck.Attack = 0.01
	duck.Release = 0.6
	duck.GainMakeup = 0
	duck.Parent = ambGroup
end
-- volume escolhido no menu do jogo (Configurações → Som), salvo na conta (Input.settings)
local function applyVolumes()
	local s = Input.settings :: any
	sfxGroup.Volume = tonumber(s.volEffects) or 0.5
	ambGroup.Volume = tonumber(s.volAmbient) or 0.6
	musicGroup.Volume = tonumber(s.volMusic) or 0.35
end
Input.SettingsChanged:Connect(applyVolumes)
applyVolumes()
-- sons criados por outros scripts (arma, veículo, explosão) também entram nos efeitos
local function adopt(inst: Instance)
	if inst:IsA("Sound") and inst.SoundGroup == nil then
		inst.SoundGroup = sfxGroup
	end
end
workspace.DescendantAdded:Connect(adopt)
SoundService.DescendantAdded:Connect(adopt)
task.spawn(function()
	for _, d in workspace:GetDescendants() do
		adopt(d)
	end
end)

local function inField(): boolean
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and Input.state.alive
end

local music: Sound? = nil
do
	local id = sid("music_menu")
	if id then
		local s = Instance.new("Sound")
		s.Name = "MusicaMenu"
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = musicGroup
		s.Parent = SoundService
		s:Play()
		music = s
	end
end

-- ===== legendas de som (acessibilidade): aparecem quando o som chegaria, mesmo sem asset =====
local capGui = UiKit.screen("VT65Captions", 15)
local capList = Instance.new("Frame")
capList.AnchorPoint = Vector2.new(0.5, 1)
capList.Position = UDim2.new(0.5, 0, 1, -170)
capList.Size = UDim2.fromOffset(640, 160)
capList.BackgroundTransparency = 1
capList.Parent = capGui
local capLayout = Instance.new("UIListLayout")
capLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
capLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
capLayout.Padding = UDim.new(0, 3)
capLayout.Parent = capList
local lastCap: { [string]: number } = {}
local function caption(key: string, what: string, pos: Vector3?, delay: number?)
	if not Input.settings.captions then
		return
	end
	local now = os.clock()
	if (lastCap[key] or 0) > now - 1.5 then
		return -- uma legenda por tipo de som a cada 1,5 s (rajada não vira parede de texto)
	end
	lastCap[key] = now
	local d = if pos then (pos - camera.CFrame.Position) * M else Vector3.zero
	local text = Accessibility.caption(what, d.X, d.Z)
	task.delay(delay or 0, function()
		-- mesmo contraste de antes (branco sobre preto); a faixa só abraça o texto, com canto leve
		local l = Instance.new("TextLabel")
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Size = UDim2.fromOffset(0, if UiKit.tv() then 34 else 26)
		l.BackgroundColor3 = Color3.new(0, 0, 0)
		l.BackgroundTransparency = 0.35
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Font = Enum.Font.GothamMedium
		l.TextSize = UiKit.text(18)
		l.Text = text
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = l
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 4)
		round.Parent = l
		l.Parent = capList
		task.delay(4, function()
			l:Destroy()
		end)
	end)
end

-- som 3D num ponto do mundo (ou 2D se pos == nil)
-- D-198: pitch (tom) e grave (só os graves: o agudo cortado, como o estrondo e o eco de longe)
local function play(
	key: string,
	pos: Vector3?,
	volume: number,
	maxDist: number?,
	delay: number?,
	pitch: number?,
	grave: boolean?
)
	local id = sid(key)
	if not id then
		return
	end
	local function go()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume * SonsBiblioteca.ganho(key)
		s.PlaybackSpeed = pitch or 1
		if grave then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.HighGain, eq.MidGain, eq.LowGain = -24, -8, 4
			eq.Parent = s
		end
		s.SoundGroup = sfxGroup
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = maxDist or 400
		local holder: Instance = SoundService
		local att: Attachment? = nil
		if pos then
			local a = Instance.new("Attachment")
			a.WorldPosition = pos
			a.Parent = workspace.Terrain
			att = a
			holder = a
		end
		s.Parent = holder
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
			if att then
				att:Destroy()
			end
		end)
	end
	if delay and delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
end

-- ===== ambiências =====
local AMB: { [string]: string } = {
	paddy = "ambience_paddy_morning",
	village = "ambience_village",
	beach = "ambience_beach",
	tunnel = "ambience_tunnel",
}
local loops: { [string]: Sound } = {}
for zone, key in AMB do
	local id = sid(key)
	if id then
		local s = Instance.new("Sound")
		s.Name = "Amb_" .. zone
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = ambGroup
		s.Parent = SoundService
		s:Play()
		loops[zone] = s
	end
end

local villages: { Vector3 } = {}
local beachX = math.huge
for _, l in MapConfig.Locations do
	if
		string.find(l.name, "An Cường")
		or string.find(l.name, "Nam Yên")
		or string.find(l.name, "An Thới")
		or string.find(l.name, "An Phước")
		or string.find(l.name, "Lạc Sơn")
	then
		table.insert(villages, Vector3.new(l.x, 0, l.z))
	end
	-- no mapa de 2 x 2 km (D-63) a praia ficou fora: sem o local, o som de praia não toca
	if string.find(l.name, "Green Beach") then
		beachX = l.x - 120 / M
	end
end
-- D-114: a vila grande de Xóm Gò (ponto forte de design, sem local da carta) também soa como vila
for _, sp in MapConfig.Strongpoints do
	if sp.name == "Vila" then
		table.insert(villages, Vector3.new(sp.x, 0, sp.z))
	end
end

local function underground(pos: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local r = workspace:Raycast(pos, Vector3.new(0, 25, 0), params)
	return r ~= nil and (r.Instance == workspace.Terrain or string.find(r.Instance.Name, "ceiling") ~= nil)
end

local function zoneAt(pos: Vector3): string
	if underground(pos) then
		return "tunnel"
	end
	if pos.X > beachX then
		return "beach"
	end
	for _, v in villages do
		if (Vector3.new(pos.X, 0, pos.Z) - v).Magnitude < 150 / M then
			return "village"
		end
	end
	return "paddy"
end

-- D-107: lugar de quem ouve, para a cauda dos tiros (SomArmas.lugar): 8 raios de 25 m em volta da
-- cabeça (tronco, parede, moita) e um para cima (copa ou telhado)
local lugar = SomArmas.LUGAR
local placeParams = RaycastParams.new()
placeParams.FilterType = Enum.RaycastFilterType.Exclude
local function measurePlace(pos: Vector3, zone: string): string
	local ignore: { Instance } = { camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		table.insert(ignore, folder)
	end
	placeParams.FilterDescendantsInstances = ignore
	local hits = 0
	for i = 0, 7 do
		local a = i * math.pi / 4
		if workspace:Raycast(pos, Vector3.new(math.cos(a), 0, math.sin(a)) * (25 / M), placeParams) then
			hits += 1
		end
	end
	local roof = workspace:Raycast(pos, Vector3.new(0, 15 / M, 0), placeParams) ~= nil
	return SomArmas.lugar(hits, 8, roof, zone == "village", zone == "tunnel")
end

-- v41 ("jogo está bem pesado ainda"): o laço calado fica pausado (no Studio, com 100 bots, eram ~97
-- canais tocando; as quatro ambiências e a música do menu tocavam o tempo todo com volume 0)
local function quiet(s: Sound, target: number)
	if target <= 0 and s.Volume < 0.002 then
		s.Volume = 0
		if s.IsPlaying then
			s:Pause()
		end
	elseif target > 0 and not s.IsPlaying then
		if s.IsPaused then
			s:Resume()
		else
			s:Play()
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		-- fora de campo (lobby, inserção, morto) o ambiente some e a música baixa entra; em campo, o
		-- contrário. A mesa do lobby fica no mundo e contava como "arrozal" (o som de água tocava no menu).
		local field = inField()
		local zone = if field then zoneAt(camera.CFrame.Position) else ""
		if field then
			lugar = measurePlace(camera.CFrame.Position, zone)
		end
		for z, s in loops do
			local target = if z == zone then 0.2 * SonsBiblioteca.ganho(AMB[z]) else 0
			s.Volume += (target - s.Volume) * 0.35
			quiet(s, target)
		end
		local m = music
		if m then
			local target = if field then 0 else 0.5
			m.Volume += (target - m.Volume) * 0.25
			quiet(m, target)
		end
	end
end)

-- ===== passos =====
-- D-191 (dono: passos conforme o piso "diretamente sob o personagem"): o raio para no que está logo
-- embaixo (a ponte vale mais que o rio), o piso sai do Shared/Superficie (terra, lama, arrozal, água,
-- areia, madeira, metal, pedra) e, na divisa, só troca depois de duas leituras seguidas. No ar (nada
-- até AIR_STUDS abaixo dos pés) não há passo.
local AIR_STUDS = 4.6 -- do centro do corpo ao chão em pé ~3,6 studs; mais que isto é pulo ou queda
local stableOf: { [Model]: Superficie.Stable } = setmetatable({}, { __mode = "k" }) :: any
local function surfaceUnder(root: BasePart, model: Model): (string?, number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local r = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	if not r then
		return nil, math.huge
	end
	local inst = r.Instance
	local attr = inst:GetAttribute("Material")
	local s = Superficie.of(
		inst == workspace.Terrain,
		r.Material.Name,
		inst.Name,
		if type(attr) == "string" then attr else nil,
		inst:FindFirstAncestor("log_bridge") ~= nil
	)
	return s, root.Position.Y - r.Position.Y
end
local function stepKey(root: BasePart, model: Model): string
	local s = surfaceUnder(root, model)
	local st = stableOf[model]
	if not st then
		st = Superficie.newStable()
		stableOf[model] = st
	end
	return Superficie.STEP[Superficie.stable(st, s or "grass")] or "step_grass"
end

local walked: { [Model]: { pos: Vector3, acc: number } } = setmetatable({}, { __mode = "k" }) :: any
-- ~0,8 m por passo. D-204: um passo por passada, do kit_passos (6 variações por chão, sem repetir a
-- última de cada soldado); antes o arquivo tinha 4 passos e tocava 1 vez a cada 4 passadas
local STRIDE = 0.8 / M
local ultimoPasso: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local function passo(key: string, pos: Vector3, vol: number, maxDist: number, quem: any)
	local chao = SomArmas.CHAO[key] or "grama"
	local v = SomArmas.sorteia(SomArmas.PASSOS, ultimoPasso[quem], math.random())
	ultimoPasso[quem] = v
	Som.kit("kit_passos", chao .. v, { pos = pos, vol = vol, minDist = 10, maxDist = maxDist })
end

local function characters(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	return list
end

-- D-91: só os 4 mais perto fazem passo (com um squad de bots andando no arrozal, a água "ficava
-- repetindo"); volumes mais baixos e o passo na água mais baixo ainda.
local NEAREST_STEPS = 4
type Near = { char: Model, root: BasePart, d: number }
task.spawn(function()
	while true do
		task.wait(0.1)
		local listener = camera.CFrame.Position
		local near: { Near } = {}
		for _, char in characters() do
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - listener).Magnitude
				if d < 60 / M then
					table.insert(near, { char = char, root = root, d = d })
				end
			end
		end
		table.sort(near, function(a: Near, b: Near): boolean
			return a.d < b.d
		end)
		for i, n in near do
			if i > NEAREST_STEPS then
				walked[n.char] = nil -- volta a contar do zero quando entrar entre os mais perto
				continue
			end
			local char, root = n.char, n.root
			do
				local w = walked[char]
				if not w then
					walked[char] = { pos = root.Position, acc = 0 }
				else
					local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(w.pos.X, 0, w.pos.Z)).Magnitude
					w.pos = root.Position
					-- D-191: no ar não conta passo (pulo, queda, transpor)
					local _, below = surfaceUnder(root, char)
					if below > AIR_STUDS then
						continue
					end
					w.acc += d
					if w.acc >= STRIDE then
						w.acc = 0
						local rain = ReplicatedStorage:GetAttribute("Rain")
						-- rastejando quase não se ouve; correndo, mais alto (movimento, 2026-11-11)
						local base = if char:GetAttribute("Prone")
							then 0.1
							elseif char:GetAttribute("Crouched") then 0.16
							elseif char:GetAttribute("Sprinting") then 0.5
							else 0.35
						local key = stepKey(root, char)
						if key == "step_paddy" then
							base *= 0.55
						end
						local vol = base * Weather.footstepVolume(if type(rain) == "number" then rain else 0) -- a chuva cobre os passos
						passo(key, root.Position, vol, 45 / M, char)
					end
				end
			end
		end
	end
end)

-- próprio corpo: aterrissagem (queda em m) e transpor/mergulho fazem o barulho do chão (Movement.client)
local function ownStep(volume: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if char and root then
		passo(stepKey(root, char), root.Position, volume, 45 / M, char)
	end
end
Bus.on("landed", function(dropM: number)
	ownStep(math.clamp(0.4 + dropM * 0.3, 0.4, 1.2))
end)
Bus.on("vault_start", function()
	ownStep(0.5)
end)

-- ===== tiro próprio (D-107; D-204: o kit da arma) =====
-- O WeaponController avisa cada tiro que sai (Bus "shot_fired"): o tiro em 1ª pessoa do kit da arma
-- (p1..p4, nunca a mesma variação duas vezes seguidas), a cauda pelo lugar de quem ouve (kit_caudas,
-- tocada até o fim: na rajada a nova apaga a mais velha, a última rola inteira) e o estojo pulando.
-- O som do próprio tiro é só daqui: o servidor manda o traçante (Combat_Tracer) só para os OUTROS
-- (CombatService.fire, exceptPlayer), então o tiro previsto no cliente não toca de novo.
local lastTail, lastShell = 0, 0
local ultimo: { [string]: number } = {} -- última variação por kit e tipo
local function variacao(chave: string, n: number): number
	local v = SomArmas.sorteia(n, ultimo[chave], math.random())
	ultimo[chave] = v
	return v
end
local function ownShot(weaponId: string?)
	local wp = if type(weaponId) == "string" then Weapons.get(weaponId) else nil
	if not wp then
		return
	end
	local a = SomArmas.arma(wp.id, wp.kind)
	local now = os.clock()
	-- ±1% de tom: só o ajuste fino; a variação de verdade são os trechos
	Som.kit(a.kit, "p" .. variacao(a.kit .. "p", SomArmas.PROPRIO), {
		vol = 0.9 * (a.vol or 1),
		pitch = 1 + (math.random() - 0.5) * 0.02,
		grupo = "tiros",
	})
	if now - lastTail > 0.12 then
		lastTail = now
		-- D-220: a gravação já traz a cauda dela; a sintética só dá o lugar (mata, vila, túnel)
		Som.kit("kit_caudas", SomArmas.cauda(a.familia, lugar, variacao("cauda", SomArmas.CAUDAS)), {
			vol = if SomGravacoes.temCauda(a.kit) then 0.3 else 0.9,
			grupo = "tiros",
			vaga = "cauda_propria",
			vagas = SomArmas.CAUDA_VAGAS_PROPRIO,
		})
	end
	-- (no ferrolho manual e na bomba o estojo sai no ciclo, não no tiro)
	if a.estojo and not a.ciclo and now - lastShell > 0.18 then
		lastShell = now
		Som.kit(a.kit, "estojo" .. variacao(a.kit .. "estojo", 2), { delay = 0.35 + math.random() * 0.15, vol = 0.6 })
	end
end
Bus.on("shot_fired", function(shot: any)
	ownShot(if type(shot) == "table" then shot.w else nil)
end)
-- v41 (pedido do dono: "a arma do tanque n sai som"): a metralhadora do assento (coaxial do atirador do
-- M48, M60 da cúpula e da porta) atirada por mim. O servidor manda o traçante e o som só para os OUTROS
-- (CombatService.fire, exceptPlayer) e o VehicleController só fazia o clarão: quem atirava não ouvia.
Bus.on("vehicle_mg_shot", function()
	ownShot("m60")
end)

-- ferrolho manobrado (fuzis de precisão) ou a bomba da espingarda: o trecho "ciclo" do kit, feito no
-- tempo da animação (Ferrolho.curve e pumpCurve) e ajustado à duração do ciclo da arma
Bus.on("bolt_cycle", function(dur: number, weaponId: string?)
	local wp = if type(weaponId) == "string" then Weapons.get(weaponId) else nil
	local a = SomArmas.arma(if wp then wp.id else "", if wp then wp.kind else nil)
	local len = Som.trecho(a.kit, "ciclo")
	if len <= 0 then
		return
	end
	local d = if type(dur) == "number" and dur > 0 then dur else len
	Som.kit(a.kit, "ciclo", { pitch = math.clamp(len / d, 0.85, 1.25) })
	if a.estojo then -- o cartucho vazio da espingarda caindo depois da bomba
		Som.kit(a.kit, "estojo" .. variacao(a.kit .. "estojo", 2), { delay = 0.5 + math.random() * 0.15, vol = 0.6 })
	end
end)

-- D-204: o clique seco da própria arma (gatilho sem munição)
Bus.on("dry_fire", function(weaponId: string?)
	local wp = if type(weaponId) == "string" then Weapons.get(weaponId) else nil
	local a = SomArmas.arma(if wp then wp.id else "", if wp then wp.kind else nil)
	Som.kit(a.kit, "seco", { vol = 0.8 })
end)

-- D-204: a recarga peça a peça (SomArmas.RECARGA), cada uma no instante da animação; a troca de arma
-- no meio cala o que ainda não tocou. A espingarda é do Ferrolho (cartucho a cartucho); o RPG-2 tem o
-- som dele (WeaponController).
local recargaGen = 0
Bus.on("reload_start", function(dur: number, _kind: string?, _n: number?, _empty: boolean?, weaponId: string?)
	recargaGen += 1
	local wp = if type(weaponId) == "string" then Weapons.get(weaponId) else nil
	if not wp then
		return
	end
	local a = SomArmas.arma(wp.id, wp.kind)
	local gen = recargaGen
	local d = if type(dur) == "number" and dur > 0 then dur else 2.5
	for _, p in
		SomArmas.agenda(a.recarga, d, function(trecho: string): number
			local _, anc = Som.trecho(a.kit, trecho)
			return anc
		end)
	do
		task.delay(p.t, function()
			if recargaGen == gen then
				Som.kit(a.kit, p.trecho, { vol = 0.85 })
			end
		end)
	end
end)
Bus.on("reload_cancel", function()
	recargaGen += 1
end)

-- D-236 (dono: "altere o barulho do dano"): levar um tiro não tinha som nenhum no próprio corpo. Agora o
-- baque gravado a cada acerto e, no máximo a cada 1,4 s, o fôlego que falta.
local baqueEm, dorEm = -10, -10
Net.event("Combat_Hit").OnClientEvent:Connect(function()
	local agora = os.clock()
	if agora - baqueEm >= 0.1 then
		baqueEm = agora
		Som.kit("kit_corpo", "baque" .. variacao("corpo_baque", 3), { vol = 0.62, low = 3 })
	end
	if agora - dorEm >= 1.4 then
		dorEm = agora
		Som.kit("kit_corpo", "dor" .. variacao("corpo_dor", 3), { vol = 0.42, delay = 0.07 })
	end
end)

-- ===== tiros dos outros: camadas, atraso do som, estalo e impacto =====
-- trecho com variação (sem repetir a última) de um kit de fora das armas
local function var(prefixo: string, n: number): string
	return prefixo .. variacao(prefixo, n)
end

-- v41 ("jogo está bem pesado ainda"): o disparo de quem está a mais de 100 m tem teto de 16 por
-- segundo (balde de 8). No Studio, com 100 bots, eram 33 sons de tiro tocando juntos; o tiroteio
-- longe continua soando cheio, e o de perto e a bala passando perto não entram no teto.
local FAR_RATE, FAR_CAP = 16, 8
local farBudget, farAt = FAR_CAP, os.clock()
local function farOk(): boolean
	local now = os.clock()
	farBudget = math.min(FAR_CAP, farBudget + (now - farAt) * FAR_RATE)
	farAt = now
	if farBudget >= 1 then
		farBudget -= 1
		return true
	end
	return false
end

Net.unreliable("Combat_Tracer").OnClientEvent:Connect(function(shot)
	local wp = Weapons.get(shot.w)
	if not wp then
		return
	end
	local origin = Vector3.new(shot.ox, shot.oy, shot.oz)
	local dir = Vector3.new(shot.dx, shot.dy, shot.dz).Unit
	local listener = camera.CFrame.Position
	local dM = (origin - listener).Magnitude * M
	local delay = dM / Ballistics.SOUND
	if dM < 2500 then
		caption(string.format("shot:%s", wp.id), string.format("Tiro de %s", wp.name or wp.id), origin, delay)
	end
	-- D-107/D-204: o tiro de perto do kit da arma (e1..e3, 3D), médio e longe do kit_distancia pela
	-- família (3D sem atenuação: o volume é o da camada), agudos caindo com a distância e, perto, a
	-- cauda pelo lugar de quem ouve (no máximo SomArmas.CAUDA_VAGAS_OUTROS juntas)
	local a = SomArmas.arma(wp.id, wp.kind)
	local near, mid, far = SomArmas.camadas(dM)
	local high = SomArmas.agudos(dM, lugar)
	local jitter = 1 + (math.random() - 0.5) * 0.02
	local layers = dM <= 100 or farOk()
	if layers and near > 0.01 then
		Som.kit(a.kit, "e" .. variacao(a.kit .. "e", SomArmas.OUTRO), {
			pos = origin,
			vol = near * (a.vol or 1),
			pitch = jitter,
			delay = delay,
			minDist = 8 / M,
			maxDist = 1500 / M,
			high = high,
			grupo = "tiros",
		})
		Som.kit("kit_caudas", SomArmas.cauda(a.familia, lugar, variacao("cauda_outros", SomArmas.CAUDAS)), {
			vol = (if SomGravacoes.temCauda(a.kit) then 0.3 else 0.75) * near,
			delay = delay,
			grupo = "tiros",
			vaga = "cauda_outros",
			vagas = SomArmas.CAUDA_VAGAS_OUTROS,
		})
	end
	local function distante(faixa: string, vol: number, h: number)
		local chave = a.familia .. faixa
		local v = variacao(chave, SomArmas.DISTANCIA)
		Som.kit("kit_distancia", SomArmas.distante(a.familia, faixa, v), {
			pos = origin,
			vol = vol,
			delay = delay,
			minDist = 1e5,
			maxDist = 2e5,
			high = h,
			grupo = "tiros",
		})
	end
	if layers and mid > 0.01 then
		distante("medio", mid * 0.9, high * 0.5)
	end
	if layers and far > 0.01 then
		distante("longe", far * 0.8, 0)
	end
	-- o ferrolho ou a bomba de quem atira perto
	if a.ciclo and dM < 40 then
		Som.kit(a.kit, "ciclo", { pos = origin, delay = delay + 0.1, vol = 0.8, minDist = 3 / M, maxDist = 60 / M })
	end
	-- estalo (supersônica) ou zunido: passagem mais próxima da trajetória (reta) até o ouvinte
	local t = (listener - origin):Dot(dir)
	if t > 0 then
		local closest = (origin + dir * t - listener).Magnitude * M
		local distM = t * M
		local tFlight = distM / math.max(wp.muzzleVelocity * 0.85, 1)
		local what, vol = SomArmas.passagem(closest, wp.muzzleVelocity * 0.85, Ballistics.SOUND)
		if what and distM > 15 then
			-- D-204: kit_balas (estalo1..3, zunido1..3), fora do grupo dos tiros: não abaixa
			Som.kit("kit_balas", var(what, 3), { delay = tFlight, vol = vol })
			caption("crack", "Bala passando perto", nil, tFlight)
		end
	end
	-- impacto perto do ouvinte: refaz a trajetória com a mesma semente
	if dM < 150 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
		local hit = Ballistics.trace({
			ox = origin.X * M,
			oy = origin.Y * M,
			oz = origin.Z * M,
			dx = dir.X,
			dy = dir.Y,
			dz = dir.Z,
			weaponId = wp.id,
			seed = shot.seed,
			maxTime = 1,
		}, function(ax, ay, az, bx, by, bz)
			local r = workspace:Raycast(Vector3.new(ax, ay, az) / M, Vector3.new(bx - ax, by - ay, bz - az) / M, params)
			if not r then
				return nil
			end
			local key = "impact_earth"
			local mat = r.Instance:GetAttribute("Material")
			if mat == "PaddyWater" or r.Material == Enum.Material.Water then
				key = "impact_water"
			elseif mat == "Bamboo" then
				key = "impact_wood"
			elseif mat == "Thatch" then
				key = "impact_thatch"
			end
			local p = r.Position * M
			return { x = p.X, y = p.Y, z = p.Z, target = key }
		end)
		if hit then
			local pos = Vector3.new(hit.x, hit.y, hit.z) / M
			local dl = (pos - listener).Magnitude * M
			if dl < 80 then
				-- D-204: kit_impactos, 4 variações por material
				local matKit = SomArmas.IMPACTO[hit.target :: string] or "terra"
				Som.kit("kit_impactos", var(matKit, SomArmas.IMPACTOS), {
					pos = pos,
					vol = 0.9,
					minDist = 10,
					maxDist = 80 / M,
					delay = hit.t + dl / Ballistics.SOUND,
				})
			end
		end
	end
end)

-- ===== F4: explosões, granada chegando, disparos e motores =====
Net.unreliable("Fire_Impact").OnClientEvent:Connect(function(e)
	local pos = Vector3.new(e.x, e.y, e.z)
	local dM = (pos - camera.CFrame.Position).Magnitude * M
	-- D-204: kit_explosoes (granada1..3; pesada1..2 e o eco1..2 rolando pelo vale), sem trocar o tom
	local T = ExplosaoEfeito.de(tostring(e.id))
	local pesada = T.classe == "pesada"
	if dM < 3000 and not pesada then
		Som.kit("kit_explosoes", var("granada", 3), {
			pos = pos,
			vol = math.clamp(1.4 - dM / 2500, 0.3, 1.4),
			minDist = 10,
			maxDist = 3000 / M,
			delay = dM / Ballistics.SOUND,
			high = SomArmas.agudos(dM * 0.5, lugar),
			grupo = "tiros",
		})
		caption("explosion", "Explosão", pos, dM / Ballistics.SOUND)
	end
	-- D-198: bomba e tiro naval: o estrondo grave e a cauda (o eco pelo vale e pela mata) logo depois,
	-- mais grave e longa; ouvidos de mais longe
	if pesada and dM < 6000 then
		local d = ExplosaoEfeito.atrasoSom(dM)
		local k = math.clamp(1.3 - dM / 4000, 0.35, 1.3)
		Som.kit("kit_explosoes", var("pesada", 2), {
			pos = pos,
			vol = k,
			minDist = 10,
			maxDist = 6000 / M,
			delay = d,
			high = SomArmas.agudos(dM * 0.5, lugar),
			grupo = "tiros",
		})
		Som.kit(
			"kit_explosoes",
			var("eco", 2),
			{ pos = pos, vol = k * 0.6, minDist = 10, maxDist = 8000 / M, delay = d + 0.22, grupo = "tiros" }
		)
		caption("explosion", "Explosão", pos, d)
	end
end)
Net.unreliable("Fire_Incoming").OnClientEvent:Connect(function(e)
	local pos = Vector3.new(e.x, e.y, e.z)
	if (pos - camera.CFrame.Position).Magnitude * M < 400 then
		play("incoming", pos, 1, 600 / M)
		caption("incoming", "Assobio de granada chegando", pos)
	end
end)
local LAUNCH: { [string]: string } = {
	mortar = "mortar_launch",
	naval = "naval_distant",
	gun_90 = "gun_90",
	rr_106 = "rr_106",
	rocket = "rr_106",
	-- D-200: o lançador do antitanque (LancadorService); sem o som próprio publicado, o do 106 mm
	rpg2 = if (tonumber((AssetIds.Sounds :: any).rpg2_disparo) or 0) ~= 0 then "rpg2_disparo" else "rr_106",
	m20 = "rr_106",
}
Net.unreliable("Fire_Launch").OnClientEvent:Connect(function(e)
	local pos = Vector3.new(e.x, e.y, e.z)
	local dM = (pos - camera.CFrame.Position).Magnitude * M
	local k = LAUNCH[e.kind]
	if k and dM < 6000 then
		local what = if e.kind == "mortar"
			then "Disparo de morteiro"
			elseif e.kind == "naval" then "Tiro naval ao longe"
			elseif e.kind == "rpg2" or e.kind == "m20" then "Disparo de lançador antitanque"
			else "Disparo de canhão/foguete"
		caption(string.format("launch:%s", e.kind), what, pos, dM / Ballistics.SOUND) -- chave, não texto
		if e.kind == "naval" then
			play(k, nil, 0.8, nil, dM / Ballistics.SOUND)
		else
			play(k, pos, 1, 2500 / M, dM / Ballistics.SOUND)
		end
	end
end)

-- ===== D-132: o A-4 do ataque aéreo (dono: "deve ter um som específico quando vai acontecer") =====
-- O evento "air" (Modules/EventosService) põe o marcador em ReplicatedStorage.VT65Eventos com o alvo
-- (X, Z), o rumo do avião (RumoX, RumoZ) e o início do aviso (Inicio, relógio do servidor). O som
-- a4_mergulho (tools/som_ataque_aereo.py) já traz o Doppler de quem está no alvo; aqui ele anda pelo
-- céu na mesma reta (200 m/s, 250 m de altura, sobre o alvo aos 9 s), para vir de onde o avião vem.
-- Pelo marcador (replicado sempre), e não por remote: quem entra no meio ouve do ponto certo.
local A4 = { speedM = 200, altM = 250, passS = 9, clipS = 12 }
local flying: { [Instance]: boolean } = {}

-- D-185 (dono: "os eventos n estao acontecendo"): o A-4 que se vê, na mesma reta do som. Era só som.
-- Silhueta em peças no tamanho real (A-4C: 12,2 m de comprimento e 8,4 m de envergadura; cinza-gaivota
-- da Marinha) e o rastro escuro do motor J52, que ajuda a achar o avião no céu. PLACEHOLDER de forma.
local function a4Model(): Model
	local m = Instance.new("Model")
	m.Name = "VT65A4"
	local gray = Color3.fromRGB(168, 170, 166)
	local function part(name: string, sizeM: Vector3, at: CFrame, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = sizeM / M
		p.CFrame = at
		p.Color = gray
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.Parent = m
		return p
	end
	-- referencial: nariz em −Z, cima em +Y (CFrame.lookAt no rumo do voo)
	local body =
		part("A4Fuselagem", Vector3.new(12.2, 1.2, 1.2), CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
	part("A4Nariz", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 0, -6.1 / M), Enum.PartType.Ball)
	part("A4Asa", Vector3.new(8.4, 0.2, 3.2), CFrame.new(0, -0.3 / M, 0.6 / M))
	part("A4Profundor", Vector3.new(3.4, 0.15, 1.3), CFrame.new(0, 0.2 / M, 5.4 / M))
	part("A4Deriva", Vector3.new(0.15, 2.2, 2.0), CFrame.new(0, 1.3 / M, 5.0 / M))
	m.PrimaryPart = body
	body.PivotOffset = body.CFrame:Inverse() -- o pivô do modelo é o referencial do desenho
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3 / M, 0)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3 / M, 0)
	a1.Parent = body
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(Color3.fromRGB(70, 68, 62))
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.Lifetime = 2.5
	trail.WidthScale = NumberSequence.new(1, 3)
	trail.LightInfluence = 1
	trail.Parent = body
	return m
end
local function airPass(marker: Instance)
	local id = sid("a4_mergulho")
	if not id or flying[marker] or marker:GetAttribute("Evento") ~= "air" then
		return
	end
	local x, z = marker:GetAttribute("X"), marker:GetAttribute("Z")
	local t0 = marker:GetAttribute("Inicio")
	if type(x) ~= "number" or type(z) ~= "number" or type(t0) ~= "number" then
		return
	end
	local elapsed = workspace:GetServerTimeNow() - t0
	if elapsed > A4.clipS - 1 then
		return -- já passou
	end
	flying[marker] = true
	local rx, rz = marker:GetAttribute("RumoX"), marker:GetAttribute("RumoZ")
	local dir = Vector3.new(if type(rx) == "number" then rx else 1, 0, if type(rz) == "number" then rz else 0)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(1, 0, 0)
	local target = Vector3.new(x, 0, z)
	local hit = workspace:Raycast(target + Vector3.new(0, 500, 0), Vector3.new(0, -1000, 0))
	local gy = if hit then hit.Position.Y else 0
	local a = Instance.new("Attachment")
	a.Name = "A4"
	a.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 1.6
	s.SoundGroup = sfxGroup
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 300 / M -- o clipe já traz a distância: o Roblox só abafa de muito longe
	s.RollOffMaxDistance = 3000 / M
	s.Parent = a
	-- D-185: o avião que se vê, no mesmo ponto do som, com o nariz no rumo
	local plane = a4Model()
	local function place(t: number)
		local along = (t - A4.passS) * A4.speedM / M
		a.WorldPosition = Vector3.new(target.X, gy + A4.altM / M, target.Z) + dir * along
		local p = a.WorldPosition
		plane:PivotTo(CFrame.lookAt(p, p + dir))
	end
	place(math.max(elapsed, 0))
	plane.Parent = workspace
	s.TimePosition = math.max(elapsed, 0)
	s:Play()
	caption("a4", "Avião em mergulho: ataque aéreo chegando", a.WorldPosition)
	local con: RBXScriptConnection
	con = RunService.Heartbeat:Connect(function()
		local t = workspace:GetServerTimeNow() - t0
		if t > A4.clipS or not s.Parent then
			con:Disconnect()
			a:Destroy()
			plane:Destroy()
			flying[marker] = nil
			return
		end
		place(t)
		-- o clipe pode começar atrasado (carregando): no Studio ficou ~1,2 s atrás da posição.
		-- Ressincroniza para a passagem do som bater com a do ponto no céu
		if s.IsPlaying and math.abs(s.TimePosition - t) > 0.3 then
			s.TimePosition = t
		end
	end)
end
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("VT65Eventos", 60)
	if not folder then
		return
	end
	folder.ChildAdded:Connect(function(m: Instance)
		task.defer(airPass, m) -- os atributos chegam junto; o defer espera o quadro
	end)
	for _, m in folder:GetChildren() do
		airPass(m)
	end
end)

-- motor dos veículos: VehicleFx.client (tom e volume pela rotação e pela carga, D-86)

local _ = RunService
