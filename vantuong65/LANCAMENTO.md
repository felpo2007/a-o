# Lançamento (F6): página do jogo, maturidade e beta fechado

Tudo aqui é para você colar no Creator Dashboard. Eu não tenho acesso à sua conta Roblox.

## 1. Página do jogo

**Nome:** `VẠN TƯỜNG '65`

**Descrição (português, 985 de 1.000 caracteres):**

```
Agosto de 1965, costa de Quảng Ngãi. Operação Starlite: fuzileiros navais dos EUA desembarcam em Green Beach e avançam contra o 1º Regimento Viet Cong entre arrozais, sebes de bambu, vilas e túneis.

• 30 contra 30 num mapa 1:1 de 4 × 2,4 km, feito a partir da carta militar e do relevo reais.
• Warfare: 5 setores em linha, 75 min. Offensive: os EUA atacam do mar, o VC defende setor por setor. Skirmish: 1 setor, 20 min.
• Papéis de squad, comandante com fogo naval e de morteiro pela grade, médicos, sapadores, túneis.
• M48A3, Ontos, LVTP-5 e helicóptero UH-34D com física calibrada com dados reais.
• Sem minimapa e sem marcador automático de inimigo: carta, bússola e rádio.
• Um ou dois tiros derrubam. Campo de tiro e tutorial por papel ao lado do QG.
• Operador de rádio, medevac, relatório pós-ação e modo daltônico.
• Jogável de ponta a ponta no controle (Xbox e PlayStation), no teclado e no mouse.

Itens à venda são só visuais e de apoio: nada compra vantagem em combate.
```

**Descrição (inglês, 973 caracteres, para a tradução automática não decidir sozinha):**

```
August 1965, Quảng Ngãi coast. Operation Starlite: US Marines land on Green Beach and push against the Viet Cong 1st Regiment through rice paddies, bamboo hedgerows, villages and tunnels.

• 30 vs 30 on a 1:1 map of 4 × 2.4 km, built from the real military chart and terrain.
• Warfare: 5 sectors in a line, 75 min. Offensive: the US attacks from the sea, the VC defends sector by sector. Skirmish: 1 sector, 20 min.
• Squad roles, a commander calling naval and mortar fire by grid, medics, sappers, tunnels.
• M48A3, Ontos, LVTP-5 and a UH-34D helicopter with physics calibrated on real data.
• No minimap and no automatic enemy markers: map, compass and radio.
• One or two hits put you down. Firing range and a short tutorial per role next to HQ.
• Radio operator, medevac, after-action report and colorblind mode.
• Fully playable on controller (Xbox and PlayStation), keyboard and mouse.

Items for sale are cosmetic or supporter-only: nothing buys a combat advantage.
```

**Imagens** (`assets/forgegui/marketing/roblox/`, geradas por `tools/make_store_images.py`):

| Uso | Arquivo | Observação |
|---|---|---|
| Ícone | `icone_512.png` | Capacete M1 sobre sacos de areia. O helicóptero ao fundo parece um UH-1; confira se combina com agosto de 1965 ou use `icone_512_alternativo.png` |
| Miniatura 1 | `miniatura_1_16x9.jpg` | Key art (fuzileiros no arrozal), 1365×768, 16:9 exato e sem ampliar |
| Miniaturas 2–5 | — | Capturas suas no Studio: helicóptero sobre o arrozal, carta de 1965, túnel, campo de tiro. Capturas do jogo vendem melhor que arte e mostram o que o jogador vai ver |

**Gênero:** Shooter. Escolha na lista do Creator Dashboard o subgênero mais próximo de tático ou
militar; a lista muda, por isso não cito o nome exato.

**Dispositivos:** computador, console (Xbox e PlayStation) e celular. No celular a interface de
toque existe só no que o Roblox dá por padrão: avise que é "melhor no controle ou no PC".

## 2. Questionário de maturidade (alvo: Moderate, Parte 9.10)

Responda pelo que o jogo **tem hoje**. Conferi no código em 2026-11-10:

| Tema | O que o jogo tem | Fonte |
|---|---|---|
| Violência | Armas de fogo realistas, explosões, personagens incapacitados e mortos. Sem desmembramento, sem execução, sem tortura | `CombatService`, `MedicalService`, `ExplosionService` |
| Sangue | **Nenhum efeito visual de sangue** no código atual. O sangramento é mecânica, com texto e efeito de tela (cor e desfoque), sem sangue visível. A Parte 9.10 permite sangue leve; se ele for adicionado, refaça esta resposta | busca por `blood`/`sangue` sem resultado em `src/` |
| Linguagem | Sem palavrão nos textos do jogo. As vozes em vietnamita ainda não existem | `Comms.luau`, interfaces |
| Humor grosseiro, medo, romance | Não há | — |
| Álcool, drogas, tabaco | Não há | assets do `ASSETS.csv` |
| Apostas e itens aleatórios pagos | Não há: preços fixos; caixas aleatórias rejeitadas (`MONETIZATION.md`) | `Commerce.luau` |
| Chat | Chat de texto padrão do Roblox, sem alteração pelo jogo. Voz não é ligada pelo jogo | sem `TextChatService` em `src/` |
| Evento real | Batalha real de 1965 (Operação Starlite), com os dois lados jogáveis. **Sem bandeiras nem símbolos políticos** nas artes e no jogo | key art, ícones e passes conferidos |

**Risco que só você decide:** as diretrizes do Roblox tratam com cuidado eventos reais sensíveis e
conflitos políticos. O jogo é histórico e neutro, mas uma guerra real com nomes reais pode cair
em revisão manual. Leia as diretrizes atuais antes de publicar e mantenha a página como está:
factual, sem glorificação e sem símbolo político.

## 3. Beta fechado (critério da F6: 2 sessões cheias sem crash)

1. Publique o place (eu publico sozinho quando a chave Open Cloud funcionar: `TODO_USUARIO.md`,
   item 1) e deixe a experiência **privada**.
2. Ligue os servidores privados (`MONETIZATION.md`) e crie um.
3. Convide ~60 testadores, ou 20–30 e deixe os bots completarem.
4. Rode **2 partidas inteiras**:
   - uma de Warfare (75 min);
   - uma de Offensive. Na aba **Servidor** do menu do jogo (P ou segurar View), escolha o modo.
5. Durante as partidas, colete:
   - o **Output do servidor** (Developer Console, F9 no jogo → Server);
   - `[VT65] arte setor`, para comparar com o fps;
   - o HUD de medição (F3) de 3 ou 4 jogadores em setores diferentes.
6. "Sem crash" = nenhum servidor caiu, nenhum erro vermelho repetido no Output e nenhum jogador
   preso sem conseguir renascer.
7. Mande para mim:
   - os erros (copie o texto);
   - os números do F3;
   - o que os testadores acharam do tutorial e do Offensive (tempo de 20 + 15 min por setor).
