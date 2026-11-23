---
project: STARLITE
type: system
status: verified
source_paths:
  - src/ServerScriptService/Modules/CombatService.luau
  - src/StarterPlayer/StarterPlayerScripts/Controllers/WeaponController.client.luau
  - src/ReplicatedStorage/Shared/Ballistics.luau
  - src/ReplicatedStorage/Shared/Hitbox.luau
  - src/ReplicatedStorage/Shared/Weapons.luau
  - src/ReplicatedStorage/Shared/Gatilho.luau
  - src/ReplicatedStorage/Shared/Medical.luau
  - src/ServerScriptService/Modules/ExplosionService.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Combate

## Resumo
O cliente decide que atirou e manda origem, direção, relógio e semente. O servidor valida, refaz a mesma balística determinística com raycasts próprios e aplica o dano pelo sistema médico. Bots usam a mesma `CombatService.fire`. Os números de dano, recarga e raio são marcados PLACEHOLDER no código (a calibrar em playtest). Ver [[Rede-e-Seguranca]] e [[Bots-e-Veiculos]].

## Responsabilidades
- Cliente (WeaponController): gatilho, mira, origem e dispersão do quadril, recarga, troca de arma, efeitos locais.
- CombatService: munição por arma e por jogador, validação do tiro, simulação, dano, marcador de acerto, drop de arma ao morrer.
- Ballistics/Hitbox: trajetória (gravidade, arrasto G1, dispersão por semente) e caixas de acerto por parte do corpo.
- Medical/MedicalService: vida, sangramento, queda, reanimação, curativo.
- ExplosionService/Explosive: dano de explosivo por distância, postura e cobertura, cratera.

## Arquivos principais
- Controllers/WeaponController.client: função shoot (monta o tiro), shotRay, canShoot.
- Modules/CombatService: fire, bulletHit, firePellets, launchGrenade, onClaim, resupply, ammoNeed, start.
- Shared/Gatilho: validate, accept, clampTime (cadência e janela de defasagem), usado nos dois lados.
- Shared/Weapons: lista das fichas (13 armas de fogo: m14, m16, m60, m1911, m79, type56, sks, rpd, type54, rpg2, m70, mosin, win12; mais facas e baionetas em Weapons.knives), RELOAD_S, DAMAGE, MAGS.
- Shared/Medical: Medical.C, Medical.SHOT, shotDamage, applyShot, applyHit, tick. Server: Modules/MedicalService (hit, Medical_Action).
- Shared/Explosive: TYPES (lethalM, casualtyM, craterM, fragJ), effect, allowCrater.

## Fluxo
1. O cliente (shoot) sorteia a semente, calcula a direção com a alça zerada (Ballistics.zeroAngle) e envia o remote Combat_Fire com arma, modo, origem, direção, semente e GetServerTimeNow. Mostra clarão, recuo e traçante local pelo Bus (shot_fired).
2. Servidor (handler de Combat_Fire em CombatService.start): recusa se morto ou caído; exige registro de munição da arma; confere números finitos (num, clockOf, seedOf); chama Gatilho.validate.
3. Gatilho.validate recusa com motivo: arma, modo, sem munição, recarregando, origem (a mais de ORIGIN_STUDS = 8 da cabeça), lugar fechado e fora do ângulo (veículo), cadência (TOLERANCE 0,15; MAX_LAG 0,25 s).
4. Origem a mais de cerca de 1 m da cabeça com sólido no meio: o tiro sai da cabeça. Depois baixa uma bala (rec.mag) e chama CombatService.fire.
5. fire monta a lista de alvos próximos (nearTargets), roda Hitbox.trace (Ballistics.trace com passo fixo e raycast no mundo, mais caixas de acerto) e envia Combat_Tracer (unreliable) aos outros clientes, que refazem a trajetória com a semente.
6. bulletHit: ignora fogo amigo; dano = Medical.shotDamage(Weapons.damageOf, zona, fração da energia de boca que chegou); chama MedicalService.hit; avisa o atirador por Combat_Confirm (dano, zona, k = ferido/caído/morto) e a vítima por Combat_Hit.
7. Tiro que não pegou ninguém no servidor é guardado por Hitbox.CLAIM_S (1 s). O cliente atirador (Controllers/Acerto) refaz a bala contra os soldados como os vê e manda Combat_Claim; onClaim confere trajetória (PATH_TOL 1,0 stud), caminho livre e distância até a peça (Hitbox.tolerance, máximo CLAIM_MAX 16) antes de aplicar o dano.
8. Dano: base por tipo (Weapons.DAMAGE: fuzil 36, mg 32, pistola 34, lançador 40, shotgun 12) ou campo damage da ficha; multiplicador de zona em Medical.SHOT (cabeça 2,5, tronco 1, membros 0,65); curva de queda por energia; headLethal 70 mata na hora.
9. Espingarda (win12, pellets): firePellets, um raio por bago com Weapons.pelletSeed; bagos no mesmo soldado somam num ferimento (Medical.pelletDamage).
10. Recarga: remote Combat_Reload; o servidor marca reloadUntil (Weapons.reloadTime, com vantagem "reload"), publica VT65RecargaIni/Dur no corpo e completa por task.delay; cancela ao trocar de arma (Posture_Set) ou com cancel = true. Tubular recarrega cartucho a cartucho.
11. Granada de mão: FieldService.throwFrom cria a peça física, espoleta de 4,5 s (EUA) e 4,0 s (VC), quica com GrenadePhysics, e chama ExplosionService.detonate (grenade_us: letal 5 m, baixas 15 m; grenade_vc: 4 e 12 m).
12. Lançador (m79, rpg2): launchGrenade usa a balística, arma depois de wp.armM; antes de armar só fere como projétil; depois chama detonate.
13. detonate: para cada Combatant até casualtyM, exposição reduzida por agachado (Explosive.CROUCH) e cobertura (COVERED), Explosive.effect decide letal, ferido ou nada, e MedicalService.hit aplica. Também chama onVehicles, e abre cratera se o orçamento permitir.
14. Sistema médico: Medical.tick sangra por nível (leve 0,1, grave 0,25, arterial 0,8 vida/s); vida 0 vira caído; janela downWindow de 60 s antes de morrer; Medical_Action tem as operações bandage, tourniquet, treat, revive, giveup (MedicalService.start).

## Dependências
Shared: Weapons, Gatilho, Ballistics, Hitbox, Medical, Explosive, Net, Rng, Pickup, CaixaMunicao, Vantagens. Server: Combatants, MedicalService, ExplosionService, AnimalService, TrainingService, CaixaMunicaoService (usa refill/resupply). Ver [[Arquitetura]], [[Progressao-e-Economia]] (vantagens, equipamento), [[UI-Arquitetura]].

## Invariantes
- O servidor é autoridade da munição (ammo por jogador); a do cliente é só cartão no HUD (Combat_Ammo).
- Cliente e servidor rodam o mesmo Ballistics com a mesma semente; mudar a conta num lado quebra o traçante e o claim.
- Sem fogo amigo em bulletHit (MedicalService.friendly).
- Conversão: 1 stud = 0,28 m (M = 0,28 em CombatService, Hitbox, Explosion).
- Relógio do tiro é hora do servidor (época Unix) e semente vai até 2^32: não validar com limite de 1e7 (causa documentada de recusa total, D-107).

## Riscos conhecidos
- CombatService.bulletHit: usa o campo global Medical.nextShot para passar o dano a MedicalService.hit (envolvido em pcall para limpar). Estado mutável de módulo compartilhado; se alguém chamar hit em paralelo por outro caminho dentro da janela, herda o dano. Hoje o código é síncrono, então não observei falha.
- CombatService.start (handler Combat_Fire): a arma enviada em shot.w só precisa existir no equipamento; não vi checagem de que ela está na mão (a recarga é cancelada por Posture_Set, mas o tiro não). Não verificado se outro módulo cobre isso.
- Os valores de dano, queda, raios e tempos estão como PLACEHOLDER; sem fonte de manual.

## Testes
Lune: tests/luau/combate.luau, armas.luau, explosao.luau, socorro.luau, lancador.luau, mira.luau, f2.luau, f4.luau (rodar com lune run). Autoteste no Studio: ver [[Studio-Ganchos]] (VT65SelfTest, VT65DevArma). Motivo de tiro recusado vai no atributo VT65TiroRecusado (só Studio).

## Pendências
- Arma nova: entrada em Weapons.list com os campos do tipo Weapon (muzzleVelocity, bcG1, magazine, modes, enabled, src), papel em Roles.PRIMARY, arte e pontos (tools/weapon_landmarks.py, WeaponArt), mira em tools/sight_align.py, som em SomKits, e conferir os testes de armas. Ordem completa: não verificada no código.
- Tabela de penetração por material (Ballistics.PASS) ainda é placeholder; ver também [[Licoes]].
