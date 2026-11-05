"""App icon of Icon Formatter (Android launcher, Windows .ico, in-app logo).

Source: assets/branding/app_icon_source.png (brush + corner brackets). The
source carries a noisy semi-transparent halo from an earlier background
removal: only the solid shapes are kept (alpha cut-out with a soft 1-2 px
anti-aliased edge), the background is fully transparent. The adaptive
foreground keeps the symbol inside the visible launcher mask with the same
proportion as the icon pack icon (tool/make_pack_icon.py), so both sit at
the size of other app icons.
Run:  python tool/make_app_icon.py   (needs Pillow)
"""
import os
from PIL import Image, ImageFilter

FRACTION = 0.60  # symbol span / 108 dp adaptive canvas (visible mask = 72 dp)

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, '..'))
src = Image.open(os.path.join(root, 'assets', 'branding', 'app_icon_source.png')).convert('RGBA')

solid = src.split()[3].point(lambda v: 255 if v >= 240 else 0)
alpha = solid.filter(ImageFilter.GaussianBlur(1.4)).point(lambda v: 0 if v < 10 else min(255, int(v * 1.06)))
rgb = src.convert('RGB')
icon = rgb.convert('RGBA')
icon.putalpha(alpha)
box = solid.getbbox()
cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
span = max(box[2] - box[0], box[3] - box[1])


def render(fraction, size):
    side = int(span / fraction)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(icon, (int(side / 2 - cx), int(side / 2 - cy)))
    return canvas.resize((size, size), Image.LANCZOS)


# in-app logo (title bar, settings profile card)
render(0.92, 1024).save(os.path.join(root, 'assets', 'branding', 'app_icon.png'))

res = os.path.join(root, 'android', 'app', 'src', 'main', 'res')
for d, legacy in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    os.makedirs(os.path.join(res, 'mipmap-' + d), exist_ok=True)
    render(0.92, legacy).save(os.path.join(res, 'mipmap-' + d, 'ic_launcher.png'))
    render(FRACTION, legacy * 108 // 48).save(os.path.join(res, 'mipmap-' + d, 'ic_launcher_foreground.png'))

ico = render(0.92, 256)
ico.save(os.path.join(root, 'windows', 'runner', 'resources', 'app_icon.ico'),
         sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('symbol box', box)
