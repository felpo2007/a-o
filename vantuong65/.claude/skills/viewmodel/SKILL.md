---
name: viewmodel
description: >
  Ajusta a arma e as mãos em 1ª pessoa do STARLITE: posição, mira (ADS), alça e massa, recarga,
  pose e captura no Studio. Use ao mexer em WeaponVisuals, WeaponController, na ficha de uma arma
  ou ao adicionar uma arma nova.
---

# Viewmodel do STARLITE

Skill própria do projeto. Receitas completas em `knowledge/Art-Assets/Armas.md`.

## Onde fica
- Arma e mãos no cliente: `src/StarterPlayer/StarterPlayerScripts/Controllers/WeaponVisuals.client.luau`.
- Tiro e mira: `src/StarterPlayer/StarterPlayerScripts/Controllers/WeaponController.client.luau`.
- Ficha da arma (`adsEyeM`, `adsSobeM`): `src/ReplicatedStorage/Shared/Weapons.luau`.
- Pontos da arma, gerados: `src/ReplicatedStorage/Shared/WeaponArt.luau`, por `tools/weapon_landmarks.py`.
- Centro da alça e da massa: `tools/sight_align.py`.
- Recarga: `src/ReplicatedStorage/Shared/Recarga.luau`.

## Como conferir no Studio
1. Ponha o soldado em campo. `VT65DevArma` = id (Server) troca a arma.
2. Mira: `Aiming = true` a cada quadro (Client). A luneta só abre por `VT65DevGranada = "mirar:<s>"`.
3. Recarga parada: `workspace.VT65DevRecarga1P` = fração.
4. Capture com a câmera do jogo. Não troque o tipo da câmera: o Studio desfaz.
5. Confira a alça e a massa no centro da tela, sem nada tapando, e olhe também a 3ª pessoa.

## Regras
- Arma nova: frente e mãos no `weapon_landmarks.py`; alça de anel ou entalhe no `sight_align.py`.
- Medida vem da malha. Ajuste a distância do olho em `adsEyeM`, na ficha da arma; o padrão da arte é
  `EYE_OFFSET_M`, em `tools/weapon_landmarks.py`. Confira sempre na captura.
- Mudança só visual não altera tiro nem dano: isso é do servidor (`CombatService`).
