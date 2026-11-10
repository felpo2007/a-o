# O que só você pode fazer (VẠN TƯỜNG '65)

Fiz sozinho tudo o que não depende da sua conta Roblox, de dinheiro, de decisão sua ou de abrir o
Studio. A lista abaixo segue a ordem de prioridade. O que está em **negrito** destrava a maior parte
do resto.

## 1. **Criar a experiência e me dar acesso de publicação** (10 min)
1. Em create.roblox.com → Creations, crie uma experiência vazia ("New Experience").
2. Anote três números, que não são segredo:
   - **universeId** (Experience ID);
   - **placeId** (Start Place);
   - seu **userId**.

   Copie `cloud.example.json` para `cloud.json` e preencha, ou me mande os números no chat.
3. Em create.roblox.com → Open Cloud → API Keys → **Create API Key**. Dê só estas permissões, e só
   para essa experiência:
   - Assets: `asset:read`, `asset:write`;
   - Universe Places / Place Publishing: `universe-places:write`;
   - Game Passes: `game-pass:read`, `game-pass:write`;
   - Developer Products: `developer-product:read`, `developer-product:write`;
   - opcional: Luau Execution (`universe.place.luau-execution-session:write`), para eu rodar
     testes no servidor do Roblox.

   Ponha data de expiração. Restrição de IP: deixe em branco, porque o IP da sessão muda.
4. **Estado em 2026-11-10:** uma chave foi salva no ambiente (segredo de rede de
   `apis.roblox.com`), mas a Roblox respondeu **401 "Invalid API Key"** em dois testes, com 1 min de
   intervalo. Confira três coisas:
   - a chave foi copiada inteira;
   - ela está ativa e dentro da validade;
   - o tipo é chave Open Cloud, não cookie nem token OAuth.

   Para trocar: menu do ambiente na barra de título da sessão → Edit → Network secrets.
5. **A chave nunca vai no chat nem no Git.** Quando eu pedir, um formulário seguro aparece. Cole a
   chave lá: ela fica no ambiente e o proxy a injeta nas chamadas a apis.roblox.com.

Com isso eu rodo `tools/roblox_cloud.py all`, que faz quatro coisas:
- sobe os 79 assets (sons, modelos e roupas);
- preenche `AssetIds.luau`;
- cria os 4 passes e os 2 produtos de apoio;
- publica o place.

## 2. Configurações que o Roblox só deixa o dono fazer (15 min)
Textos prontos e imagens: **`LANCAMENTO.md`** (página do jogo, guia do questionário e beta).
- **Questionário de maturidade:** alvo **Moderate** (Parte 9.10), com violência realista não
  gráfica e sangue leve. Sem isso o jogo não é aprovado para todos os públicos.
- **Servidores privados:** ligar e definir o preço (sugestão em `MONETIZATION.md`).
- **Assinatura "Reserva da Unidade":** criar só se a conta for elegível, e colar o ID em
  `SUBSCRIPTION_UNIT_RESERVE`.
- **Preços:** revisar as sugestões em `MONETIZATION.md`. Ativar o Managed Pricing depois das
  primeiras vendas.

## 3. Testar no Studio o que eu não consigo medir aqui
Nada rodou dentro do Roblox. Os critérios abaixo exigem o Studio ou o jogo publicado. Abra
`place/VanTuong65.rbxl`, use Test → Local Server e me mande os erros do Output e os números do HUD
(F3).

| Fase | O que medir |
|---|---|
| F1 | fps (99% dos quadros ≥ 60) e travessia leste–oeste a pé |
| F2 | partida de 60 min sem erro no servidor (os bots completam 15v15) |
| F3 | fps no setor 3 com a arte e comparação lado a lado com fotos de 1965 |
| F4 | 30v30 com os 6 veículos ativos e heartbeat do servidor estável |
| F5 | fps no pior setor com a arte. O Output mostra `[VT65] arte setor N` e a fração das sebes |
| F6 | beta fechado: 2 partidas cheias sem crash (Warfare e Offensive), tutorial e campo de tiro (roteiro em `LANCAMENTO.md`) |

F5: o teto de arte por setor (`ArtBudget.SECTOR_MAX`, 2,5 milhões) é um chute conservador.
- Se o fps sobrar, diga quanto: eu subo o teto e as sebes ganham touceiras.
- Se faltar, eu desço o teto.

Features de lançamento (D-48). Confira no Studio:
- **Acessibilidade:** menu do jogo (P) → Configurações → Acessibilidade:
  - modo daltônico (cor dos traçantes);
  - campo de visão;
  - legendas de som.
- **Relatório pós-ação:** aparece no fim da partida. Para não esperar, rode na barra de comando,
  no lado do servidor: `workspace:SetAttribute("VT65DevEnd", true)`. Para trocar de modo:
  `workspace:SetAttribute("VT65DevMode", "Offensive")`. Só funciona no Studio.
- **Marcação imperfeita:** binóculo (B ou ↑) + marcar (Z ou RB) num inimigo. Aparece um círculo
  que some em 1 min.
- **Arma do inimigo:** mate um bot e segure F ou X sobre a arma caída.
- **Equipamento por peso:** menu → Squad e papel; vale no próximo spawn.
- **Operador de rádio:** papel novo. Sem ele, o líder do squad não fala com o comandante.
- **Pá:** roda de equipamento → Pá de trincheira, em setor do seu lado e fora da água.
- **Medevac:** pouse o UH-34D a até 15 m de um ferido caído.
- **Animais:** atire perto de uma vila. Se o búfalo andar de ré, troque o sinal em
  `AnimalService.FACE_YAW`.

Roteiro da F4:
1. Escolha EUA → papel *Tripulante de blindado* → sente no M48A3 (W/S/A/D) e no LVTP-5 (entre na
   água: deve cair para 11 km/h).
2. Escolha *Piloto* → UH-34D: Espaço/Ctrl coletivo, W/S/A/D cíclico, Q/E pedais. No calor e
   carregado, ele **não paira fora do efeito solo**: decole correndo.
3. Escolha *Comandante* → **N** → digite a grade (o painel mostra a sua) e peça tiro naval.
   Depois corrija com "mais 100, direita 50".
4. Escolha *Morteiro* → **J** → posição de morteiro → **N** → missão de 81 mm. Do lado VC, use o
   82 mm.
5. Escolha *Antitanque* (VC) → **Z** dispara o RPG-2 contra o M48. Pela frente não deve furar;
   pelo lado, sim.
6. Se a arte de um veículo aparecer de ré (o canhão para trás), troque `math.rad(90)` por
   `math.rad(-90)` em `ART_YAW` (`VehicleService.luau`). O ForgeGUI não informa a frente do modelo.

### Controle (Parte 12): só com controle real
Jogue **3 partidas inteiras só com controle**, sem tocar no mouse nem no teclado, passando por:
- todos os papéis;
- os veículos;
- o mapa, o spawn, o comandante (alvo no mapa) e o menu do jogo (segurar View).

Anote qualquer tela sem foco, qualquer botão que não respondeu e qualquer estado travado. Para
gravar a sessão, use F8 no teclado do PC de teste; F9 reproduz.

Matriz:

| Controle | Plataforma |
|---|---|
| Xbox Series | PC, com fio e Bluetooth |
| DualSense | PC, com fio e Bluetooth |
| DualShock 4 | PC |
| Genérico | PC |
| Xbox Series X\|S | console |
| PlayStation 5 | console |

Confira também:
- os ícones certos de cada controle;
- a vibração;
- o texto lido a 3 m da TV;
- o piso de 60 fps no console.

Há relatos de Thumbstick1/ButtonA sem resposta no Input Action System. A reserva no
UserInputService já cobre, mas diga se notar atraso.

## 4. Decisões históricas que precisam de você ou de um consultor
- Confirmar o fuso de 1965 (**UTC+8**, hora de Saigon), que define a luz do amanhecer (D-27).
- Fotos de 1965 para conferir as cores dos uniformes e os modelos (dossiê da Parte 9.1).
- Consultor vietnamita para casas, altares, túmulos e vozes (Parte 9.9).

## 5. ForgeGUI (a decisão de gastar crédito é sua)
O **gerador de imagens** do ForgeGUI está terminando os pedidos em `outcome_unknown`
("worker interruption" aos 15 min). Isso já aconteceu com 6 moldes de roupa, 3 texturas de tecido
e o som do rotor do UH-34D. Os de modelos 3D e de sons funcionam.

- O **remesh** (redução de malha) também falhou assim **10 vezes** na F5: cozinha, celeiro, poço,
  altar, túmulo, capacete M1, colete, capacete de fibra, morteiro 82 mm e uma tentativa do bambu.
  - Os jobs estão em `ASSETS.csv`.
  - Já resolvi por redução local, sem crédito (D-45). O chamado serve para conferir a cobrança.
- Vale abrir um chamado no suporte do ForgeGUI, com os jobs listados em `ASSETS.csv`, e confirmar
  se houve cobrança.
- A regra do serviço é **não regenerar** esses jobs.
- As roupas já estão resolvidas por código (D-30).

Se o suporte do ForgeGUI confirmar que não houve cobrança, me autorize a pedir de novo.

## 6. Pesquisa (F0)
- Baixar as fotos **CORONA** de 1965–66 no USGS EarthExplorer com a sua conta (lista e passos em
  `research/F0_CORONA.md`). Elas fecham o erro < 25 m no setor leste e o uso do solo de 1965.

## 7. Repositório próprio
Esta sessão não pode criar repositórios. Se quiser o jogo fora do `a-o`:
1. Crie um repositório **vazio** `felpo2007/vantuong65`.
2. Me avise: eu movo a pasta com o histórico.

Hoje tudo está no branch `claude/bold-albattani-67hga9` do `felpo2007/a-o`. Se quiser, abro um PR
para o `main`.
