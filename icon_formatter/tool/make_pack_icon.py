"""Launcher icon of the icon packs created by Icon Formatter (template APK).

Source: assets/branding/pack_icon_source.png, the round white icon with the
black and red stacked layers. The legacy icon and the in-app picture use it
as it is; the adaptive icon is a white background plus the symbol alone
(white keyed out), sized like the app icon (tool/make_app_icon.py).
Run:  py -3.10 tool/make_pack_icon.py   (needs Pillow)
"""
import os
from PIL import Image

FRACTION = 0.52  # symbol span / 108 dp adaptive canvas (visible mask = 72 dp)

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, '..'))
res = os.path.join(root, 'iconpack_template', 'app', 'src', 'main', 'res')
src = Image.open(os.path.join(root, 'assets', 'branding', 'pack_icon_source.png')).convert('RGBA')
w, h = src.size

sym = Image.new('RGBA', src.size, (0, 0, 0, 0))
px, out = src.load(), sym.load()
cx0, cy0, rad = w / 2, h / 2, min(w, h) * 0.45
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a < 200 or (x - cx0) ** 2 + (y - cy0) ** 2 > rad * rad:
            continue
        ink = 255 - min(r, g, b)
        if ink < 18:
            continue
        k = min(1.0, (ink - 18) / 120)

        def un(c):
            return max(0, min(255, int(255 - (255 - c) / max(k, 1e-3))))
        out[x, y] = (un(r), un(g), un(b), int(255 * k))
box = sym.split()[3].point(lambda v: 255 if v > 128 else 0).getbbox()
cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
span = max(box[2] - box[0], box[3] - box[1])


def symbol(size):
    side = int(span / FRACTION)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(sym, (int(side / 2 - cx), int(side / 2 - cy)))
    return canvas.resize((size, size), Image.LANCZOS)


os.makedirs(os.path.join(res, 'mipmap-xxxhdpi'), exist_ok=True)
symbol(432).save(os.path.join(res, 'mipmap-xxxhdpi', 'ic_launcher_foreground.png'))
src.resize((192, 192), Image.LANCZOS).save(os.path.join(res, 'mipmap-xxxhdpi', 'ic_launcher.png'))
src.resize((1024, 1024), Image.LANCZOS).save(os.path.join(root, 'assets', 'branding', 'pack_icon.png'))

os.makedirs(os.path.join(res, 'mipmap-anydpi-v26'), exist_ok=True)
with open(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w', encoding='utf-8') as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/white" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
print('symbol', box)
