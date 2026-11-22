---
project: STARLITE
type: map
status: verified
source_paths:
  - src/ReplicatedStorage/Shared/MapasRet.luau
  - tools/mapas_ret.py
  - tools/blender/ret_frente.py
  - src/ServerStorage/VT65Build/Data_frente/Layout.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Vale das Cinco Passagens (Linha de Frente)

700 × 300 m, sem publicar. Peças e posições atuais: `uv run python tools/kb.py mapa frente <setor>`.

## Objetivos (planta, em metros)
Base Oeste (35,150) → A Olaria (135,150) → B Escola (245,190) → **C Mercado (350,150, início)** →
D Engenho (455,110) → E Esteios (565,150) → Base Leste (665,150).

## Rotas
- **Três famílias de leste a oeste:** estrada principal (y de 120 a 146), trilha norte (y de 190 a
  238) e trilha sul (y de 62 a 100), com ligações a cada 80-110 m.
- **Rio de norte a sul, 15 m de largura.** Ponte rodoviária de (306,133) a (329,125); passarelas de
  (323,234) a (347,233) e de (292,62) a (313,62).
- **30 conjuntos de nascer** nas faixas norte e sul, cada um com duas saídas.

## Lugares
| Setor | Núcleo | Fecha o pátio | Proteção na captura |
|---|---|---|---|
| A | Fornos ao norte | Galpão a leste, secagem a oeste, coberturas | Pilhas de tijolo |
| B | Escola em U, aberta ao sul | Três alas com varanda | Figueira, cisterna |
| C | Praça de bancas | Sobrado, galeria, cais nas duas margens | Bancas e carroça |
| D | Galpão com plataforma ao sul | Depósito, oficina, canal atrás | Carroça, meda, sacos |
| E | Casa comunal ao norte | Quatro palafitas | Figueira, potes, meda |

## Invariantes
- Centro da captura livre; construções fecham o pátio a 12-18 m (`miolo`).
- Cais com altura do gerador (`base`), sem patamar. Piso do Engenho na altura do pátio (`nivel`).
- `tools/mapas_check.luau` cobra os marcos de cada setor e o chão atrás do cais.

## Pendências
Fichas em `testes/D-243_vale_2026-11-22.md`: chegada da Olaria, fundo do Engenho, textura de chão por
lugar, qualidade alta, visadas e fps.
