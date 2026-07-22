from PIL import Image, ImageDraw
import os
import shutil
from collections import deque

SRC = r"c:\Users\alika\OneDrive\Belgeler\KYRCODE\ayskampus\assets\logos"
SIZE = 512
PAD = 36


def flood_transparent_bg(img: Image.Image, is_bg) -> Image.Image:
    """Remove background only via flood-fill from edges (keeps inner whites)."""
    img = img.convert("RGBA")
    w, h = img.size
    pixels = img.load()
    visited = [[False] * w for _ in range(h)]
    q = deque()

    def enqueue(x, y):
        if 0 <= x < w and 0 <= y < h and not visited[y][x]:
            r, g, b, a = pixels[x, y]
            if is_bg(r, g, b, a):
                visited[y][x] = True
                q.append((x, y))

    for x in range(w):
        enqueue(x, 0)
        enqueue(x, h - 1)
    for y in range(h):
        enqueue(0, y)
        enqueue(w - 1, y)

    while q:
        x, y = q.popleft()
        r, g, b, a = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            enqueue(nx, ny)
    return img


def remove_near_black(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r < 22 and g < 22 and b < 22:
                pixels[x, y] = (r, g, b, 0)
            elif r < 45 and g < 45 and b < 45:
                brightness = (r + g + b) / 3
                alpha = int(255 * (brightness / 45))
                pixels[x, y] = (r, g, b, max(0, min(255, alpha)))
    return img


def content_bbox(img: Image.Image):
    return img.split()[-1].getbbox()


def to_square_circle(img: Image.Image, size=SIZE, pad=PAD, circle_bg=None) -> Image.Image:
    bbox = content_bbox(img)
    if not bbox:
        raise RuntimeError("empty image after bg remove")
    cropped = img.crop(bbox)
    # square crop centered on content
    cw, ch = cropped.size
    side = max(cw, ch)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(cropped, ((side - cw) // 2, (side - ch) // 2), cropped)

    inner = size - pad * 2
    resized = square.resize((inner, inner), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if circle_bg is not None:
        ImageDraw.Draw(canvas).ellipse((1, 1, size - 2, size - 2), fill=circle_bg)

    ox = (size - inner) // 2
    oy = (size - inner) // 2
    canvas.paste(resized, (ox, oy), resized)

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    r, g, b, a = canvas.split()
    a = Image.composite(a, Image.new("L", (size, size), 0), mask)
    return Image.merge("RGBA", (r, g, b, a))


def main():
    original_dir = os.path.join(SRC, "original")
    os.makedirs(original_dir, exist_ok=True)

    for name in ("mt_logo.png", "gaun_logo.png", "ays_logo.png"):
        src_path = os.path.join(SRC, name)
        bak = os.path.join(original_dir, name)
        if not os.path.exists(bak):
            shutil.copy2(src_path, bak)

    # MT: white outer bg -> transparent, circular crop
    mt = Image.open(os.path.join(original_dir, "mt_logo.png"))
    mt = flood_transparent_bg(
        mt, lambda r, g, b, a: r > 240 and g > 240 and b > 240
    )
    mt = to_square_circle(mt, pad=48, circle_bg=None)
    mt.save(os.path.join(SRC, "mt_logo.png"), "PNG")
    print("OK mt_logo.png")

    # GAUN: only outer white, keep inner white ring
    gaun = Image.open(os.path.join(original_dir, "gaun_logo.png"))
    gaun = flood_transparent_bg(
        gaun, lambda r, g, b, a: r > 240 and g > 240 and b > 240
    )
    gaun = to_square_circle(gaun, pad=8, circle_bg=None)
    gaun.save(os.path.join(SRC, "gaun_logo.png"), "PNG")
    print("OK gaun_logo.png")

    # AYS: black bg gone, navy circle so colors pop
    ays = Image.open(os.path.join(original_dir, "ays_logo.png"))
    ays = remove_near_black(ays)
    ays = to_square_circle(ays, pad=72, circle_bg=(11, 31, 58, 255))
    ays.save(os.path.join(SRC, "ays_logo.png"), "PNG")
    print("OK ays_logo.png")


if __name__ == "__main__":
    main()
