---
project: STARLITE
type: handoff
status: verified
source_paths:
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Passagem de sessão

Substitua este arquivo ao fim de cada sessão. No máximo 25 linhas.

- **Foco:** prompt V5, área piloto da Vila (Objetivo C). **Não expandir sem a aprovação visual do dono.**
- **No ar:** v152, sem nada da V5. O lote 121 (D-253 e D-254) está no Git e não foi publicado.
- **Ver o piloto:** no Edit, `workspace:SetAttribute("VT65DevPiloto", true)` e Play. Para o capim parado valer,
  rode `workspace.Terrain.Decoration = false` no cliente.
- **Passou:** autoteste 18 de 18 com bots, captura pelo VC, escada e porta, vento zero, Lune 1.014, pytest 84.
- **Não testado:** fps real, duas pessoas, celular, controle, SLIM, streaming andando, captura pelos EUA.
- **Custo:** a Vila ficou de 25% a 38% mais cara em chamadas e de 65% a 125% em triângulos. Maior parte a mais de 130 m.
- **Defeitos:** janela lateral escura por dentro (aba de bambu); grama nativa ainda se mexe no build normal.
- **Decisões do dono:** visual; lados das bases; desligar a grama nativa no mapa inteiro.
- **Antes e depois:** `testes/lote121/antes_depois.jpg`. Relatório: `testes/LOTE121_D253-254_2026-11-22.md`.
- **Foto no Studio:** dispare o spawn logo após `TerrainReady`; com o menu aberto o sol fica preso às 17 h.
- **Comboio:** continua fechado (`MapasRet.LIBERADOS = false`).
- **Abra a próxima sessão na pasta `vantuong65`**: só assim as skills do projeto aparecem.
- **Próxima ação:** esperar a resposta do dono sobre o piloto.
