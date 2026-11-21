"""Moldes v3 (tools/make_clothing_v3.py): tamanho do Roblox, mesmas regiões da v2, áreas de pele
transparentes onde o Characters põe a cor de pele, estêncil no bolso certo e arquivos em dia."""

import re
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import make_clothing as v2  # noqa: E402
import make_clothing_v3 as v3  # noqa: E402

KEYS = sorted(v3.OUTFITS)


def img(key: str) -> np.ndarray:
    return np.asarray(Image.open(v3.OUT / f"{key}.png").convert("RGBA"))


def alpha_at(key: str, box, dx: int, dy: int) -> int:
    return int(img(key)[box[1] + dy, box[0] + dx, 3])


def test_regioes_iguais_a_v2():
    assert v3.TORSO == v2.TORSO and v3.R_LIMB == v2.R_LIMB and v3.L_LIMB == v2.L_LIMB
    assert (v3.W, v3.H) == (v2.W, v2.H) == (585, 559)


@pytest.mark.parametrize("key", KEYS)
def test_molde(key):
    path = v3.OUT / f"{key}.png"
    assert path.is_file(), f"rode: uv run python tools/make_clothing_v3.py ({key})"
    im = Image.open(path)
    assert im.size == (585, 559) and im.mode == "RGBA"
    a = np.asarray(im)[..., 3]
    assert a[10, 10] == 0  # fora das regiões
    assert alpha_at(key, v3.TORSO["front"], 64, 50) == 255  # peito
    assert alpha_at(key, v3.TORSO["back"], 64, 50) == 255


@pytest.mark.parametrize("key", KEYS)
def test_arquivo_em_dia(key):
    """O PNG é o que o código gera hoje (determinístico)."""
    fresh = np.asarray(v3.render(v3.OUTFITS[key]))
    assert np.array_equal(fresh, img(key)), f"{key}.png velho: rode tools/make_clothing_v3.py"


@pytest.mark.parametrize("key", [k for k in KEYS if v3.OUTFITS[k].kind == "shirt"])
def test_mao_transparente(key):
    for limb in (v3.R_LIMB, v3.L_LIMB):
        for face in ("F", "B", "L", "R"):
            assert alpha_at(key, limb[face], 32, 122) == 0, f"mão em {face}"
        assert alpha_at(key, limb["down"], 32, 32) == 0


def test_mangas():
    f = v3.R_LIMB["F"]
    assert alpha_at("us_shirt_v3", f, 32, 90) == 255  # antebraço coberto
    assert alpha_at("us_shirt_rolled_v3", f, 32, 20) == 255  # braço coberto
    assert alpha_at("us_shirt_rolled_v3", f, 32, 70) == 0  # arregaçada acima do cotovelo
    assert alpha_at("vc_black_shirt_v3", f, 32, 70) == 255
    assert alpha_at("vc_black_shirt_v3", f, 32, 100) == 0  # arregaçada no antebraço


def test_camisa_us_por_dentro_e_vc_por_fora():
    fr = v3.TORSO["front"]
    assert alpha_at("us_shirt_v3", fr, 30, 118) == 0  # LowerTorso: aparece a calça
    assert alpha_at("vc_khaki_shirt_v3", fr, 30, 118) == 255
    assert alpha_at("us_pants_v3", fr, 30, 118) == 255


def test_decote_vc_pele_e_us_camiseta():
    fr = v3.TORSO["front"]
    assert alpha_at("vc_khaki_shirt_v3", fr, 64, 6) == 0
    assert alpha_at("vc_black_shirt_v3", fr, 64, 4) == 0
    assert alpha_at("us_shirt_v3", fr, 64, 6) == 255  # camiseta verde no V


def test_estencil_usmc_no_bolso_esquerdo():
    """O bolso esquerdo do soldado fica à DIREITA da frente no molde (visto de frente)."""
    fr = v3.TORSO["front"]
    a = img("us_shirt_v3")[fr[1] + 40 : fr[1] + 58, fr[0] : fr[2], :3].astype(float).mean(axis=2)
    dark = a < np.median(a) - 25  # tinta do estêncil bem mais escura que o tecido
    right = dark[:, 80:110].sum()  # bolso esquerdo do soldado
    left = dark[:, 18:48].sum()  # bolso direito
    assert right > 40 and left < 5, (right, left)


def test_botas_us_e_sandalia_vc():
    for limb in (v3.R_LIMB, v3.L_LIMB):
        f = limb["F"]
        boot = img("us_pants_v3")[f[1] + 100 : f[1] + 124, f[0] + 4 : f[2] - 4]
        assert boot[..., 3].min() == 255 and boot[..., :3].mean() < 60, "bota de couro preto"
        for key in ("vc_khaki_pants_v3", "vc_green_pants_v3", "vc_black_pants_v3"):
            shin = img(key)[f[1] + 98 : f[1] + 108, f[0] + 2 : f[2] - 2, 3]
            assert shin.mean() < 30, f"{key}: canela à mostra (pele)"
            sole = img(key)[f[1] + 126, f[0] + 2 : f[2] - 2]
            assert sole[:, 3].min() == 255 and sole[:, :3].mean() < 60, f"{key}: sola de pneu"
            assert alpha_at(key, limb["down"], 32, 32) == 255


def test_calca_us_sem_bolso_de_carga():
    """Lado de fora da coxa liso (a calça de 4 bolsos de 1965; carga só no uniforme de selva)."""
    f = v3.R_LIMB["R"]  # lado de fora da perna direita
    thigh = (
        img("us_pants_v3")[f[1] + 20 : f[1] + 50, f[0] + 6 : f[2] - 6, :3]
        .astype(float)
        .mean(axis=2)
    )
    assert thigh.std() < 12


def test_chaves_lidas_pelo_gear_existem():
    src = (ROOT / "src/ServerScriptService/Modules/Gear.luau").read_text(encoding="utf-8")
    literal = set(re.findall(r'"([a-z]\w*_v3)"', src))
    for variant in ("khaki", "green", "black"):  # montadas como "vc_" .. variante .. "_shirt_v3"
        literal |= {f"vc_{variant}_shirt_v3", f"vc_{variant}_pants_v3"}
    assert literal <= set(v3.OUTFITS), literal - set(v3.OUTFITS)
    assert set(v3.OUTFITS) <= literal
