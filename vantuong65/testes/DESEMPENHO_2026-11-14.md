# Desempenho: medida e o que alivia a mata (lote 13, 2026-11-14)

Pedido do dono: seguir com "um lote de desempenho (medir e aliviar a mata)", depois da análise do
lote 12 (`testes/ANALISE_LOTE12_2026-11-14.md`).

**Como foi medido:** Studio pelo MCP, place da v57. Com a câmera parada (Scriptable) em vistas fixas,
o cliente mede o fps pela média do `RenderStepped` em 120 a 150 quadros. Ele lê também o tempo de
desenho por quadro: `Stats.RenderCPUFrameTime` (CPU) e `RenderGPUFrameTime` (GPU). Para cada parte
do cenário escondida (`Transparency` = 1), mede de novo e mede a volta.

## Duas armadilhas da medida no Studio
1. **Janela em segundo plano:** o Studio limita o jogo a 15 fps. Com o Studio atrás de outra janela,
   todas as vistas deram 15 fps cravados, com ou sem corte. Os "7–15 fps" da análise do lote 12
   vinham disso. Antes de medir: trazer o Studio para a frente
   (`(New-Object -ComObject WScript.Shell).AppActivate(<pid>)`). Com a janela na frente, a mesma
   sessão foi a 55,8 fps.
2. **Bots no mesmo processo:** no Studio, o servidor (com os bots) roda na mesma máquina e disputa a
   CPU com o cliente. Para isolar o desenho: `ReplicatedStorage:SetAttribute("BotFill", 0)` (sem bots;
   `nil` devolve). Num servidor do Roblox, o servidor roda em outra máquina.

## Resultados (Studio na frente, PC do dono)
| Vista | Sem bots | Com bots (24, servidor a 36 Hz) | Sem a mata |
|---|---|---|---|
| Base dos EUA olhando a oeste | 38–43 fps | 24–28 fps | 50 fps |
| Xóm Gò olhando a mata A | 46–49 fps | 38–42 fps | 60 fps |
| Borda da mata A | 50–51 fps | — | 60 fps |

O tempo de desenho, olhando a mata, foi de 18 a 21 ms na CPU e de 7 a 9 ms na GPU. O gargalo é a CPU
(quantidade de coisas a desenhar), não a placa.

**O que cada parte custa** (diferença de fps ao esconder, vistas acima, sem bots):
- árvores do Poly Haven (5.991 peças: tronco, galhos e copa transparente): 6 a 11 fps;
- arbustos (1.585 peças, 10,5 mil triângulos cada): ~4 a 5 fps;
- o resto da mata (bambu, palmeiras, capim-elefante, taioba, bananeira, tràm): a medida oscilou
  (−5 a +5 fps);
- a mata inteira: ~10 fps (~5 ms de CPU e ~5 ms de GPU);
- sombra do sol: ~4 fps;
- interface: ~1 fps; pós-efeitos (brilho, raios, cor): ~1 fps;
- casas e objetos: nada mensurável.

## O que foi tentado e não entrou
**Não desenhar as plantas baixas longe da câmera** (arbusto, taioba, capim-elefante e bananeira a
mais de 200 m; árvores ficam). Com o Studio na frente e sem bots, o ganho ficou no ruído:
- base: 43,1 → 44,7 e 41,5 → 34,3 fps;
- Xóm Gò: 49,0 → 48,2 e 48,7 → 48,4;
- borda da mata: 49,6 → 52,2 e 50,7 → 51,7.

Como tinha um custo de jogo (a mais de 200 m, um soldado deitado atrás de um arbusto ficaria à
vista), o corte saiu. O `LocalTransparencyModifier` também não tirou o custo de forma estável.

## O que pode aliviar de verdade (decisão do dono)
Cada uma muda o visual ou um pedido anterior:
1. **Menos árvores na mata:** as árvores são o maior custo. Com −30% delas, o ganho esperado é de
   ~2–3 fps, proporcional ao custo medido (estimativa, não medida). A mata do objetivo A ficou 1,8
   vez mais cheia a pedido (D-123).
2. **Menos arbustos:** −50% deve dar ~2 fps (estimativa).
3. **Sombra do sol desligada por padrão:** ~4 fps medidos. Hoje ela vem ligada (`InputMap.gfxShadows`
   = true) e o jogador pode desligar nas configurações.
4. **Malha mais leve na vegetação:** fora, porque a D-66 pede no mínimo 8 mil triângulos por planta.

**O que falta medir:** um celular de verdade e o jogo publicado num servidor do Roblox. O contador no
canto da tela ("FPS · ms") já mostra o fps no aparelho.
