---
project: STARLITE
type: handoff
status: verified
source_paths:
last_verified: 2026-11-23
verified_commit: 2e9fa42
---
# Passagem de sessão

Substitua este arquivo ao fim de cada sessão. No máximo 25 linhas.

- **Foco:** reconstrução artística da Vila, setor piloto de 88 x 88 m (D-255). **Não expandir sem a aprovação do dono.**
- **No ar:** v152, sem nada da V5. Os lotes 121 e 122 estão no Git e não foram publicados.
- **Ver o piloto:** no Edit, `workspace:SetAttribute("VT65DevPiloto", true)` e Play.
- **Planta:** `cd tools; uv run --group arte python vila_piloto_plano.py --gravar`. Plantas: `tools/vila_plantas.py`.
- **Passou:** captura pelos EUA, caminhada em 6 rotas, bots sem travar no setor, 0 erro de script, `verifica.ps1`.
- **Intermitente:** granada de bot no autoteste falhou em 2 de 4 rodadas com o setor. Causa não isolada.
- **Não testado:** fps real, duas pessoas, celular, controle, SLIM, streaming a pé, escadas neste lote.
- **Custo:** de 35% a 59% mais chamadas e de 49% a 87% mais triângulos nas vistas da Vila.
- **Falta na arte:** chão nu em 62% das imagens (meta 35%); chão molhado; a qualidade segue abaixo da referência.
- **Risco:** avisos `TexturePack (429)` no Studio; uma sessão ficou com o pagode sem textura.
- **Decisões do dono:** visual; lados das bases; desligar a grama nativa no mapa inteiro.
- **Antes e depois:** `testes/lote122/antes_depois.jpg`. Relatório: `testes/LOTE122_D255_2026-11-23.md`.
- **Foto no Studio:** dispare o spawn logo após `TerrainReady`; com o menu aberto o sol fica preso às 17 h.
- **Autoteste:** use um Play novo a cada rodada; repetir na mesma sessão invalida a granada.
- **Comboio:** continua fechado (`MapasRet.LIBERADOS = false`).
- **Abra a próxima sessão na pasta `vantuong65`**: só assim as skills do projeto aparecem.
- **Próxima ação:** esperar a resposta do dono sobre o piloto.
