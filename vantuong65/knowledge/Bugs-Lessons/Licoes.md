---
project: STARLITE
type: lessons
status: verified
source_paths:
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Lições de engenharia

Só o que foi visto de verdade e pode se repetir. Antes de corrigir algo parecido, procure aqui.
Formato: **sintoma** → causa → correção → como evitar.

## Boot e mapas
- **Soldado caía fora do mapa novo** → os Scripts de servidor corriam e guardavam o `MapConfig` antigo →
  `MapaBoot.iniciar()` antes do primeiro `require` nos 5 Scripts → todo Script de servidor novo faz o mesmo.
- **Nenhuma captura contava** → altura do piso guardada como 0 antes de o terreno existir → ler depois
  do terreno pronto → não guardar altura de chão no boot.
- **Blocos brancos e peças visuais colidindo nos mapas novos** → regras de colisão por nó não eram lidas →
  `VT65Build/NosRet`, gerado pelo `ret_registrar.py` → rodar `ret_registrar.py jogo` em todo modelo novo.
- **Nascer bloqueado por corrimão e meda** → as saídas ignoravam pontes → pontes na máscara do gerador.

## Modelos e colocação
- **Peça fora do lugar por alguns metros** → o pivô do modelo é o centro da caixa (visual + colisão), não a
  origem da receita → medir pelas colisões do `metricas.json`.
- **Escada presa no meio** → cruzava uma divisória, e a cabeça batia na treliça → conferir colisões no
  caminho e 2,07 m de vão; testar andando (D-243, passarela do Engenho).
- **Rota do Pathfinding "ok" mas soldado parado** → o alvo estava fora da parede → usar alvos dentro do
  cômodo e confirmar a altura final do soldado.
- **Pátio parece deserto** → construções a 25-30 m de uma captura de 16 m → fechar o anel a 12-18 m.
- **Parede caiada com manchas de vaca** → material de barro com limiar forte em escala grande → reboco
  próprio, com falhas pequenas e tijolo por baixo (`_reboco` em `tools/blender/ret_frente.py`).
- **Interior escuro** → lampião acima da treliça e todos numa ponta → altura máxima e escolha espalhada
  (`InteriorLuz.pontosMercado`).
- **Modelo novo some ou sai sem textura logo após subir** → "Asset content representation is being
  generated" → esperar alguns minutos antes de concluir que há erro.

## Luau
- **Linha começando com `(x :: T).y = ...` vira chamada da linha anterior** → usar `local a: any = x`.
- **`pcall(fn)` com função sem retorno dá erro de tipo** → `pcall(function(): any fn() return nil end)`.
- **`math.hypot` não existe no Luau** → `math.sqrt(a*a + b*b)`.
- **Alguns testes Lune conferem texto exato do código** → ao mudar a linha, mantenha o literal ou ajuste o teste.

## Windows e ferramentas
- **Acentos estragados** → `Get-Content`/`Set-Content` no PowerShell 5.1 → editar por Python com UTF-8 e preservar o fim de linha.
- **luau-lsp "limpo" falso** → os diagnósticos saem no stderr → usar `cmd /c ... 2>&1`.
- **`stylua --check` acusa tudo** → o checkout tem CRLF → `tools/dev/stylua_utf8.ps1`.

## Teste no Studio
- **`get_console_output` despeja milhares de linhas** → filtrar com `LogService:GetLogHistory()`.
- **`execute_luau` move o personagem errado logo após nascer** → o `Character` ainda vai trocar → esperar e pegar `P.Character` de novo.
- **Câmera dentro de uma casa na foto** → conferir a planta com `kb.py mapa <id> <setor>` antes.
