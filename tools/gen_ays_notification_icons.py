from PIL import Image
from pathlib import Path

src = Path('assets/logos/ays_circle.png')
img = Image.open(src).convert('RGBA')
w, h = img.size
pixels = img.load()
out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
op = out.load()
for y in range(h):
    for x in range(w):
        r, g, b, a = pixels[x, y]
        if a < 20:
            continue
        lum = (r + g + b) / 3
        aa = a if lum < 245 else int(a * 0.15)
        if aa < 15:
            continue
        op[x, y] = (255, 255, 255, aa)

bbox = out.getbbox()
if bbox:
    out = out.crop(bbox)

side = max(out.size)
square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
square.paste(out, ((side - out.size[0]) // 2, (side - out.size[1]) // 2))

sizes = {
    'drawable-mdpi': 24,
    'drawable-hdpi': 36,
    'drawable-xhdpi': 48,
    'drawable-xxhdpi': 72,
    'drawable-xxxhdpi': 96,
}
res = Path('android/app/src/main/res')
for folder, px in sizes.items():
    d = res / folder
    d.mkdir(parents=True, exist_ok=True)
    # Status-bar safe white silhouette (Android tints with notification color)
    square.resize((px, px), Image.Resampling.LANCZOS).save(
        d / 'ic_stat_ays.png', optimize=True
    )
    # Full-color AYS mark for OEMs / large icon (exact logo at notification scale)
    img.resize((px, px), Image.Resampling.LANCZOS).save(
        d / 'ic_notification_ays.png', optimize=True
    )
    print('ok', folder, px)

print('done')
