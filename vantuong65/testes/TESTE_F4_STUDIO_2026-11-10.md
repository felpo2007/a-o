# Teste da F4 e da arma nas mãos no Studio (2026-11-10, até 12:20)

Studio 0.746, Play solo com 29 bots, pelo MCP. O place salvo às 12:20 tem as mudanças da D-55.

## Como o papel foi escolhido
Blindado e helicóptero só abrem com o time a partir de 16 (`Roles.HEAVY_UNLOCK`). No Play solo do
Studio o time EUA tem 15 (14 bots e o jogador), então o menu não oferece esses papéis. Para testar,
defini `Role` (e, no RPG, `Faction`) direto no servidor e sentei o jogador pelo `Seat:Sit`. Os
comandos de direção foram as teclas reais (W, Espaço) pelo MCP.

## Resultados
| Item | Resultado | Medido |
|---|---|---|
| M48A3: sentar como motorista | ok | assento ocupado; a física passa ao jogador (`GetNetworkOwner`) |
| M48A3: W por 6 s | ok | ~19 km/h aos 5 s, na areia da praia (o cálculo para estrada é 26,5 km/h); freia ao soltar; chassi a 3° |
| UH-34D: piloto, Espaço por 6 s | ok, com ressalva | decola e sobe a **8,0 m/s constantes**, que é o teto do código (`math.clamp(climb, -10, 8)`); continua subindo ao soltar, porque o coletivo fica onde foi posto |
| RPG-2 (VC) contra o M48A3, de frente, a 11 m | ok | integridade 100 → 100 (não furou) |
| RPG-2 contra o M48A3, de lado, a 11 m | ok | integridade 100 → 19 (furou) |
| Erros de script | nenhum | cliente e servidor |

**Ressalva do UH-34D:** com pouca carga, o modelo de potência dá subida acima de 8 m/s, e o código
corta em 8. A ficha usada na calibração (D-38) é de 600 ft/min (3 m/s) em subida vertical na carga
máxima. Falta decidir o teto da subida com carga leve a partir de uma fonte. Não mudei o número.

## Arma nas mãos e traçante (D-55)
- **Mãos na arma (IK):** num bot em pé, a mão direita fica no punho (0,00 stud) e a esquerda a
  0,32 stud (9 cm) do apoio. Testei em 3 bots.
- **Deitado:** a arma fica a 0,21 m do chão, com o cano na horizontal. A mão esquerda fica a 8 cm do
  apoio e a direita a 23 cm do punho.
- **Traçante da M60:** numa rajada de 2,5 s houve 26 clarões e 2 traçantes. Cada risco tem 3,4 m e
  anda pela trajetória. Com 1 traçante em 5, a média seria ~5; 2 é um resultado possível só pelas
  sementes, mas fica anotado.

## Segunda rodada (até 12:42): comandante, morteiro, Ontos, mar e LVTP-5
| Item | Resultado | Medido |
|---|---|---|
| Tiro naval 5" (comandante), alvo pelo mapa a 800 m | ok | 1 disparo do navio; 4 impactos com 3 s entre eles, a 37–88 m do alvo (média 67 m; CEP de projeto 60 m); aviso de chegada 2,5 s antes |
| Morteiro 81 mm, alvo a ~900 m | ok | resposta "no alvo em 30 s · elevação 1140 mils"; 6 disparos e 6 impactos a 21–81 m (média 46 m; CEP 35 m) |
| Ontos, canhão 106 mm | ok | tubos 6 → 5 → 4; 2 impactos |
| **Mar** | **corrigido** | o terreno não tinha mar: 1 ponto de água no mapa todo. O DEM dá 0 m no mar, e o gerador só põe água abaixo de 0. Agora o fundo desce da costa (D-56); há água a leste da praia |
| **LVTP-5 na água** | **corrigido** | flutuando, o centro do chassi fica abaixo da superfície, e o raio do piso acertava a areia do fundo: andava a 21 km/h na água. Agora o raio sai do topo: **10,8 km/h** na água (ficha: 11), andou 22 m, flutua |
| Erros de script | nenhum | |

Para o comandante e o morteiro, o papel e a posição do tubo (`MortarX`/`MortarZ`) foram definidos
no servidor; o pedido foi o remote do jogo (`Commander_Request`), igual ao do painel.

**Efeito de teste, não do jogo:** mover pelo servidor um veículo parado faz o `AlignOrientation`
voltar o rumo ao de origem. Por isso, nos testes, os veículos andaram para lados diferentes do
pedido.

## Não testado
- A construção da posição de morteiro pela tecla J e o painel do comandante (digitar a grade e
  "mais 100, direita 50"). A conta da correção é testada no Lune (`f4.luau`).
- Tudo com mais de um jogador (o MCP só roda Play solo).
