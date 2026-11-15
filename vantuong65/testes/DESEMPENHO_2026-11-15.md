# Desempenho e beleza do mapa: medir, mexer no que pesa, medir de novo (lote 37, 2026-11-15)

Pedido do dono: aplicar um texto sobre beleza e desempenho do mapa. O texto pede:
- medir antes e depois;
- sombra só no que importa;
- simplificar o que está longe;
- colisões simples nos objetos;
- cuidado com a transparência da folhagem;
- reuso de modelos;
- detalhe concentrado nos caminhos, interiores e objetivos.

## Como foi medido
- **Onde:** Studio pelo MCP, sem bots (`BotFill` 0), seis vistas fixas a 1,7 m do chão:
  - base dos EUA olhando o oeste;
  - Xóm Gò olhando a mata B;
  - dentro da mata B (Serraria);
  - ponte D olhando o norte;
  - arrozal A olhando o leste;
  - base do VC olhando o leste.
- **Qualidade gráfica fixa:** nível 10 (perto do PC) e nível 3 (perto do que o Roblox escolhe num
  aparelho fraco). Com a qualidade no automático, o Studio atrás de outra janela baixa sozinho a
  qualidade e a sombra some da conta.
- **O que conta:** chamadas de desenho da cena e da sombra e triângulos por quadro
  (`Stats.SceneDrawcallCount`, `ShadowsDrawcallCount`, `SceneTriangleCount`,
  `ShadowsTriangleCount`). Para cada mudança, um teste A/B na mesma vista, alternando com e sem.

**Limite desta medida:** o dono estava usando o computador, então o Studio ficou atrás de outra
janela (o fps trava em 15). O tempo de CPU e de GPU por quadro mudava entre dois regimes, ~12 ms e
~25–30 ms de CPU, sem relação com o que estava sendo testado. Por isso o antes e depois é por
chamadas e triângulos, e não por fps. O fps no aparelho fica com o dono (o contador no canto da
tela).

## O que pesa (nível 10, escondendo cada parte; triângulos em mil)
| Parte (peças) | Base EUA | Mata B | Base VC |
|---|---|---|---|
| Casas e objetos (934) | −1.555 | ~0 | −660 |
| Outras plantas: bambu, palmeira, capim-elefante, bananeira, taioba, tràm (2.317) | −1.340 | −620 | −1.314 |
| Folhas das árvores, com transparência (2.101) | −429 | −568 | −433 |
| Madeira das árvores (4.202) | −437 | ~0 | −298 |
| Arbustos (853) | −347 | −706 | −460 |
| Sombra do sol (chamadas de sombra) | 187 → 0 | 203 → 0 | 461 → 0 |

- No nível 3, na base dos EUA (3,0 milhões de triângulos), casas e objetos eram 1,39 milhão. Quase
  tudo era a **cerca de bambu**: 62 das 65 cercas ficam em An Cường (2), na frente da base, com
  16.418 triângulos cada. Esconder só as cercas tirou 1,12 milhão de triângulos no nível 10 e 0,73
  milhão no nível 3.
- **Folhagem com transparência:** esconder as 2.101 folhas mudou a GPU em menos de 1 ms. Não é o
  gargalo neste PC (a GPU ficou entre 1 e 5,5 ms por quadro).
- **Física:** no servidor, 0,045 ms por passo com 25.301 peças paradas, e o batimento em 0,14 ms.
  As colisões dos objetos não pesam hoje.
- **Reuso:** 12.044 malhas no mapa, de 759 modelos diferentes; o Roblox desenha as iguais juntas
  (100 a 290 chamadas de cena por vista).
- **Distância:** todas as malhas já estão com `RenderFidelity` automática (detalhe menor longe). O
  `LevelOfDetail` do modelo não pode ser ligado por script (D-57).

## O que mudou (v82)
1. **Sombra das árvores respeitando a opção** (defeito):
   - **O defeito:** a folha das árvores prontas fica num submodelo, e o cliente procurava a marca
     `PlantShadow` só no modelo mais perto. Com "Sombra das árvores: desligada" (o padrão), as copas
     que chegavam pelo streaming ficavam com sombra: 586 copas numa sessão do Studio.
   - **Agora:** a planta sai do servidor sem sombra, e o cliente liga ou desliga subindo até o modelo
     marcado.
   - **No Studio:** com a opção desligada, 0 peças de copa com sombra; ligada, as 1.758; desligada
     de novo, 0.
   - **A/B:** de 8 a 52 chamadas de sombra e até 260 mil triângulos a menos por quadro.
2. **Cerca de bambu com 6 mil triângulos** (era 16.418):
   - mesma redução das plantas (`tools/vegetacao_6k.py`, D-135);
   - desvio máximo de 1,4 cm na malha; de perto, no Studio, a cerca continua igual.
3. **Cortina de fora da área sem tronco invisível:** 1.754 peças a menos. As plantas da cortina não
   têm colisão (ninguém chega lá).

## O que foi testado e não entrou
- **Sombra só nos objetos grandes:** desligar a sombra dos 148 objetos pequenos (potes, sacos,
  caixas, arame farpado, varal, placas) não mudou as chamadas de sombra (242 → 247 e 476 → 467) e
  tirou no máximo 90 mil triângulos. O Roblox já desenha os iguais juntos. Ficou como estava.
- **Colisão simples nos objetos:** a física custa 0,045 ms por passo. Script também não muda o
  `CollisionFidelity`. Vale medir de novo com 60 jogadores num servidor do Roblox.

## Antes e depois (triângulos por quadro, em milhões)
| Vista | Nível 3 antes | Nível 3 depois | Nível 10 antes | Nível 10 depois (2 medidas) |
|---|---|---|---|---|
| Base EUA → oeste | 3,00 | 2,49 | 4,64 | 3,93 / 3,85 |
| Xóm Gò → mata B | 1,24 | 1,12 | 2,20 | 1,98 / 2,11 |
| Mata B | 1,99 | 2,00 | 2,32 | 2,61 / 2,39 |
| Ponte D → norte | 1,61 | 1,60 | 1,85 | 1,97 / 2,09 |
| Arrozal A → leste | 2,59 | 2,58 | 4,52 | 4,18 / 4,81 |
| Base VC → leste | 2,34 | 2,20 | 4,74 | 4,09 / 4,70 |

- **Nível 10:** a medida varia ±0,6 milhão entre duas passadas iguais (o streaming e o detalhe por
  distância mudam). Só a base dos EUA cai nas duas.
- **Nível 3:** varia menos. A base dos EUA caiu 17%; as vistas sem cerca ficaram iguais.
- **No mapa todo:**
  - peças, de 24.868 para 23.114;
  - peças com sombra no servidor, de 2.677 para 919 (as copas agora saem sem sombra);
  - arte, de 34,66 para 33,98 milhões de triângulos.

## O que pode aliviar mais (decisão do dono)
1. **Outras plantas longe dos caminhos.** Bambu, capim-elefante e bananeira são o maior custo de
   planta nas vistas abertas: 1,3 milhão de triângulos na base dos EUA e na do VC. Afinar essas
   plantas longe dos caminhos e dos objetivos concentra o detalhe onde se anda, como o texto pede.
   Muda a cobertura.
2. **Sombra do sol no celular desligada por padrão.** Ela soma de 110 a 490 chamadas por quadro. Hoje
   o celular segue a escolha do jogador (`Graficos`, perfil de celular da Parte 13).
3. **Medir no aparelho:** o fps do jogo publicado num celular e num servidor cheio.

## Lote 38 (v83, D-153): bambu, capim-elefante e bananeira afinados longe dos caminhos
Escolha do dono: "afinar plantas longe".
- **Regra:** na mata, a mais de 30 m das estradas e trilhas E a mais de 60 m de objetivo, QG ou vila,
  fica metade dessas três espécies. A passagem é suave em 15 m. O sorteio é fixo pela posição,
  depois de todos os sorteios, então o resto da mata não muda. A mata cerrada da Serraria não afina.
- **No Studio:**
  - bambu 603 → 524, capim-elefante 633 → 503, bananeira 254 → 202 (261 plantas a menos);
  - arte do mapa 33,98 → 32,42 milhões de triângulos (−4,6%).
- **Vistas, nível 3 (milhões de triângulos, v82 → v83):**
  - base EUA 2,49 → 2,47;
  - Xóm Gò 1,12 → 1,19 (dentro da oscilação);
  - mata B 2,00 → 1,98;
  - ponte D 1,60 → 1,55;
  - arrozal A 2,58 → 2,41;
  - base VC 2,20 → 2,16.

  O ganho por vista é pequeno porque as plantas que saíram ficam no fundo da mata. As vistas das
  bases olham para as vilas, onde o bosque fica inteiro.
- **No nível 10:** dentro da oscilação da v82.
