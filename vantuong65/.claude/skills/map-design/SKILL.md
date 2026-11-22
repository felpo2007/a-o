---
name: map-design
description: >
  Projeta, monta e revisa lugares e rotas dos mapas do STARLITE (Vale das Cinco Passagens, Estrada
  do Bambu e mapa principal): planta, pátio de captura, coberturas, visadas, chegada, interiores,
  densidade e cenas do Comboio. Use antes de alterar tools/mapas_ret.py ou construir um setor.
---

# Map design do STARLITE

Skill própria do projeto. O método geral de fases e ritmo está na skill `level-design`.

## Antes de desenhar
1. Dados atuais: `uv run python tools/kb.py mapa <frente|comboio> [setor]`.
2. Contexto: `knowledge/World/Map-Index.md` e a nota do mapa. O pedido do lugar fica em
   `especificacao/mapas_retangulares/PROMPT.txt` (fora do Git).
3. Reaproveite: `uv run python tools/kb.py ativo <termo>` antes de criar um modelo.

## Ordem de trabalho
1. **Função do lugar:** identidade, entradas, percurso lateral, interior que conecta dois acessos e
   a visada longa que precisa ser cortada.
2. **Planta:** feche a captura com construções a 12-18 m do centro (`miolo`). Deixe o centro livre e
   ponha proteção baixa perto dele. Muros e cercas entram por último (`muros`).
3. **Terreno:** `cais` (base no fundo do rio), `canais`, `NIVEL_DO_PATIO` e `pracas_extra`.
4. **Gerar e conferir:** `uv run --group arte python tools/mapas_ret.py <id>` sem avisos e
   `lune run tools/mapas_check.luau` com `problemas: 0`. Olhe a planta antes de abrir o Studio.
5. **No Studio:** fotografe chegada, interior e percurso lateral. Ande pelas portas e escadas e
   deixe os bots rodarem pelo menos duas janelas de 80 s, contando os parados.
6. **Ficha:** oito critérios com `aprovado`, `corrigir` ou `não verificado`, com a evidência.

## Armadilhas já vistas (`knowledge/Bugs-Lessons/Licoes.md`)
- O pivô do modelo é o centro da caixa, não a origem da receita.
- Confira o vão com 2,07 m de soldado: treliça e divisória já travaram uma escada.
- Rota "ok" do Pathfinding não prova nada: o alvo precisa estar dentro do cômodo.
- Pátio a 25-30 m do centro parece deserto, mesmo com modelos bons.
- Não use nome, layout ou mapa de outro jogo.
