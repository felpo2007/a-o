# Teste com a arte publicada (Studio, 2026-11-10)

Primeiro teste com a arte do ForgeGUI publicada no Roblox. O place da nuvem (placeId 125635672454807,
versão 5) foi aberto no Studio. O código corrigido foi copiado para o Studio pelo MCP, com conferência
byte a byte contra o repositório, e não foi salvo pelo Studio. O teste foi em Play solo, com 29 a 30
bots.

## Resumo
| Medida | Resultado |
|---|---|
| Autoteste (`VT65SelfTest`) | **11 ok, 0 falhas, 0 pulados**. É a primeira vez sem pulados: os animais entraram |
| Arte carregada | 5.044 a 5.151 modelos; setores 1–5 com 2,39 a 2,50 milhões de triângulos (teto 2,5 mi) |
| Sebes (fração das touceiras que coube) | 19–20 / 38–39 / 24 / 21–22 / 54% nos setores 1–5 |
| fps no Studio, por setor | 59 / 60 / 60 / 60 / 60. Pior quadro: 72 ms no setor 1, logo após o teleporte; 20–21 ms nos demais |
| Terreno pronto | 43–53 s |
| Erros de script | nenhum |

Os fps são do Studio neste PC, com janela de 1236 × 576 e vsync. Não valem como medida de celular nem
de servidor cheio.

## Defeitos achados e corrigidos
1. **A arma real nunca aparecia.** O modelo publicado chega aninhado (Model > Model > Model > MeshPart),
   e o `attachWeapon` procurava a peça só no primeiro nível. A busca agora é recursiva.
2. **A arma real viria atravessada e sem pontos.**
   - O modelo chega centrado na caixa, sem `Muzzle`, `Sight`, `Grip` nem `Support`, e cada arma
     aponta para um lado.
   - Sem os pontos, ficariam desligados o clarão de boca, o traçante, a mira e o IK das mãos.
   - Novo `tools/weapon_landmarks.py`: lê os GLB e gera `Shared/WeaponArt.luau`, com a frente e os 4
     pontos de cada uma das 9 armas.
   - Novo `GunModel.fit`: prepara o modelo publicado na convenção da arma provisória (pivô no punho,
     boca em −Z).
   - Conferido:
     - nas 9 armas, a boca em −Z e os pontos nos lugares certos (captura com marcas);
     - M14 na mão: os 4 pontos presentes;
     - nos personagens: 30 de 30 armas com a arte real;
     - em primeira pessoa: a arma real aparece no quadril;
     - mirando: a alça fica exatamente no centro da tela, em (618, 288);
     - arma caída: a base da caixa fica no chão, com o prompt de pegar.
3. **A mão esquerda parava a 20 cm do apoio.**
   - Medido: o IK do braço só alcança ~2,05 studs a partir do ombro (erro de 3 cm a 2,05 studs; de
     17 cm a 2,57).
   - A pega em pé veio 0,5 stud para trás e 0,3 para o centro. O pior caso entre as 9 armas ficou em
     1,96 studs.
   - Resultado: mãos a 7 e 11 cm do punho e do apoio (antes 6 e 20).
4. **Deitado, as mãos ficavam a 27 e 24 cm da arma.** Uma busca em grade de 27 poses, medida no
   próprio Studio, achou uma pose com 8 e 10 cm. Nessa busca o erro foi até 43 cm, e não depende só da
   distância: o IK deitado erra por outros motivos.
5. **Animais da vila sem arte.**
   - O búfalo e a galinha estavam no manifest do ForgeGUI, mas fora do plano de upload e do
     `AssetIds`.
   - Foram publicados pelo Open Cloud: búfalo 135711693555155, galinha 92356283821226.
   - Resultado: 141 animais (33 búfalos e 108 galinhas), os 141 se movendo; o búfalo tem textura
     (SurfaceAppearance).
6. **Animais e veículos andariam de ré.**
   - O importador do Roblox gira o GLB 180° em Y. Os ângulos medidos nos GLB ficavam invertidos.
   - Visto em captura: a cabeça do búfalo, o canhão do M48A3, os tubos do Ontos, a proa do LVTP-5 e o
     nariz do UH-34D apontam para −X; a cabeça da galinha aponta para −Z.
   - Corrigido:
     - `VehicleService.ART_YAW` passou para −90° nos 4 veículos;
     - `AnimalService.FACE_YAW` passou para −90° (búfalo) e 0 (galinha).
   - Conferido em Play: no M48A3 o canhão aponta para a frente do chassi.

## Observações (não corrigidas)
- **Mira:** na M14, a caixa da culatra ocupa a metade de baixo da tela. O olho fica perto da alça
  traseira. (Corrigido na segunda rodada, abaixo.)
- **RPD:** o cano do modelo sobe ~6° em relação à caixa. É só visual: o tiro sai da câmera.
- **Primeira pessoa e mira:** só a M14 foi conferida na mão. Nas outras 8, os pontos foram conferidos
  no modelo, não em jogo. (As 9 foram conferidas na segunda rodada, abaixo.)
- **Avisos `ContentId ... No asset content representation`:**
  - IDs 124251417301593, 102331967959169, 138533985753217 e 135346936478811;
  - nenhum é ID nosso;
  - não estão em 16 dos modelos publicados (procurei em malhas, texturas e mapas);
  - parecem conteúdo que o Roblox ainda está processando. Não quebram nada.
- **DataStore:** "Studio access to APIs is not allowed". Isso é uma configuração da experiência
  (Game Settings → Security), decisão sua. Sem ela, o perfil não salva no Studio.
- **Captura de tela:** com a janela do Studio minimizada, o `screen_capture` do MCP devolve tela
  branca.

## Segunda rodada (mesmo dia): mira das 9 armas e pendências
Feita no place publicado como versão 13, reaberto no Studio, com as correções copiadas pelo MCP e
conferidas byte a byte. Detalhes em D-60.

| Arma | Mão direita / esquerda até o alvo do IK | Massa até o centro da tela | Giro da arma na mira |
|---|---|---|---|
| M14 | 7 / 11 cm | 0,1 px | 0,7° |
| Type 56 | 7 / 11 cm | 0,1 px | 0,0° |
| SKS | 7 / 11 cm | 0,1 px | 0,0° |
| M60 | 7 / 11 cm | 0,1 px | 3,6° |
| RPD | 7 / 11 cm | 0,1 px | 0,0° |
| M79 | 7 / 9 cm | 0,1 px | 0,0° |
| M1911 | 7 / 5 cm | 0,1 px | 0,7° |
| Type 54 | 7 / 3 cm | 0,1 px | 0,7° |
| RPG-2 | 7 / 5 cm | 0,1 px | 0,0° |

O tiro sai do centro da tela, então a massa precisa estar ali. Cada arma foi conferida também por
captura da tela mirando.

- **Corrigido na mira:**
  - **M14:** a massa ficava ~2° abaixo do centro, porque o topo usado era o das orelhas que protegem
    a massa. Agora o topo é medido a até 2 mm do plano do cano, e a massa aparece no meio da janela
    da alça de dioptro.
  - **Caixa da culatra tomando a metade da tela:** o olho foi para cima do punho (rosto na coronha).
  - **Pistolas:** antes o olho ficava a 9 cm, como num fuzil. Agora fica a 45 cm (braço estendido).
  - **Type 54:** aparecia de perfil. O modelo veio girado 27° em guinada. O giro é medido pelo eixo
    principal dos vértices e corrigido em `GunModel.fit`.
  - **RPD:** vinha de lado (7,2° de guinada). Corrigida do mesmo jeito, sem ajuste manual.
  - **M60:** o modelo tem a alça de transporte levantada no meio da linha de visada. O olho vai 3 cm
    para a direita, 3,2 cm para cima e 10 cm para trás.
  - **M79:** a escada de mira levantada fica na frente da massa. A referência passou a ser o meio da
    janela da escada.
- **Avisos `ContentId`:** nesta rodada eles vêm como `rbxassethash://…`, que é conteúdo interno de
  malha do Roblox. Nenhuma das 32.584 instâncias do cliente usa os 4 IDs da primeira rodada. Não é
  código do jogo, e não há o que corrigir aqui.
- **Autoteste depois de tudo: 11 ok, 0 falhas, 0 pulados.**
- **Não feito:** ligar o "Enable Studio Access to API Services". Ele fica na aba Security das
  configurações do jogo, e configuração de segurança fica com você (passo a passo no
  `TODO_USUARIO.md`).
