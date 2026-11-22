"""Folha de contato: uv run --group arte python tools/dev/folha.py saida.jpg a.jpg b.jpg"""

import sys

from PIL import Image

arqs = sys.argv[2:]
cel = (640, 480)
cols = 3
lin = (len(arqs) + cols - 1) // cols
tela = Image.new("RGB", (cols * cel[0], lin * cel[1]), (20, 20, 20))
for i, a in enumerate(arqs):
    im = Image.open(a).convert("RGB")
    im.thumbnail(cel)
    x = (i % cols) * cel[0] + (cel[0] - im.width) // 2
    y = (i // cols) * cel[1] + (cel[1] - im.height) // 2
    tela.paste(im, (x, y))
tela.save(sys.argv[1], quality=90)
print(tela.size, len(arqs))
