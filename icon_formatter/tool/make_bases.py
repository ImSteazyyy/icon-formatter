"""Built-in base icons: a squircle and a circle plate, drawn from scratch.

Same plate as the reference the app was calibrated on: 0.93 of the canvas,
black, alpha 105 at the top to 183 at the bottom, a thin light rim. Squircle
exponent 4.25 (the app's reference squircle); the circle is the Lucent one.
Run:  py -3.10 tool/make_bases.py   (needs Pillow)
"""
import os
from PIL import Image

SIZE, SS = 192, 4
here = os.path.dirname(os.path.abspath(__file__))
out = os.path.normpath(os.path.join(here, '..', 'assets', 'bases'))


def plate(inside):
    big = SIZE * SS
    a = 0.93 * big / 2
    c = big / 2
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    px = img.load()
    rim = 1.3 * SS
    for y in range(big):
        alpha = 105 + 78 * y / big
        for x in range(big):
            d = inside((x + 0.5 - c) / a, (y + 0.5 - c) / a)
            if d > 1:
                continue
            # distance to the edge in pixels (approximate, from the shape value)
            edge = (1 - d) * a / 4.0
            if edge < rim:
                px[x, y] = (128, 128, 128, 160)
            else:
                px[x, y] = (0, 0, 0, int(alpha))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


plate(lambda u, v: abs(u) ** 4.25 + abs(v) ** 4.25).save(os.path.join(out, 'squircle.png'))
plate(lambda u, v: u * u + v * v).save(os.path.join(out, 'circle.png'))
print('ok')
