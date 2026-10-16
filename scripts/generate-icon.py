#!/usr/bin/env python3
"""Render the app's simple crescent mark with stdlib only; no asset dependencies."""
from pathlib import Path
import json, struct, zlib, math
assets = Path(__file__).resolve().parents[1] / 'native/App/MySleepAssets.xcassets'
assets.mkdir(exist_ok=True)
(assets / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
size = 1024
rows = bytearray()
for y in range(size):
    rows.append(0)
    for x in range(size):
        shade = y / size
        color = [int(14 - 7 * shade), int(28 - 13 * shade), int(57 - 23 * shade)]
        # Antialias with a one-pixel signed-distance ramp.
        moon = 280 - math.hypot(x - 470, y - 540)
        cut = math.hypot(x - 598, y - 415) - 253
        coverage = max(0, min(1, min(moon, cut) + .5))
        for sx, sy, radius in [(750, 295, 15), (795, 459, 9), (607, 188, 9)]:
            coverage = max(coverage, max(0, min(1, radius - math.hypot(x-sx, y-sy) + .5)))
        color = [round(c * (1-coverage) + target * coverage) for c, target in zip(color, [150, 201, 255])]
        rows.extend(color)
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')
for name, platform in [('MySleepIcon', 'ios'), ('MySleepWatchIcon', 'watchos')]:
    directory = assets / (name + '.appiconset')
    directory.mkdir(exist_ok=True)
    (directory / 'icon.png').write_bytes(png)
    (directory / 'Contents.json').write_text(json.dumps({'images':[{'filename':'icon.png', 'idiom':'universal', 'platform':platform, 'size':'1024x1024'}], 'info':{'author':'xcode', 'version':1}}, indent=2))
