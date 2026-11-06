# Instruções para o Claude Code

Projeto: estratégias de trade IBOV + S&P 500 com validação fora da amostra e modelo dedicado
para GOOGL. Responda sempre em português.

## Antes de qualquer coisa
1. Leia `SPEC.md` (especificação), `PROGRESS.md` (onde paramos) e `ASSUMPTIONS.md` (suposições).
2. Prepare o ambiente: `uv sync --locked` e confira com `uv run python run.py --check-env`.

## Como trabalhar
- **Uma etapa por sessão.** Execute a próxima etapa pendente do PROGRESS.md até cumprir o
  "Pronto quando" dela. Não avance para a etapa seguinte.
- Avance sem pedir confirmação a cada passo. Pergunte só se faltar algo que mude o resultado de
  forma relevante; senão, assuma o razoável e registre em `ASSUMPTIONS.md`.
- Ao terminar a etapa:
  1. `uv run pytest` e `uv run ruff check .` passando;
  2. `PROGRESS.md` atualizado: etapa atual, o que foi feito, resultados-chave com números,
     suposições, problemas e próximos passos;
  3. commit em `main` e `git push`.

## Regras inegociáveis
- Nunca invente dados ou resultados: todo número sai de código executado. Se uma fonte falhar,
  diga qual e use o fallback.
- O repositório é **público**: chaves só no `.env` (já no `.gitignore`), nunca no código.
- Parâmetros da SPEC ficam em `config/default.toml` e são travados por testes. Mudar um deles
  exige registro no `ASSUMPTIONS.md`.
- Holdout da GOOGL (últimos 24 meses): intocado até o fim da Etapa 6 e rodado uma única vez.
- Comandos: `uv run python run.py --universe mvp|full`; testes de rede com `RUN_NETWORK_TESTS=1`.
