# Aceite do setor piloto (prompt V5, §19, e reconstrução da Vila)

Situação em 2026-11-23. **Aguardando a aprovação visual do dono. O resto do mapa não foi tocado e nada foi publicado.**
Comparação com as mesmas câmeras: `testes/lote122/antes_depois.jpg`. Números: `docs/QA_RESULTS.md`.

## Critérios visuais (`docs/ART_DIRECTION.md`, §9)
| # | Critério | Situação | Evidência |
|---:|---|---|---|
| 1 | Chão vazio até 35% abaixo do horizonte | **Não atingido** | Média de 62% (antes, 69%); só as residências passam |
| 2 | Três tipos de construção por vista | Atingido | Avaliação visual das seis câmeras |
| 3 | Palha sem beiral reto | Parcial | Franja nos modelos novos; de longe ainda parece reta |
| 4 | Objetos em volta de toda construção | Parcial | 54 objetos de cena; não conferido casa a casa |
| 5 | Vegetação em três alturas | Atingido | Capim, arbusto e bananeira, bambu, coqueiro e árvore |
| 6 | Relevo, umidade e mais de um material | **Parcial** | Relevo e valas existem; falta chão molhado convincente |
| 7 | Portas, escadas e interiores percorridos | Parcial | Quatro interiores andando; escadas não retestadas |
| 8 | Antes e depois claramente diferentes | **Decisão do dono** | `testes/lote122/antes_depois.jpg` |

## Entregas técnicas
| Entrega | Situação | Evidência |
|---|---|---|
| Biblioteca de modelos em Blender | Feita | 51 pastas `ret_pov_*` |
| Vegetação própria | Feita | Coqueiros, árvores, arbustos, pedras e capim |
| PBR e folha de paredes envelhecidas | Feita | `ret_pov_trim`, só no setor |
| Captura, bots e caminhada | Feita | `docs/QA_RESULTS.md` |
| Autoteste | **Intermitente** | Granada de bot falhou em 2 de 4 rodadas |
| Fps, celular e duas pessoas | **Pendente** | Não medidos |
| SLIM | **Pendente** | Só depois de entrar no arquivo do place |

## Decisões do dono
1. Aprovar o visual da Vila ou dizer o que mudar.
2. Lados das bases: o prompt pede EUA a oeste e Vietnã a leste; o jogo hoje tem VC a oeste e EUA a leste.
3. Desligar a grama nativa no mapa inteiro. Sem isso a regra de vento zero não fica completa.
