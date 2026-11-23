# Plano de otimização (prompt V5, §7)

Estado de cada técnica na área piloto. "Usada" significa que está no código ou nos modelos; o ganho só é afirmado
com medida em `docs/QA_RESULTS.md`.

| # | Técnica | Estado | Como |
|---|---|---|---|
| 1 | Trim Sheets | Usada | 4 casas no conjunto `Trim_M/W/O/P` da vila |
| 2 | Texture Baking | Usada | Atlas com AO, normal e ORM por modelo |
| 3 | SLIM | Pendente | Só vale no arquivo do place; entra depois da aprovação |
| 4 | LOD | Motor | LOD automático do Roblox; sem sistema próprio |
| 5 | Mesh Instancing | Usada | Cerca, sacos, carga, poças e casas repetem o mesmo MeshId |
| 6 | Atlases | Usada | Um atlas por grupo em cada modelo |
| 7 | Occlusion Culling | Motor | Nativo; sem sistema próprio |
| 8 | Frustum Culling | Motor | Nativo; sem sistema próprio |
| 9 | Instance Streaming | Já ligado | Falta testar o piloto com o jogador se movendo |
| 10 | Retopology | Parcial | Teto de triângulos por grupo no pipeline |
| 11 | RenderFidelity | Padrão | `Automatic`, sem `Precise` |
| 12 | Colisão | Usada | Caixas simples; marcas de chão sem colisão |
| 13 | Transparência | Usada | Marcas suaves em `Decal`; capim em cartões recortados |
| 14 | Sombras | Usada | Marcas de chão e capim não fazem sombra |
| 15 | Scripts | Usada | Saíram os laços de poeira, folhas e balanço da camuflagem |

## Resultado medido
Com o setor de 88 x 88 m, as vistas da Vila têm de 35% a 59% mais chamadas e de 49% a 87% mais triângulos
(`docs/QA_RESULTS.md`). Os gargalos a atacar, nesta ordem: variedade de malhas no setor (48 chaves), chamadas extras
na vista de controle (causa não isolada) e geometria distante. Fps ainda não foi medido.

## Descartado por enquanto
- Sistema próprio de LOD ou culling: o motor já faz.
- Um atlas único para o mapa: custaria memória mesmo quando só uma parte aparece.
