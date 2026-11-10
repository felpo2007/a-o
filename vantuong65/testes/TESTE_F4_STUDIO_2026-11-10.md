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

## Não testado
- LVTP-5 entrando na água (deve cair para ~11 km/h): não há água a menos de 200 m a leste do
  depósito.
- Comandante (tiro naval por grade e correção), morteiros 81/82 mm e Ontos.
- Tudo com mais de um jogador (o MCP só roda Play solo).
