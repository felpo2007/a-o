# Resultados de QA: área piloto da Vila

Medido em 2026-11-22 numa cópia local no Studio, com o piloto ligado por `VT65DevPiloto`. Nada foi publicado.
O PC estava com outro jogo aberto, por isso nenhum número de fps ou de tempo de quadro entra aqui.

## Passou
| Teste | Resultado |
|---|---|
| Lune, mapas, pytest, ruff, luau-lsp, notas (`verifica.ps1`) | 1.014 testes Lune, 84 pytest, 0 erros |
| Autoteste do jogo com 52 bots e o piloto | 18 ok, 0 falhas, 0 pulados |
| Erros de script na partida | 0 |
| Montagem | 18 trocas, 50 cercas, 720 tufos de capim, 5 árvores afastadas, 143 peças, 0 falhas |
| Captura do Objetivo C | Passou de neutro para VC com os bots |
| Bots na Vila | 10 observados por 48 s: nenhum preso |
| Escada, varanda e porta da casa | Andando: subiu 2,5 m e entrou |
| Vento em jogo | `GlobalWind` 0, turbulência 0, ondas 0, no servidor e no cliente |
| Vento depois de respawn e em outro mapa | Continua 0 |
| Script tentando ligar o vento | Volta a 0 |
| Capim parado | Semelhança entre quadros de 0,95 (a casa dá 0,96). Com a grama nativa dava 0,5 |

## Desempenho: mesmo build, piloto desligado e ligado
Câmera a 1,7 m, FOV 70, sem bots. Cada linha é chamadas de desenho / milhões de triângulos.

| Vista | Qualidade | Sem piloto | Com piloto | Diferença |
|---|---:|---:|---:|---|
| Coração da Vila | 3 | 224 / 2,05 | 292 / 3,39 | +30% / +65% |
| Vila, olhando a mata | 3 | 152 / 1,82 | 209 / 3,73 | +38% / +105% |
| Mata B (controle) | 3 | 210 / 2,82 | 226 / 2,74 | +8% / -3% |
| Coração da Vila | 10 | 306 / 3,32 | 384 / 5,85 | +25% / +76% |
| Vila, olhando a mata | 10 | 187 / 2,09 | 255 / 4,71 | +36% / +125% |
| Mata B (controle) | 10 | 315 / 5,33 | 321 / 5,19 | +2% / -3% |

**O piloto ficou mais pesado na Vila.** Antes do capim, com tudo a mais de 130 m removido, ele somava só de 0,18 a
0,25 milhão de triângulos e de 59 a 84 chamadas. O resto vem de geometria distante. A causa provável é a casa sobre
esteios, que deixa ver a mata por baixo, mas isso não foi isolado.

## Não testado
- **Fps, 1% low, tempo de quadro de CPU e GPU:** exigem o PC sem outro jogo e a janela em primeiro plano.
- **Dois jogadores reais, celular, tablet e controle.**
- **Captura pelos EUA:** só a captura pelo VC foi vista.
- **SLIM:** só existe depois que o modelo entra no arquivo do place.
- **Streaming andando pela Vila:** só testado levando o personagem até o lugar.
- **Memória:** variou de 1,4 a 2,3 GB entre sessões, sem comparação confiável.

## Defeitos conhecidos
- A janela lateral da casa parece um retângulo preto por dentro: é o lado de baixo da aba de bambu.
- A grama nativa do terreno ainda existe no build normal. Ela se mexe mesmo com vento zero e só foi desligada por
  comando no teste. Tirá-la vale para o mapa inteiro.
- Telhados vermelhos antigos continuam em parte da Vila, porque só 18 construções foram trocadas.
