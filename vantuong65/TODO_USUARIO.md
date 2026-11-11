# O que só você pode fazer (VẠN TƯỜNG '65)

Fiz sozinho tudo o que não depende da sua conta Roblox, de dinheiro, de decisão sua ou de abrir o
Studio. A lista abaixo segue a ordem de prioridade. O que está em **negrito** destrava a maior parte
do resto.

## 1. ~~Criar a experiência e me dar acesso de publicação~~ (feito em 2026-11-10)
- A experiência foi criada, e os números estão em `cloud.json`.
- A chave Open Cloud está no `.env` e funciona. **A chave nunca vai no chat nem no Git.**
- 82 assets estão publicados: sons, modelos, roupas e os animais. O place foi publicado.
- Falta criar os 4 passes e os 2 produtos de apoio (`tools/roblox_cloud.py create-store`). Isso
  só quando você decidir os preços (`MONETIZATION.md`).
- **Itens em Robux da D-72 (kits e renascer onde caiu): a chave não tem permissão.** Tentei criar
  em 2026-11-11 e o Roblox respondeu "Scope not authorized". Escolha um dos caminhos:
  1. **Dar a permissão à chave** (5 min): Creator Dashboard → Open Cloud → API Keys → a chave do
     VT65 → em Access Permissions, adicione **game-pass** e **developer-product** com
     leitura e escrita, na experiência VẠN TƯỜNG '65 → Save. Depois me avise: eu rodo
     `create-store PASS_KIT_VETERAN PASS_KIT_ELITE PRODUCT_RESPAWN_INPLACE`.
  Também tentei pelo Studio (assistente com MCP, 2026-11-11): "Scope 'developer-product:write'
  has not been granted". Outro caminho é liberar no Studio: Assistant → MCP Permissions →
  **game-pass:write** e **developer-product:write**, e aprovar a pasta
  `assets/forgegui/marketing` para o ícone subir.
  2. **Criar à mão** no Creator Dashboard → a experiência → Monetization:
     - Game Pass "Kit Veterano", R$ 149, ícone `assets/forgegui/marketing/gamepass_kit_veterano.jpg`;
     - Game Pass "Kit de Elite", R$ 299, ícone `assets/forgegui/marketing/gamepass_kit_elite.jpg`;
     - Developer Product "Renascer onde caiu", R$ 25.
     Depois me mande os 3 IDs: eu colo em `Shared/Commerce.luau` e publico.
  Enquanto os IDs forem 0, tudo funciona com os créditos do jogo e pelo posto; só o botão de
  Robux fica escondido.
- **Perfil salvando nos testes do Studio** (opcional, 1 min). É configuração de segurança, por isso
  fica com você. Sem ela, o Output avisa "Studio access to APIs is not allowed" e o perfil não salva
  no Studio; no jogo publicado não muda nada.
  1. No Studio, com o place aberto e fora do Play: aba **Página Inicial (Home)** → **Configurações
     do jogo (Game Settings)**.
  2. Na lista da esquerda: **Segurança (Security)**.
  3. Ligue **Ativar acesso do Studio aos serviços de API (Enable Studio Access to API Services)**.
  4. **Salvar (Save)**.

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
| F1 | fps (99% dos quadros ≥ 60) e travessia leste–oeste a pé (2 km: esperado 8–12 min, D-63) |
| F2 | partida de 60 min sem erro no servidor (os bots completam 15v15) |
| F3 | fps no setor 3 com a arte e comparação lado a lado com fotos de 1965 |
| F4 | 30v30 com os 6 veículos ativos e heartbeat do servidor estável |
| F5 | fps no pior setor com a arte. O Output mostra `[VT65] arte setor N` e a fração das sebes |
| F6 | beta fechado: 2 partidas cheias sem crash (Warfare e Offensive), tutorial e campo de tiro (roteiro em `LANCAMENTO.md`) |

**Mata com as árvores prontas (D-67): meça o fps no jogo publicado.**
- As 3 árvores do ForgeGUI viraram 4 árvores do Poly Haven com folha em cartão recortado, com o
  mesmo número de triângulos.
- No Studio em primeiro plano deu 53,2 fps de média no ponto mais denso (99% dos quadros abaixo
  de 25 ms); na D-66 eram 45.
- No jogo, sem o Studio, o número tende a ser maior.
- Com o FC 26 aberto ao mesmo tempo, a GPU de 2 GB travou no Studio (`DXGI_ERROR_DEVICE_HUNG`).
- Onde: nasça pelos EUA e entre na mata entre An Thới (2) e Nam Yên (4). Olhe o HUD (F3).
- Se ficar abaixo de 60, diga o número: eu desço `ArtBudget.JUNGLE_DENSITY`.
- Se sobrar, dá para pôr mais mata.

**Armas com mais detalhe (opcional, decisão sua).** Na D-67 as 9 armas ganharam aço fosco e
textura mais nítida, mas a malha continua a do gerador. Para mais detalhe, o caminho é o do Front44:
você baixa modelos do Sketchfab com a sua conta (eu não posso entrar nem criar conta) e eu preparo.
Candidatos com licença CC BY (crédito obrigatório, que eu ponho no README e na página), achados
pela busca pública em 2026-11-11. Confira a qualidade na página antes de baixar:
- SKS: "Type 56 Carbine / SKS" (haoliu95, 54,6 mil triângulos)
  https://sketchfab.com/3d-models/d5fc1eb5bbd549b7818a63f4decaa86f
- M60: "M60 Light Machine Gun" (Badboy17Aiden, 19,8 mil)
  https://sketchfab.com/3d-models/cbf408387dc94a30abe11afb3698ac13
- RPD: "Low-Poly RPD" (TastyTony, 13,5 mil)
  https://sketchfab.com/3d-models/fecd845923fb4106b2abca4a80f82491
- M79: "M79 Grenade Launcher" (denis1.eremin, 8,5 mil)
  https://sketchfab.com/3d-models/f1309916894a45e3ae6eb24f17f728d4
- Type 56: "TYPE-56-1 LOW POLY" (eninbolshevik1918, 12,5 mil)
  https://sketchfab.com/3d-models/39af2dd81b6549b9905b03f4a192edd8
- M1911 e Type 54 (TT-33): já estão baixadas no Front44 (`Downloads\F44_Sketchfab`, CC BY).
- M14 e RPG-2: a busca não achou modelo baixável com licença livre.

**ForgeGUI sem crédito:** restam 3.693, e cada modelo custa 4.000.
- Com mais crédito, gero o monte de cipó e uma copa tomada de cipó nova; a de agora ficou em
  `outcome_unknown`.
- Planos: https://forgegui.com/plans

F5: o teto de arte por setor (`ArtBudget.SECTOR_MAX`, 16 milhões desde a D-64) segue sem medição.
- Se o fps sobrar, diga quanto: eu subo o teto e as sebes ganham touceiras.
- Se faltar, eu desço o teto.

**Autoteste no motor (mais rápido):** durante o Play, na barra de comando do lado do servidor,
rode `workspace:SetAttribute("VT65SelfTest", true)`.
- Em ~2 min, o Output mostra uma linha `[VT65 TESTE] ok/FALHA/pulado` por sistema:
  terreno, bots, campo de tiro (raia e balística), deitado, arma caída, rádio, animais, arte no
  chão, chuva, pá, medevac, Offensive e relatório pós-ação.
- Me mande essas linhas. Para o teste da pá, escolha o lado EUA.

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
- **Armadilhas VC:** sapador VC → roda de equipamento → Construir → estacas ou granada com fio.
  Depois, como engenheiro EUA, chegue agachado perto: deve aparecer "Armadilha à vista".
- **Animais:** atire perto de uma vila: eles devem fugir. A frente do búfalo e da galinha já foi
  conferida no Studio (D-58).

Roteiro da F4:
1. Escolha EUA → papel *Tripulante de blindado* → sente no M48A3 (W/S/A/D) e no LVTP-5. O mapa de
   2 × 2 km não tem mar (D-63): o LVTP-5 só anda em terra.
2. Escolha *Piloto* → UH-34D: Espaço/Ctrl coletivo, W/S/A/D cíclico, Q/E pedais. No calor e
   carregado, ele **não paira fora do efeito solo**: decole correndo.
3. Escolha *Comandante* → **N** → digite a grade (o painel mostra a sua) e peça tiro naval.
   Depois corrija com "mais 100, direita 50".
4. Escolha *Morteiro* → **J** → posição de morteiro → **N** → missão de 81 mm. Do lado VC, use o
   82 mm.
5. Escolha *Antitanque* (VC) → **Z** dispara o RPG-2 contra o M48. Pela frente não deve furar;
   pelo lado, sim.
6. A frente da arte dos 4 veículos já foi conferida no Studio (D-58: `ART_YAW` = −90°). Diga se
   algum ainda parecer de ré.

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
