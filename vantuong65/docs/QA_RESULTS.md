# Resultados de QA: setor piloto da Vila

Medido em 2026-11-23 numa cópia local no Studio, com `VT65DevPiloto`. Nada foi publicado.
O jogo do dono estava aberto em segundo plano, por isso nenhum número de fps entra aqui.

## Passou
| Teste | Resultado |
|---|---|
| `verifica.ps1` | Lune, mapas, pytest, ruff, luau-lsp e notas sem erro |
| Montagem | 32 construções (24 + 8 bancas), 19 cercas, 166 plantas, 254 capim, 134 peças, 0 falhas |
| Erros de script na partida | 0 |
| Captura do Objetivo C | Neutro para EUA, com um jogador parado no centro, em menos de 90 s |
| Bots | 14 observados por 80 s: 3 no setor, nenhum preso nele |
| Caminhada | Portão do pagode, mercearia, casa de chá, casa comunal, entrada sul e fundos do mercado |
| Troncos | 31 com colisão; 29 de 30 raios pararam neles |
| Vento | `GlobalWind`, ondas e velocidade das ondas em 0 |

## Falha intermitente
**Granada de bot no autoteste.** Com o setor: 2 rodadas com 18 de 18 e 2 com 17 de 18, com a granada a 13,8 m e 5,3 m do
alvo (o limite é 5 m). Sem o setor: 1 rodada válida, 18 de 18. Nas rodadas com a posição registrada, o bot estava na base
dos EUA, a mais de 200 m do setor. Isso sugere que o setor não é a causa, mas **a causa não foi isolada**.

## Desempenho: mesmo build, setor desligado e ligado
Câmera a 1,7 m, FOV 70, sem bots. Cada célula é chamadas de desenho / milhões de triângulos.

| Vista | Qualidade | Sem setor | Com setor | Diferença |
|---|---:|---:|---:|---|
| Coração da Vila | 3 | 229 / 2,10 | 318 / 3,22 | +39% / +53% |
| Vila, olhando a mata | 3 | 151 / 1,85 | 240 / 2,95 | +59% / +59% |
| Mata B (controle) | 3 | 212 / 2,85 | 275 / 2,86 | +30% / 0% |
| Coração da Vila | 10 | 304 / 3,42 | 410 / 5,09 | +35% / +49% |
| Vila, olhando a mata | 10 | 188 / 2,12 | 298 / 3,96 | +59% / +87% |
| Mata B (controle) | 10 | 316 / 5,34 | 380 / 5,36 | +20% / 0% |

- **O setor é mais caro.** Nas vistas da Vila, de 35% a 59% mais chamadas e de 49% a 87% mais triângulos.
- **A vista de controle subiu 20% a 30% em chamadas** com os mesmos triângulos. A causa não foi isolada.
- Na qualidade 1, o coração da Vila com o setor deu 192 chamadas e 0,66 milhão de triângulos, sem comparação.

## Chão nu (critério 1 da direção de arte)
Fração de pixels cor de terra abaixo do horizonte, por classificação de cor. É uma medida aproximada. A meta é 35%.

| Câmera | Antes | Depois |
|---|---:|---:|
| Entrada | 73% | 74% |
| Pátio do objetivo | 97% | 85% |
| Residências | 70% | 14% |
| Vista aérea | 40% | 41% |
| Rua leste | 63% | 90% |
| Rua oeste | 73% | 64% |
| **Média** | **69%** | **62%** |

**Não atingido.** Só a câmera das residências fica abaixo da meta.

## Não testado
- **Fps, 1% low e tempo de quadro:** exigem o PC sem outro jogo e a janela em primeiro plano.
- **Duas pessoas, celular, tablet e controle.**
- **SLIM:** só existe depois que o modelo entra no arquivo do place.
- **Streaming andando de longe até a Vila:** o personagem foi levado até o lugar.
- **Escadas das casas sobre esteios neste lote.**
- **Memória:** variou entre sessões, sem comparação confiável.

## Riscos e defeitos conhecidos
- O Studio registrou até cerca de 500 avisos `Failed to upload TexturePack (429)` por sessão. Em uma sessão as texturas do
  pagode não carregaram; nas seguintes, sim. Não se sabe se isso acontece no jogo publicado.
- A grama nativa ainda existe no build normal e se mexe mesmo com vento zero.
- Janela lateral escura por dentro nas casas sobre esteios (lado de baixo da aba de bambu).
- Casas e coqueiros fora do setor continuam no padrão antigo, e a transição aparece na vista aérea.
