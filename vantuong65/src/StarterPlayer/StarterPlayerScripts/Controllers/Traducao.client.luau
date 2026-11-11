--!strict
-- Tradução da interface (D-84). Cada texto que vai para a tela (rótulos e botões da interface, as
-- folhas 3D do lobby) é traduzido na hora pelo dicionário do idioma escolhido (Shared/Lang). O
-- português é guardado: trocar o idioma no menu retraduz tudo o que está aberto.
-- Idioma: opção "Idioma" do menu (padrão "automático" = idioma da conta Roblox; sem dicionário,
-- inglês). Caixas de texto (o que o jogador digita) nunca são traduzidas.
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage.Shared.Lang)
local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local dataFolder = ReplicatedStorage.Shared:FindFirstChild("LangData")

local tables: { [string]: Lang.Table } = {}
local current = "pt"
local tbl: Lang.Table? = nil

type TextObj = TextLabel | TextButton
local orig: { [TextObj]: string } = setmetatable({}, { __mode = "k" }) :: any
local shown: { [TextObj]: string } = setmetatable({}, { __mode = "k" }) :: any

local function load(code: string): Lang.Table?
	if code == "pt" then
		return nil
	end
	if tables[code] then
		return tables[code]
	end
	local m = dataFolder and dataFolder:FindFirstChild(code)
	if not (m and m:IsA("ModuleScript")) then
		return nil
	end
	local ok, dict = pcall(require, m)
	if not ok or type(dict) ~= "table" then
		warn("[VT65] dicionário de idioma com erro: " .. code)
		return nil
	end
	local t = Lang.compile(dict :: any)
	tables[code] = t
	return t
end

local function render(obj: TextObj, src: string)
	orig[obj] = src
	local out = src
	local t = tbl
	if t then
		out = Lang.translate(t, src) or src
	end
	shown[obj] = out
	if obj.Text ~= out then
		(obj :: any).Text = out -- (o verificador não escreve em união de classes)
	end
end

local function onText(obj: TextObj)
	local text = obj.Text
	if shown[obj] == text then
		return -- a própria tradução escrevendo
	end
	render(obj, text)
end

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function watch(inst: Instance)
	if watched[inst] or not (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
		return
	end
	watched[inst] = true
	local obj = inst :: TextObj
	onText(obj)
	obj:GetPropertyChangedSignal("Text"):Connect(function()
		onText(obj)
	end)
end

local function watchTree(root: Instance)
	for _, d in root:GetDescendants() do
		watch(d)
	end
	root.DescendantAdded:Connect(watch)
end

local function pick(): string
	local want = Input.settings.lang
	if want == "auto" then
		local ok, id = pcall(function()
			return LocalizationService.RobloxLocaleId
		end)
		return Lang.fromLocale(if ok then id else nil)
	end
	return want
end

local function setLanguage(code: string)
	if code == current then
		return
	end
	current = code
	tbl = load(code)
	player:SetAttribute("Lang", code)
	for obj, src in orig do
		if obj.Parent then
			render(obj, src)
		end
	end
end

-- antes de olhar a tela: o idioma da conta (a configuração salva chega logo depois)
current = "pt"
setLanguage(pick())
player:SetAttribute("Lang", current)
Input.SettingsChanged:Connect(function()
	setLanguage(pick())
end)

watchTree(player:WaitForChild("PlayerGui"))
-- folhas e etiquetas 3D do lobby (LobbyScene: pastas VT65Lobby…)
local function watchLobby(c: Instance)
	if string.sub(c.Name, 1, 9) == "VT65Lobby" then
		watchTree(c)
	end
end
for _, c in workspace:GetChildren() do
	watchLobby(c)
end
workspace.ChildAdded:Connect(watchLobby)
