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
4. **A chave nunca vai no chat nem no Git.** Quando eu pedir, um formulário seguro aparece. Cole a
   chave lá: ela fica no ambiente e o proxy a injeta nas chamadas a apis.roblox.com.

Com isso eu rodo `tools/roblox_cloud.py all`, que faz quatro coisas:
- sobe os 79 assets (sons, modelos e roupas);
- preenche `AssetIds.luau`;
- cria os 4 passes e os 2 produtos de apoio;
- publica o place.

## 2. Configurações que o Roblox só deixa o dono fazer (15 min)
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

## 4. Decisões históricas que precisam de você ou de um consultor
- Confirmar o fuso de 1965 (**UTC+8**, hora de Saigon), que define a luz do amanhecer (D-27).
- Fotos de 1965 para conferir as cores dos uniformes e os modelos (dossiê da Parte 9.1).
- Consultor vietnamita para casas, altares, túmulos e vozes (Parte 9.9).

## 5. ForgeGUI (a decisão de gastar crédito é sua)
Três pedidos terminaram como `outcome_unknown`. A regra do serviço é **não regenerar** sem confirmar
se houve cobrança:
- loop do rotor do UH-34D;
- 6 moldes de roupa: no lugar deles há placeholders gerados por código;
- capa v1/v2: já refeita na v3.

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
