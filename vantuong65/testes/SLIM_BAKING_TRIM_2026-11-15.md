# SLIM, baking e trim sheets no nosso pipeline (lote 39, 2026-11-15)

Pedido do dono: aplicar um texto que recomenda três métodos:
- **SLIM:** o Roblox gera versões leves dos modelos parados.
- **Baking:** o detalhe de um modelo pesado é passado para um leve, em mapas de textura.
- **Trim sheets:** uma folha de materiais dividida por muitos objetos.

O primeiro passo que o texto sugere é testar o SLIM numa casa completa e num pequeno conjunto de
cenário.

## SLIM: o que ele exige e onde trava

**O que a documentação exige** ([SLIM](https://create.roblox.com/docs/workspace/streaming/slim)):
- `StreamingEnabled` no Workspace (temos);
- o place salvo no Roblox;
- o **Team Create ligado** na experiência: a nuvem só gera o SLIM nesse caso;
- o modelo **salvo no arquivo do place**, com `LevelOfDetail = SLIM`. O SLIM é para geometria
  parada: acrescentar ou tirar peças, trocar material ou mexer na malha durante a partida impede o
  desenho certo.

**Onde estamos:**
1. **Toda a arte é posta pelo servidor quando o jogo abre** (`AssetLoader`, D-57).
   - Os modelos vêm do `InsertService` e são clonados, assentados no chão e tingidos (as casas da vila
     mudam de cor).
   - Nenhum modelo do mapa está salvo no arquivo do place, então nada pode usar SLIM hoje.
2. **O Team Create** é uma configuração da experiência; é escolha do dono ligar.
3. **O pipeline não grava SLIM.** Teste feito nesta sessão:
   - um place vazio em XML foi aberto no Studio;
   - foram inseridos `vila_casa_03`, `granary`, `water_jar` e `straw_stack`, com
     `LevelOfDetail = SLIM` (no modo de edição, o Studio aceitou);
   - o arquivo foi salvo e lido no Lune 0.8, que monta o nosso place.

   O Lune 0.8 falhou em dois pontos:
   - **O valor do SLIM:** ele não conhece o 4 de `ModelLevelOfDetail` ("does not contain numeric
     value 4").
   - **O formato novo do `Content`:** o Studio grava `<Content><uri>…</uri></Content>` e o Lune
     esperava `<url>`.
     - Trocando a etiqueta no texto, ele leu os modelos, mas as 59 peças de malha chegaram sem
       `MeshId` (a malha está no `MeshContent`, que ele não conhece).
     - Na hora de gravar, deu erro de tipo no `AssetService.Tags`.

**Para testar o SLIM de verdade, falta:**
1. **Ligar o Team Create** na experiência (dono).
2. **Atualizar o Lune** para uma versão que conheça o SLIM e o `Content` novo, ou gravar o place por
   outro caminho. É uma ferramenta do PC do dono (`vt65-tools`), e o pipeline inteiro passa por ela.
3. **Pôr a casa de teste e o pequeno conjunto no arquivo do place**, já assentados e tingidos, e tirar
   essas cópias do `AssetLoader`.
4. **Publicar e comparar** no jogo publicado, perto e longe: aparência e tempo de quadro.

**Onde o SLIM deve ajudar mais:**
- **As 19 construções feitas de peças** (pagode, casa comunal, serraria, cais etc.), com até 51
  peças com sombra cada (as tábuas); o SLIM junta peças.
- **As casas do Blender:** já têm só 6 malhas visíveis (paredes, piso, estrutura, telhado, mobília e
  anexos) mais 50 caixas de colisão invisíveis. Para elas, o ganho seria o detalhe menor à distância.

## Baking: já é o nosso caminho
O Blender do projeto já assa o modelo detalhado no leve (`comum.assar`, com `selected_to_active`):
- **casas da vila** (`vila.py`): 3 atlas de 1024 por casa (telhado, casa e mobília), assados de uma
  versão detalhada, com 16 amostras por texel;
- **objetos das bases** (`bases.py`), **veículos** (`veiculos.py`, `assar_atlas`) e **faca**
  (`tools/faca`).

O que não passa por ele são os modelos do gerador (ForgeGUI) e as árvores do Poly Haven, que já vêm
com textura. Para os próximos objetos do Blender, o caminho continua o mesmo.

## Trim sheets: o que mudaria
- **Hoje cada casa e cada objeto de base tem os próprios atlas.** No mapa:
  - as casas da vila usam 104 texturas diferentes (26 modelos);
  - as bases, 138 (30 modelos);
  - as plantas, 32 (12 modelos);
  - os outros objetos, 42.
- **Com uma trim sheet da vila** (madeira clara, madeira velha, bambu, palha, metal enferrujado,
  amarrações), as partes de construção de todas as casas dividiriam as mesmas poucas texturas. Fica
  menos memória e menos download no celular, e as casas novas saem mais rápido.
- **O custo:** refazer o UV das casas no Blender e perder parte do detalhe único assado. Manchas
  próprias de cada casa ficariam por cima, em decalque ou no atlas da mobília.
- **Não medido:** quanto da memória de textura é das casas. No Studio, a textura ocupa 179 MB, mas
  esse número inclui o próprio Studio e o servidor; num celular o Roblox também baixa a qualidade da
  textura.

## Decisões do dono
1. **SLIM:** ligar o Team Create e autorizar a troca do Lune (e, depois, a mudança das casas e bases
   para dentro do arquivo do place, começando por uma casa de teste).
2. **Trim sheet:** fazer a folha da vila e testar numa casa (comparar a aparência e o número de
   texturas antes de mexer nas outras).

## Lote 40 (D-155): o SLIM preparado, sem trocar o Lune
- **Caminho:** o Rojo grava o `LevelOfDetail` = 4 (SLIM) e o Lune passa adiante sem ler. A casa de
  teste e 5 objetos em volta são copiados do jogo rodando (`tools/estatico_copiar.luau`) e viram
  modelos fixos (`tools/estatico.py`). O `AssetLoader` devolve a cópia fixa no lugar da nova.
- **Studio:** o log bate com a v83, os raios param nas paredes e a foto de fora é idêntica.
- **Limite:** o interior sai claro. Peça de malha criada fora do Studio não tem a colisão calculada
  (`PhysicsData`), e a luz usa essa forma para a sombra de dentro (com `Hull` calculado no Studio,
  escurece; com `Box`, não).
- **Desligado** até o Team Create (`assets/estatico/ativos.json`).
