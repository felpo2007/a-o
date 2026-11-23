# Entrega do prompt de jogabilidade (Prompt B, §25), 2026-11-20

Os 24 itens do prompt foram feitos em 19 lotes (71 a 89; decisões D-187 a D-204 no `DESIGN.md`), cada
um testado no Lune e no Studio e publicado. Versão atual: **v122** (versão 127 do place). Os
relatórios de teste de cada lote estão em `testes/LOTE<nn>_*.md`; a verificação final dos cenários
do §24 está em `testes/LOTE89_VERIFICACAO_2026-11-20.md`.

Legenda da coluna "Testado":
- **Studio:** conferido no Studio com números;
- **Lune:** só nos testes automáticos;
- **não:** não testado.

## 1. O que foi feito
| Item | O que mudou | Decisão | Testado |
|---|---|---|---|
| 1. Sumir no carro; corrida depois do tiro | O corpo só some na 1ª pessoa do assento; na perseguição aparece; ao sair volta ao normal; os outros sempre veem o ocupante. A perna ferida não limita mais a corrida | D-187 | Studio |
| 2. +20% a pé e L3 | `Movement.FOOT_SPEED_K = 1,2` aplicado uma vez na definição (acelerações junto); L3 alterna a corrida | D-188 | Studio (velocidade); Lune (L3) |
| 3–5. Inclinar, botão combinado, vibração | Inclinar com três estados (um aperto inclina, outro volta, o outro lado vai direto); no celular o botão de tiro mira e atira; a vibração só para quem eliminou | D-189 | Lune e emulação |
| 6. Superfícies | O piso logo debaixo do pé decide o passo e o efeito; troca com duas leituras seguidas | D-191 | Studio |
| 7. Ragdoll | O golpe que matou empurra o corpo (bala leve, explosão mais forte perto); morte no veículo solta do assento e o corpo cai fora | D-192 | Studio |
| 8. Granadas | Sem metragem no aviso; o freio no chão depende do piso; o servidor faz a única explosão | D-191 | Studio |
| 9. Sons das armas | Kit de som próprio por arma (síntese própria): 4 tiros em 1ª pessoa, 3 de outro soldado, clique seco, recarga peça a peça, ferrolho ou bomba, estojo; cauda pelo lugar, distância, bala, passos, impactos, explosões, pazadas; mixagem com grupo dos tiros | D-204 | Studio (medido, não ouvido) |
| 10. Troca de arma | A altura da arma é um estado; trocar no meio não pula; a recarga é cancelada pela troca; nada duplica | D-194 | Studio |
| 11. Roda com imagens | 9 fichas com o modelo 3D de cada item, munição e "EM USO"; sem pulo entre vizinhas | D-190 | Studio |
| 12. Binóculo | Fora da vaga 7, da roda, da tecla B, do tutorial e do toque | D-190 | Studio |
| 13. Pá | Uma pazada por aperto (1,4 s), o buraco cresce em 6, validado no servidor, restaurado na partida nova | D-195 | Studio |
| 14. Sumir no carro (investigação) | Coberto no item 1 | D-187 | Studio |
| 15. Torreta | Lugares e escotilhas giram com a torre, no servidor e nos clientes; o cano não entra no casco | D-196 | Studio |
| 16. Destruição de veículos | Porte pela massa, explosão do tamanho, propulsão e assentos desligados, ocupantes pelo dano, destroço queimando | D-197 | Studio |
| 17. Explosões do ataque aéreo | Clarão, bola de fogo, poeira, coluna de fumaça, detritos pela superfície, tremor ajustável; tamanho separado do dano | D-198 | Studio |
| 18. Helicóptero | UH-34D refeito pela silhueta medida no desenho; rotor e disco borrado pela rotação | D-199 | Studio |
| 19. RPG do VC | RPG-2 com tubo, recarga, alça, projétil visível, cartão; o servidor valida tudo | D-200 | Studio |
| 20. Objetivos e relevo | Objetivos 140–220 m mais perto do centro; centro em baixada; mais relevo fora | D-201 | Studio e medidas |
| 21. Comemoração | Cena com os três melhores do time que venceu, aparência congelada no fim e gestos | D-202 | Studio |
| 22. Ciclo completo | Fim → comemoração → votação (com um mapa) → restauração → contagem; tarefas presas à partida; logística, caixas, bots e capim queimado voltam; contagem pelo relógio do servidor com apito | D-193, D-203 | Studio |
| 23. Rede e desempenho | Servidor confirma dano, munição, pazada, votos e resultado; efeitos com teto (24 corpos, 3 explosões grandes, 4 luzes, 40 detritos, caudas em vagas); limpeza por rodada | todos | Studio |
| 24. Verificação | Os cenários do §24 com um jogador e os bots; três ciclos sem acúmulo | lote 89 | Studio |

## 2. Arquivos alterados (desde o lote 71)
São 208 arquivos em `src`, `tools` e `tests`. Os principais:

- **Regras puras** (`src/ReplicatedStorage/Shared`): `Movement`, `InputMap`, `Equipar`, `Gatilho`,
  `Superficie`, `GrenadePhysics`, `Corpos`, `Explosive`, `ExplosaoEfeito`, `VeiculoDano`,
  `VehicleDrive`, `Vehicles`, `FieldWork`, `ItemAnim`, `Lancador`, `Weapons`, `Rodada`,
  `Comemoracao`, `SomArmas`, `SomKits` (gerado), `RotorVisual`, `SoldierAnims`, `BotBrain`,
  `MapConfig`, `AssetIds`, `Net`.
- **Servidor** (`src/ServerScriptService/Modules`): `CombatService`, `MedicalService`,
  `CorposService`, `ExplosionService`, `FieldService`, `FieldWorkService`, `VehicleService`,
  `LancadorService`, `ArmaNaMao`, `MatchService`, `RodadaService`, `SpawnService`, `BotService`,
  `BotVehicles`, `CommanderService`, `LogisticsService`, `CaixaMunicaoService`, `TrapService`,
  `TrainingService`, `StaticArt`, `AssetLoader`, `ImagensUi`.
- **Cliente** (`src/StarterPlayer/StarterPlayerScripts/Controllers`): `Input`, `Movement`,
  `WeaponController`, `WeaponVisuals`, `Ferrolho`, `KnifeView`, `ItemView`, `Wheel`, `RodaArte`,
  `BarraItens`, `Inclinar`, `Haptics`, `Aparelho`, `ToqueHud`, `ToqueTelas`, `VehicleController`,
  `VehicleFx`, `VeiculoDano`, `RotorDisco`, `ExplosionFx`, `LancadorFx`, `AvisoGranada`,
  `AudioController`, `Som`, `Acerto`, `Contagem`, `FimDeRodada`, `CenaComemoracao`, `HudCampo`,
  `GameMenu`, `PostureController`, `SoldierAnimations`, `ThirdPerson`, `ObraToque`, `HeliEvento`.
- **Mapa:** `src/ServerStorage/VT65Build/Data/*` (relevo, estradas e vila regerados) e os 59
  modelos de arte fixa em `src/Workspace/Estatico`.
- **Ferramentas:**
  - `tools/crop_world.py` (relevo e objetivos) e `tools/tempos_chegada.py`;
  - `tools/blender/veic_uh34d.py` e `tools/rotor_borrao.py`;
  - `tools/sons_rpg.py`, `tools/sons_partida.py` e `tools/sons_armas.py`.
- **Testes:** `tests/luau/*` (52 arquivos, 788 testes) e `tests/test_*.py` (76 testes).

## 3. O que dá para ajustar depois
### No jogo (Configurações)
- **Controles:** inclinar (segurar ou alternar), mirar e correr (segurar ou alternar), tempo de
  segurar, zonas mortas, limiar do gatilho, sensibilidades, inverter Y, assistência de mira.
- **Celular:** botão de tiro (mira e atira, ou só atira) e o resto do toque.
- **Imagem e som:** tremor das explosões, volumes (efeitos, ambiente, música), vibração (disparo,
  dano e explosões), legendas de som, modo daltônico, campo de visão.

### No código (números com o arquivo)
| O quê | Onde | Hoje |
|---|---|---|
| Velocidade a pé | `Shared/Movement.FOOT_SPEED_K` | 1,2 |
| Perna ferida limita a corrida | `Shared/Movement.LEG_WOUND_LIMITS` | false |
| Contagem do começo | `Modules/MatchService.PREP_S` | 10 s |
| Fases do fim | `Shared/Rodada.DUR` | fim 8, comemoração 12, votação 15, restauração 3 s |
| Mapas da votação | `Shared/Rodada.MAPAS` | 1 (Vạn Tường) |
| Pá | `Shared/FieldWork.DIG` | 6 pazadas de 1,4 s |
| Corpos | `Shared/Corpos` | teto 24, vida 25 s, empurrão bala 8 e explosão 30 studs/s |
| Explosões grandes | `Shared/ExplosaoEfeito.LIMITES` | 3 grandes, 4 luzes, 40 detritos |
| RPG-2 | `Shared/Lancador.FICHA` | recarga, alça (100 m), munição |
| Recarga peça a peça | `Shared/SomArmas.RECARGA` | as frações da animação |
| Caudas juntas | `Shared/SomArmas.CAUDA_VAGAS_*` | 2 do próprio tiro, 4 dos outros |
| Mixagem | `Controllers/AudioController` | limitador −6 dB 8:1; ambiente abaixa 3:1 e volta em 0,6 s |
| Timbre de cada arma | `tools/sons_armas.py` (`ARMAS`) | por calibre, cano, ação e material (rodar e subir de novo o kit) |
| Gestos da comemoração | `Shared/Comemoracao` | 4 gestos, sequência por lugar |

## 4. Comandos finais
### Computador
- **A pé:**
  - WASD anda; Shift corre; Espaço pula e transpõe; C agacha (tocar) e deita (segurar).
  - Botão direito mira; botão esquerdo atira; botão do meio é o corpo a corpo.
  - R recarrega; V muda o modo de tiro (tocar) e a alça (segurar); Q e E inclinam.
  - X dá o último item (tocar) e abre a roda de equipamento (segurar); 1 a 9 e 0 escolhem a vaga
    (1 principal, 2 secundária, 3 granada, 4 fumaça, 5 bandagem, 6 torniquete, 8 pá, 9 construir,
    0 ferramenta do papel).
  - Z marca (tocar) e abre a roda de comunicação (segurar); G é a bandagem rápida; T, o torniquete.
  - Caps Lock fala no rádio (segurar); U troca o canal; F interage (segurar); K põe a baioneta.
  - O alterna 1ª e 3ª pessoa; I troca o ombro; H desiste quando caído.
  - Mirando, Shift prende a respiração.
- **Veículo:** W/S acelera e freia (ré), A/D vira. Atirador: botão esquerdo atira, direito dá a
  ótica, F é a coaxial e X troca a munição. C troca de assento; Y sai.
- **Helicóptero:** Espaço/Ctrl é o coletivo, WASD o cíclico, Q/E os pedais e R estabiliza.
- **Geral:** M abre o mapa tático; P, o menu do jogo.

### Controle
- **A pé:**
  - Analógico esquerdo anda e L3 alterna a corrida; A pula.
  - L2 mira; R2 atira; R3 é o corpo a corpo; R1 lança a granada rápida.
  - B agacha (tocar) e deita (segurar); X recarrega (tocar) e interage (segurar).
  - Y troca a arma (tocar) e põe a baioneta (segurar).
  - L1 dá o último item (tocar) e abre a roda (segurar).
  - Direcional: direita marca e abre a comunicação; esquerda muda o modo de tiro e a alça; cima
    alterna 1ª e 3ª pessoa e troca o ombro; baixo dá a bandagem rápida e o rádio (segurar).
  - Mirando: LB e RB inclinam, L3 prende a respiração.
- **Veículo:** RT acelera, LT freia e dá ré, analógico esquerdo vira. Atirador: R2 atira, L2 ótica,
  R1 coaxial, X munição. Y (segurar) troca de assento; B (segurar) sai.
- **Helicóptero:** RT/LT coletivo, analógico esquerdo cíclico, RB/LB pedais, A (segurar)
  estabiliza.
- **Geral:** Select abre o mapa (tocar) e o menu (segurar). O Start fica para o menu do Roblox.

### Celular e tablet
- Analógico flutuante à esquerda anda; arrastar à direita gira a câmera.
- O botão FOGO mira e atira com uma pressão (opção "só atira" nas Configurações); arrastar nele
  gira a câmera enquanto o outro dedo anda.
- **Botões fixos:** AGACHAR (tocar agacha, segurar deita), ITEM (último item / roda), COMUNICAR
  (marcar / roda), CÂMERA (1ª/3ª pessoa e ombro), ◄ e ► (inclinar).
- **Botões que aparecem quando servem:** RECARGA, GOLPE, FÔLEGO, BANDAGEM, RÁDIO, interagir e
  DESISTIR.
- **Veículo:** o analógico acelera e vira; no helicóptero, a alavanca da tela é o coletivo.

## 5. Testes e resultados
- **Automáticos:** Lune 788 testes em 52 arquivos; pytest 76; ruff, StyLua e luau-lsp limpos;
  traduções em 100% (en, es, vi).
- **Studio:** cada lote tem o seu relatório com números (`testes/LOTE71…89`). Na verificação final
  (lote 89):
  - velocidade sem acumular (17,808 em todos os casos);
  - granada com uma explosão e sem metragem;
  - pá com uma pazada por aperto e o buraco crescendo;
  - veículo visível para os outros em 3 entradas e saídas;
  - destruição com uma explosão;
  - morte por explosão e no veículo com corpo e renascer;
  - troca de arma sem munição duplicada nem recarga de graça;
  - roda com as imagens e o binóculo fora;
  - votação com um mapa;
  - três ciclos sem acúmulo (mesmo número de objetos no mesmo modo, terreno idêntico, 0 erros).
- **Publicado:** v110 a v122 (a primeira publicação depois do lote 71 foi a v110).

## 6. O que ainda depende de algo de fora ou ficou limitado
- **Dois jogadores de verdade:** não deu para testar. O teste com servidor e clientes do Studio
  precisa da interface, e o controle da tela foi recusado. O que os outros veem foi medido pela
  réplica no servidor. Precisa de uma sessão com duas contas ou do teste "Clients and Servers"
  aberto por você.
- **Controle e celular de verdade:** as regras estão nos testes e na emulação, mas não num aparelho.
- **Sons:** feitos por síntese e medidos; ninguém ouviu. Se preferir gravações de verdade, os pontos
  de troca são os trechos de cada kit (`Shared/SomKits`, um arquivo por kit).
- **Tiro do comandante no Studio:** o perfil local tem posto 1 e o comandante pede posto 3; a guarda
  ficou nos testes.
- **Passos em metal e pedra:** usam o som da madeira e o da areia (`Superficie.MISSING_STEPS`).
- **Placeholders do prompt:** construir, caixa de munição, bolsa do médico e rádio usam formas
  simples na roda.
- **Jogo publicado:** não foi conferido com jogadores.
