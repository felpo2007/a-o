# Controle em primeiro lugar (Parte 12)

## 1. Auditoria: o que NÃO funcionava só com controle (antes, sessão 4)
| # | Onde | Problema | Correção |
|---|---|---|---|
| 1 | `WeaponController` | atirar e mirar só no mouse; R e V no teclado | RT/LT (limiar ajustável), X tocar recarrega, ← seletor |
| 2 | `MedicalController` | G, T, F, H só no teclado | ↓ bandagem rápida (o sangramento mais urgente), roda de equipamento, X segurado reanima/trata, B segurado desiste quando caído |
| 3 | `PostureController` | agachar só no C; sem deitar, inclinar e correr | B tocar/segurar, LB/RB mirando, L3 alterna corrida (servidor valida) |
| 4 | — | não existiam corpo a corpo, baioneta, binóculo, alça de mira, granadas, fumaça, marcação, rodas e canal de rádio | criados: R3, Y segurado, ↑, ← segurado, roda (LB), RB tocar/segurar, → |
| 5 | `GameUI` | facção/squad/papel e spawn só por clique, sem foco inicial | foco no 1º item, moldura amarela de alto contraste, cursor com ímã no mapa, LB/RB entre spawns, Y troca de papel |
| 6 | `GameUI` | mapa só no M | View tocar (Select), B/Select fecham |
| 7 | `CommanderController` | **exigia digitar a grade** num TextBox | habilidade → alvo no mapa com o cursor; correções e "perigo próximo" por botão; a grade digitada vira opção do teclado |
| 8 | `CommanderController` | construir só no J | roda de equipamento → Construir |
| 9 | `VehicleController` | tudo no teclado; **A (pular) tirava do assento** | layout de veículos da Parte 12.3; A e Espaço afundados em veículo; sair = B segurado |
| 10 | `VehicleController` | antitanque no Z | o lançador vira 2ª arma (Y troca, RT dispara) |
| 11 | `ShopController` | loja no B (teclado) e sem foco | menu do jogo → Loja (ou L), navegável |
| 12 | câmera | analógico direito sem zona morta/curva/sensibilidade do jogo, sem assistência | `CameraLook`: zona morta radial, 3 curvas, sensibilidade por modo e eixo, aceleração de giro, assistência mínima |
| 13 | geral | menus não cancelavam mira e corrida; sem tratamento de controle desconectado; sem vibração | máquina de estados (`InputMap.event`), aviso de reconexão, `Haptics` |
| 14 | `DebugHud` | F3/F8/F9 só no teclado | **de propósito**: ferramenta do testador, fora do jogo |

## 2. Layout padrão (Xbox / PlayStation)
Infantaria, veículos, mapa e menus seguem a tabela da Parte 12 botão a botão. O teste
`tests/luau/controle.luau` falha se alguma linha divergir.

O teclado e o mouse continuam funcionando:

| Ação | Teclado/mouse |
|---|---|
| Atirar / mirar | botão esquerdo / direito |
| Correr | Shift |
| Corpo a corpo | botão do meio |
| Último item / roda de equipamento | X tocar / segurar |
| Marcar / roda de comunicação | Z tocar / segurar |
| Inclinar (mirando) | Q / E |
| Agachar / deitar | C tocar / segurar |
| Recarregar / interagir | R / F segurado |
| Trocar arma / baioneta | 1 / K |
| Binóculo / bandagem rápida / torniquete | B / G / T |
| Seletor / alça de mira | V tocar / segurar |
| Canal de rádio | U |
| Mapa / menu do jogo / loja | M / P / L |
| Desistir (caído) | H |
| Apoio de fogo / construir | N / J |
| Veículo | WASD; Espaço/Ctrl (coletivo); Q/E (pedais); R (estabilizar); C (trocar assento); Y (sair) |

## 3. Arquitetura
- `Shared/InputMap.luau` (puro, testado):
  - contextos com prioridade: global, infantaria, mira, veículo terrestre, helicóptero, roda, mapa e
    menu;
  - ações por botão (press, tap ou hold, nunca duplo toque);
  - padrões ajustáveis com validação;
  - zona morta radial e curvas;
  - giro com aceleração;
  - assistência mínima;
  - roda radial, cursor com ímã e máquina de estados.
- `Controllers/Input.luau` (runtime):
  - **Input Action System**: um `InputContext` por contexto, `InputAction`/`InputBinding` por
    botão;
  - **reserva no UserInputService**, porque há relatos de Thumbstick1/ButtonA sem resposta no IAS.
    As duas fontes são deduplicadas por botão, e a primeira que chega vence;
  - gatilhos sintetizados pelo valor analógico, com o limiar do jogador;
  - analógicos lidos de `GetGamepadState`;
  - `PreferredInput`;
  - ícones via `GetImageForKeyCode`, que mostra o ícone certo para Xbox ou PlayStation;
  - `GuiService.MenuOpened/Closed`;
  - desconexão: pausa com aviso e retoma com o primeiro controle que apertar um botão;
  - volta ao jogo **só depois de soltar todos os botões**, relendo o controle;
  - movimento com a zona morta do jogo, via `ControlModule.moveFunction`;
  - configurações salvas na conta (`Settings_Get`/`Settings_Save`, saneadas no servidor);
  - gravador e reprodutor de entradas.
- Servidor (`FieldService`):
  - registra o tipo de entrada de cada jogador (atributo `InputType` + `AnalyticsService`), para
    medir controle x mouse e, se preciso, criar fila só de controle;
  - marcações e mensagens predefinidas;
  - granadas, fumaça, corpo a corpo e baioneta.

## 4. O que só um controle real pode confirmar
- Cada binding no IAS. Se algum falhar, a reserva no UIS já cobre, mas vale anotar qual.
- Os ícones: Xbox, DualSense, DualShock 4 e controle genérico.
- Os motores de vibração, inclusive os de gatilho. Há relatos de que não funcionam no Xbox Series;
  o código confere `IsMotorSupported` antes de usar.
- A legibilidade a 3 m da TV (`IsTenFootInterface` → texto mínimo de 24 px).
- O critério da Parte 12: 3 partidas inteiras só com controle, sem travar, a 60 fps no console.

Matriz de teste e roteiro: `TODO_USUARIO.md`, item 3.
