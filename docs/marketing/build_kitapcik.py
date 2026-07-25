# -*- coding: utf-8 -*-
"""KampüsteyimAPP kurumsal tanıtım kitapçığı — yeniden tasarım."""
from __future__ import annotations

from pathlib import Path

from PIL import Image as PILImage
from reportlab.lib.colors import HexColor, white
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Flowable,
    Image,
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "KampusteyimAPP_Kurumsal_Tanitim.pdf"
SHOTS = Path(__file__).resolve().parent / "shots"
ASSETS = Path(
    r"C:\Users\alika\.cursor\projects\c-Users-alika-OneDrive-Belgeler-KYRCODE-ayskampus\assets"
)
BRAND = ROOT / "assets" / "brand"
LOGOS = ROOT / "assets" / "logos"
FONTS = ROOT / "assets" / "fonts"

INSTAGRAM = "@kampusteyimapp"
INSTAGRAM_URL = "instagram.com/kampusteyimapp"

NAVY = HexColor("#071824")
NAVY2 = HexColor("#0B1F33")
TEAL = HexColor("#1FA6A0")
CYAN = HexColor("#2EC4B6")
SOFT = HexColor("#EEF5F8")
SOFT2 = HexColor("#E4F0F4")
MUTED = HexColor("#5A6A7A")
INK = HexColor("#1A2B3A")
LINE = HexColor("#C9D8E2")
GOLD = HexColor("#C9A227")

PAGE_W, PAGE_H = A4


def _long_path(p: Path) -> Path:
    s = str(p.resolve())
    if not s.startswith("\\\\?\\") and len(s) > 240:
        return Path("\\\\?\\" + s)
    return p


def prepare_shots() -> None:
    SHOTS.mkdir(parents=True, exist_ok=True)
    mapping = {
        "mgiris-43e4": "01_login.png",
        "mgirissayfa-dc31": "02_login_form.png",
        "ana1-50588": "03_feed.png",
        "ana1hikaye1-d939": "04_story.png",
        "ana1hikaye1ara-942": "05_search.png",
        "aratestetkinlik-11df": "06_events.png",
        "aratestetkinlikprofil-dea": "07_profile.png",
    }
    for f in ASSETS.glob("*.png"):
        for key, out in mapping.items():
            if key in f.name:
                (SHOTS / out).write_bytes(_long_path(f).read_bytes())


def register_fonts() -> None:
    pdfmetrics.registerFont(TTFont("Noto", str(FONTS / "NotoSans-Regular.ttf")))
    pdfmetrics.registerFont(TTFont("NotoBold", str(FONTS / "NotoSans-Bold.ttf")))


def logo_file(
    src: Path,
    dest_name: str,
    size: int = 512,
    bg: tuple[int, int, int] | None = (255, 255, 255),
) -> Path:
    """Logo’yu kare, keskin ve PDF-dostu PNG olarak hazırlar."""
    dest = SHOTS / dest_name
    im = PILImage.open(src).convert("RGBA")
    # kenar boşluğunu kırp
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    # kare canvas
    side = max(im.size)
    canvas = PILImage.new("RGBA", (side, side), (0, 0, 0, 0))
    ox = (side - im.size[0]) // 2
    oy = (side - im.size[1]) // 2
    canvas.paste(im, (ox, oy), im)
    canvas = canvas.resize((size, size), PILImage.Resampling.LANCZOS)
    if bg is None:
        canvas.save(dest, format="PNG")
    else:
        out = PILImage.new("RGB", (size, size), bg)
        out.paste(canvas, mask=canvas.split()[-1])
        out.save(dest, format="PNG")
    return dest


def fixed_logo(path: Path, size_mm: float) -> Image:
    s = size_mm * mm
    img = Image(str(path), width=s, height=s)
    img.hAlign = "CENTER"
    return img


def phone(path: Path, max_w=76 * mm, max_h=138 * mm) -> Image:
    im = PILImage.open(path)
    w, h = im.size
    scale = min(max_w / w, max_h / h)
    img = Image(str(path), width=w * scale, height=h * scale)
    img.hAlign = "CENTER"
    return img


class AccentBar(Flowable):
    def __init__(self, width=40 * mm, height=2.2, color=TEAL):
        super().__init__()
        self.width = width
        self.height = height
        self.color = color

    def draw(self):
        self.canv.setFillColor(self.color)
        self.canv.roundRect(0, 0, self.width, self.height, 1, fill=1, stroke=0)


class QuoteBand(Flowable):
    """Tam genişlik vurgu bandı."""

    def __init__(self, text: str, width: float):
        super().__init__()
        self.text = text
        self.band_w = width
        self.band_h = 22 * mm

    def wrap(self, availWidth, availHeight):
        return self.band_w, self.band_h

    def draw(self):
        c = self.canv
        c.setFillColor(SOFT2)
        c.roundRect(0, 0, self.band_w, self.band_h, 6, fill=1, stroke=0)
        c.setFillColor(TEAL)
        c.rect(0, 0, 3.5, self.band_h, fill=1, stroke=0)
        c.setFillColor(INK)
        c.setFont("Noto", 9.5)
        # basit satır kırımı
        words = self.text.split()
        lines, cur = [], ""
        max_chars = 78
        for w in words:
            trial = (cur + " " + w).strip()
            if len(trial) > max_chars:
                lines.append(cur)
                cur = w
            else:
                cur = trial
        if cur:
            lines.append(cur)
        y = self.band_h - 8 * mm
        for line in lines[:3]:
            c.drawString(10, y, line)
            y -= 5 * mm


class EcosystemDiagram(Flowable):
    """Üç aktör → merkez platform şeması."""

    def __init__(self, width: float):
        super().__init__()
        self.w = width
        self.h = 72 * mm

    def wrap(self, availWidth, availHeight):
        return self.w, self.h

    def _box(self, c, x, y, bw, bh, fill, title, sub, title_color=white):
        c.setFillColor(fill)
        c.roundRect(x, y, bw, bh, 5, fill=1, stroke=0)
        c.setFillColor(title_color)
        c.setFont("NotoBold", 9)
        c.drawCentredString(x + bw / 2, y + bh - 11, title)
        c.setFont("Noto", 7.2)
        c.setFillColor(HexColor("#D7E6EF") if title_color == white else MUTED)
        for i, line in enumerate(sub[:3]):
            c.drawCentredString(x + bw / 2, y + bh - 22 - i * 10, line)

    def _arrow(self, c, x1, y1, x2, y2):
        c.setStrokeColor(TEAL)
        c.setLineWidth(1.4)
        c.line(x1, y1, x2, y2)

    def draw(self):
        c = self.canv
        bw, bh = 48 * mm, 28 * mm
        cx = self.w / 2
        # merkez
        self._box(
            c,
            cx - 30 * mm,
            22 * mm,
            60 * mm,
            30 * mm,
            NAVY2,
            "KampüsteyimAPP",
            ["Doğrulama · Akış · Kariyer", "Etkinlik · Guard · Plus"],
        )
        # üst üç aktör
        actors = [
            (4 * mm, "Öğrenci", ["Sosyal · CV-AI", "Başvuru · Odak"]),
            (cx - bw / 2, "Firma", ["İşveren markası", "Staj-AI · İlan"]),
            (self.w - bw - 4 * mm, "Topluluk", ["Resmi kimlik", "Etkinlik · Duyuru"]),
        ]
        for x, title, sub in actors:
            self._box(c, x, self.h - bh - 2 * mm, bw, bh, HexColor("#12324A"), title, sub)
            self._arrow(c, x + bw / 2, self.h - bh - 2 * mm, cx, 52 * mm)
        c.setFillColor(MUTED)
        c.setFont("Noto", 7.5)
        c.drawCentredString(cx, 6 * mm, "Tek kampüs ekosistemi · doğrulanmış hesaplar · ölçülebilir etkileşim")


class ProcessFlow(Flowable):
    """Yatay süreç şeridi."""

    def __init__(self, width: float, steps: list[tuple[str, str]]):
        super().__init__()
        self.w = width
        self.steps = steps
        self.h = 34 * mm

    def wrap(self, availWidth, availHeight):
        return self.w, self.h

    def draw(self):
        c = self.canv
        n = len(self.steps)
        gap = 4 * mm
        box_w = (self.w - gap * (n - 1)) / n
        box_h = 24 * mm
        y = 6 * mm
        for i, (title, sub) in enumerate(self.steps):
            x = i * (box_w + gap)
            c.setFillColor(SOFT if i % 2 == 0 else SOFT2)
            c.roundRect(x, y, box_w, box_h, 4, fill=1, stroke=0)
            c.setFillColor(TEAL)
            c.circle(x + 7, y + box_h - 8, 5, fill=1, stroke=0)
            c.setFillColor(white)
            c.setFont("NotoBold", 7)
            c.drawCentredString(x + 7, y + box_h - 10.5, str(i + 1))
            c.setFillColor(NAVY2)
            c.setFont("NotoBold", 8)
            c.drawString(x + 14, y + box_h - 11, title)
            c.setFillColor(MUTED)
            c.setFont("Noto", 6.8)
            c.drawString(x + 14, y + 8, sub)
            if i < n - 1:
                c.setStrokeColor(TEAL)
                c.setLineWidth(1.2)
                c.line(x + box_w + 0.5 * mm, y + box_h / 2, x + box_w + gap - 0.5 * mm, y + box_h / 2)


class StackDiagram(Flowable):
    """Dikey güven / altyapı katmanları."""

    def __init__(self, width: float, layers: list[tuple[str, str, object]]):
        super().__init__()
        self.w = width
        self.layers = layers
        self.h = 8 * mm + len(layers) * 14 * mm

    def wrap(self, availWidth, availHeight):
        return self.w, self.h

    def draw(self):
        c = self.canv
        y = self.h - 12 * mm
        for title, sub, fill in self.layers:
            c.setFillColor(fill)
            c.roundRect(0, y - 2 * mm, self.w, 12 * mm, 3, fill=1, stroke=0)
            c.setFillColor(white if fill in (NAVY, NAVY2, TEAL) else NAVY2)
            c.setFont("NotoBold", 8.5)
            c.drawString(8, y + 3.5, title)
            c.setFont("Noto", 7)
            c.setFillColor(HexColor("#D5E4EE") if fill in (NAVY, NAVY2, TEAL) else MUTED)
            c.drawRightString(self.w - 8, y + 3.5, sub)
            y -= 14 * mm


class MatrixGrid(Flowable):
    """2x2 kurumsal değer matrisi."""

    def __init__(self, width: float, cells: list[tuple[str, str]]):
        super().__init__()
        self.w = width
        self.cells = cells
        self.h = 58 * mm

    def wrap(self, availWidth, availHeight):
        return self.w, self.h

    def draw(self):
        c = self.canv
        gap = 3 * mm
        cw = (self.w - gap) / 2
        ch = (self.h - gap) / 2
        fills = [HexColor("#0E2A40"), HexColor("#12324A"), HexColor("#0F3A3A"), HexColor("#1A3348")]
        for i, (title, body) in enumerate(self.cells[:4]):
            col, row = i % 2, i // 2
            x = col * (cw + gap)
            y = self.h - (row + 1) * ch - row * gap
            c.setFillColor(fills[i])
            c.roundRect(x, y, cw, ch, 4, fill=1, stroke=0)
            c.setFillColor(CYAN)
            c.setFont("NotoBold", 8.5)
            c.drawString(x + 6, y + ch - 12, title)
            c.setFillColor(HexColor("#C9DBE8"))
            c.setFont("Noto", 7.2)
            # wrap body
            words = body.split()
            lines, cur = [], ""
            for w in words:
                trial = (cur + " " + w).strip()
                if len(trial) > 36:
                    lines.append(cur)
                    cur = w
                else:
                    cur = trial
            if cur:
                lines.append(cur)
            ty = y + ch - 24
            for line in lines[:4]:
                c.drawString(x + 6, ty, line)
                ty -= 9


class OrgSchema(Flowable):
    """Firma / Topluluk değer şeması — iki kolon kutular."""

    def __init__(self, width: float, left_title: str, left_items: list[str], right_title: str, right_items: list[str]):
        super().__init__()
        self.w = width
        self.left_title = left_title
        self.left_items = left_items
        self.right_title = right_title
        self.right_items = right_items
        self.h = 62 * mm

    def wrap(self, availWidth, availHeight):
        return self.w, self.h

    def _col(self, c, x, title, items, fill):
        col_w = (self.w - 4 * mm) / 2
        c.setFillColor(fill)
        c.roundRect(x, 0, col_w, self.h, 5, fill=1, stroke=0)
        c.setFillColor(CYAN)
        c.setFont("NotoBold", 9)
        c.drawString(x + 7, self.h - 12, title)
        c.setStrokeColor(HexColor("#2A4A62"))
        c.setLineWidth(0.6)
        c.line(x + 7, self.h - 16, x + col_w - 7, self.h - 16)
        c.setFillColor(white)
        c.setFont("Noto", 7.5)
        y = self.h - 28
        for it in items[:6]:
            c.setFillColor(TEAL)
            c.circle(x + 11, y + 2, 1.6, fill=1, stroke=0)
            c.setFillColor(HexColor("#E2EEF5"))
            c.drawString(x + 17, y, it)
            y -= 8.5

    def draw(self):
        c = self.canv
        col_w = (self.w - 4 * mm) / 2
        self._col(c, 0, self.left_title, self.left_items, NAVY2)
        self._col(c, col_w + 4 * mm, self.right_title, self.right_items, HexColor("#0F2F2E"))


def styles():
    return {
        "cover_title": ParagraphStyle(
            "cover_title",
            fontName="NotoBold",
            fontSize=30,
            leading=36,
            textColor=white,
            alignment=TA_CENTER,
        ),
        "cover_sub": ParagraphStyle(
            "cover_sub",
            fontName="Noto",
            fontSize=11.5,
            leading=17,
            textColor=HexColor("#B8E8E3"),
            alignment=TA_CENTER,
        ),
        "cover_tag": ParagraphStyle(
            "cover_tag",
            fontName="NotoBold",
            fontSize=10,
            leading=14,
            textColor=CYAN,
            alignment=TA_CENTER,
        ),
        "h1": ParagraphStyle(
            "h1",
            fontName="NotoBold",
            fontSize=17,
            leading=22,
            textColor=NAVY2,
            spaceAfter=6,
        ),
        "h2": ParagraphStyle(
            "h2",
            fontName="NotoBold",
            fontSize=11.5,
            leading=16,
            textColor=NAVY2,
            spaceBefore=6,
            spaceAfter=3,
        ),
        "body": ParagraphStyle(
            "body",
            fontName="Noto",
            fontSize=9.7,
            leading=14.5,
            textColor=INK,
            alignment=TA_JUSTIFY,
            spaceAfter=5,
        ),
        "bullet": ParagraphStyle(
            "bullet",
            fontName="Noto",
            fontSize=9.2,
            leading=13.5,
            textColor=INK,
        ),
        "caption": ParagraphStyle(
            "caption",
            fontName="Noto",
            fontSize=8,
            leading=10.5,
            textColor=MUTED,
            alignment=TA_CENTER,
            spaceBefore=2,
            spaceAfter=6,
        ),
        "footer": ParagraphStyle(
            "footer",
            fontName="Noto",
            fontSize=8,
            textColor=MUTED,
            alignment=TA_CENTER,
            leading=11,
        ),
        "sign": ParagraphStyle(
            "sign",
            fontName="NotoBold",
            fontSize=11,
            leading=15,
            textColor=NAVY2,
            alignment=TA_CENTER,
        ),
        "sign_sub": ParagraphStyle(
            "sign_sub",
            fontName="Noto",
            fontSize=8.5,
            leading=12,
            textColor=MUTED,
            alignment=TA_CENTER,
        ),
        "ig": ParagraphStyle(
            "ig",
            fontName="NotoBold",
            fontSize=12,
            leading=16,
            textColor=TEAL,
            alignment=TA_CENTER,
        ),
        "kicker": ParagraphStyle(
            "kicker",
            fontName="NotoBold",
            fontSize=8.5,
            leading=11,
            textColor=TEAL,
            spaceAfter=2,
        ),
    }


def bullets(items: list[str], st) -> ListFlowable:
    return ListFlowable(
        [
            ListItem(Paragraph(i, st["bullet"]), leftIndent=6, bulletColor=TEAL)
            for i in items
        ],
        bulletType="bullet",
        start="•",
        leftIndent=10,
        bulletFontName="NotoBold",
        bulletFontSize=9,
        spaceBefore=2,
        spaceAfter=4,
    )


def feature_card(title: str, body: str, st, width=170 * mm) -> KeepTogether:
    data = [
        [Paragraph(f"<font color='#1FA6A0'>▸</font>  <b>{title}</b>", st["h2"])],
        [Paragraph(body, st["body"])],
    ]
    t = Table(data, colWidths=[width])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), SOFT),
                ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                ("LEFTPADDING", (0, 0), (-1, -1), 11),
                ("RIGHTPADDING", (0, 0), (-1, -1), 11),
                ("TOPPADDING", (0, 0), (0, 0), 8),
                ("BOTTOMPADDING", (0, -1), (-1, -1), 8),
            ]
        )
    )
    return KeepTogether([t, Spacer(1, 5)])


def section_head(num: str, title: str, st) -> KeepTogether:
    return KeepTogether(
        [
            Paragraph(f"BÖLÜM {num}", st["kicker"]),
            Paragraph(title, st["h1"]),
            AccentBar(36 * mm),
            Spacer(1, 4 * mm),
        ]
    )


def shot_with_caption(file: str, caption: str, st, w=80 * mm, h=148 * mm):
    p = SHOTS / file
    if not p.exists():
        return []
    return [phone(p, w, h), Paragraph(caption, st["caption"])]


def draw_cover(canvas, doc):
    c = canvas
    c.saveState()
    c.setFillColor(NAVY)
    c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    # üst teal şerit
    c.setFillColor(TEAL)
    c.rect(0, PAGE_H - 8 * mm, PAGE_W, 8 * mm, fill=1, stroke=0)
    # alt teal şerit
    c.rect(0, 0, PAGE_W, 10 * mm, fill=1, stroke=0)
    # dekoratif dikey accent
    c.setFillColor(CYAN)
    c.rect(12 * mm, 40 * mm, 2.2, PAGE_H - 80 * mm, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Noto", 7.5)
    c.drawCentredString(PAGE_W / 2, 3.5 * mm, f"Instagram  {INSTAGRAM}  ·  {INSTAGRAM_URL}")
    c.restoreState()


def draw_page(canvas, doc):
    c = canvas
    c.saveState()
    # üst bar
    c.setFillColor(NAVY2)
    c.rect(0, PAGE_H - 11 * mm, PAGE_W, 11 * mm, fill=1, stroke=0)
    # logo küçük (kampüs)
    logo = SHOTS / "logo_kampus_header.png"
    if logo.exists():
        c.drawImage(
            str(logo),
            14 * mm,
            PAGE_H - 9.2 * mm,
            width=6.5 * mm,
            height=6.5 * mm,
            mask="auto",
        )
    c.setFillColor(white)
    c.setFont("NotoBold", 8)
    c.drawString(22 * mm, PAGE_H - 7.2 * mm, "KampüsteyimAPP")
    c.setFont("Noto", 7.5)
    c.drawRightString(PAGE_W - 14 * mm, PAGE_H - 7.2 * mm, "Kurumsal Tanıtım")
    # alt bar
    c.setFillColor(TEAL)
    c.rect(0, 0, PAGE_W, 9 * mm, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Noto", 7.2)
    c.drawString(14 * mm, 3.2 * mm, INSTAGRAM)
    c.drawRightString(PAGE_W - 14 * mm, 3.2 * mm, f"Sayfa {doc.page}")
    c.restoreState()


def build() -> Path:
    prepare_shots()
    register_fonts()
    st = styles()

    # Logolar — sadece KampüsteyimAPP + AYS Tech
    logo_kampus = logo_file(
        BRAND / "kampusteyim_icon.png", "logo_kampus.png", size=640, bg=(255, 255, 255)
    )
    logo_kampus_dark = logo_file(
        BRAND / "kampusteyim_icon.png", "logo_kampus_dark.png", size=640, bg=(7, 24, 36)
    )
    logo_file(
        BRAND / "kampusteyim_icon.png", "logo_kampus_header.png", size=128, bg=(11, 31, 51)
    )
    logo_ays = logo_file(LOGOS / "ays_circle.png", "logo_ays.png", size=512, bg=(255, 255, 255))
    logo_ays_dark = logo_file(
        LOGOS / "ays_circle.png", "logo_ays_dark.png", size=512, bg=(7, 24, 36)
    )

    doc = SimpleDocTemplate(
        str(OUT),
        pagesize=A4,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=16 * mm,
        bottomMargin=14 * mm,
        title="KampüsteyimAPP — Kurumsal Tanıtım",
        author="Kayra Çatalkaya · AYS Tech",
    )

    story: list = []
    content_w = PAGE_W - 32 * mm

    # ══════════ KAPAK ══════════
    story.append(Spacer(1, 18 * mm))
    story.append(fixed_logo(logo_kampus_dark, 32))
    story.append(Spacer(1, 6 * mm))
    story.append(Paragraph("KampüsteyimAPP", st["cover_title"]))
    story.append(Spacer(1, 2 * mm))
    story.append(Paragraph("Kampüsün kurumsal dijital ekosistemi", st["cover_sub"]))
    story.append(Spacer(1, 8 * mm))
    story.append(Paragraph("FİRMALAR  ·  RESMİ ÜNİVERSİTE TOPLULUKLARI", st["cover_tag"]))
    story.append(Spacer(1, 4 * mm))
    story.append(
        Paragraph(
            "Ekosistem şeması · operasyon süreçleri · kariyer hunisi<br/>"
            "Güvenli, doğrulanmış ve kampüse özel kurumsal sunum",
            st["cover_sub"],
        )
    )
    story.append(Spacer(1, 14 * mm))
    # ikili logo satırı: Kampüsteyim + AYS
    pair = Table(
        [
            [
                fixed_logo(logo_kampus_dark, 18),
                fixed_logo(logo_ays_dark, 18),
            ]
        ],
        colWidths=[40 * mm, 40 * mm],
        hAlign="CENTER",
    )
    pair.setStyle(
        TableStyle(
            [
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ]
        )
    )
    story.append(pair)
    story.append(Spacer(1, 3 * mm))
    story.append(
        Paragraph(
            "KampüsteyimAPP  ·  Altyapı: AYS Tech",
            st["cover_sub"],
        )
    )
    story.append(Spacer(1, 16 * mm))
    story.append(Paragraph(f"Instagram  {INSTAGRAM}", st["cover_tag"]))
    story.append(Paragraph(INSTAGRAM_URL, st["cover_sub"]))
    story.append(Spacer(1, 12 * mm))
    story.append(Paragraph("Hazırlayan: Kayra Çatalkaya  ·  AYS Tech", st["cover_sub"]))
    story.append(Paragraph("Temmuz 2026", st["cover_sub"]))
    story.append(PageBreak())

    # ══════════ 1 ══════════
    story.append(section_head("01", "Kampüs ekosistemi", st))
    story.append(
        Paragraph(
            "KampüsteyimAPP; öğrenci, firma ve resmi üniversite topluluklarını tek doğrulanmış "
            "dijital çatı altında birleştirir. Amaç dağınık kanallar değil — ölçülebilir, güvenli "
            "ve kampüse özel bir etkileşim ağıdır.",
            st["body"],
        )
    )
    story.append(Spacer(1, 3 * mm))
    story.append(EcosystemDiagram(content_w))
    story.append(Spacer(1, 4 * mm))
    story.append(Paragraph("Kurumsal değer alanları", st["h2"]))
    story.append(
        MatrixGrid(
            content_w,
            [
                ("Güven", "Altın / mavi / yeşil rozetler ve AYS Tech Guard ile itibar katmanı."),
                ("Erişim", "Doğrudan öğrenci kitlesi — dağınık sosyal kanallar yerine tek kampüs."),
                ("Operasyon", "Etkinlik, duyuru, kota ve başvuru tek panelde yönetilir."),
                ("Kariyer", "CV-AI + Staj-AI ile işveren–aday köprüsü hızlanır."),
            ],
        )
    )
    story.append(PageBreak())

    # ══════════ 1b — süreç ══════════
    story.append(section_head("02", "Kurumsal katılım süreci", st))
    story.append(
        Paragraph(
            "Firma veya resmi topluluk hesabı, onay sonrası kampüste görünür hale gelir. "
            "Aşağıdaki şema tipik aktivasyon yolunu özetler:",
            st["body"],
        )
    )
    story.append(Spacer(1, 3 * mm))
    story.append(
        ProcessFlow(
            content_w,
            [
                ("Başvuru", "Resmi hesap talebi"),
                ("Doğrulama", "Kimlik & rozet"),
                ("Yayın", "Akış / etkinlik"),
                ("Ölçüm", "Etkileşim & başvuru"),
            ],
        )
    )
    story.append(Spacer(1, 5 * mm))
    story.append(
        QuoteBand(
            "Bu kitapçık gerçek uygulama ekranlarıyla hazırlandı — teknik döküm değil; "
            "firmaların ve toplulukların kampüste ne kazandığını anlatır.",
            content_w,
        )
    )
    story.append(Spacer(1, 5 * mm))
    story.append(Paragraph("Güven ve altyapı katmanları", st["h2"]))
    story.append(
        StackDiagram(
            content_w,
            [
                ("Deneyim katmanı", "Akış · Hikâye · Reels · Etkinlik", TEAL),
                ("Kariyer katmanı", "CV-AI · Staj-AI · Plus", HexColor("#178A84")),
                ("Kimlik katmanı", "Doğrulama rozetleri · Gizlilik", NAVY2),
                ("Güvenlik katmanı", "AYS Tech Guard · Moderasyon", NAVY),
                ("Altyapı", "AYS Tech · Firebase · Mobil (iOS/Android)", HexColor("#051018")),
            ],
        )
    )
    story.append(PageBreak())

    # ══════════ 3 — giriş (2 kolon) ══════════
    story.append(section_head("03", "Marka deneyimi ve güvenli giriş", st))
    story.append(
        Paragraph(
            "Sade, profesyonel ve kampüs kimliğini yansıtan bir karşılama. "
            "Misafir akışa göz atabilir; kurumsal ve öğrenci hesapları güvenle giriş yapar.",
            st["body"],
        )
    )
    left = shot_with_caption("01_login.png", "Karşılama &amp; marka kimliği", st, 78 * mm, 140 * mm)
    right = shot_with_caption("02_login_form.png", "Kampüs hesabıyla giriş", st, 78 * mm, 140 * mm)
    if left and right:
        t = Table(
            [[left[0], right[0]], [left[1], right[1]]],
            colWidths=[88 * mm, 88 * mm],
            hAlign="CENTER",
        )
        t.setStyle(
            TableStyle(
                [
                    ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("TOPPADDING", (0, 0), (-1, -1), 2),
                ]
            )
        )
        story.append(t)
    story.append(PageBreak())

    # ══════════ 4 — akış ══════════
    story.append(section_head("04", "Kampüs akışı: görünürlük ve etkileşim", st))
    story.append(
        Paragraph(
            "Akış; firmaların, toplulukların ve öğrencilerin aynı dilde konuştuğu canlı vitrindir. "
            "Resmi hesaplar altın / mavi rozetle, KampüsteyimPlus üyeleri yeşil tick ile öne çıkar.",
            st["body"],
        )
    )
    text_col = [
        Paragraph("Firmalar için", st["h2"]),
        bullets(
            [
                "Marka ve işveren hikâyesini öğrenci dilinde paylaşın.",
                "Staj / kariyer içeriklerini hashtag ile keşfettirin.",
                "Doğrulanmış firma hesabıyla güven inşa edin.",
            ],
            st,
        ),
        Paragraph("Topluluklar için", st["h2"]),
        bullets(
            [
                "Etkinlik heyecanını ve duyuruları akışta canlı tutun.",
                "Altın tick ile resmi topluluk kimliğini gösterin.",
            ],
            st,
        ),
    ]
    shot = shot_with_caption(
        "03_feed.png", "Akış · hikâye halkası · rozetler", st, 70 * mm, 132 * mm
    )
    if shot:
        t = Table(
            [[text_col, [shot[0], shot[1]]]],
            colWidths=[95 * mm, 78 * mm],
        )
        t.setStyle(
            TableStyle(
                [
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("ALIGN", (1, 0), (1, 0), "CENTER"),
                    ("LEFTPADDING", (0, 0), (0, 0), 0),
                    ("RIGHTPADDING", (1, 0), (1, 0), 0),
                ]
            )
        )
        story.append(t)
    story.append(PageBreak())

    # ══════════ 5 — hikâye ══════════
    story.append(section_head("05", "Hikâye: 24 saatlik kampüs nabzı", st))
    story.append(
        Paragraph(
            "Anlık görünürlük için hikâyeler 24 saat sonra otomatik silinir. "
            "Etkinlik countdown’u, staj hatırlatması veya topluluk anları doğal ritimle dolaşır.",
            st["body"],
        )
    )
    story.append(Spacer(1, 2 * mm))
    story.append(
        ProcessFlow(
            content_w,
            [
                ("Çekim", "Kamera / galeri"),
                ("Yayın", "24 saat hikâye"),
                ("İzleme", "Görüntüleyen listesi"),
                ("Etkileşim", "Beğeni kalbi"),
            ],
        )
    )
    story.append(Spacer(1, 4 * mm))
    for f in shot_with_caption("04_story.png", "Hikâye ekle · 24 saat · paylaş", st, 82 * mm, 148 * mm):
        story.append(f)
    story.append(PageBreak())

    # ══════════ 6 — reels ══════════
    story.append(section_head("06", "Reels, medya ve içerik koruması", st))
    story.append(
        Paragraph(
            "Kampüs Reels ile kısa, dikey ve yüksek etkileşimli videolar. "
            "Fotoğraf ve videoda indirme yoktur — içerik korunur. "
            "Dosyalar Plus ile paylaşılır ve karşı tarafta indirilebilir.",
            st["body"],
        )
    )
    story.append(Spacer(1, 3 * mm))
    story.append(
        StackDiagram(
            content_w,
            [
                ("Reels &amp; sosyal medya", "Beğeni · yorum · mention · bildirim", TEAL),
                ("Medya koruması", "Foto / video: izle, indirme yok", NAVY2),
                ("Dosya (Plus)", "PDF / not paylaşımı + indirme", HexColor("#178A84")),
                ("AYS Tech Guard", "Metin · link · medya · dosya denetimi", NAVY),
            ],
        )
    )
    story.append(Spacer(1, 4 * mm))
    story.append(
        QuoteBand(
            "İçerik güvenliği + modern sosyal ritim = markanızın kampüste güvenle yaşaması.",
            content_w,
        )
    )
    story.append(PageBreak())

    # ══════════ 7 — arama ══════════
    story.append(section_head("07", "Keşif: arama, hashtag ve doğrulanmış profiller", st))
    story.append(
        Paragraph(
            "Kişi, @handle ve #gönderi ile kampüsü keşfedin. "
            "Firma, Topluluk, AI Bot ve üniversite etiketleri net ayrılır.",
            st["body"],
        )
    )
    for f in shot_with_caption(
        "05_search.png", "Keşfet · trend hashtag’ler · doğrulanmış profiller", st, 82 * mm, 148 * mm
    ):
        story.append(f)
    story.append(PageBreak())

    # ══════════ 8 — etkinlik ══════════
    story.append(section_head("08", "Etkinlik operasyon şeması", st))
    story.append(
        Paragraph(
            "Görsel, tarih, yer, hedef kitle, son başvuru ve kota tek kartta. "
            "Öğrenci Başvur der; organizatör doluluğu canlı izler.",
            st["body"],
        )
    )
    story.append(Spacer(1, 2 * mm))
    story.append(
        ProcessFlow(
            content_w,
            [
                ("Oluştur", "Kart + kota"),
                ("Duyur", "Akış / hikâye"),
                ("Başvuru", "Öğrenci tıklar"),
                ("Yönet", "Doluluk izle"),
            ],
        )
    )
    story.append(Spacer(1, 3 * mm))
    for f in shot_with_caption(
        "06_events.png", "Etkinlik kartı · resmi topluluk · Başvur", st, 82 * mm, 148 * mm
    ):
        story.append(f)
    story.append(PageBreak())

    # ══════════ 9 — profil / kariyer ══════════
    story.append(section_head("09", "Kariyer hunisi: CV-AI → Staj-AI", st))
    story.append(
        Paragraph(
            "Profil; vitrin, ağ ve kariyer araçlarının buluşma noktasıdır. "
            "CV-AI ATS uyumlu özgeçmiş üretir; Staj-AI ilan ve başvuruyu tek panelde toplar.",
            st["body"],
        )
    )
    story.append(Spacer(1, 2 * mm))
    story.append(
        ProcessFlow(
            content_w,
            [
                ("Profil", "Kimlik + rozet"),
                ("CV-AI", "ATS · dil · tema"),
                ("Staj-AI", "İlan / teklif"),
                ("Eşleşme", "Başvuru hunisi"),
            ],
        )
    )
    story.append(Spacer(1, 3 * mm))
    text_col = [
        Paragraph("Profilde neler var?", st["h2"]),
        bullets(
            [
                "Çalışma odası: senkron sayaç + sohbet.",
                "Plus: yeşil tick, dosya, CV güçleri.",
                "Gizlilik: görünürlük, arama, engelleme.",
            ],
            st,
        ),
    ]
    shot = shot_with_caption("07_profile.png", "Profil · CV-AI · Staj-AI", st, 70 * mm, 132 * mm)
    if shot:
        t = Table([[text_col, [shot[0], shot[1]]]], colWidths=[95 * mm, 78 * mm])
        t.setStyle(
            TableStyle(
                [
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("ALIGN", (1, 0), (1, 0), "CENTER"),
                ]
            )
        )
        story.append(t)
    story.append(PageBreak())

    # ══════════ 10 — firma / topluluk şema ══════════
    story.append(section_head("10", "Firma &amp; topluluk değer şeması", st))
    story.append(
        Paragraph(
            "İki kurumsal aktör aynı platformda farklı operasyonel kazanımlar elde eder. "
            "Aşağıdaki şema yan yana özetler:",
            st["body"],
        )
    )
    story.append(Spacer(1, 3 * mm))
    story.append(
        OrgSchema(
            content_w,
            "Firma",
            [
                "İşveren görünürlüğü",
                "Staj &amp; işe alım hunisi",
                "Etkinlik / kariyer günü",
                "Doğrulanmış itibar",
                "Plus: dosya + yeşil tick",
                "Guard ile güvenli marka alanı",
            ],
            "Resmi Topluluk",
            [
                "Altın tick ile resmi kimlik",
                "Etkinlik: başvuru + kota",
                "Duyuru otoritesi",
                "Üye etkileşimi (hikâye/Reels)",
                "Çalışma odası / ortak odak",
                "Sahte hesaptan net ayrışma",
            ],
        )
    )
    story.append(Spacer(1, 5 * mm))
    story.append(Paragraph("Ortak sonuç", st["h2"]))
    story.append(
        Paragraph(
            "Tek uygulama içinde güvenilir görünürlük, operasyonel hız ve kampüs içi ölçülebilir etkileşim — "
            "dağıtık WhatsApp grupları veya genel sosyal ağlara bağımlılık azalır.",
            st["body"],
        )
    )
    story.append(PageBreak())

    # ══════════ 11 — envanter şematik ══════════
    story.append(section_head("11", "Yetenek haritası", st))
    story.append(
        Paragraph(
            "KampüsteyimAPP yetenekleri dört operasyonel blokta toplanır:",
            st["body"],
        )
    )
    story.append(Spacer(1, 2 * mm))
    story.append(
        MatrixGrid(
            content_w,
            [
                (
                    "Sosyal",
                    "Akış, hikâye, Reels, mention, hashtag, beğeni, yorum, repost.",
                ),
                (
                    "Kurumsal",
                    "Etkinlik, duyuru, rozetler, resmi hesap, keşfet.",
                ),
                (
                    "Kariyer",
                    "CV-AI, Staj-AI, Plus kota/dil/tema, dosya paylaşımı.",
                ),
                (
                    "Güven",
                    "Guard, gizlilik, engelleme, şikâyet, medya koruması.",
                ),
            ],
        )
    )
    story.append(Spacer(1, 4 * mm))
    story.append(
        bullets(
            [
                "Android &amp; iOS mobil uygulama",
                "KampüsteyimPlus: deneme, yeşil tick, admin yönetimi",
                "Çalışma odası: senkron sayaç + sohbet",
                "Bildirimler: beğeni, yorum, takip, hikâye / Reels",
            ],
            st,
        )
    )
    story.append(PageBreak())

    # ══════════ 12 — kapanış ══════════
    story.append(section_head("12", "Birlikte büyüyelim", st))
    story.append(
        Paragraph(
            "KampüsteyimAPP; firmanızın yetenek havuzuna, topluluğunuzun üyelerine ve "
            "kampüsün nabzına aynı anda dokunmanızı sağlar. Resmi rozetler, güvenli içerik, "
            "etkinlik operasyonu ve kariyer araçlarıyla kampüste var olmak tek, modern "
            "ve ölçülebilir bir deneyimdir.",
            st["body"],
        )
    )
    story.append(Spacer(1, 3 * mm))
    story.append(
        ProcessFlow(
            content_w,
            [
                ("Tanışma", "Demo / sunum"),
                ("Aktivasyon", "Resmi hesap"),
                ("Yayın", "İlk içerik"),
                ("Büyüme", "Ölçüm &amp; Plus"),
            ],
        )
    )
    story.append(Spacer(1, 4 * mm))
    story.append(
        QuoteBand(
            f"Bizi Instagram’da takip edin — {INSTAGRAM}  ·  {INSTAGRAM_URL}",
            content_w,
        )
    )
    story.append(Spacer(1, 4 * mm))
    story.append(
        Paragraph(
            "Demo, ortaklık veya resmi hesap aktivasyonu için AYS Tech ile iletişime geçebilirsiniz.",
            st["body"],
        )
    )
    story.append(Spacer(1, 6 * mm))
    story.append(Paragraph(INSTAGRAM, st["ig"]))
    story.append(Paragraph(INSTAGRAM_URL, st["sign_sub"]))
    story.append(Spacer(1, 8 * mm))
    story.append(Paragraph("Saygılarımızla,", st["sign_sub"]))
    story.append(Spacer(1, 6 * mm))

    # imza: logolar güzel boyutlarda
    logos = Table(
        [
            [
                fixed_logo(logo_kampus, 22),
                fixed_logo(logo_ays, 22),
            ]
        ],
        colWidths=[85 * mm, 85 * mm],
        hAlign="CENTER",
    )
    logos.setStyle(
        TableStyle(
            [
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(logos)
    names = Table(
        [
            [
                Paragraph("<b>Kayra Çatalkaya</b><br/>Kurucu / Ürün", st["sign"]),
                Paragraph("<b>AYS Tech</b><br/>Altyapı &amp; Teknoloji Partneri", st["sign"]),
            ]
        ],
        colWidths=[85 * mm, 85 * mm],
    )
    names.setStyle(
        TableStyle(
            [
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("BOX", (0, 0), (0, 0), 0.6, TEAL),
                ("BOX", (1, 0), (1, 0), 0.6, TEAL),
                ("TOPPADDING", (0, 0), (-1, -1), 12),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 12),
                ("BACKGROUND", (0, 0), (-1, -1), SOFT),
            ]
        )
    )
    story.append(names)
    story.append(Spacer(1, 10 * mm))
    story.append(
        Paragraph(
            "© 2026 KampüsteyimAPP · AYS Tech · Tüm hakları saklıdır.<br/>"
            "Pazarlama amaçlıdır · özellikler sürümlerle genişleyebilir · "
            f"Instagram {INSTAGRAM}",
            st["footer"],
        )
    )

    doc.build(story, onFirstPage=draw_cover, onLaterPages=draw_page)
    # kök kopya (kolay erişim)
    root_copy = ROOT / "KampusteyimAPP_Kurumsal_Tanitim.pdf"
    root_copy.write_bytes(OUT.read_bytes())
    return OUT


if __name__ == "__main__":
    path = build()
    print(path)
    print("bytes", path.stat().st_size)
