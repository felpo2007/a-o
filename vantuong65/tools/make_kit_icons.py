"""Ícones dos Game Passes de equipamento (D-72): "Kit Veterano" e "Kit de Elite".

Base: a key art do jogo (assets/forgegui/marketing/capa_keyart.jpg), recortada em quadrado,
escurecida e com o nome em estêncil e o nível. 512 x 512 (o Roblox arredonda os cantos).

Uso: uv run python tools/make_kit_icons.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

MKT = Path(__file__).resolve().parent.parent / "assets/forgegui/marketing"
KITS = [
    ("gamepass_kit_veterano.jpg", "KIT", "VETERANO", "NÍVEL 1", (0.55, 0.6, 0.42)),
    ("gamepass_kit_elite.jpg", "KIT DE", "ELITE", "NÍVEL 2", (0.62, 0.5, 0.3)),
]


def font(size: int, vi: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    # Impact não tem os acentos vietnamitas: o nome do jogo vai em Arial Bold
    names = ("arialbd.ttf", "DejaVuSans-Bold.ttf") if vi else ("impact.ttf", "arialbd.ttf")
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def make(dst: str, top: str, big: str, level: str, tint: tuple[float, float, float]) -> None:
    src = Image.open(MKT / "capa_keyart.jpg").convert("RGB")
    w, h = src.size
    s = min(w, h)
    im = src.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2)).resize((512, 512))
    im = ImageEnhance.Brightness(im).enhance(0.45)
    over = Image.new("RGB", im.size, tuple(int(255 * c) for c in tint))
    im = Image.blend(im, over, 0.28)
    d = ImageDraw.Draw(im)
    d.rectangle((18, 18, 494, 494), outline=(214, 203, 170), width=6)
    d.rectangle((18, 360, 494, 494), fill=(40, 36, 28))

    def center(text: str, y: int, f, color) -> None:
        box = d.textbbox((0, 0), text, font=f)
        d.text(((512 - (box[2] - box[0])) // 2, y), text, font=f, fill=color)

    center(top, 60, font(58), (214, 203, 170))
    center(big, 140, font(100 if len(big) > 6 else 118), (234, 226, 200))
    center(level, 380, font(64), (190, 166, 116))
    center("VẠN TƯỜNG '65", 452, font(28, vi=True), (176, 62, 48))
    im.save(MKT / dst, quality=92)
    print("gravado", MKT / dst)


def main() -> None:
    for k in KITS:
        make(*k)


if __name__ == "__main__":
    main()
