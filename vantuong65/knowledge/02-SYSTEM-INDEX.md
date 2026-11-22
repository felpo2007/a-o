---
project: STARLITE
type: index
status: verified
source_paths:
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Índice de sistemas

Só o que existe no código. Para achar um módulo: `uv run python tools/kb.py onde <termo>`.

| Sistema | Nota | Por onde entrar no código |
|---|---|---|
| Boot e organização | [[Arquitetura]] | `src/ServerScriptService/Services/Main.server.luau`, `src/ServerScriptService/Modules/MapaBoot.luau` |
| Rede e segurança | [[Rede-e-Seguranca]] | `src/ReplicatedStorage/Shared/Net.luau` |
| Combate e armas | [[Combate]] | `src/ServerScriptService/Modules/CombatService.luau`, `src/ReplicatedStorage/Shared/Weapons.luau` |
| Partida, modos e nascer | [[Modos-e-Partida]] | `src/ServerScriptService/Modules/MatchService.luau`, `src/ServerScriptService/Modules/RodadaService.luau`, `src/ServerScriptService/Modules/SpawnService.luau` |
| Bots e veículos | [[Bots-e-Veiculos]] | `src/ServerScriptService/Modules/BotService.luau`, `src/ServerScriptService/Modules/VehicleService.luau` |
| Perfil, progressão e loja | [[Progressao-e-Economia]] | `src/ServerScriptService/Modules/ProfileSchema.luau` |
| Telas e interface | [[UI-Arquitetura]] | `src/StarterPlayer/StarterPlayerScripts/Controllers/MenuPrincipal.client.luau` |
| Mapas | [[Map-Index]], [[Pipeline-Mapas]] | `tools/mapas_ret.py`, `src/ServerScriptService/Modules/ArtPlan.luau` |
| Modelos e Blender | [[Blender-Pipeline]] | `tools/blender/ret.py`, `tools/ret_registrar.py`, `tools/roblox_cloud.py` |
| Arte de armas | [[Armas]] | `tools/weapon_landmarks.py`, `tools/acabamentos.py` |
| Arte de personagens e telas | [[Personagens-e-UI]] | `tools/blender/armas_catalogo.py`, `tools/catalogo_imagens.py` |
| Veículos e sons (arte) | [[Veiculos-e-Sons]] | `tools/sons_armas.py`, `tools/blender/veiculos.py` |
| Desempenho | [[Performance-Baseline]], [[Arte-Fixa-e-Texturas]] | `src/ServerScriptService/Modules/ArtBudget.luau` |
| Testes | [[Test-Strategy]], [[Studio-Metodo]], [[Studio-Ganchos]], [[Ferramentas]] | `tools/dev/verifica.ps1` |
| Erros resolvidos | [[Licoes]] | |
