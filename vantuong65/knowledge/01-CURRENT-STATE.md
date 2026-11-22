---
project: STARLITE
type: state
status: verified
source_paths:
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Estado atual

Compacto de propósito. Detalhe lote a lote: `PROGRESS.md`.

## No ar
- **v150** (versão 155 do place, lote 118, D-249), do commit `3be7fed`.
- A capa da página é o key art STARLITE: Vietnã 1965 (ícone e primeira miniatura).
- O jogo publicado usa só o [[Mapa-Principal]] de 700 × 700 m.

## Em andamento: pedidos de 22/11 (D-246)
Feito: jogo, moedas, bandeiras, janelas e capa (v147), carreira (D-247), luz (D-248) e materiais (D-249).
Falta: telas no estilo das imagens, Comboio e áudios da Toolbox.

## Em andamento: D-243, dois mapas retangulares (sem publicar)
`MapasRet.LIBERADOS = false`: só abrem no Studio, com `VT65DevMapa`.

| Parte | Situação |
|---|---|
| Regras, modos, HUD, nascer, carta, votação | Feitas e testadas no Studio |
| [[Vale-das-Cinco-Passagens]]: cinco lugares | 1ª versão no commit `5f83094` |
| [[Estrada-do-Bambu]]: cinco cenas | **Pendente** (hoje usa casas genéricas) |
| Teleporte entre mapas, dois jogadores, celular | **Não testado** |
| Qualidade alta e fps | **Não medido** |

## Prioridades
1. Cinco cenas do Comboio, no padrão do Vale.
2. Corrigir o que as fichas do Vale marcaram (`testes/D-243_vale_2026-11-22.md`).
3. Teste com dois jogadores, teleporte e desempenho, antes de liberar os mapas.

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
