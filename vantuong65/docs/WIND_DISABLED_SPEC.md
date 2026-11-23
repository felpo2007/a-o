# Regra: não existe vento no jogo

Prompt V5, §4. Decisão D-253. Vale para todos os mapas, dispositivos e efeitos.

## Como é garantido
- `Shared/SemVento` zera `GlobalWind` e `AirTurbulenceIntensity` no servidor e no cliente, e volta a zerar se algum
  script mudar a propriedade.
- `tests/luau/sem_vento.luau` varre o código e falha se aparecer vento novo.

## O que saiu
| Sistema | Antes | Agora |
|---|---|---|
| Poeira no ar em volta da câmera | flutuava | removida |
| Folhas caindo sob a copa | caíam | removidas |
| Camuflagem de mato no uniforme | balançava | parada |
| Som de vento na cabine dos veículos | tocava | removido |
| Partículas com `WindAffectsDrag` | ligado | desligado |
| Fumaça de explosão | pendia para um lado | sobe reta |
| Ondas na água do terreno | ligadas | desligadas |

## O que continua, porque não é vento
Poeira de veículo, impacto, estojos, fumaça de tiro e de incêndio, respingos, explosões, rotor, animação de
personagens e animais. A poeira parada na luz dos lampiões, dentro das casas, também fica.

| Bandeira da comemoração | ondulava | dobras fixas |

## Conferido
- Nos testes de código: 6 de 6.
- Em jogo, no servidor e no cliente: `GlobalWind = 0, 0, 0`, `AirTurbulenceIntensity = 0`, ondas 0.
- Continua zero depois de respawn, em outro mapa e quando um script tenta ligar o vento.
- Capim do piloto parado: semelhança de 0,95 entre dois quadros, contra 0,96 da casa.

## Pendente: a grama nativa do terreno
Com `GlobalWind` zero, a grama de `Terrain.Decoration` **continua se mexendo** (semelhança de 0,5 entre quadros).
Script do jogo não pode desligá-la: só o arquivo do place, em `tools/bake_place.luau`. Desligar vale para o mapa
inteiro e deixa o chão liso onde ainda não há capim parado, por isso fica para depois da aprovação do piloto.
