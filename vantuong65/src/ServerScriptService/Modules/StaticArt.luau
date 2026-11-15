--!strict
-- GERADO por tools/estatico.py (D-155). Não edite à mão: rode o script de novo.
-- Arte fixa no arquivo do place (SLIM): chave e pivô de cada modelo de
-- src/Workspace/Estatico. O AssetLoader não põe a cópia de mesma chave cujo pivô cai a
-- menos de StaticArt.TOL studs (e devolve a fixa no lugar).

export type Entry = { key: string, x: number, y: number, z: number }

local StaticArt = {}
StaticArt.TOL = 1
StaticArt.items = {} :: { Entry }

return StaticArt
