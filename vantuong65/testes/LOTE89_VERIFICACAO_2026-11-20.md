# Lote 89: verificação final do prompt de jogabilidade (§24), 2026-11-20

Uma sessão no Studio, numa cópia local do place da v122 (fora do repositório), com um jogador
(fuzileiro dos EUA, M14) e os bots dos dois lados.

## Dois jogadores: não foi possível nesta sessão
- O teste com servidor e dois clientes ("Clients and Servers") só abre pela interface do Studio, e o
  controle da tela foi recusado.
- Pela linha de comando (`-task StartServer -numtestserverplayersuponstartup 2`), o Studio
  reconheceu o pedido mas abriu sozinho, sem servidor nem clientes, e fechou em 69 s.
- Nos cenários marcados "o que os outros veem", a medida foi a réplica no servidor, que é o que os
  outros clientes recebem, e não um segundo cliente.

## A câmera do MCP
- A câmera ficou presa (Scriptable) no QG, a 81 m do soldado. O servidor recusou 6 tiros por
  "origem" e corrigiu a munição do cliente, o que pareceu recarga de graça.
- Para os testes de munição e troca de arma, a câmera foi presa à cabeça do soldado a cada quadro
  (`BindToRenderStep`, só no teste). Com isso, 0 tiros recusados.

## Cenários do §24
| Cenário | Resultado | Onde |
|---|---|---|
| Renascer e trocar de rodada várias vezes | andar 17,808 studs/s (14 × 1,2 × 1,06 da vantagem do perfil) depois de 3 renascimentos, 3 entradas e saídas de veículo e 3 ciclos de partida: não acumula | Studio, hoje |
| Receber tiros correndo | corrida continua com a perna ferida (7,48 m/s) | Studio, D-187; Lune |
| L3 alterna a corrida | aperto liga, soltar não desliga, limpa ao morrer, renascer, veículo e túnel | Lune, D-188 (controle de verdade não) |
| Inclinar, repetir, trocar de lado | três estados (`InputMap.leanNext`) | Lune, D-189 |
| Botão combinado no celular | mira e atira com uma pressão pela arma | Lune e emulação, D-189 (celular de verdade não) |
| Dois dedos no celular | — | não testado (precisa de aparelho) |
| Só o autor vibra na eliminação | o servidor manda a confirmação só para quem atirou (`Combat_Confirm:FireClient(by)`) | código e Lune, D-189 (dois jogadores não) |
| Passos pelo piso | piso debaixo do pé, troca com duas leituras; hoje os passos tocaram as 6 variações da grama | Studio, D-191 e D-204 |
| Morte por explosão e no veículo | explosão: caído, morto na 2ª granada, o corpo jogado 3,1 m e ancorado, renasceu na 1ª tentativa; veículo: o jipe destruído com o soldado dentro matou, o corpo a 0,7 m do destroço, renasceu | Studio, hoje (rampa: D-192) |
| Granada | 1 explosão por granada, nenhuma metragem na tela (o único "100 m" visível é a barra de escala da carta) | Studio, hoje |
| Trocar de arma no meio de outras ações | 20 → 15 em 5 tiros; trocar sem recarregar: 15 × 8; recarga cancelada pela troca: 15 × 8 (sem recarga de graça); recarga inteira: 20 × 7; 8 trocas rápidas: 20 × 7 | Studio, hoje |
| Roda | 9 fichas com o modelo 3D de cada item; o carregador não mudou com a roda aberta e fechada | Studio, hoje |
| Binóculo | fora da roda; a vaga 7 não o põe na mão | Studio, hoje |
| Segurar RT com a pá | 3 s segurando: 1 pazada ("Buraco: 1/6") | Studio, hoje |
| RT repetido | cada aperto avança o buraco (1/6 → 2/6 → 3/6). No teste o soldado girou 91° sozinho entre apertos (a câmera do MCP) e uma pazada foi para o buraco que ficou à frente | Studio, hoje |
| Entrar e sair dos veículos | o servidor (o que os outros veem): 33 de 33 peças visíveis ao volante, a pé e como passageiro, em 3 entradas e saídas seguidas; a própria vista em 1ª pessoa esconde o corpo (a perseguição o mostra, D-187) | Studio, hoje |
| Torreta | tripulação e escotilhas na torre, o cano fora do casco | Studio, D-196 |
| Destruir veículo e ataque aéreo | 1 explosão do veículo (`impacto:veiculo` 1); ataque aéreo: D-198 | Studio, hoje e D-198 |
| RPG | inventário, munição, projétil, impacto e recarga | Studio, D-200 |
| Os cinco objetivos | mais centrais, alcançáveis a pé e pelos 5 veículos | D-201 (medidas e teste `estradas`) |
| Encerrar a partida | pódio do time que venceu (com a cópia congelada); hoje o VC venceu com o pódio vazio (bot não pontua no placar dos jogadores) | Studio, D-202 e hoje |
| Votar com um mapa | a tela "VOTAÇÃO DO MAPA" abre com Vạn Tường; o voto contou (0 → 1); a partida seguinte começou | Studio, hoje |
| Três ciclos de partida | ver a tabela abaixo: nada acumula | Studio, hoje |

## Três ciclos (cada medida 25 s depois do começo da partida)
| Partida | Modo | Bots | Descendentes do workspace | Memória (Studio) | Corpos | Caixotes | Caixas | Veículos | Terreno do centro (sólidos / capim) | Erros |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 (antes) | Warfare | 59 | 73.667 | 2.042 MB | 0 | 4 | 1 | 9 | 52.560 / 26.131 | 0 |
| 2 | Offensive | 49 | 70.382 | 2.379 MB | 0 | 4 | 0 | 9 | 52.560 / 26.131 | 0 |
| 3 | Warfare | 59 | 73.673 | 2.403 MB | 0 | 4 | 0 | 9 | 52.560 / 26.131 | 0 |
| 4 | Offensive | 49 | 70.380 | 2.410 MB | 0 | 4 | 0 | 9 | 52.560 / 26.131 | 0 |

- **Antes do 1º fim**, a partida 1 teve uma granada, dois buracos de pá, um jipe criado e destruído
  com o soldado dentro, 22 corpos e as lutas dos bots (16 morteiros e 13 granadas). Tudo saiu.
- **Mesmo modo:** os descendentes ficaram iguais com diferença de até 6 (Warfare: 73.667 → 73.673;
  Offensive: 70.382 → 70.380).
- **Memória do Studio (servidor e cliente juntos):** subiu 337 MB da partida 1 (a arte ainda
  carregando) para a 2, e depois só +24 e +7 MB.
- **Cliente:** andar 17,808 nas quatro partidas, 88 → 89 telas e depois estáveis, 26 sons no
  SoundService e 0 erros. Os "TexturePack" do Studio local foram descontados.

## Não testado
- Dois jogadores de verdade, controle de verdade, celular e tablet.
- O jogo publicado.
- O ataque aéreo e a torreta nesta sessão (estão nos lotes deles).
