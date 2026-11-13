"""Etapa C (Tarefa C): assets das bases iniciais (EUA em Chu Lai e VC na mata), do zero no Blender.

Mesmo caminho dos novos (`novos.py`), com três acréscimos para peças grandes:
- vários atlas por asset (`grupos`: cada um com teto de triângulos e textura próprios), para a lona
  de uma barraca de 16 m não dividir 1024 px com o interior;
- vários nós por atlas (`no` de cada objeto da receita): no GLB cada nó vira uma MeshPart (a
  silhueta do alvo, a cancela que gira, as placas de distância);
- colisão de sólidos convexos (`Colisao_*`) e zonas de toque (`Zona_*`) no próprio GLB, também
  listadas no metricas.json no referencial do Roblox.

Para cada atlas: pré-redução, limpeza, redução pela tolerância de desvio (`comum.escolher_alvo`)
ou sem redução (`sem_reducao`: arame, telhado ondulado, bandeiras, esteiras), UV nova e bake
(`comum.produzir`: cor, normal, rugosidade, metal e oclusão). GLB em studs, Y para cima, base no
chão, centro da caixa na origem; frente em +Z do GLB (no Roblox, -Z depois do giro da D-58).

Uso:
    blender -b --factory-startup -P tools/blender/bases.py -- <chave>
    blender -b --factory-startup -P tools/blender/bases.py -- <chave> --so-montar
    blender -b --factory-startup -P tools/blender/bases.py -- <chave> --previa [azimute]
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bases_us  # noqa: E402
import bases_vc  # noqa: E402
import comum as C  # noqa: E402
import glb  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402

PRE_REDUCAO = 60000
STUD = C.M_POR_STUD

# metas de triângulos por classe (a soma dos atlas); todas ficam na classe "prop" do ArtBudget
# (teto de 20 mil por modelo, D-66)
CLASSES_BASE = {
    "pequeno": 2000,
    "prop": 5000,
    "construcao": 8000,
    "base_grande": 14000,
}

F = {
    "mil1712": "MIL-T-1712T (everyspec.com)",
    "tm8340": "TM 10-8340-211-13 (tentsshelters.tpub.com; espelho mobileradar.org)",
    "mil1712e": "MIL-T-1712E, 1957 (catálogo UNT)",
    "blazich": "Blazich, 'SATS and Chu Lai' (2022)",
    "shulimson": "Shulimson & Johnson, U.S. Marines in Vietnam: The Landing and the Buildup, "
    "1965 (1978)",
    "fm515": "FM 5-15 Field Fortifications (ago/1968)",
    "tm9_2330": "TM 9-2330-213-14&P (reboques M105/M107)",
    "tm5_6115": "TM 5-6115-275-14 (MEP-018A, 1977)",
    "tm11_5820": "TM 11-5820-348-15 (RC-292, 1966)",
    "eo10834": "Executive Order 10834 (1959; ushistory.org)",
    "wiki_usmc_flag": "Wikipedia, Flag of the United States Marine Corps",
    "wiki_conex": "Wikipedia, Conex box",
    "wiki_drum": "Wikipedia, Drum (container)",
    "wiki_marston": "Wikipedia, Marston Mat",
    "wiki_starlite": "Wikipedia, Operation Starlite",
    "tm10_7200": "TM 10-7200-200-13 (galões; trecho com OCR ruim)",
    "tm9_6920": "TM 9-6920-210-14 / USMC TM 6920-14/1 (1968)",
    "action_target": "Action Target (fabricante; E-type 19,5 x 40 pol)",
    "foto_kyha": "Foto oficial do USMC 'MAG-36 helicopter pads, Chu Lai, September 1965' "
    "(Wikimedia Commons)",
    "cia_vc": "CIA, 'VC Bases in Cambodia' (NIC, c. 1968; cia.gov/readingroom)",
    "fao": "FAO, Farm structures, cap. 5 'Roofs'",
    "vi_hc": "vi.wikipedia, Bếp Hoàng Cầm",
    "nhandan": "Nhân Dân, 'Tìm lại người nhóm lửa' (Hoàng Cầm, 1951, campanha de Hòa Bình)",
    "tc531": "TC 5-31 Viet Cong Boobytraps, Mines and Mine Warfare Techniques (1967)",
    "macv": "MACV P-3300/5 VC-NVA Employment of Mines & Booby Traps (1967)",
    "awm": "Australian War Memorial REL43477 (rede do VC, c. 1965)",
    "wiki_gaz": "Wikipedia, GAZ-69",
    "wiki_m38": "Wikipedia, Willys M38",
    "wiki_ta": "Wikipedia, Citroën Traction Avant (de/en)",
    "wiki_bambos": "Wikipedia, Bambusa bambos",
    "vehicles": "Shared/Vehicles.luau (fichas com fonte do próprio jogo)",
}

GP_MEDIUM = {
    "comprimento_m": [9.96, f"{F['mil1712']}: 32 pés 8 pol"],
    "largura_m": [4.88, f"{F['mil1712']}: 16 pés"],
    "cumeeira_m": [3.05, f"{F['mil1712']}: 10 pés"],
    "parede_m": [1.68, f"{F['tm8340']}: 5 pés 6 pol"],
    "porta_altura_m": [1.83, f"{F['mil1712']}: 6 pés"],
    "mastros": [2, f"{F['tm8340']}: 2 mastros centrais e 1 cumeeira"],
    "telhado": ["4 águas", F["mil1712"]],
    "cor": ["verde-oliva", F["mil1712e"]],
    "comprimento_cumeeira_m": [5.08, "derivado: comprimento - largura (águas iguais)"],
    "porta_largura_m": [1.2, "PLACEHOLDER"],
    "cordas_estacas": [None, "PLACEHOLDER: cordas do beiral até estacas a 1,5 m"],
    "parede_jogo_m": [2.35, "decisão do dono (2026-11-11): soldado de 2,0 m, vão livre ≥ 2,3 m"],
    "cumeeira_jogo_m": [3.72, "parede do jogo + 1,37 m (a mesma inclinação da fonte)"],
    "porta_jogo_m": [
        [1.2, 2.4],
        "decisão do dono (2026-11-11): soldado de 2,0 m, vão livre ≥ 2,3 m",
    ],
}
GP_LARGE = {
    "comprimento_m": [15.85, f"{F['tm8340']}: 52 pés"],
    "largura_m": [5.49, f"{F['tm8340']}: 18 pés"],
    "cumeeira_m": [3.73, f"{F['tm8340']}: cumeeira de 12 pés 3 pol"],
    "parede_m": [1.68, f"{F['tm8340']}: beiral de 5 pés 6 pol"],
    "mastros": [4, f"{F['tm8340']}: 4 mastros centrais articulados"],
    "telhado": ["4 águas", F["tm8340"]],
    "cor": ["verde-oliva", "PLACEHOLDER (a GP Medium é OD pela MIL-T-1712E)"],
    "comprimento_cumeeira_m": [10.36, "derivado: comprimento - largura (águas iguais)"],
    "porta_largura_m": [1.2, "PLACEHOLDER"],
    "parede_jogo_m": [2.35, "decisão do dono (2026-11-11): soldado de 2,0 m, vão livre ≥ 2,3 m"],
    "cumeeira_jogo_m": [4.4, "parede do jogo + 2,05 m (a mesma inclinação da fonte)"],
    "porta_jogo_m": [
        [1.2, 2.4],
        "decisão do dono (2026-11-11): soldado de 2,0 m, vão livre ≥ 2,3 m",
    ],
}
CATRE = {"catre_m": [[1.9, 0.68, 0.43], "PLACEHOLDER (catre dobrável; sem fonte oficial)"]}
SACO = {
    "saco_m": [
        [0.5, 0.28, 0.12],
        "PLACEHOLDER: o mesmo da sandbag_wall (saco de 14 x 26 pol, Wikipedia, cheio a ~3/4)",
    ]
}

USO_PADRAO = (
    "Nós visuais: CanCollide=false, CanQuery=false, CanTouch=false. Nós Colisao_*: "
    "Transparency=1, CanCollide=true, CastShadow=false, CanQuery=true se 'bala' = 'para' (se "
    "'passa', CanQuery=false ou o Material no PASS do CombatService), atributo Material = o "
    "'material' da lista. Nós Zona_*: Transparency=1, CanCollide=false, CanQuery=false, "
    "CanTouch=true."
)

BASES: dict[str, dict] = {
    # ------------------------------------------------------------------ EUA
    "us_tent_gp_medium": {
        "nome": "barraca GP Medium (alojamento, 6 catres)",
        "base": "US",
        "classe": "base_grande",
        "grupos": {
            "Lona": {"teto": 6000, "tex": 1024, "costas": False},
            "Interior": {"teto": 6000, "tex": 1024},
        },
        "casca": ["Lona"],
        "medidas": {**GP_MEDIUM, **CATRE},
    },
    "us_tent_gp_large": {
        "nome": "barraca GP Large sobre strongback (alojamento, 12 catres)",
        "base": "US",
        "classe": "base_grande",
        "grupos": {
            "Lona": {"teto": 8000, "tex": 1024, "costas": False},
            "Interior": {"teto": 7000, "tex": 1024},
        },
        "casca": ["Lona"],
        "medidas": {
            **GP_LARGE,
            "strongback": [
                None,
                f"{F['blazich']}: o NMCB 10 montou 900 barracas com strongback em Chu Lai a "
                "partir de julho de 1965 (quantas prontas em agosto: sem fonte)",
            ],
            "piso_altura_m": [0.3, "PLACEHOLDER"],
            "caibros_m": [1.22, "PLACEHOLDER: caibros e montantes a cada 4 pés"],
            **CATRE,
        },
    },
    "us_command_tent": {
        "nome": "barraca de comando (COC) com antenas RC-292 e mesa de mapa",
        "base": "US",
        "classe": "base_grande",
        "grupos": {
            "Lona": {"teto": 6000, "tex": 1024, "costas": False},
            "Sacos": {"teto": 4000, "tex": 1024},
            "Interior": {"teto": 5000, "tex": 1024, "inclui": ["Antenas"], "metal": True},
        },
        "casca": ["Lona"],
        "medidas": {
            **{k: v for k, v in GP_MEDIUM.items() if k != "cordas_estacas"},
            "barraca_do_coc": [
                None,
                "PLACEHOLDER: o tipo de barraca do COC do USMC em 1965 não foi achado "
                f"(o PC da 3ª Divisão em Da Nang era um bunker: {F['shulimson']}, p. 187)",
            ],
            "rc292_mastro_m": [9.14, f"{F['tm11_5820']}: mastro de 30 pés em 12 seções AB-35"],
            "rc292_altura_total_m": [[11.3, 12.6], f"{F['tm11_5820']}: 37 a 41,5 pés"],
            "rc292_estais": [4.57, f"{F['tm11_5820']}: 3 estais a 15 pés, 120° entre si"],
            "rc292_radiais": [3, f"{F['tm11_5820']}: 3 radiais a 140° do elemento vertical"],
            "rc292_radial_m": [1.9, "PLACEHOLDER (depende da frequência)"],
            "radios": [
                "AN/PRC-10",
                f"{F['shulimson']}, p. 175: o AN/PRC-25 só chegou em novembro de 1965; medidas "
                "do PRC-10 e do telefone EE-8: PLACEHOLDER",
            ],
            "mesa_mapa_m": [[2.4, 1.2, 0.9], "PLACEHOLDER (chapa de compensado de 8 x 4 pés)"],
            **SACO,
        },
    },
    "us_mess_tent": {
        "nome": "refeitório de campanha (GP Large de lados enrolados)",
        "base": "US",
        "classe": "base_grande",
        "grupos": {
            "Lona": {"teto": 7000, "tex": 1024, "costas": False},
            "Interior": {"teto": 7000, "tex": 1024, "metal": True},
        },
        "casca": ["Lona"],
        "medidas": {
            **GP_LARGE,
            "refeitorio_chu_lai": [
                None,
                f"{F['blazich']}: o NMCB 10 fez um refeitório para 1.600 homens (a partir de julho "
                "de 1965); em agosto, refeitório de barraca é PLACEHOLDER",
            ],
            "fogao_m59_m": [
                [1.07, 0.61, 0.69],
                "TM 10-7360-204-13&P (gabinete de 42 x 24 x 27 pol; só trecho de busca)",
            ],
            "lata_32_gal_m": [[0.54, 0.68], "PLACEHOLDER"],
            "aquecedor_imersao": [
                None,
                "PLACEHOLDER: forma do M67 (TM 9-4540-202-12&P dá 35 1/4 pol, eixo incerto)",
            ],
            "mesas_bancos": [None, "PLACEHOLDER"],
        },
    },
    "us_bunker": {
        "nome": "bunker de sacos de areia com teto de toras",
        "base": "US",
        "classe": "construcao",
        "grupos": {
            "Sacos": {"teto": 7000, "tex": 1024, "escondidas": True},
            "Estrutura": {"teto": 1500, "tex": 512},
        },
        "casca": ["Sacos"],
        "medidas": {
            "externo_m": [[3.8, 3.8, 2.8], "PLACEHOLDER (FM 5-15 tem bunkers, medidas não lidas)"],
            "pe_direito_m": [2.35, "decisão do dono (2026-11-11): soldado de 2,0 m, vão ≥ 2,3 m"],
            "porta_m": [[1.25, 2.35], "idem; passagem ≥ 1,0 m (PLACEHOLDER de projeto)"],
            "seteira_m": [[1.2, 0.22], "PLACEHOLDER (de 1,50 a 1,72 m: olho do soldado de 2,0 m)"],
            **SACO,
        },
    },
    "us_watchtower": {
        "nome": "torre de vigia de madeira com parapeito de sacos",
        "base": "US",
        "classe": "construcao",
        "grupos": {
            "Estrutura": {"teto": 5000, "tex": 1024, "inclui": ["Telhado"], "metal": True},
            "Sacos": {"teto": 2500, "tex": 512, "escondidas": True},
        },
        "casca": [],
        "medidas": {
            "plataforma_m": [4.5, "PLACEHOLDER (torre de vigia: sem fonte)"],
            "planta_m": [[2.4, 2.4], "PLACEHOLDER"],
            "altura_total_m": [
                7.45,
                "PLACEHOLDER (2,45 m livres sobre a plataforma: soldado de 2,0 m)",
            ],
            "degraus_m": [0.3, "PLACEHOLDER"],
            **SACO,
        },
    },
    "us_concertina": {
        "nome": "concertina tripla (módulo de 7,6 m)",
        "base": "US",
        "classe": "construcao",
        "grupos": {"Arame": {"teto": 9000, "tex": 512, "sem_reducao": True, "metal": True}},
        "casca": [],
        "medidas": {
            "rolo_diametro_m": [0.9, f"{F['fm515']}: 90 cm de diâmetro, 15 m estendido"],
            "cerca_tripla": ["2 rolos na base e 1 em cima", f"{F['fm515']}, p. 6-16"],
            "piquetes_m": [3.8, f"{F['fm515']}: piquetes longos a cada 5 passos"],
            "fila_de_tras_m": [0.9, f"{F['fm515']}: fila de trás 90 cm atrás"],
            "piquete_acima_do_chao_m": [1.2, "PLACEHOLDER (piquete em U longo de 1,5 m, FM 5-15)"],
            "espiras_m": [0.38, "PLACEHOLDER (número de espiras: sem fonte)"],
            "farpas": [None, "não modeladas (a cada 5 cm pelo FM 5-15; finas demais para a malha)"],
        },
    },
    "us_gate": {
        "nome": "portão com guarita, cancela e placa",
        "base": "US",
        "classe": "construcao",
        "grupos": {
            "Portao": {
                "teto": 7000,
                "tex": 1024,
                "inclui": ["Guarita", "Cancela", "Placa"],
                "metal": True,
            }
        },
        "casca": [],
        "medidas": {
            "placa": [
                "7TH MARINES / CHU LAI / U.S. MARINE CORPS",
                f"{F['wiki_starlite']}: a 7ª de Fuzileiros (Cel. Peatross) estava em Chu Lai em "
                "agosto de 1965; o desenho e as cores da placa são PLACEHOLDER",
            ],
            "guarita_m": [[2.0, 2.0, 2.6], "PLACEHOLDER (porta de 1,0 x 2,35 m: soldado de 2,0 m)"],
            "cancela_m": [5.0, "PLACEHOLDER (estrada de 4 m)"],
        },
    },
    "us_flagpole": {
        "nome": "mastros com a bandeira dos EUA e a do USMC",
        "base": "US",
        "classe": "construcao",
        "grupos": {
            "Bandeiras": {"teto": 4000, "tex": 1024, "sem_reducao": True},
            "Mastros": {"teto": 3000, "tex": 512},
        },
        "casca": [],
        "medidas": {
            "bandeira_eua_proporcao": [1.9, f"{F['eo10834']}: largura 1,0 x comprimento 1,9"],
            "estrelas": [50, f"{F['eo10834']} (50 estrelas desde 04/07/1960)"],
            "bandeira_eua_m": [[1.52, 2.89], "PLACEHOLDER (tamanho; a razão é da EO 10834)"],
            "bandeira_usmc_m": [[1.32, 1.57], f"{F['wiki_usmc_flag']}: 52 x 62 pol (1939)"],
            "emblema_usmc": [None, "PLACEHOLDER: emblema simplificado (globo, âncora e águia)"],
            "mastros_m": [[9.0, 7.0], "PLACEHOLDER"],
        },
    },
    "us_range_bench": {
        "nome": "bancada de tiro com banco e saco de apoio",
        "base": "US",
        "classe": "prop",
        "grupos": {"Principal": {"teto": 3000, "tex": 512}},
        "casca": [],
        "medidas": {
            "bancada_m": [
                [1.2, 0.62, 0.82],
                "PLACEHOLDER (pedido do dono; o USMC atirava deitado)",
            ],
        },
    },
    "us_range_target": {
        "nome": "alvo de silhueta tipo E num suporte",
        "base": "US",
        "classe": "pequeno",
        "grupos": {"Alvo": {"teto": 1500, "tex": 512, "forca_ao": 0.3}},
        "casca": [],
        "medidas": {
            "silhueta_e_m": [[0.495, 1.016], f"{F['action_target']}; tipos E e F: {F['tm9_6920']}"],
            "centro_m": [1.2, "TrainingService.TARGET_CENTER_M (o jogo)"],
            "cor": ["verde-oliva", "PLACEHOLDER"],
        },
    },
    "us_range_berm": {
        "nome": "barranco de proteção do estande (16 m)",
        "base": "US",
        "classe": "prop",
        "grupos": {"Barranco": {"teto": 4000, "tex": 1024, "normais": False}},
        "casca": [],
        "medidas": {"barranco_m": [[16.0, 7.2, 3.0], "PLACEHOLDER (crista de 1,2 m, taludes 45°)"]},
    },
    "us_range_sign": {
        "nome": "placas de distância (25, 100, 200 e 300 m)",
        "base": "US",
        "classe": "pequeno",
        "grupos": {"Placas": {"teto": 1500, "tex": 512}},
        "casca": [],
        "medidas": {"placa_m": [[0.62, 0.42, 1.33], "PLACEHOLDER (desenho e tamanho)"]},
    },
    "us_motor_pool": {
        "nome": "garagem e oficina (motor pool) com telhado de zinco",
        "base": "US",
        "classe": "base_grande",
        "grupos": {
            "Telhado": {
                "teto": 7000,
                "tex": 1024,
                "sem_reducao": True,
                "metal": True,
                "normais": False,
            },
            "Estrutura": {"teto": 7000, "tex": 1024, "inclui": ["Oficina"], "metal": True},
        },
        "casca": ["Telhado"],
        "medidas": {
            "galpao_m": [[12.0, 12.0], "PLACEHOLDER (2 boxes de 6 m)"],
            "beiral_m": [4.2, "PLACEHOLDER (acima dos 3,1 m do M48A3)"],
            "cumeeira_m": [5.0, "PLACEHOLDER"],
            "m48a3_m": [[9.3, 3.65, 3.1], F["vehicles"]],
            "lvtp5_m": [[9.04, 3.57, 2.92], F["vehicles"]],
            "m35a2_m": [[7.0, 2.4, 2.8], "Wikipedia, M35 2½-ton cargo truck (277 x 96 x 112 pol)"],
            "m151_m": [[3.37, 1.63, 1.8], "Wikipedia, M151 MUTT (com capota)"],
            "chapa_ondulada": [
                [0.068, 0.013],
                "PLACEHOLDER (onda de 2 2/3 x 1/2 pol, o padrão comum)",
            ],
        },
    },
    "us_helipad": {
        "nome": "heliponto de esteira AM-2 (módulo de 14,6 m)",
        "base": "US",
        "classe": "prop",
        "grupos": {"Esteira": {"teto": 6000, "tex": 1024, "sem_reducao": True, "metal": True}},
        "casca": [],
        "medidas": {
            "placa_am2_m": [[3.658, 0.61, 0.038], f"{F['blazich']}: 12 pés x 2 pés x 1,5 pol"],
            "material": [
                "AM-2 de alumínio",
                f"{F['foto_kyha']}: 'AM-2 matting laid on a compacted laterite base'; a pista "
                f"de Chu Lai também era AM-2 ({F['blazich']})",
            ],
            "uh34d_rotor_m": [17.07, "Vehicles.luau / D-36 (rotor de 56 pés)"],
            "helicopteros_na_starlite": [
                None,
                f"{F['shulimson']}, p. 80-81: os UH-34 do HMM-261 e HMM-361 (MAG-16) saíram de "
                "Da Nang; o MAG-36 chegou a Ky Ha (Chu Lai) em 31/08/1965",
            ],
            "cor_antiderrapante": [None, "PLACEHOLDER"],
        },
    },
    "us_armor_revetment": {
        "nome": "baia de blindados (terra em U e piso M8A1)",
        "base": "US",
        "classe": "construcao",
        "grupos": {
            "Baia": {"teto": 5000, "tex": 1024, "normais": False},
            "Piso": {"teto": 2500, "tex": 512, "sem_reducao": True, "metal": True},
        },
        "casca": [],
        "medidas": {
            "placa_m8a1_m": [[0.559, 3.658], f"{F['wiki_marston']}: 22 x 144 pol"],
            "m8a1_em_chu_lai": [None, f"{F['blazich']}: pátios e taxiway com M8A1/M8A2 de aço"],
            "baia_m": [[5.59, 10.97], "PLACEHOLDER (10 x 3 placas; cabem M48A3 e LVTP-5)"],
            "talude_m": [[1.5, 0.8], "PLACEHOLDER (altura e crista; 45°)"],
        },
    },
    "us_fuel_drums": {
        "nome": "ponto de combustível (6 tambores de 55 galões e bomba)",
        "base": "US",
        "classe": "prop",
        "grupos": {"Principal": {"teto": 5000, "tex": 1024, "metal": True}},
        "casca": [],
        "medidas": {
            "tambor_m": [[0.584, 0.876], f"{F['wiki_drum']}: Ø 23 x 34,5 pol por fora"],
            "estencil": [None, "PLACEHOLDER (MOGAS / AVGAS 115/145; cor OD)"],
        },
    },
    "us_water_trailer": {
        "nome": "reboque-pipa de 400 galões (M107)",
        "base": "US",
        "classe": "prop",
        "grupos": {"Principal": {"teto": 5000, "tex": 1024, "metal": True}},
        "casca": [],
        "medidas": {
            "reboque_m": [
                [4.14, 2.09, 1.95],
                f"{F['tm9_2330']}: 13 pés 7 1/8 pol x 6 pés 10 1/4 "
                "pol, 6 pés 4 3/4 pol até a tampa",
            ],
            "m149": [
                None,
                "o M149 pedido não tem data de adoção achada; o M106A1/M107A1 é de 1956 "
                "(especificação no catálogo UNT): ficou o M107",
            ],
            "tanque_rodas": [None, "PLACEHOLDER (dentro das medidas do TM)"],
        },
    },
    "us_generator": {
        "nome": "gerador de 10 kW sobre skid",
        "base": "US",
        "classe": "prop",
        "grupos": {"Principal": {"teto": 3000, "tex": 512, "metal": True}},
        "casca": [],
        "medidas": {
            "gerador_m": [[1.45, 0.74, 0.73], f"{F['tm5_6115']}: 57 x 29 x 28 3/4 pol"],
            "modelo_1965": [None, "PLACEHOLDER (o MEP-018A é posterior; o de 1965 não achado)"],
        },
    },
    "us_conex": {
        "nome": "contêiner CONEX",
        "base": "US",
        "classe": "prop",
        "grupos": {"Principal": {"teto": 2500, "tex": 1024, "metal": True}},
        "casca": [],
        "medidas": {
            "conex_m": [
                [2.59, 1.91, 2.1],
                f"{F['wiki_conex']}: 8 pés 6 x 6 pés 3 x 6 pés 10,5 pol",
            ],
            "portas_cor_estencil": [None, "PLACEHOLDER"],
        },
    },
    "us_jerrycans": {
        "nome": "galões de 5 galões (combustível e água)",
        "base": "US",
        "classe": "pequeno",
        "grupos": {"Principal": {"teto": 2000, "tex": 512, "metal": True}},
        "casca": [],
        "medidas": {
            "galao_m": [[0.33, 0.168, 0.46], f"{F['tm10_7200']} (altura incerta)"],
            "marcas": [None, "PLACEHOLDER"],
        },
    },
    # ------------------------------------------------------------------ VC
    "vc_lean_to": {
        "nome": "abrigo de palha de uma água (lean-to) com jirau",
        "base": "VC",
        "classe": "prop",
        "grupos": {"Abrigo": {"teto": 6000, "tex": 1024}},
        "casca": [],
        "medidas": {
            "planta_m": [[4.0, 2.0, 1.5], f"{F['cia_vc']}: cabanas de ~4 x 2 x 1,5 m"],
            "inclinacao_graus": [39.5, f"{F['fao']}: folha de palmeira ≥ 1:1,5 (~34°)"],
            "palha_cm": [12, f"{F['fao']}: sapê de 15-20 cm (folha: PLACEHOLDER de 12 cm)"],
            "bambu_cm": [[8, 10], f"{F['wiki_bambos']}: colmos de 3 a 20 cm"],
            "alturas_m": [
                [2.5, 0.85],
                "PLACEHOLDER (frente ≥ 2,3 m: soldado de 2,0 m; o fundo é baixo, só no jirau)",
            ],
            "jirau_m": [[3.6, 1.0, 0.45], "PLACEHOLDER"],
        },
    },
    "vc_hoang_cam_kitchen": {
        "nome": "cozinha com fogão Hoàng Cầm",
        "base": "VC",
        "classe": "prop",
        "grupos": {
            "Cozinha": {"teto": 6000, "tex": 1024},
            "Duto": {"teto": 2500, "tex": 512, "normais": False},
        },
        "casca": [],
        "medidas": {
            "invencao": [
                "1951, campanha de Hòa Bình",
                f"{F['nhandan']}; Hoàng Cầm (1916-1996), cozinheiro da Divisão 308",
            ],
            "camara_m": [0.8, f"{F['vi_hc']}: cubo de 0,8 ou 1 m"],
            "duto_secao_m": [[0.25, 0.3], f"{F['vi_hc']}: 25 x 25 ou 30 x 30 cm"],
            "panela_ate_camara1_m": [2.5, f"{F['vi_hc']}: 2,5-3 m"],
            "camara1_ate_camara2_m": [3.0, f"{F['vi_hc']}: 3-5 m"],
            "ramais": [[3, 4.0], f"{F['vi_hc']}: 3 ramais de 4-7 m"],
            "abrigo_fornalha": [
                None,
                "PLACEHOLDER (cumeeira de 2,9 m: passagem de 1,5 m com 2,3 m livres)",
            ],
        },
    },
    "vc_hammock": {
        "nome": "rede de náilon com pano (tăng) por cima",
        "base": "VC",
        "classe": "prop",
        "grupos": {"Rede": {"teto": 3500, "tex": 1024}},
        "casca": [],
        "medidas": {
            "rede": ["náilon de paraquedas verde", F["awm"]],
            "comprimentos": [None, "PLACEHOLDER (rede de 2,2 m entre paus a 3,2 m)"],
        },
    },
    "vc_weapon_rack": {
        "nome": "armeiro de bambu",
        "base": "VC",
        "classe": "pequeno",
        "grupos": {"Armeiro": {"teto": 2000, "tex": 512}},
        "casca": [],
        "medidas": {"armeiro_m": [[2.3, 0.8, 1.24], "PLACEHOLDER (sem fonte)"]},
    },
    "vc_range_target": {
        "nome": "alvo de palha e bambu",
        "base": "VC",
        "classe": "pequeno",
        "grupos": {"Alvo": {"teto": 2000, "tex": 512}},
        "casca": [],
        "medidas": {
            "alvo_m": [[0.4, 0.96], "PLACEHOLDER (sem fonte de alvos de treino do VC)"],
            "centro_m": [1.2, "TrainingService.TARGET_CENTER_M (o jogo)"],
        },
    },
    "vc_range_rest": {
        "nome": "apoio de tiro de bambu",
        "base": "VC",
        "classe": "pequeno",
        "grupos": {"Apoio": {"teto": 1500, "tex": 512}},
        "casca": [],
        "medidas": {"apoio_m": [[3.4, 0.6], "PLACEHOLDER"]},
    },
    "vc_car_shelter": {
        "nome": "abrigo de palha para carro",
        "base": "VC",
        "classe": "construcao",
        "grupos": {"Abrigo": {"teto": 7000, "tex": 1024}},
        "casca": [],
        "medidas": {
            "vao_m": [[5.6, 3.2, 2.5], "PLACEHOLDER (≥ 2,3 m: soldado de 2,0 m)"],
            "gaz69_m": [[3.85, 1.75, 1.95], F["wiki_gaz"]],
            "traction_avant_m": [[4.65, 1.79, 1.54], F["wiki_ta"]],
            "willys_m38_m": [[3.38, 1.57, 1.88], F["wiki_m38"]],
            "peugeot403_m": [[4.47, 1.67, 1.51], "Wikipedia, Peugeot 403 (sedã)"],
            "carro_do_vc": [
                None,
                "sem fonte de carro do VC em Quảng Ngãi em 1965 (pedido do dono)",
            ],
            "inclinacao_graus": [38, F["fao"]],
        },
    },
    "vc_punji": {
        "nome": "canteiro de estacas punji (2 x 1 m)",
        "base": "VC",
        "classe": "pequeno",
        "grupos": {"Punji": {"teto": 2500, "tex": 512, "normais": False, "sem_reducao": True}},
        "casca": [],
        "medidas": {
            "estacas": ["bambu rachado, ponta tostada", F["tc531"]],
            "no_chao_coberto": [None, F["macv"]],
            "cova_m": [[0.46, 0.46, 0.3], f"{F['tc531']} (não modelada: precisa cavar o terreno)"],
            "estaca_m": [[0.25, 0.45], "PLACEHOLDER"],
        },
    },
}

USO = {
    "us_range_target": "Nó Silhueta: CanQuery=true e atributo RangeTarget (distância em m), como a "
    "Part 'Alvo' do TrainingService.",
    "vc_range_target": "Nó Silhueta: CanQuery=true e atributo RangeTarget (distância em m), como a "
    "Part 'Alvo' do TrainingService.",
    "us_gate": "Nó Cancela: gira em volta do pino (extras.cancela_pivo_studs, eixo "
    "extras.cancela_eixo_roblox) junto com Colisao_Cancela; aberta ~ 70°.",
    "us_range_sign": "4 nós no mesmo lugar (Placa25, Placa100, Placa200, Placa300): o código "
    "destrói os 3 que não servem.",
    "us_watchtower": "Escada: Colisao_Degrau* a cada 0,30 m (o Humanoid sobe por degraus); se não "
    "subir, pôr uma TrussPart invisível no lugar.",
    "us_concertina": "Colisao_Concertina: CanQuery=false (a bala passa pelo arame).",
    "vc_punji": "Zona_Punji: CanTouch=true para o dano das estacas; sem colisão.",
    "vc_hoang_cam_kitchen": "extras.fumaca_saidas_studs: 3 pontos para um ParticleEmitter de "
    "fumaça rala (o fogão espalha a fumaça rente ao chão).",
    "us_helipad": "Módulo de 14,6 m: 1 por helicóptero (rotor de 17 m sobra 1,2 m de cada lado).",
}


# =============================================================== pipeline
def normalizar(r) -> list[float]:
    """Centro da caixa (visual + colisão) em X/Y na origem e Z mínimo = 0. Devolve o desvio."""
    los, his = [], []
    for o in r.objs:
        lo, hi = C.caixa(o)
        los.append(lo)
        his.append(hi)
    for c in r.colisao:
        p = np.array(c["pontos"])
        los.append(p.min(axis=0))
        his.append(p.max(axis=0))
    lo, hi = np.min(los, axis=0), np.max(his, axis=0)
    t = np.array([-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]])
    m = Matrix.Translation(Vector(t.tolist()))
    for o in r.objs + r.baixos:
        M.mover(o, m)
    for c in r.colisao:
        c["pontos"] = [tuple((np.array(p) + t).tolist()) for p in c["pontos"]]
    for k, v in list(r.extras.items()):
        if k.endswith("_m") and isinstance(v, list):
            if v and isinstance(v[0], list):
                r.extras[k] = [[a + b for a, b in zip(p, t, strict=True)] for p in v]
            elif len(v) == 3:
                r.extras[k] = [a + b for a, b in zip(v, t, strict=True)]
    return t.tolist()


def marcar_no(obj, idx: int) -> None:
    me = obj.data
    if "vt65_no" in me.attributes:
        me.attributes.remove(me.attributes["vt65_no"])
    a = me.attributes.new("vt65_no", "INT", "FACE")
    a.data.foreach_set("value", np.full(len(me.polygons), idx, np.int32))


def arrays_por_no(obj):
    """Como `comum.arrays_malha`, separando os triângulos pelo atributo de face `vt65_no`."""
    me = obj.data
    me.calc_loop_triangles()
    nv, nl = len(me.vertices), len(me.loops)
    co = np.empty(nv * 3, np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    vi = np.empty(nl, np.int64)
    me.loops.foreach_get("vertex_index", vi)
    nrm = np.empty(nl * 3, np.float64)
    me.corner_normals.foreach_get("vector", nrm)
    nrm = nrm.reshape(-1, 3)
    uv = np.zeros((nl, 2))
    if me.uv_layers:
        u = np.empty(nl * 2, np.float64)
        me.uv_layers.active.data.foreach_get("uv", u)
        uv = u.reshape(-1, 2)
    nt = len(me.loop_triangles)
    tl = np.empty(nt * 3, np.int64)
    me.loop_triangles.foreach_get("loops", tl)
    tl = tl.reshape(-1, 3)
    tp = np.empty(nt, np.int64)
    me.loop_triangles.foreach_get("polygon_index", tp)
    no_poly = np.zeros(len(me.polygons), np.int32)
    if "vt65_no" in me.attributes:
        me.attributes["vt65_no"].data.foreach_get("value", no_poly)
    no_tri = no_poly[tp]
    chave = np.column_stack([co[vi], nrm, uv]).round(6)
    _, primeiro, inv = np.unique(chave, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    P, Nn, T = co[vi][primeiro], nrm[primeiro], uv[primeiro]
    idx = inv[tl]
    saida = []
    for k in np.unique(no_tri):
        sel = idx[no_tri == k]
        usados = np.unique(sel)
        mapa = np.full(len(P), -1, np.int64)
        mapa[usados] = np.arange(len(usados))
        saida.append(
            (int(k), P[usados], Nn[usados], T[usados], mapa[sel].reshape(-1).astype(np.uint32))
        )
    return saida


def malha_convexa(pontos):
    """Fecho convexo dos pontos (m): posições, normais de face e índices."""
    bm = bmesh.new()
    for p in pontos:
        bm.verts.new(Vector(p))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    lixo = [
        g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)
    ]
    bmesh.ops.delete(bm, geom=lixo, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    centro = sum((v.co for v in bm.verts), Vector()) / max(1, len(bm.verts))
    pos, nrm, idx = [], [], []
    for f in bm.faces:
        n = f.normal.copy()
        vs = list(f.verts)
        if n.dot(f.calc_center_median() - centro) < 0:
            n = -n
            vs = vs[::-1]
        for v in vs:
            idx.append(len(pos))
            pos.append(tuple(v.co))
            nrm.append(tuple(n))
    bm.free()
    return np.array(pos, np.float64), np.array(nrm, np.float64), np.array(idx, np.uint32)


def para_roblox(p) -> list[float]:
    """Ponto do Blender (m, Z em cima, frente -Y) -> referencial do modelo no Roblox depois do giro
    de 180° em Y do importador (studs, Y em cima, frente -Z): (-x, z, y) / 0,28."""
    return [round(-p[0] / STUD, 3), round(p[2] / STUD, 3), round(p[1] / STUD, 3)]


def atlas_de(cfg: dict, grupo: str) -> str:
    for a, g in cfg["grupos"].items():
        if grupo == a or grupo in g.get("inclui", []):
            return a
    raise KeyError(f"grupo {grupo} sem atlas no catálogo")


def montar(chave: str):
    mod = bases_us if chave.startswith("us_") else bases_vc
    r = getattr(mod, f"receita_{chave}")()
    desl = normalizar(r)
    return r, desl


def main() -> None:
    a = C.argumentos()
    chave = a[0]
    cfg = BASES[chave]
    t0 = time.time()
    cena = C.cena_vazia()
    C.preparar_bake(cena)
    cpu = "--cpu" in a or "--cpu-todos" in a
    if "--cpu" in a:
        # sem GPU (o dono joga no mesmo PC): Cycles na CPU com 4 threads
        cena.cycles.device = "CPU"
        cena.render.threads_mode = "FIXED"
        cena.render.threads = 4
    elif "--cpu-todos" in a:
        # CPU com todas as threads: com o driver NVIDIA 556.29 o Blender 5.3 recusa o OptiX e o
        # CUDA aparece mas renderiza na CPU (medido: 44 s "na GPU" x 33 s na CPU)
        cena.cycles.device = "CPU"
    else:
        C.log("dispositivo do bake:", bases_us.B.usar_cuda(cena))
    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    pasta.mkdir(parents=True, exist_ok=True)
    trab.mkdir(parents=True, exist_ok=True)
    r, _ = montar(chave)
    for o in r.objs + r.baixos:
        o["atlas"] = atlas_de(cfg, o["grupo"])
    for o in r.baixos:
        # só servem de alvo do bake: fora do render (senão escurecem a oclusão dos vizinhos)
        o.hide_render = True
        C._visibilidade(o, False)
    nos: list[str] = []
    for o in r.objs:
        if o["no"] not in nos:
            nos.append(o["no"])
    resumo = {
        at: {
            "objetos": sum(1 for o in r.objs if o["atlas"] == at),
            "triangulos": sum(
                C.triangulos(o) for o in r.objs if o["atlas"] == at and not o.get("so_bake")
            ),
        }
        for at in cfg["grupos"]
    }
    C.log("montado", chave, resumo, "colisão", len(r.colisao), "nós", nos)
    if "--so-montar" in a:
        C.log("ok", chave, "só montagem")
        return
    if "--previa" in a:
        i = a.index("--previa")
        az = float(a[i + 1]) if len(a) > i + 1 else 40.0
        N.previa_alta(r.objs, trab / f"previa_alta_{int(az)}.png", az)
        C.log("ok", chave, "prévia")
        return
    for o in r.objs + r.baixos:
        if o.type == "MESH":
            marcar_no(o, nos.index(o["no"]))

    capturas: list[dict] = []

    def captura(partes, caminho, texturas, metal=False, rugosidade=0.9, cor_fator=None):
        for nome, obj in partes:
            capturas.append(
                {"grupo": nome, "malhas": arrays_por_no(obj), "texturas": texturas, "metal": metal}
            )
        tris = sum(len(m[4]) // 3 for m in capturas[-1]["malhas"])
        return {"triangulos": tris, "mb": 0.0}

    original = C.exportar_glb
    C.exportar_glb = captura
    info_grupos = {}
    baixos = []
    try:
        for atlas, gcfg in cfg["grupos"].items():
            tex = gcfg["tex"]
            altos = [o for o in r.objs if o["atlas"] == atlas]
            geo = [o for o in altos if not o.get("so_bake")]
            geo_red = [o for o in geo if not o.get("substituido")]
            manuais = [o for o in r.baixos if o["atlas"] == atlas]
            alto_ref = N.juntar_copias(geo, f"alto_{atlas}")
            tris_alto = C.triangulos(alto_ref)
            tris_man = sum(C.triangulos(o) for o in manuais)
            sem_red = gcfg.get("sem_reducao", False)
            partes, tentativas, limpeza = [], [], {}
            if geo_red:
                # a parte reduzida (ou só limpa, com `sem_reducao`)
                base = N.juntar_copias(geo_red, f"base_{atlas}")
                if not sem_red and C.triangulos(base) > PRE_REDUCAO:
                    C.reduzir(base, PRE_REDUCAO, planar_graus=0.5)
                limpeza = C.limpar(base, escondidas=gcfg.get("escondidas", False), n_dir=96)
                if sem_red:
                    parte = C.copiar(base, f"baixo_{atlas}")
                    C.triangular(parte)
                    tentativas = [{"alvo": None, "tris": C.triangulos(parte), "obs": "sem redução"}]
                else:
                    parte, tentativas = C.escolher_alvo(base, max(300, gcfg["teto"] - tris_man))
                if gcfg.get("normais", True):
                    C.normais_para_fora(parte)
                bpy.data.objects.remove(base)
                partes.append(parte)
            if manuais:
                # a parte feita à mão (lona, paredes de sacos, chapas): sem redução nem
                # recálculo de normais (já nascem viradas para fora)
                parte = N.juntar_copias(manuais, f"manual_{atlas}")
                C.triangular(parte)
                parte.hide_render = False
                C._visibilidade(parte, True)
                partes.append(parte)
                tentativas.append({"alvo": None, "tris": tris_man, "obs": "malha baixa à mão"})
            baixo = partes[0] if len(partes) == 1 else M.juntar(partes, f"baixo_{atlas}")
            C.log(atlas, "alta", tris_alto, "à mão", tris_man, "limpeza", limpeza)
            C.suavizar(baixo, gcfg.get("suave", cfg.get("suave", 50)))
            n_ilhas = C.desdobrar(
                baixo, margem=4 / tex, visibilidade=gcfg.get("visibilidade", True)
            )
            d = C.desvio(baixo, alto_ref, n=12000)
            C.log(atlas, "desvio", d)
            bpy.data.objects.remove(alto_ref)
            # Lona fina com baixa à mão: o filtro de faces de costas do `produzir` tirava pedaços da
            # face de FORA da lona alta (onde a baixa, mais grossa de grade, passa por fora dela) e
            # o raio do bake atravessava até o interior escuro (pontos pretos na lona)
            filtro = C.filtrar_costas
            if not gcfg.get("costas", True):
                C.filtrar_costas = lambda *args, **kw: 0
            try:
                res = C.produzir(
                    cena,
                    baixo,
                    altos,
                    tex,
                    trab / atlas,
                    trab / f"{atlas}.glb",
                    atlas,
                    forca_ao=gcfg.get("forca_ao", 0.55),
                    metal=gcfg.get("metal", False),
                    amostras_ao=48 if cpu else 128,
                )
            finally:
                C.filtrar_costas = filtro
            baixo.hide_render = True
            baixos.append(baixo)
            info_grupos[atlas] = {
                "triangulos_alta": tris_alto,
                "triangulos": res["exportacao"]["triangulos"],
                "teto": gcfg["teto"],
                "sem_reducao": sem_red,
                "texturas_px": res["texturas_px"],
                "uso_uv": C.uso_uv(baixo),
                "ilhas_uv": n_ilhas,
                "desvio_m": d,
                "tentativas": tentativas,
                "limpeza": limpeza,
                "bake": res["bake"],
            }
    finally:
        C.exportar_glb = original

    # GLB final: um material por atlas, um nó por `no`, colisão e zonas
    g = glb.Glb()
    mesmo_lugar = bool(r.extras.get("mesmo_lugar"))
    desl_no: dict[str, np.ndarray] = {}
    todos_pts = []
    tris_vis = 0
    nos_saida = []
    for cap in capturas:
        ids = {k: g.texture(*v) for k, v in cap["texturas"].items()}
        mi = g.material(
            f"{chave}_{cap['grupo']}",
            ids.get("cor"),
            ids.get("normal"),
            ids.get("mr"),
            metal=cap["metal"],
        )
        for k, p, n, t, idx in cap["malhas"]:
            nome = nos[k]
            p = p.copy()
            if mesmo_lugar:
                c = (p.min(axis=0) + p.max(axis=0)) / 2
                desl_no[nome] = np.array([c[0], c[1], 0.0])
                p -= desl_no[nome]
            P, Nn, T = glb.de_blender(p, n, t)
            g.mesh(nome, P, Nn, T, idx, mi)
            todos_pts.append(p)
            tris_vis += len(idx) // 3
            nos_saida.append({"no": nome, "atlas": cap["grupo"], "triangulos": len(idx) // 3})
    mc = g.material("Colisao", None, rugosidade=1.0, cor_fator=(0.8, 0.05, 0.05, 1.0))
    col_saida = []
    tris_col = 0
    ref = next(iter(desl_no.values())) if desl_no else np.zeros(3)
    for c in r.colisao:
        pts = np.array(c["pontos"]) - ref
        p, n, idx = malha_convexa(pts.tolist())
        P, Nn, T = glb.de_blender(p, n, np.zeros((len(p), 2)))
        prefixo = "Zona" if c["tipo"] == "zona" else "Colisao"
        nome = f"{prefixo}_{c['nome']}"
        g.mesh(nome, P, Nn, None, idx, mc)
        tris_col += len(idx) // 3
        rb = np.array([para_roblox(q) for q in pts.tolist()])
        lo, hi = rb.min(axis=0), rb.max(axis=0)
        item = {
            "no": nome,
            "tipo": c["tipo"],
            "centro_studs": [round(float(x), 3) for x in (lo + hi) / 2],
            "tamanho_studs": [round(float(x), 3) for x in hi - lo],
            "bala": c["bala"],
            "material": c["material"],
        }
        if c["tipo"] == "prisma":
            item["pontos_studs"] = rb.round(3).tolist()
        if c["obs"]:
            item["obs"] = c["obs"]
        col_saida.append(item)
    saida = pasta / f"{chave}.glb"
    dados = g.bytes()
    saida.write_bytes(dados)
    allp = np.concatenate(todos_pts)
    lo, hi = allp.min(axis=0), allp.max(axis=0)
    dim = hi - lo
    extras = {}
    for k, v in r.extras.items():
        if k.endswith("_m") and isinstance(v, list) and v and isinstance(v[0], list):
            extras[k[:-2] + "_studs"] = [para_roblox(np.array(p) - ref) for p in v]
        elif k.endswith("_m") and isinstance(v, list) and len(v) == 3:
            extras[k[:-2] + "_studs"] = para_roblox(np.array(v) - ref)
        elif k == "cancela_eixo_blender":
            extras["cancela_eixo_roblox"] = {"X": "X", "Y": "Z", "Z": "Y"}[v]
        else:
            extras[k] = v
    metricas = pasta / "metricas.json"
    if metricas.is_file():
        metricas.unlink()
    teto = sum(gc["teto"] for gc in cfg["grupos"].values())
    texturas = [f"{gc['tex']}" for gc in cfg["grupos"].values()]
    C.gravar_json(
        metricas,
        {
            "chave": chave,
            "tipo": "base",
            "base": cfg["base"],
            "nome": cfg["nome"],
            "classe": cfg["classe"],
            "classe_artbudget": "prop",
            "meta_triangulos": teto,
            "medidas_reais": cfg["medidas"],
            "frente": "-Y no Blender = +Z no GLB; no Roblox, depois do giro de 180° do importador "
            "(D-58), a frente fica em -Z (LookVector). Conferir no Studio.",
            "casca": cfg.get("casca", []),
            "novo": {
                "arquivo": f"assets/blender/{chave}/{saida.name}",
                "triangulos": tris_vis,
                "triangulos_colisao": tris_col,
                "triangulos_glb": glb.triangulos(saida),
                "texturas_px": {"cor": [cfg["grupos"][next(iter(cfg["grupos"]))]["tex"]] * 2},
                "atlas": len(cfg["grupos"]),
                "texturas_lista": texturas,
                "mb": round(len(dados) / 2**20, 3),
                "dim_m_xyz": [round(float(x), 3) for x in (dim[0], dim[2], dim[1])],
                "dim_studs_xyz": [round(float(x) / STUD, 2) for x in (dim[0], dim[2], dim[1])],
                "nos": nos_saida,
            },
            "grupos": info_grupos,
            "colisao": col_saida,
            "extras": extras,
            "uso": USO_PADRAO + (" " + USO[chave] if chave in USO else ""),
            "tempo_total_s": round(time.time() - t0, 1),
        },
    )
    C.log(
        "ok",
        chave,
        {"tri": tris_vis, "col": tris_col, "mb": round(len(dados) / 2**20, 2)},
        "em",
        round(time.time() - t0, 1),
        "s",
    )


if __name__ == "__main__":
    main()
