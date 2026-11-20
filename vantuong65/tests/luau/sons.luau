--!strict
-- Kits de som (D-204; prompt de jogabilidade, §9): cada arma com o seu kit (tiro em 1ª e 3ª pessoa,
-- seco, recarga, ciclo, estojo) e os kits do campo; os trechos do Shared/SomKits (gerado por
-- tools/sons_armas.py) sem sobreposição; variação sem repetir a última; a recarga no tempo da
-- animação; o tiro previsto no cliente não toca de novo quando o servidor confirma.
-- Uso: lune run tests/luau/sons.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local SomArmas = require("../../src/ReplicatedStorage/Shared/SomArmas") :: any
local SomKits = require("../../src/ReplicatedStorage/Shared/SomKits") :: any

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FALHA " .. name .. ": " .. tostring(err))
	end
end

local ids = fs.readFile("src/ReplicatedStorage/Shared/AssetIds.luau")
local function idDe(kit: string): number
	return tonumber(string.match(ids, kit .. " = (%d+)")) or 0
end
local function tem(kit: string, trecho: string)
	local k = SomKits[kit]
	assert(k, "kit " .. kit)
	assert(k.seg[trecho], kit .. " sem o trecho " .. trecho)
end

test("toda arma tem kit publicado com 4 tiros próprios, 3 de outros, seco, recarga, ciclo e estojo", function()
	local n = 0
	for arma, a in SomArmas.ARMA do
		n += 1
		assert(idDe(a.kit) > 0, "id publicado: " .. a.kit)
		for v = 1, SomArmas.PROPRIO do
			tem(a.kit, "p" .. v)
		end
		for v = 1, SomArmas.OUTRO do
			tem(a.kit, "e" .. v)
		end
		tem(a.kit, "seco")
		assert(SomArmas.RECARGA[a.recarga], arma .. ": recarga " .. tostring(a.recarga))
		for _, e in SomArmas.RECARGA[a.recarga] do
			tem(a.kit, e[1])
		end
		if a.recarga == "tubo" then
			tem(a.kit, "cartucho")
		end
		if a.ciclo then
			tem(a.kit, "ciclo")
		end
		if a.estojo then
			tem(a.kit, "estojo1")
			tem(a.kit, "estojo2")
		end
	end
	assert(n == 12, "12 armas de fogo: " .. n)
	-- kits diferentes: nenhuma arma toca o kit de outra (a identidade não é só o tom)
	local visto = {}
	for arma, a in SomArmas.ARMA do
		assert(not visto[a.kit], arma .. " repete " .. a.kit)
		visto[a.kit] = true
	end
end)

test("kits do campo: caudas por família e lugar, distância, bala, passos, impactos, explosões e pazadas", function()
	for _, kit in
		{ "kit_caudas", "kit_distancia", "kit_balas", "kit_passos", "kit_impactos", "kit_explosoes", "kit_campo" }
	do
		assert(idDe(kit) > 0, "id publicado: " .. kit)
	end
	for _, fam in { "fuzil", "pistola", "pesado" } do
		for _, lug in SomArmas.LUGARES do
			for v = 1, SomArmas.CAUDAS do
				tem("kit_caudas", SomArmas.cauda(fam, lug, v))
			end
		end
		for _, faixa in { "medio", "longe" } do
			for v = 1, SomArmas.DISTANCIA do
				tem("kit_distancia", SomArmas.distante(fam, faixa, v))
			end
		end
	end
	for v = 1, 3 do
		tem("kit_balas", "estalo" .. v)
		tem("kit_balas", "zunido" .. v)
		tem("kit_explosoes", "granada" .. v)
	end
	for _, k in { "acerto_corpo", "acerto_cabeca", "acerto_abate" } do
		tem("kit_balas", k)
	end
	for _, chao in SomArmas.CHAO do
		for v = 1, SomArmas.PASSOS do
			tem("kit_passos", chao .. v)
		end
	end
	for _, mat in SomArmas.IMPACTO do
		for v = 1, SomArmas.IMPACTOS do
			tem("kit_impactos", mat .. v)
		end
	end
	for v = 1, SomArmas.IMPACTOS do
		tem("kit_impactos", "carne" .. v)
	end
	for v = 1, 2 do
		tem("kit_explosoes", "pesada" .. v)
		tem("kit_explosoes", "eco" .. v)
	end
	for v = 1, 4 do
		tem("kit_campo", "pazada" .. v)
	end
end)

test("trechos: dentro do arquivo, sem sobreposição, com 50 ms de silêncio entre eles e a âncora dentro", function()
	local total = 0
	for kit, k in SomKits do
		local lista = {}
		for nome, s in k.seg do
			table.insert(lista, { nome = nome, a = s[1], len = s[2], anc = s[3] })
			total += 1
		end
		table.sort(lista, function(x, y)
			return x.a < y.a
		end)
		for i, s in lista do
			assert(s.a >= 0 and s.len > 0 and s.a + s.len <= k.dur + 1e-6, kit .. "/" .. s.nome .. " fora do arquivo")
			assert(s.anc >= 0 and s.anc <= s.len, kit .. "/" .. s.nome .. " âncora")
			local prox = lista[i + 1]
			if prox then
				assert(prox.a - (s.a + s.len) >= 0.05 - 1e-6, kit .. ": " .. s.nome .. " encosta em " .. prox.nome)
			end
		end
	end
	assert(total >= 250, "trechos: " .. total)
end)

test("variação: nunca a mesma duas vezes seguidas e todas aparecem", function()
	for _, n in { 2, 3, 4, 6 } do
		local ultima: number? = nil
		local contou = {}
		local seed = 7
		for _ = 1, 400 do
			seed = (seed * 1103515245 + 12345) % 2147483648
			local v = SomArmas.sorteia(n, ultima, seed / 2147483648)
			assert(v >= 1 and v <= n, "fora")
			assert(v ~= ultima, string.format("repetiu %d (n %d)", v, n))
			contou[v] = (contou[v] or 0) + 1
			ultima = v
		end
		for v = 1, n do
			assert((contou[v] or 0) > 400 / n * 0.5, string.format("n %d: %d saiu %d vezes", n, v, contou[v] or 0))
		end
	end
	assert(SomArmas.sorteia(1, 1, 0.5) == 1)
	assert(SomArmas.sorteia(4, 9, 0.99) == 4, "última inválida")
	assert(SomArmas.sorteia(4, 4, 0.999) == 3 and SomArmas.sorteia(4, 1, 0) == 2)
end)

test("recarga no tempo da animação: âncora na fração, em ordem, e acaba antes do fim", function()
	for arma, a in SomArmas.ARMA do
		local k = SomKits[a.kit]
		for _, dur in { 2.0, 2.4, 5.0, 5.5 } do
			local ag = SomArmas.agenda(a.recarga, dur, function(trecho: string): number
				return k.seg[trecho][3]
			end)
			assert(#ag == #SomArmas.RECARGA[a.recarga], arma)
			local antes = -1
			for i, p in ag do
				assert(p.t >= 0, arma .. ": negativo")
				assert(p.t >= antes - 0.03, string.format("%s: %s fora de ordem a %.1f s", arma, p.trecho, dur))
				antes = p.t
				local fr = SomArmas.RECARGA[a.recarga][i][2]
				local seg = k.seg[p.trecho]
				-- a âncora cai na fração (salvo quando o trecho começaria antes de 0)
				if fr * dur >= seg[3] then
					assert(math.abs(p.t + seg[3] - fr * dur) < 1e-6, arma .. ": âncora")
				end
				assert(p.t + seg[2] <= dur + 0.45, string.format("%s: %s passa do fim a %.1f s", arma, p.trecho, dur))
			end
		end
	end
	-- caixa: o encaixe do carregador cai em 0,64 da recarga (WeaponVisuals: o novo some dentro da arma)
	local m14 = SomKits.kit_m14.seg
	local ag = SomArmas.agenda("caixa", 2.4, function(t: string): number
		return m14[t][3]
	end)
	for _, p in ag do
		if p.trecho == "entra" then
			assert(math.abs(p.t + m14.entra[3] - 0.64 * 2.4) < 1e-6)
		end
	end
end)

test("amarras: o tiro próprio só pelo Bus, o servidor não devolve o traçante a quem atirou", function()
	local cs = fs.readFile("src/ServerScriptService/Modules/CombatService.luau")
	assert(string.find(cs, "if other ~= exceptPlayer then", 1, true), "o traçante não volta para quem atirou")
	local ac = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/AudioController.client.luau")
	for _, t in
		{
			'Bus.on("shot_fired"',
			'Som.kit(a.kit, "p" .. variacao(a.kit .. "p", SomArmas.PROPRIO)',
			'Som.kit(a.kit, "e" .. variacao(a.kit .. "e", SomArmas.OUTRO)',
			'vaga = "cauda_propria"',
			'Bus.on("reload_start"',
			'Bus.on("dry_fire"',
			"duck.SideChain = shotGroup",
		}
	do
		assert(string.find(ac, t, 1, true), "AudioController: " .. t)
	end
	-- nada da biblioteca de antes (classe com o tom trocado, corpo uma oitava abaixo, eco de efeito)
	for _, t in { "SomArmas.LIB", "a.pitch * 0.55", "EchoSoundEffect" } do
		assert(not string.find(ac, t, 1, true), "AudioController ainda usa " .. t)
	end
	local som = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/Som.luau")
	assert(string.find(som, "s.PlaybackRegion = NumberRange.new(seg[1], seg[1] + seg[2])", 1, true))
	assert(string.find(som, "TweenInfo.new(0.08", 1, true), "a cauda velha some em 80 ms, sem corte seco")
	assert(not string.find(som, "EchoSoundEffect", 1, true) and not string.find(som, "ReverbSoundEffect", 1, true))
	local wc = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/WeaponController.client.luau")
	assert(not string.find(wc, "S.reload_m14", 1, true), "recarga pelo kit, não pelo lado")
	local _, secos = string.gsub(wc, 'Bus.fire%("dry_fire", wp.id%)', "")
	assert(secos == 2, "clique seco da arma: " .. secos)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
