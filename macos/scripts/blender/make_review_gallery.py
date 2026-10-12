"""Package local Blender renders as a readable, entirely offline review gallery.

No app data, network resources, fonts, or scripts are loaded by the gallery.
Pillow is a development-only dependency for contact sheets and thumbnails.
"""
import argparse
from html import escape
import hashlib
import json
from pathlib import Path
import re
import shutil

from PIL import Image, ImageDraw, ImageFont

MACOS = Path(__file__).resolve().parents[2]


def font(size):
    for path in ("/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"):
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--art-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--study", action="store_true")
    parser.add_argument("--zip", action="store_true", help="Also create a sibling ZIP of the offline gallery")
    args = parser.parse_args()
    art, output = args.art_dir.resolve(), args.output.resolve()
    manifest = json.loads((art / "manifest.json").read_text())
    catalog = (MACOS / "Sources/KeynestCore/ProviderPreset.swift").read_text()
    names = dict(re.findall(r'\.init\(id:\s*"([^"]+)",\s*name:\s*"([^"]+)"', catalog))
    records = []
    for identifier, brand in sorted(manifest["providers"].items()):
        records.append(dict(id=f"brand-{identifier}", name=names[identifier],
                            kind="品牌珐琅挂件", triangles=brand["charmTriangles"]))
    for identifier, palette in manifest["palettes"].items():
        if args.study and identifier != "ice":
            continue
        records.append(dict(id=f"glass-{identifier}", name=f'{palette["name"]} / {identifier.title()}',
                            kind="通用玻璃钥匙", triangles=manifest["baseTriangles"]))
    if not args.study and (len(manifest["providers"]) != 61 or len(records) != 67):
        raise ValueError("The full review must include every 61 brand and all six key colors")
    for directory in (output, output / "images", output / "thumbnails", output / "overview"):
        directory.mkdir(parents=True, exist_ok=True)
    for record in records:
        source = art / "previews/individual" / f'{record["id"]}.png'
        with Image.open(source) as image:
            if min(image.size) < 1024:
                raise ValueError(f"Review image below 1024 pixels: {source.name}")
            record["width"], record["height"] = image.size
            thumb = image.convert("RGB")
            thumb.thumbnail((640, 640), Image.Resampling.LANCZOS)
            thumb.save(output / "thumbnails" / f'{record["id"]}.jpg', quality=93)
        shutil.copy2(source, output / "images" / source.name)

    pages = []
    title_font, label_font, detail_font = font(44), font(26), font(20)
    for start in range(0, len(records), 12):
        page = start // 12 + 1
        entries = records[start:start + 12]
        canvas = Image.new("RGB", (2288, 2000), "#f5f7fb")
        draw = ImageDraw.Draw(canvas)
        draw.text((64, 34), "KEYNEST · 精修挂件 / Refined charms", font=title_font, fill="#203044")
        draw.text((66, 104), f"Blender 离线预览 · 第 {page} 页 · 点击图库中的单项查看 1536 px 原图", font=detail_font, fill="#63738a")
        for index, record in enumerate(entries):
            x, y = 64 + (index % 4) * 540, 165 + (index // 4) * 590
            draw.rounded_rectangle((x, y, x + 516, y + 565), radius=24, fill="white", outline="#e0e5ee", width=2)
            with Image.open(output / "images" / f'{record["id"]}.png') as source:
                image = source.convert("RGB").resize((496, 496), Image.Resampling.LANCZOS)
                canvas.paste(image, (x + 10, y + 10))
            name = record["name"]
            label_size = 26
            while draw.textlength(name, font=font(label_size)) > 484 and label_size > 18:
                label_size -= 1
            draw.text((x + 17, y + 511), name, font=font(label_size), fill="#23344a")
            draw.text((x + 17, y + 544), record["id"], font=font(15), fill="#718096")
        draw.text((66, 1942), "真实导出网格与 Blender 材质的静态渲染；App 实时光照与玻璃表现分别验证。", font=detail_font, fill="#63738a")
        filename = f"overview-{page:02d}.jpg"
        canvas.save(output / "overview" / filename, quality=95)
        pages.append(filename)

    cards = []
    for record in records:
        identifier, name = record["id"], escape(record["name"])
        cards.append(f'''<article class="card" data-search="{escape((record["name"] + ' ' + identifier).lower(), quote=True)}">
<a href="images/{identifier}.png" target="_blank" rel="noopener"><img src="thumbnails/{identifier}.jpg" width="640" height="640" loading="lazy" alt="{name}"></a>
<div class="caption"><h2>{name}</h2><p>{record["kind"]} · {record["triangles"]:,} triangles</p><a href="images/{identifier}.png" target="_blank" rel="noopener">查看 {record["width"]} × {record["height"]} 原图 ↗</a></div></article>''')
    overview_links = "".join(f'<a href="overview/{page}" target="_blank" rel="noopener">第 {index + 1} 页 ↗</a>' for index, page in enumerate(pages))
    html = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Keynest · 挂件高清检查图库</title><style>
*{box-sizing:border-box}body{margin:0;background:#f5f7fb;color:#203044;font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{max-width:1480px;margin:auto;padding:48px 28px}h1{font-size:34px;line-height:1.25;margin:8px 0 16px;letter-spacing:-.7px}header{max-width:900px;margin-bottom:30px}.eyebrow{font-size:12px;letter-spacing:2px;color:#77879d}p{color:#65758a}a{color:#25669f;text-decoration:none}a:hover{text-decoration:underline}.overview{display:flex;gap:10px;flex-wrap:wrap;margin:18px 0}.overview a{padding:8px 14px;background:white;border:1px solid #dce3ed;border-radius:10px}input{border:1px solid #ccd7e5;border-radius:12px;padding:12px 15px;background:white;max-width:400px;width:100%;font:inherit}input:focus{outline:3px solid #b9dbff;outline-offset:2px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:22px}.card{background:white;border:1px solid #e0e6ef;border-radius:20px;overflow:hidden}.card img{display:block;width:100%;height:auto}.caption{padding:4px 18px 20px}.caption h2{font-size:17px;margin:8px 0 4px}.caption p{font-size:12px;margin:0 0 12px}footer{margin-top:32px;color:#718096;font-size:13px}.card[hidden]{display:none}</style>
<main><header><div class="eyebrow">KEYNEST / LOCAL DESIGN REVIEW</div><h1>挂件高清检查图库</h1>
<p>__COUNT__ 张新版独立图片：品牌保持自己的轮廓与镂空，通用钥匙提供六种颜色。点击任一图片可查看高清原图。此页面与所有图片均在本地，无外部字体、图片或请求。</p>
<p><strong>这是 Blender 离线材质与灯光预览，不是 App 实时效果截图。</strong>图片对应此次重新导出的模型；App 使用相同网格，实时光照、珐琅和玻璃材质另行匹配。</p>
<div class="overview">__OVERVIEWS__</div><input id="search" type="search" placeholder="搜索品牌或颜色名称" aria-label="搜索品牌或颜色名称"></header>
<section class="grid">__CARDS__</section><footer>品牌轮廓的来源和许可继承 ProviderIcons 中的记录；玻璃钥匙、金属连接件与本地制作流水线为 Keynest 原创。旧版预览未混入本图库。</footer></main>
<script>const input=document.getElementById('search');input.addEventListener('input',()=>{const q=input.value.trim().toLowerCase();document.querySelectorAll('.card').forEach(card=>{card.hidden=!card.dataset.search.includes(q)})});</script></html>'''
    html = html.replace("__COUNT__", str(len(records))).replace("__OVERVIEWS__", overview_links).replace("__CARDS__", "\n".join(cards))
    (output / "index.html").write_text(html)
    (output / "catalog.json").write_text(json.dumps({"artRevision": manifest.get("artRevision"), "images": records, "overviewPages": pages}, ensure_ascii=False, indent=2) + "\n")
    # The review archive travels independently of the source repository, so
    # include the upstream license/provenance records for derivative marks.
    attribution = output / "attribution"
    attribution.mkdir(exist_ok=True)
    icons = MACOS / "Resources/ProviderIcons"
    for name in ("LICENSE", "LICENSE-LOBEHUB-0.7.txt", "LICENSE-SIMPLEICONS.md",
                 "LICENSE-VENDOR-ASSETS.md", "SOURCES.md", "SOURCES-0.7.md"):
        shutil.copy2(icons / name, attribution / name)
    shutil.copy2(art / "manifest.json", output / "mesh-manifest.json")
    (attribution / "README.txt").write_text(
        "Keynest local artwork review / 品牌来源与许可\n\n"
        "The generic glass key, suspension hardware, modeling code and studio are original Keynest work.\n"
        "Brand contours are derived from the provider artwork identified in SOURCES.md and SOURCES-0.7.md.\n"
        "Their upstream licenses and trademark rights still apply. Vendor assets are not represented as open-source artwork.\n"
        "Display does not imply endorsement. No user data is included.\n\n"
        "通用玻璃钥匙、金属连接件与建模流水线为 Keynest 原创；品牌轮廓属于原品牌图稿的衍生制作，\n"
        "继续适用此目录记录的上游许可和商标权，不代表品牌方背书。\n")
    html = html.replace("品牌轮廓的来源和许可继承 ProviderIcons 中的记录", '<a href="attribution/README.txt">品牌轮廓的来源和许可记录</a>')
    (output / "index.html").write_text(html)
    if args.zip:
        archive = shutil.make_archive(str(output), "zip", root_dir=output.parent, base_dir=output.name)
        archive_path = Path(archive)
        digest = hashlib.sha256()
        with archive_path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        archive_path.with_suffix(".zip.sha256").write_text(f"{digest.hexdigest()}  {archive_path.name}\n")
        print(f"KEYNEST_GALLERY_ARCHIVE {archive}")
    print(f"KEYNEST_GALLERY_READY {output / 'index.html'} images={len(records)} pages={len(pages)}")


if __name__ == "__main__":
    main()
