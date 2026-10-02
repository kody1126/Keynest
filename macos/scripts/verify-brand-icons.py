#!/usr/bin/env python3
"""Offline integrity/dimension/coverage checks and a visual review contact sheet."""
from pathlib import Path
import hashlib, json, math, re
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parent.parent
manifest = json.loads((ROOT/'scripts/brand-icon-manifest.json').read_text())
providers = re.findall(r'\.init\(id: "([^"]+)"', (ROOT/'Sources/KeynestCore/ProviderPreset.swift').read_text())
expected_tools = [a['id'] for a in manifest['assets'] if a['directory'] == 'ToolIcons']
entries = [('ProviderIcons', p) for p in providers] + [('ToolIcons', p) for p in expected_tools]
assets = {(a['directory'], a['id']): a for a in manifest['assets']}
preserved = {a['id']:a['outputSHA256'] for a in manifest['preservedAssets']}
for folder, id in entries:
    path = ROOT/'Resources'/folder/(id+'.png')
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', id
    im = Image.open(path).convert('RGBA')
    assert im.getbbox(), id
    if (folder, id) in assets:
        assert im.size == (256,256), (id,im.size)
        assert hashlib.sha256(data).hexdigest() == assets[(folder,id)]['outputSHA256'], id
    else:
        assert hashlib.sha256(data).hexdigest() == preserved[id], id
for folder in ['ProviderIcons','ToolIcons']:
    directory = ROOT/'Resources'/folder
    for line in (directory/'SHA256SUMS').read_text().splitlines():
        digest,filename=line.split('  ',1)
        assert hashlib.sha256((directory/filename).read_bytes()).hexdigest() == digest, filename
columns,cell=8,150
sheet=Image.new('RGB',(columns*cell,math.ceil(len(entries)/columns)*cell),(240,242,245))
draw=ImageDraw.Draw(sheet)
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',12)
for i,(folder,id) in enumerate(entries):
    x,y=(i%columns)*cell,(i//columns)*cell
    draw.rounded_rectangle((x+8,y+8,x+142,y+126),radius=10,fill='white')
    im=Image.open(ROOT/'Resources'/folder/(id+'.png')).convert('RGBA');im.thumbnail((90,90),Image.Resampling.LANCZOS)
    sheet.paste(im,(x+(cell-im.width)//2,y+20+(90-im.height)//2),im)
    label=('T: ' if folder=='ToolIcons' else '')+id
    draw.text((x+cell//2,y+135),label,fill=(25,30,38),font=font,anchor='mm')
target=ROOT/'.build/icon-sources-0.7/brand-contact-sheet.png';target.parent.mkdir(parents=True,exist_ok=True);sheet.save(target)
print(f'PASS: {len(providers)} provider icons, {len(expected_tools)} tool icons; PNGs, dimensions, hashes, original preservation.')
print(target)
