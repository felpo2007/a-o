--!strict
-- D-240: as cenas da tela de carregamento. O ReplicatedFirst roda antes de o ReplicatedStorage chegar,
-- então os IDs de `AssetIds.Capas` ficam copiados aqui (o teste `telas.luau` confere que são os mesmos).
return {
	127113724350027, -- fuzileiros olham o arrozal e a vila
	75529421549577, -- patrulha entre as casas
	102077571679866, -- combate na vila debaixo de chuva
	108723457521434, -- trincheira em 1ª pessoa
	121763364440920, -- patrulha noturna no bambuzal
	102197151301930, -- travessia do riacho na mata
	106648597763688, -- posto de comando, rádio e carta
} :: { number }
