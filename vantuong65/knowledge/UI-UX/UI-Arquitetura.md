---
project: STARLITE
type: system
status: verified
source_paths:
  - src/ReplicatedFirst/Estilo.luau
  - src/ReplicatedFirst/Cortina.luau
  - src/ReplicatedFirst/Idioma.luau
  - src/StarterPlayer/StarterPlayerScripts/Controllers/UiKit.luau
  - src/StarterPlayer/StarterPlayerScripts/Controllers/MenuPrincipal.client.luau
  - src/StarterPlayer/StarterPlayerScripts/Controllers/Input.luau
  - src/StarterPlayer/StarterPlayerScripts/Controllers/ToqueUi.luau
  - src/StarterPlayer/StarterPlayerScripts/Controllers/Traducao.client.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# UI Arquitetura

## Resumo
A interface é toda criada em código Luau no cliente, sem telas montadas no Studio. Cada tela é um módulo em StarterPlayerScripts/Controllers; os tokens visuais ficam em ReplicatedFirst/Estilo e o UiKit os reexporta e acrescenta botões ligados à entrada. As telas conversam por Bus (eventos) e pelos remotes do servidor. Ver [[Arquitetura]], [[Progressao-e-Economia]], [[Rede-e-Seguranca]], [[Studio-Ganchos]].

## Responsabilidades
- Estilo (ReplicatedFirst): painéis escuros, títulos em Oswald, corpo em Arimo, cor de época só como acento. Fica antes dos Controllers porque a tela de entrada e o idioma rodam primeiro.
- UiKit: screen, button, bind, focus, fit, modal, abas, pilha de telas, chips de dica de botão, tween com movimento reduzido.
- Input: dispositivo atual (device, isGamepad, touchActive), ações por contexto (Input.on), configurações (setSetting).
- Traducao.client: traduz TextLabel, TextButton, placeholders e ProximityPrompt pelo dicionário de Shared/Lang.
- Cortina e UiEfeitos: transição de tela cheia e efeitos de interface.

## Arquivos principais
- Lobby e menus: MenuPrincipal.client (lobby, abre uma vez por sessão e deixa o atributo MenuPrincipal true), LobbyPalco e LobbyScene (cena local do acampamento), GameMenu.client (menu do jogo, abas), IdiomaLobby.client.
- Preparação: DeployScreen (lógica do caminho TIME, GRUPO, CLASSE, ONDE NASCER e pedidos ao servidor) e Preparacao (desenho dos três primeiros passos). O passo 04 é a carta do GameUI.
- Carta de nascer e mapa: GameUI.client (dono das telas e entradas do mapa) e CartaView (desenha a carta).
- Armário e loja: ArmarioTela (categorias, grade, ficha; comprar leva à Intendência e ao Arquivo), ShopController.client (loja, abas), Progresso.client (Intendência, avisos de ganho, promoção), CaixasTela.client (aba CAIXAS e roleta), ArquivoTela.client, TelaPasse.client, TelaMissoes.client, DiariaEntrada.client, CampanhaCliente (cópia única do Campanha_State).
- HUD: HudCampo (bússola, arma e postura), HudInfantaria (vida, direção do dano, abates, esquadrão), FrontHud, PainelComandos, Toast (avisos).
- Toque: ToqueTelas (lógica pura), ToqueUi, ToqueHud, ToqueAuto, ToqueVeiculo, Aparelho (gráficos e rede móvel), Haptics, VirtualCursor.
- Texto: TextoCabe (nenhum texto passa da caixa), Estilo.textoK para preferência de tamanho.

## Fluxo
- Abertura: UiKit.screen cria o ScreenGui; a tela chama UiKit.opened(nome, DisplayOrder) e UiKit.closed ao fechar. Telas abrem por Bus: shop_open (com a aba), passe_open, missoes_open, caixas_show; shop_close avisa o lobby.
- Voltar: cada tela registrada na pilha consulta UiKit.backFor(nome) no handler de ui_back; só a de cima trata, com intervalo de 0,15 s. O foco de antes é restaurado ao fechar, apenas no controle.
- Abas: UiKit.abas devolve a fileira com clique, toque, LB/RB e Q/E; vale quando a tela está por cima. UiKit.modal faz a confirmação (tela VT65Confirma, ordem 95), fecha por VOLTAR.
- Troca grande de tela: Cortina.passar(fn, título, sub) cobre, executa a troca e descobre; um pedido espera o anterior. Movimento reduzido só esmaece.
- Idioma: Idioma (ReplicatedFirst) grava Input.setSetting("lang", código) e a Traducao retraduz o que está aberto.

## Dependências
Shared/Net e Bus para eventos, Shared/Lang e LangData para idioma, Shared/Toque e InputMap para toque e teclas, Shared/Efeitos (conta pura dos efeitos), Shared/Commerce e Progression para preços e estado. Ver [[Combate]] e [[Modos-e-Partida]] para o que o HUD mostra.

## Invariantes
- O servidor decide tudo; a UI só mostra e pede. Preços saem de GetProductInfoAsync e a posse do Commerce_State.
- Toda tela nova usa os tokens do Estilo e as peças do UiKit; os tokens antigos de papel (CARD, INK, MANILA, STAMP) ficam só para o que não foi refeito.
- Todo botão passa por UiKit.button ou UiKit.bind, que o registra no VirtualCursor (controle) e no dedo gordo do toque.
- Toda tela que fecha com VOLTAR se registra na pilha, senão B, Esc e Backspace não a alcançam.
- Texto traduzido: o texto de tela precisa existir nos dicionários en, es e vi (tools/i18n/extrai.py gera telas.json; mescla.py junta traduções e confere %d, %s). O português é a chave.
- Na TV (UiKit.tv) o texto não fica abaixo de 24 px; nada essencial fora da área segura.

## Riscos conhecidos
- Arquivos muito grandes concentram muita lógica de tela (ShopController.client, CaixasTela.client, CartaView, MenuPrincipal.client, LobbyScene). Mudança sem teste local tende a quebrar outras abas.
- GameMenu.client e ShopController.client têm remapeamento e foco próprios; no Studio via MCP, controle fantasma pode abrir cartas sozinho (relatado no CLAUDE.md do jogo; não reproduzido aqui).

## Testes
tests/luau: componentes, interface, telas, transicoes, idiomas, lobby, armario, loja, loja_vitrine, passe, toque, toque_telas, toque_veiculo, hud_infantaria, preparacao, nascer, comemoracao. Nenhum foi executado nesta nota. Verificação visual só no Studio (ganhos VT65DevTela, ver [[Studio-Ganchos]]).

## Pendências
- Antes de criar componente novo, procure em UiKit (button, abas, modal, chips, fit, panel, itemCard, stat, tag, bar), em Toast (info, sucesso, recompensa, alerta, erro) e em UiEfeitos (faiscas, onda, raios, halo, cintilas, varre, brasas, tremer, clarao). Estender o que existe e rodar tests/luau/componentes.luau.
- Texto novo: registrar nos três dicionários e rodar extrai.py --faltam.
- Lista de lacunas de UI aberta: não verificado.
