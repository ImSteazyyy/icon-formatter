"""App icon of Icon Formatter (Android launcher, Windows .ico, in-app logo).

Source: assets/branding/app_icon_source.png, the round white icon with the
black and red symbol. The in-app logo, the legacy launcher icon and the
Windows .ico use it as it is. The adaptive icon splits it: a white
background layer and the symbol alone as foreground (white keyed out),
sized like other app symbols inside the launcher mask.
Run:  py -3.10 tool/make_app_icon.py   (needs Pillow)
"""
import os
from PIL import Image

FRACTION = 0.52  # symbol span / 108 dp adaptive canvas (visible mask = 72 dp)

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, '..'))
src = Image.open(os.path.join(root, 'assets', 'branding', 'app_icon_source.png')).convert('RGBA')
w, h = src.size

# the symbol: dark or saturated pixels inside the white disc; alpha follows
# the distance from white, so the anti-aliased edge stays smooth
sym = Image.new('RGBA', src.size, (0, 0, 0, 0))
px, out = src.load(), sym.load()
cx0, cy0, rad = w / 2, h / 2, min(w, h) * 0.45
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a < 200 or (x - cx0) ** 2 + (y - cy0) ** 2 > rad * rad:
            continue
        ink = 255 - min(r, g, b)  # 0 on white, high on black or red
        if ink < 18:
            continue
        k = min(1.0, (ink - 18) / 120)
        # un-mix from white so edge pixels keep their true colour
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


def whole(size):
    return src.resize((size, size), Image.LANCZOS)


whole(1024).save(os.path.join(root, 'assets', 'branding', 'app_icon.png'))
res = os.path.join(root, 'android', 'app', 'src', 'main', 'res')
for d, legacy in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    os.makedirs(os.path.join(res, 'mipmap-' + d), exist_ok=True)
    whole(legacy).save(os.path.join(res, 'mipmap-' + d, 'ic_launcher.png'))
    symbol(legacy * 108 // 48).save(os.path.join(res, 'mipmap-' + d, 'ic_launcher_foreground.png'))
whole(256).save(os.path.join(root, 'windows', 'runner', 'resources', 'app_icon.ico'),
                sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('symbol box', box)
