--!strict
-- Tradução da interface (D-84). Cada texto que vai para a tela é traduzido na hora pelo
-- dicionário do idioma escolhido (Shared/Lang). O português é guardado: trocar o idioma no menu
-- retraduz tudo o que está aberto.
--
-- O que é coberto:
--   * TextLabel e TextButton do PlayerGui;
--   * TextLabel e TextButton dentro de SurfaceGui e BillboardGui no workspace (folhas e placas do
--     lobby, marcadores, rótulos de alvo, placas do mapa);
--   * TextBox: só o PlaceholderText (o que o jogador digita nunca é traduzido);
--   * ProximityPrompt (ActionText e ObjectText, que o próprio Roblox desenha): troca local, só do
--     prompt que está na tela (ProximityPromptService.PromptShown).
--
-- Custo no mapa (dezenas de milhares de instâncias): nada de varrer o workspace a cada mudança.
--   * uma leitura única no começo, em fatias (cede o quadro a cada FATIA itens);
--   * depois só o DescendantAdded do workspace, que olha o ClassName de cada instância nova e
--     ignora tudo que não é TextLabel, TextButton ou TextBox;
--   * os prompts não são varridos: entram quando aparecem na tela.
--
-- Fonte (vietnamita): as fontes de época (SpecialElite, Oswald, Gotham...) não têm todas as letras
-- vietnamitas. Com o idioma "vi", se o texto tem letra de U+0100 a U+1FFF e a fonte do rótulo não
-- é uma das seguras, a FontFace passa para a Arimo (peso e estilo mantidos). Texto sem essas letras,
-- ou outro idioma, devolve a fonte original.
--
-- Idioma: opção "Idioma" do menu (padrão "automático" = idioma da conta Roblox; sem dicionário,
-- inglês).
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage.Shared.Lang)
local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local dataFolder = ReplicatedStorage.Shared:FindFirstChild("LangData")

local tables: { [string]: Lang.Table } = {}
local current = "pt"
local tbl: Lang.Table? = nil

local SLICE = 2500 -- instâncias lidas por quadro na leitura única do workspace
local ARIMO = "rbxasset://fonts/families/Arimo.json"
-- famílias que têm as letras vietnamitas; qualquer outra é trocada pela Arimo quando preciso
local VIET_SAFE = { "Arimo", "Roboto" }

type TextObj = TextLabel | TextButton
type WithFont = TextLabel | TextButton | TextBox
local function weak<K, V>(): { [K]: V }
	return setmetatable({}, { __mode = "k" }) :: any
end
local orig: { [TextObj]: string } = weak() -- português de cada rótulo/botão
local shown: { [TextObj]: string } = weak() -- o que está escrito agora (a tradução)
local hintOrig: { [TextBox]: string } = weak() -- português do PlaceholderText
local hintShown: { [TextBox]: string } = weak()
local fontOrig: { [WithFont]: Font } = weak() -- fonte original dos rótulos que trocaram para a Arimo

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

local function tr(src: string): string
	local t = tbl
	if t then
		return Lang.translate(t, src) or src
	end
	return src
end

-- ===== fonte do vietnamita =====
local function lacksViet(face: Font): boolean
	for _, name in VIET_SAFE do
		if string.find(face.Family, name, 1, true) then
			return false
		end
	end
	return true
end

local function fixFont(obj: WithFont, text: string)
	local saved = fontOrig[obj]
	local any = obj :: any -- (o verificador não escreve FontFace em união de classes)
	if current == "vi" and Lang.needsWide(text) then
		local face = any.FontFace :: Font
		if lacksViet(face) then
			fontOrig[obj] = face
			any.FontFace = Font.new(ARIMO, face.Weight, face.Style)
		end
	elseif saved then
		fontOrig[obj] = nil
		any.FontFace = saved
	end
end

-- ===== TextLabel e TextButton =====
local function render(obj: TextObj, src: string)
	orig[obj] = src
	local out = tr(src)
	shown[obj] = out
	if obj.Text ~= out then
		(obj :: any).Text = out -- (o verificador não escreve em união de classes)
	end
	fixFont(obj, out)
end

local function onText(obj: TextObj)
	local text = obj.Text
	if shown[obj] == text then
		return -- a própria tradução escrevendo
	end
	render(obj, text)
end

-- ===== TextBox: só o PlaceholderText =====
local function renderHint(box: TextBox, src: string)
	hintOrig[box] = src
	local out = tr(src)
	hintShown[box] = out
	if box.PlaceholderText ~= out then
		box.PlaceholderText = out
	end
	fixFont(box, out)
end

local function onHint(box: TextBox)
	local text = box.PlaceholderText
	if hintShown[box] == text then
		return
	end
	renderHint(box, text)
end

local watched: { [Instance]: boolean } = weak()
local function watch(inst: Instance)
	if watched[inst] then
		return
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		watched[inst] = true
		local obj = inst :: TextObj
		onText(obj)
		obj:GetPropertyChangedSignal("Text"):Connect(function()
			onText(obj)
		end)
	elseif inst:IsA("TextBox") then
		watched[inst] = true
		local box = inst :: TextBox
		onHint(box)
		box:GetPropertyChangedSignal("PlaceholderText"):Connect(function()
			onHint(box)
		end)
	end
end

local function watchTree(root: Instance)
	for _, d in root:GetDescendants() do
		watch(d)
	end
	root.DescendantAdded:Connect(watch)
end

-- ===== ProximityPrompt (ActionText e ObjectText, desenhados pelo Roblox) =====
type PromptRec = { a: string, o: string, ta: string, to: string, conns: { RBXScriptConnection } }
local prompts: { [ProximityPrompt]: PromptRec } = weak()
local onScreen: { [ProximityPrompt]: boolean } = weak() -- os que estão na tela agora

local function renderPrompt(p: ProximityPrompt)
	local act, obj = p.ActionText, p.ObjectText
	local rec = prompts[p]
	if not rec then
		rec = { a = act, o = obj, ta = act, to = obj, conns = {} }
		prompts[p] = rec
	else
		-- o texto que está lá não é o que escrevemos: o servidor trocou, vira o novo português
		if act ~= rec.ta then
			rec.a = act
		end
		if obj ~= rec.to then
			rec.o = obj
		end
	end
	local ta, to = tr(rec.a), tr(rec.o)
	rec.ta, rec.to = ta, to
	if p.ActionText ~= ta then
		p.ActionText = ta
	end
	if p.ObjectText ~= to then
		p.ObjectText = to
	end
end

ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
	onScreen[prompt] = true
	renderPrompt(prompt)
	local rec = prompts[prompt]
	if rec and #rec.conns == 0 then
		-- enquanto está na tela, uma troca de texto vinda do servidor também é traduzida
		table.insert(
			rec.conns,
			prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
				renderPrompt(prompt)
			end)
		)
		table.insert(
			rec.conns,
			prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
				renderPrompt(prompt)
			end)
		)
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
	onScreen[prompt] = nil
	local rec = prompts[prompt]
	if rec then
		for _, c in rec.conns do
			c:Disconnect()
		end
		table.clear(rec.conns)
	end
end)

-- ===== idioma =====
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
	for box, src in hintOrig do
		if box.Parent then
			renderHint(box, src)
		end
	end
	for p in onScreen do
		if p.Parent then
			renderPrompt(p)
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

-- ===== SurfaceGui e BillboardGui no workspace =====
-- Só os textos: um TextLabel/TextButton/TextBox no workspace só aparece dentro de um SurfaceGui ou
-- BillboardGui. O ClassName é a checagem mais barata que existe.
local TEXT_CLASS = { TextLabel = true, TextButton = true, TextBox = true } :: { [string]: boolean }

workspace.DescendantAdded:Connect(function(inst: Instance)
	if TEXT_CLASS[inst.ClassName] then
		watch(inst)
	end
end)

-- leitura única do que já estava lá (lobby, placas do mapa), em fatias para não travar o quadro
task.spawn(function()
	local all = workspace:GetDescendants()
	for i, d in all do
		if TEXT_CLASS[d.ClassName] then
			watch(d)
		end
		if i % SLICE == 0 then
			task.wait()
		end
	end
end)
