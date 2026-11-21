# 100 itens novos nas caixas: testes (D-178, 2026-11-16)

Nada foi comprado com Robux. Os itens vieram da troca de Fragmentos e de uma Caixa de Recompensa,
com Fragmentos e Bilhetes dados pelos ganchos de Studio (`VT65DevCaixa = "fragmentos"` e
`"bilhetes"`). O resultado saiu do servidor, como no jogo. O Studio rodou com cópias locais do place,
numa janela de 671 × 525.

## Lune e Python
- `tests/luau/caixas.luau` (27 ok):
  - são 100 itens novos;
  - a fatia de cada raridade nas 10 caixas é igual à de antes (a tabela da MONETIZATION, caixa por
    caixa);
  - todo item novo está numa caixa grátis e na de Suprimentos, com peso inteiro ≥ 1;
  - acrescentar raridade que a caixa não tem é recusado;
  - os 60 acabamentos novos não se compram com $ ("só nas caixas"), não têm produto de Robux e
    estão na troca de Fragmentos.
- `tests/luau/skins.luau` (17 ok) e `tests/luau/arquivo.luau` (9 ok): o catálogo com os 60
  acabamentos (`soCaixa`, chave "CAIXA") e o álbum com 175 itens.
- `tests/test_acabamentos.py` (6 ok):
  - as 60 receitas do catálogo existem no gerador;
  - cada uma das 23 pinta em 0..1 e tem desenho, com 1 a 4 cores;
  - o ruído repete com a mesma semente;
  - o triângulo cobre a área certa;
  - madeira, latão, metal e pano saem certos pela cor;
  - a laca de ouro fica ouro e a de madrepérola fica clara (o ouro saía branco e foi corrigido).
- Suíte inteira: 41 arquivos Lune, 697 ok e 0 falhas; pytest 67; ruff, StyLua e luau-lsp limpos
  (só os 2 avisos antigos do LoadingScreen).

## Texturas (`tools/acabamentos.py`)
- 83 texturas (60 novas e 23 dos acabamentos antigos), com prévia de lado de cada arma. Revisadas
  arma por arma. Receitas refeitas depois da 1ª prévia:
  - tigre, damasco, carbono, escamas, lava e chamas;
  - raio, curvas de nível, estrelas, titânio queimado e laca;
  - malaquita (receita nova);
  - camuflagem e pixel passaram a medir a cobertura.
- Bandoleira: na Tipo 56 e na M14 o pano verde-oliva entrava como madeira. Agora é "pano" e não
  é pintado (conferido na prévia das máscaras).

## Studio
- Grade de 12 armas com os acabamentos novos (`acabamentos_d178/armas_novas.jpg`): a textura cai
  certa na malha de cada arma.
- Acabamentos antigos que antes não apareciam (`armas_antigas_e_novas.jpg`): M14 de bétula, M14
  com fita, M60 verde-oliva e outros, agora visíveis.
- Fluxo real, troca → equipar → campo:
  - a troca de 2.500 Fragmentos deu o "M14 · Tigre de Fogo" (lendário);
  - `Gear_Equip` → `WeaponSkins = m14=skin_m14_tigre_fogo`;
  - a M14 de 1ª e de 3ª pessoa veio com a textura e a SurfaceAppearance guardada
    (`primeira_pessoa_m14.jpg`).
- Cartão: emblema Aurora, plaqueta de titânio azul e moldura de gelo, trocados e equipados. O
  degradê aparece no fundo do emblema (a sigla fica na cor dela), na plaqueta e na borda da
  moldura (`cartao_degrade.jpg` mostra as imagens dos itens).
  - Voltando ao emblema comum, o degradê some (fundo escondido, sem UIGradient).
- Roleta da Caixa de Recompensa: parou no item do servidor (índice 42, desvio de 0,5 px). Saiu o
  "M60 · Noite Urbana", acabamento novo comum (`recompensa_m60.jpg`).
  - EQUIPAR → em campo de metralhador, a M60 de 1ª pessoa veio com a textura dele (o ID confere com
    o resolvido).
- 0 erros no cliente e no servidor.

## O que ficou de fora ou não foi testado
- Aviso no Output do Studio: cada textura nova no `TextureID` escreve 3 vezes "No asset content
  representation found". Acontece com a imagem enviada como Image e com a de Decal, e mesmo
  pré-carregada por ImageLabel; a textura carrega e aparece. As texturas ficaram como Decal (como
  as do chão e da loja). Não foi visto no jogo publicado.
- A textura leva 1 a 3 s para chegar na primeira vez; antes disso a arma aparece clara. A roleta
  pré-carrega as texturas da faixa antes de girar (até 1,5 s, junto dos moldes).
- Sem a SurfaceAppearance, a arma com acabamento perde o mapa de relevo e o de brilho da original.
  Script não troca o mapa de cor de uma SurfaceAppearance.
- A M79 e o RPG-2 têm acabamentos antigos com textura nova, mas não foram vistos no Studio.
