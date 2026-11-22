---
project: STARLITE
type: index
status: verified
source_paths:
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Comece aqui

Memória de engenharia do STARLITE. **O código e os testes dizem o que é verdade; as notas dizem onde
olhar e por que as coisas são assim.** Funciona sem o Obsidian: são arquivos Markdown.

## Em toda tarefa
1. **Situar:** [[01-CURRENT-STATE]] e, se for continuação, [[HANDOFF]].
2. **Buscar:** `uv run python tools/kb.py onde <termos>`. Abra de 1 a 3 notas, só o trecho útil.
3. **Verificar:** confira no código o que a nota afirma. Divergiu? O código vale, e a nota é corrigida.
4. **Fazer e testar:** a menor mudança coerente, reaproveitando o que existe.
5. **Registrar:** só o que economiza trabalho depois (tabela abaixo).

Se a primeira busca não bastar, amplie. Bug difícil pode pedir leitura maior; o limite é ponto de
partida, não proibição.

## Consultas rápidas (leem o código na hora)
| Pergunta | Comando (`uv run python tools/kb.py ...`) |
|---|---|
| Onde está isso? | `onde <termos>` |
| O que este módulo faz, quem usa? | `modulo <Nome>` |
| Quem envia e quem escuta este remote? | `remote <Nome>` |
| Por que foi decidido assim? | `decisao D-243 [--texto]` |
| Já existe esse modelo? | `ativo <termo>` |
| O que há neste setor do mapa? | `mapa frente C` |
| A base está íntegra? | `check` |
| Quais notas o código já ultrapassou? | `velhas` |
| Reconferi esta nota | `confere <nota>` |

## Onde cada coisa fica
| Tipo | Lugar |
|---|---|
| Regras permanentes | `CLAUDE.md` |
| Como cada sistema funciona | `knowledge/Systems`, `UI-UX`, `World`, `Art-Assets`, `Optimization`, `Tests` |
| Decisões (ADR) | `DESIGN.md`, numeradas D-xxx. Nova decisão entra lá; mudou, a nova cita a antiga |
| Erros resolvidos | [[Licoes]] |
| Estado atual | [[01-CURRENT-STATE]] |
| Passagem entre sessões | [[HANDOFF]], sempre substituído |
| Histórico lote a lote | `PROGRESS.md` e `testes/` (só abrir por busca: são grandes) |
| O que só o dono faz | `TODO_USUARIO.md` |

## Estados de uma nota
- `verified`: conferida no código no `verified_commit`.
- `planned`: ideia ou requisito ainda não feito.
- `stale`: pode estar desatualizada; confira antes de usar.
- `deprecated`: substituída; a nota diz por qual.

## Não entra aqui
Código copiado, logs, conversa, segredos, IDs de conta. **O repositório é público.**

Índice dos sistemas: [[02-SYSTEM-INDEX]]. Skills e quando usar: [[Skills]].
