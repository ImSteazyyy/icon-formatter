"""Builds assets/iconpack_base.apk: the icon pack template compiled once with
SLOTS empty drawables (slot_0000.png ...) and placeholder res/xml files.

On Android, Icon Formatter fills the slots with the pack's PNGs, writes
appfilter/drawable XML and mapping.json, re-signs the APK with apksig and
installs it through Shizuku (see android/.../PackInstaller.kt). Run on
Windows with the Android SDK + JDK:  python tool/make_base_apk.py
"""
import base64
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

SLOTS = 2000
CAL_GROUPS = 12
PACK_ID = 'com.iconformatter.pack.device'
PACK_NAME = 'Icon Formatter Pack'
# 1x1 transparent PNG
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
PLACEHOLDER_XML = '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n'

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, '..'))
template = os.path.join(root, 'iconpack_template')
dest = os.path.join(root, 'assets', 'iconpack_base.apk')

sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or r'D:\dev\android-sdk'
work = tempfile.mkdtemp(prefix='ifbase_')
proj = os.path.join(work, 'tpl')
shutil.copytree(template, proj, ignore=shutil.ignore_patterns('build', '.gradle', 'local.properties'))
main = os.path.join(proj, 'app', 'src', 'main')
drw = os.path.join(main, 'res', 'drawable-nodpi')
xml = os.path.join(main, 'res', 'xml')
os.makedirs(drw, exist_ok=True)
os.makedirs(xml, exist_ok=True)
os.makedirs(os.path.join(main, 'assets'), exist_ok=True)
for i in range(SLOTS):
    with open(os.path.join(drw, 'slot_%04d.png' % i), 'wb') as f:
        f.write(PNG)
# dynamic calendar icons: CAL_GROUPS apps x 31 days (calNN_1 .. calNN_31);
# appfilter's <calendar prefix="calNN_"/> makes the launcher pick today's day
for g in range(CAL_GROUPS):
    for d in range(1, 32):
        with open(os.path.join(drw, 'cal%02d_%d.png' % (g, d)), 'wb') as f:
            f.write(PNG)
for n in ('appfilter.xml', 'drawable.xml'):
    with open(os.path.join(xml, n), 'w', encoding='utf-8') as f:
        f.write(PLACEHOLDER_XML)
with open(os.path.join(main, 'assets', 'mapping.json'), 'w') as f:
    f.write('[]')
with open(os.path.join(proj, 'local.properties'), 'w') as f:
    f.write('sdk.dir=%s\n' % sdk.replace('\\', '/'))
# keep resource paths readable: the app finds slot files by name
with open(os.path.join(proj, 'gradle.properties'), 'a') as f:
    f.write('\nandroid.enableResourceOptimizations=false\n')

cmd = [os.path.join(proj, 'gradlew.bat' if os.name == 'nt' else 'gradlew'), 'assembleRelease', '--no-daemon', '-q',
       '-PpackId=' + PACK_ID, '-PpackName=' + PACK_NAME, '-PpackVersionCode=1', '-PpackVersionName=1.0']  # version patched on the phone (DevicePack.patchManifest)
r = subprocess.run(cmd, cwd=proj, shell=(os.name == 'nt'))
if r.returncode != 0:
    sys.exit('gradle failed')
apk = os.path.join(proj, 'app', 'build', 'outputs', 'apk', 'release', 'app-release.apk')
shutil.copy(apk, dest)
names = zipfile.ZipFile(dest).namelist()
slots = [n for n in names if 'slot_' in n]
print(len(slots), 'slots;', [n for n in names if n.startswith('res/xml')], '->', dest, os.path.getsize(dest), 'bytes')
shutil.rmtree(work, ignore_errors=True)
