---
project: STARLITE
type: state
status: verified
source_paths:
last_verified: 2026-11-23
verified_commit: 2e9fa42
---
# Estado atual

Compacto de propósito. Detalhe lote a lote: `PROGRESS.md`.

## No ar
- **v152** (versão 157 do place, lote 120, D-251 e D-252), do commit `d373747`.
- A capa da página é o key art STARLITE: Vietnã 1965 (ícone e primeira miniatura).
- O jogo publicado usa só o [[Mapa-Principal]] de 700 × 700 m.

## Foco atual: reconstrução da Vila, setor piloto (D-253 a D-255)
Lotes 121 e 122 no Git, **sem publicar**. `VilaPiloto.LIGADA = false`; no Studio, `VT65DevPiloto = true`.
Setor de 88 x 88 m pronto para o dono ver. Não expandir antes da aprovação. Situação em `docs/PILOT_ACCEPTANCE.md`.

## Em andamento: pedidos de 22/11 (D-246)
Feito: jogo, moedas, bandeiras, janelas e capa (v147), carreira (D-247), luz (D-248), materiais (D-249) e
telas em preto e latão (D-250), cenas do Comboio (D-251) e áudios da biblioteca (D-252).
Falta: liberar o Comboio, depois do teste com duas pessoas e do teleporte.

## Em andamento: D-243, dois mapas retangulares (sem publicar)
`MapasRet.LIBERADOS = false`: só abrem no Studio, com `VT65DevMapa`.

| Parte | Situação |
|---|---|
| Regras, modos, HUD, nascer, carta, votação | Feitas e testadas no Studio |
| [[Vale-das-Cinco-Passagens]]: cinco lugares | 1ª versão no commit `5f83094` |
| [[Estrada-do-Bambu]]: cinco cenas | 1ª versão (D-251), fichas em `testes/LOTE120_D251-252_2026-11-22.md` |
| Teleporte entre mapas, dois jogadores, celular | **Não testado** |
| Qualidade alta e fps | **Não medido** |

## Prioridades
1. Teste com dois jogadores, teleporte e desempenho, antes de liberar os mapas.
2. Corrigir o que as fichas do Vale marcaram (`testes/D-243_vale_2026-11-22.md`).
3. Andar pelas portas e escadas dos prédios novos do Comboio e medir visadas.

## Bloqueios e dependências do dono
- Itens em `TODO_USUARIO.md`.
- O Obsidian não está instalado neste PC. A base funciona sem ele; para navegar, instale e abra a
  pasta `knowledge` como cofre.
- O repositório guarda dois projetos: o de trade na raiz e o jogo em `vantuong65/`. O `CLAUDE.md` da
  raiz entra em toda sessão do jogo. Separar é decisão do dono (`TODO_USUARIO.md`, item 7).

## Riscos confirmados no código (ainda sem correção)
Achados ao documentar. Detalhes em [[Rede-e-Seguranca]], [[Progressao-e-Economia]] e [[Combate]].
- **Clarão da torreta:** `BotService.start` envolve `CombatService.fire` sem repassar o argumento
  `boca`. Com os bots ligados, o clarão deve sair da arma do soldado (não visto no Studio).
- **`Commerce_Track`:** sem limite de taxa nem de tamanho no `item`, que vai ao `AnalyticsService`.
- **Recompensa diária:** o dia é gravado antes dos créditos, que ficam em memória até o próximo
  save. Uma queda do servidor nesse intervalo perde os créditos do dia.
- **Códigos de resgate:** a lista está em `Shared/Codigos`, que o cliente consegue ler.
- **`Suprimento_Comprar`:** sem o `guard` de frequência. A venda paga segue desligada.

## Remodelagens ainda pedidas (lote de 21/11)
Soldados, casas e vegetação; imagens do catálogo de acabamentos.
