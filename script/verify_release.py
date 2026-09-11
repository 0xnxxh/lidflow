#!/usr/bin/env python3
"""Validate the public release contract and cryptographic update signature."""
import base64
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
build = (root / 'BUILD_NUMBER').read_text().strip()
app = root / 'dist/LidFlow.app'
dmg = root / f'dist/LidFlow-v{version}.dmg'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
key = (root / 'Config/sparkle_public_ed_key.txt').read_text().strip()
assert len(base64.b64decode(key, validate=True)) == 32
assert info['CFBundleShortVersionString'] == version
assert info['CFBundleVersion'] == build
assert info['CFBundleIdentifier'] == 'app.lidflow.local'
assert info['SUPublicEDKey'] == key
assert info['SUFeedURL'] == 'https://github.com/0xnxxh/lidflow/releases/latest/download/appcast.xml'
assert info['CFBundleIconFile'] == 'AppIcon'
assert info['LSMinimumSystemVersion'] == '14.0'
assert (app / 'Contents/Resources/AppIcon.icns').read_bytes() == (root / 'Resources/AppIcon.icns').read_bytes()
assert list((app / 'Contents/Resources').glob('*.bundle/Contents/Resources/Shaders.metal'))
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items = ET.parse(root / 'dist/appcast.xml').findall('./channel/item')
assert len(items) == 1
item = items[0]
assert item.findtext('sparkle:version', namespaces=ns) == build
assert item.findtext('sparkle:shortVersionString', namespaces=ns) == version
assert item.findtext('sparkle:minimumSystemVersion', namespaces=ns) == '14.0'
enclosure = item.find('enclosure')
assert enclosure is not None
assert enclosure.attrib['url'] == f'https://github.com/0xnxxh/lidflow/releases/download/v{version}/{dmg.name}'
assert int(enclosure.attrib['length']) == dmg.stat().st_size
signature = enclosure.attrib[f'{{{ns["sparkle"]}}}edSignature']
assert len(base64.b64decode(signature, validate=True)) == 64
subprocess.run(['xcrun', 'swift', str(root / 'script/verify_update.swift'), key, signature, str(dmg)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(f'Release metadata, resources and signed archive verified: v{version} ({build})')
