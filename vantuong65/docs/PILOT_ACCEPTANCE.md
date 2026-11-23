# Aceite da área piloto (prompt V5, §19)

Situação em 2026-11-22. **Aguardando a aprovação visual do dono. O resto do mapa não foi tocado.**
Comparação com as mesmas câmeras: `testes/lote121/antes_depois.jpg`. Números: `docs/QA_RESULTS.md`.

| # | Entrega | Situação | Evidência |
|---:|---|---|---|
| 1 | Casa vietnamita em Blender | Feita | `ret_vila_palafita_a` e `_b`, 15,7 mil e 11,6 mil triângulos |
| 2 | Interior explorável | Feita | Subiu a escada e entrou andando |
| 3 | PBR | Feita | `SurfaceAppearance` com cor, normal e ORM |
| 4 | Trim sheets | Feita | 4 modelos de casa |
| 5 | Baking | Feita | Atlas com AO por modelo |
| 6 | Vegetação própria | Parcial | Capim novo; bananeira, samambaia e arbustos são reaproveitados |
| 7 | Chão refeito | Feita | Terra, capim e folhas por distância da rua |
| 8 | Estrada detalhada | Feita | Sulcos de roda, poças e terra molhada |
| 9 | Set dressing | Feita | Sacos, carga, carroça, potes, palha, cercas |
| 10 | Iluminação final | Aguarda o dono | Manhã, relógio parado |
| 11 | SLIM | **Pendente** | Só depois de entrar no arquivo do place |
| 12 | LOD e RenderFidelity | Feita | `Automatic`, LOD do motor |
| 13 | Instancing | Feita | Mesmo MeshId nas repetições |
| 14 | Colisões otimizadas | Feita | Caixas; marcas e capim sem colisão |
| 15 | Streaming | Parcial | Carrega no lugar; não testado andando |
| 16 | Ausência de vento | Parcial | Zero em jogo; a grama nativa só sai no teste |
| 17 | Captura funcional | Feita | Neutro para VC; EUA não testado |
| 18 | Multiplayer | **Pendente** | 52 bots e 1 jogador; faltam 2 pessoas |
| 19 | Benchmark | Parcial | Chamadas e triângulos; fps inválido neste PC agora |
| 20 | Fotos antes e depois | Feita | Mesmas câmeras |

## Decisões do dono
1. Aprovar o visual da Vila ou dizer o que mudar.
2. Lados das bases: o prompt pede EUA a oeste e Vietnã a leste; o jogo hoje tem VC a oeste e EUA a leste.
3. Desligar a grama nativa no mapa inteiro. Sem isso a regra de vento zero não fica completa.
