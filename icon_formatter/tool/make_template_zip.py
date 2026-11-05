"""Packs iconpack_template/ into assets/iconpack_template.zip (bundled with the
app and used by "Crea APK" in the Icon Pack Builder). Run after editing the
template:  python tool/make_template_zip.py"""
import os
import zipfile

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, '..', 'iconpack_template')
dest = os.path.join(here, '..', 'assets', 'iconpack_template.zip')
with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in ('build', '.gradle')]
        for f in files:
            if f == 'local.properties':
                continue
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, root).replace(os.sep, '/'))
print(len(zipfile.ZipFile(dest).namelist()), 'files ->', os.path.normpath(dest))
