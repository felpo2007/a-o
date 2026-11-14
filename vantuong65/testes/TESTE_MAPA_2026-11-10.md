# Teste do mapa e das texturas (Studio, 2026-11-10)

Feito no place publicado como versão 22, aberto no Studio, em Play solo. As capturas foram tiradas
pelo MCP com a câmera posicionada em cada setor, com o streaming pedido para a área.

## Defeito grave achado e corrigido: arte enterrada
- **Sintoma:** em An Cường (2) não aparecia nenhuma casa nem vegetação, só o greybox (terreno,
  diques e caixas de sebe). Os 54 modelos de arte da área estavam em y = 0, e o terreno ali fica em
  y = 70 (~20 m acima).
- **Causa:** o servidor dispara a geração do terreno (~50 s) e a colocação da arte ao mesmo tempo
  (`task.spawn` nos dois). A arte fazia o raio até o chão antes de o terreno existir, não achava
  nada e ia para y = 0.
- **Efeitos:**
  - as vilas ficavam enterradas;
  - os placeholders das casas eram apagados mesmo assim, então as vilas ficavam sem casa nenhuma;
  - os animais andavam debaixo da terra;
  - a medição de fps da arte (59–60 nos 5 setores, no relatório de mais cedo) foi feita com a arte
    enterrada e **não vale**.
- **Correção:**
  - o `AssetLoader` espera o `TerrainReady` antes de pôr a arte;
  - modelo sem chão embaixo agora gera aviso;
  - o autoteste ganhou "arte no chão".
- **Conferido:**
  - a base dos modelos fica a 0,00 m do chão;
  - a arte termina de ser posta 17 s depois do terreno;
  - autoteste "arte no chão": 5.046 de 5.048 modelos a até 2 m. O pior é uma entrada de túnel a
    +2,7 m, sobre o poço.

## O que as capturas mostram
- **Casas:** bem texturizadas. A casa de palha com varanda tem telhado de palha, paredes caiadas,
  portas de madeira e base de pedra.
- **Vegetação das vilas** (touceiras de bambu, coqueiro, bananeira): fica boa à distância.
- **`hill_tree` (árvore das colinas):** quebrada de perto, um emaranhado de triângulos soltos com
  lascas cinza-claras.
  - A causa é a malha, não a textura: a redução local para caber no teto de 3 mil triângulos da
    vegetação destruiu a forma.
  - Os GLB da vegetação são opacos (JPEG, sem transparência), então o `AlphaMode` não é a causa.
- **Sebes:** 3.387 das 3.827 peças (89%) continuam como caixas verde-escuras de `LeafyGrass`.
  - Só 440 viraram touceiras, por causa do teto de triângulos por setor.
  - É o que mais aparece na paisagem e dá cara de greybox.
- **Terreno:** usa os materiais padrão do Roblox (lama, chão, capim, areia, água). Não há
  `MaterialVariant` nem cor ajustada, e o capim das colinas é um verde saturado que destoa da
  areia e do arrozal.
- **Praia (Green Beach):** areia e mar corretos. O disco amarelo translúcido na areia é a marcação
  do ponto forte.
- **Texturas que não carregam:** a checagem por `ContentProvider` não serve.
  - `PreloadAsync` com o ID em texto deu "Failure" em 145 de 146 IDs, inclusive nos que aparecem
    texturizados nas capturas.
  - `GetAssetFetchStatus` repetiu esse resultado.
  - A prova que vale é a captura: casas, veículos, armas, búfalo e vegetação aparecem com textura.

## fps: não medido nesta rodada
As medições deram 9–15 fps em todos os setores. Mas esconder a arte, as sebes e as sombras não
mudou nada (12 → 13 → 14 → 13 fps). Na hora, um jogo de PC estava em primeiro plano com a CPU em
94%, e o Studio ficou em segundo plano. Esses números não valem. A medição com a arte visível
precisa ser refeita com o PC livre e o Studio em primeiro plano.

## Autoteste
**10 ok, 0 falhas, 2 pulados.** Os pulados são deitado e pá, que precisam do personagem do
jogador, e ele estava fora de jogo por causa dos teleportes das medições. Os dois passaram na
rodada anterior e não dependem da arte.
