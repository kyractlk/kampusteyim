"""MT Mobil web favicon / PWA icon uretici.

Sorun: navy kare uzerinde kucuk logo sekmesi bulanik gosteryordu.
Cozum: seffaf zemin + logo dairenin kenara kadar dolmasi;
16/32px icin sadece siluet kismini buyuterek okunurluk.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'assets' / 'logos' / 'mt_circle.png'
WEB = ROOT / 'web'
ICONS = WEB / 'icons'


def circular_mask(size: int) -> Image.Image:
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).ellipse((0, 0, size - 1, size - 1), fill=255)
    return m


def prepare_logo(im: Image.Image) -> Image.Image:
    """Alfa bbox ile kirp; daire zaten kare."""
    im = im.convert('RGBA')
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    # Kareye oturt
    side = max(im.size)
    square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    square.paste(im, ((side - im.width) // 2, (side - im.height) // 2), im)
    return square


def crop_mark(im: Image.Image) -> Image.Image:
    """Kucuk favicon: metni at, ustteki 3 silueti buyut."""
    w, h = im.size
    # Logo icerigi yaklasik ust %58 (siluet + cizgi)
    top = int(h * 0.08)
    bottom = int(h * 0.58)
    left = int(w * 0.12)
    right = int(w * 0.88)
    mark = im.crop((left, top, right, bottom))
    # Beyaz daire zeminine ortala
    side = max(mark.size) + 8
    canvas = Image.new('RGBA', (side, side), (255, 255, 255, 255))
    canvas.paste(mark, ((side - mark.width) // 2, (side - mark.height) // 2), mark)
    canvas.putalpha(circular_mask(side))
    return canvas


def fit_circle(im: Image.Image, size: int, pad: float = 0.02) -> Image.Image:
    """Seffaf kare; logo daireyi neredeyse doldurur (navy kare yok)."""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    inner = max(1, int(size * (1 - pad * 2)))
    logo = im.copy()
    if logo.width != logo.height:
        s = max(logo.size)
        sq = Image.new('RGBA', (s, s), (0, 0, 0, 0))
        sq.paste(logo, ((s - logo.width) // 2, (s - logo.height) // 2), logo)
        logo = sq
    logo = logo.resize((inner, inner), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', (inner, inner), (0, 0, 0, 0))
    out.paste(logo, (0, 0), circular_mask(inner))
    x = (size - inner) // 2
    y = (size - inner) // 2
    canvas.paste(out, (x, y), out)
    return canvas


def fit_maskable(im: Image.Image, size: int, safe_pad: float = 0.18) -> Image.Image:
    """PWA maskable: navy zemin + guvenli alan padding."""
    bg = (11, 31, 58, 255)
    canvas = Image.new('RGBA', (size, size), bg)
    inner = max(1, int(size * (1 - safe_pad * 2)))
    logo = im.copy()
    logo.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - logo.width) // 2
    y = (size - logo.height) // 2
    canvas.paste(logo, (x, y), logo)
    return canvas


def main() -> None:
    ICONS.mkdir(exist_ok=True)
    full = prepare_logo(Image.open(SRC))
    mark = crop_mark(full)

    # Sekme faviconlari — seffaf, buyuk daire
    fit_circle(mark, 16, 0.0).save(WEB / 'favicon-16.png', optimize=True)
    fit_circle(mark, 32, 0.0).save(WEB / 'favicon.png', optimize=True)
    fit_circle(full, 48, 0.02).save(WEB / 'favicon-48.png', optimize=True)
    fit_circle(full, 64, 0.02).save(WEB / 'favicon-64.png', optimize=True)

    ico16 = fit_circle(mark, 16, 0.0)
    ico32 = fit_circle(mark, 32, 0.0)
    ico48 = fit_circle(full, 48, 0.02)
    ico16.save(
        WEB / 'favicon.ico',
        format='ICO',
        sizes=[(16, 16), (32, 32), (48, 48)],
        append_images=[ico32, ico48],
    )

    # Boot / PWA
    fit_circle(full, 128, 0.02).save(WEB / 'mt-logo.png', optimize=True)
    fit_circle(full, 180, 0.02).save(ICONS / 'apple-touch-icon.png', optimize=True)
    fit_circle(full, 192, 0.02).save(ICONS / 'Icon-192.png', optimize=True)
    fit_circle(full, 512, 0.02).save(ICONS / 'Icon-512.png', optimize=True)
    fit_maskable(full, 192).save(ICONS / 'Icon-maskable-192.png', optimize=True)
    fit_maskable(full, 512).save(ICONS / 'Icon-maskable-512.png', optimize=True)

    print('OK favicons regenerated (transparent + mark for small sizes)')
    for p in sorted(
        list(WEB.glob('favicon*'))
        + list(WEB.glob('mt-logo*'))
        + list(ICONS.glob('Icon*.png'))
        + list(ICONS.glob('apple*.png'))
    ):
        print(f'  {p.relative_to(ROOT)}  {p.stat().st_size}b')


if __name__ == '__main__':
    main()
