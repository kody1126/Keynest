#!/usr/bin/env python3
"""Build-time only: download the explicitly curated public brand-asset manifest.
No dependency installation, app launch, credentials, or runtime image requests.
Use --download for network acquisition; otherwise render verified cached sources.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse, hashlib, json, subprocess, sys
from urllib.parse import urlparse
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / 'scripts/brand-icon-manifest.json'
CACHE = ROOT / '.build/icon-sources-0.7/assets'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def acquire(asset, download):
    directory, icon_id = asset['directory'], asset['id']
    if directory not in {'ProviderIcons', 'ToolIcons'} or not icon_id.replace('-', '').isalnum():
        raise ValueError('Unexpected manifest destination')
    source = asset['source']
    if urlparse(source).scheme != 'https':
        raise ValueError('HTTPS source required')
    cached = CACHE / (directory + '-' + icon_id + '.' + asset['format'])
    if download and not cached.exists():
        temp = cached.with_suffix(cached.suffix + '.download')
        subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location',
                        '--connect-timeout', '15', '--max-time', '60', '--retry', '1',
                        asset.get('downloadURL', source), '-o', str(temp)], check=True)
        temp.replace(cached)
    if not cached.is_file():
        raise FileNotFoundError(cached)
    if asset.get('sourceSHA256') and sha(cached) != asset['sourceSHA256']:
        raise ValueError('Source checksum changed for ' + icon_id)
    if asset.get('gitBlobSHA1'):
        data = cached.read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if blob != asset['gitBlobSHA1']:
            raise ValueError('Pinned Git object mismatch for ' + icon_id)
    asset['sourceSHA256'] = sha(cached)
    rendered = cached
    if asset['format'] == 'svg':
        svg = cached.read_text()
        # The curated SVG must be self-contained. Do not render references that
        # could read other files or make network requests.
        import re
        if re.search(r'(?:href|xlink:href)\s*=\s*[\"\'](?!#|data:)', svg) or '<!ENTITY' in svg or '<script' in svg.lower():
            raise ValueError('External reference or active SVG: ' + icon_id)
        if asset.get('color'):
            svg = svg.replace('<svg ', '<svg fill="#' + asset['color'] + '" ', 1)
        svg = svg.replace('currentColor', '#' + asset.get('color', '111111'))
        prepared = cached.with_suffix('.prepared.svg')
        prepared.write_text(svg)
        rendered = cached.with_suffix('.rendered.png')
        subprocess.run(['rsvg-convert', '--keep-aspect-ratio', '--width', '512', '--height', '512',
                        str(prepared), '-o', str(rendered)], check=True)
    im = Image.open(rendered).convert('RGBA')
    if not im.getbbox():
        raise ValueError('Empty image: ' + icon_id)
    # Keep the source composition and colors. Fit to a transparent square;
    # the native icon view supplies the white well and its normal padding.
    ratio = 256 / max(im.size)
    im = im.resize((max(1, round(im.width * ratio)), max(1, round(im.height * ratio))), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (256, 256))
    canvas.alpha_composite(im, ((256-im.width)//2, (256-im.height)//2))
    target = ROOT / 'Resources' / directory / (icon_id + '.png')
    target.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(target, optimize=True)
    asset['outputSHA256'] = sha(target)
    return asset


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    for asset in manifest.get('preservedAssets', []):
        original = ROOT / 'Resources/ProviderIcons' / (asset['id'] + '.png')
        if sha(original) != asset['outputSHA256']:
            raise ValueError('Original icon changed: ' + asset['id'])
    CACHE.mkdir(parents=True, exist_ok=True)
    failures = []
    with ThreadPoolExecutor(max_workers=6) as executor:
        futures = [(asset, executor.submit(acquire, asset.copy(), args.download)) for asset in manifest['assets']]
        for asset, future in futures:
            try:
                asset.update(future.result())
                print('OK', asset['directory'], asset['id'], flush=True)
            except Exception as error:
                failures.append(asset['id'])
                print('FAILED', asset['id'], str(error), file=sys.stderr, flush=True)
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    for name in ['ProviderIcons', 'ToolIcons']:
        folder = ROOT / 'Resources' / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder/'SHA256SUMS').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in sorted(folder.glob('*.png'))))
    if failures:
        sys.exit('Unfinished assets: ' + ', '.join(failures))

if __name__ == '__main__':
    main()
