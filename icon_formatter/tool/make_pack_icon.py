"""Launcher icon of the icon packs created by Icon Formatter (template APK).

Source: assets/branding/pack_icon_source.png (stacked layers on pure black,
no glow). Only the black is removed: alpha ramps over the 1-2 px
anti-aliased edge, inside the shapes the colours stay exactly as they are;
edge pixels are un-mixed from the black so no dark fringe or halo remains.
Output: adaptive icon with a transparent background, symbol sized like other
app icons (same proportion as the app icon, tool/make_app_icon.py), plus a
legacy PNG for Android 7.x.
Run:  python tool/make_pack_icon.py   (needs Pillow)
"""
import os
from PIL import Image

FRACTION = 0.60  # symbol span / 108 dp adaptive canvas (visible mask = 72 dp)
LO, HI = 24, 96  # black .. shape: alpha ramp on the strongest channel

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, '..'))
res = os.path.join(root, 'iconpack_template', 'app', 'src', 'main', 'res')
src = Image.open(os.path.join(root, 'assets', 'branding', 'pack_icon_source.png')).convert('RGB')

data = []
for r, g, b in src.get_flattened_data():
    m = max(r, g, b)
    a = 0.0 if m <= LO else (1.0 if m >= HI else (m - LO) / (HI - LO))
    if a <= 0:
        data.append((0, 0, 0, 0))
    elif a >= 1:
        data.append((r, g, b, 255))
    else:
        # edge pixel = colour * a + black * (1 - a): recover the colour
        data.append((min(255, round(r / a)), min(255, round(g / a)), min(255, round(b / a)), round(a * 255)))
icon = Image.new('RGBA', src.size)
icon.putdata(data)

box = icon.split()[3].point(lambda v: 255 if v > 127 else 0).getbbox()
cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
span = max(box[2] - box[0], box[3] - box[1])


def render(fraction, size):
    side = int(span / fraction)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(icon, (int(side / 2 - cx), int(side / 2 - cy)))
    return canvas.resize((size, size), Image.LANCZOS)


os.makedirs(os.path.join(res, 'mipmap-xxxhdpi'), exist_ok=True)
render(FRACTION, 432).save(os.path.join(res, 'mipmap-xxxhdpi', 'ic_launcher_foreground.png'))
render(0.86, 192).save(os.path.join(res, 'mipmap-xxxhdpi', 'ic_launcher.png'))
render(0.86, 1024).save(os.path.join(root, 'assets', 'branding', 'pack_icon.png'))

os.makedirs(os.path.join(res, 'mipmap-anydpi-v26'), exist_ok=True)
with open(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w', encoding='utf-8') as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/transparent" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
print('symbol', box)
