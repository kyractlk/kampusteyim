# -*- coding: utf-8 -*-
"""GAÜN Rektörlüğü için ürün odaklı KampüsteyimAPP sunumu."""
from __future__ import annotations

import shutil
from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN
from pptx.util import Inches

from build_pptx import (
    CYAN,
    INK,
    LINE,
    MUTED,
    NAVY,
    NAVY2,
    NAVY3,
    SOFT,
    TEAL,
    WHITE,
    add_multiline,
    add_shot,
    add_textbox,
    bullet_block,
    footer_bar,
    header_bar,
    matrix_2x2,
    process_row,
    rounded_rect,
    section_title,
    stack_layers,
)

HERE = Path(__file__).resolve().parent
SHOTS = HERE / "shots"
OUT = HERE / "KampusteyimAPP_GAUN_Urun_Odakli_Sunum.pptx"
TOTAL = 9


def new_deck():
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)
    return prs, prs.slide_layouts[6]


def dark_background(slide, prs):
    bg = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE, 0, 0, prs.slide_width, prs.slide_height
    )
    bg.fill.solid()
    bg.fill.fore_color.rgb = NAVY
    bg.line.fill.background()
    glow = slide.shapes.add_shape(
        MSO_SHAPE.OVAL, Inches(9.4), Inches(-1.2), Inches(5.4), Inches(5.4)
    )
    glow.fill.solid()
    glow.fill.fore_color.rgb = NAVY3
    glow.fill.transparency = 18
    glow.line.fill.background()


def add_page_frame(slide, prs, page, kicker, title):
    header_bar(slide, prs, "Gaziantep Üniversitesi Rektörlüğü")
    section_title(slide, kicker, title)
    footer_bar(slide, prs, page, TOTAL)


def add_phone_panel(slide, image_name, left, top, width, height):
    rounded_rect(slide, left, top, width, height, NAVY2)
    inner = Inches(0.12)
    add_shot(
        slide,
        SHOTS / image_name,
        left + inner,
        top + inner,
        width - inner * 2,
        height - inner * 2,
    )


def cover(prs, blank):
    slide = prs.slides.add_slide(blank)
    dark_background(slide, prs)

    logo = SHOTS / "logo_kampus.png"
    if logo.exists():
        slide.shapes.add_picture(str(logo), Inches(0.8), Inches(0.65), width=Inches(1.05))

    add_textbox(
        slide,
        Inches(0.8),
        Inches(2.0),
        Inches(7.3),
        Inches(0.55),
        "KampüsteyimAPP",
        size=38,
        bold=True,
        color=WHITE,
    )
    add_textbox(
        slide,
        Inches(0.8),
        Inches(2.75),
        Inches(7.4),
        Inches(1.25),
        "Kampüsün dijital\nbuluşma noktası",
        size=34,
        bold=True,
        color=CYAN,
    )
    add_textbox(
        slide,
        Inches(0.8),
        Inches(4.25),
        Inches(7.0),
        Inches(0.9),
        "Öğrencileri, resmi toplulukları, etkinlikleri ve kampüs "
        "duyurularını tek bir güvenli deneyimde birleştirir.",
        size=18,
        color=RGBColor(0xD5, 0xE4, 0xEE),
    )
    add_textbox(
        slide,
        Inches(0.8),
        Inches(6.25),
        Inches(6.5),
        Inches(0.35),
        "GAÜN için ürün ve pilot uygulama sunumu",
        size=13,
        bold=True,
        color=CYAN,
    )
    add_phone_panel(
        slide,
        "03_feed.png",
        Inches(9.05),
        Inches(0.65),
        Inches(3.15),
        Inches(6.2),
    )


def vision(prs, blank):
    slide = prs.slides.add_slide(blank)
    add_page_frame(slide, prs, 2, "01 · ÜRÜN VİZYONU", "Tek kampüs, tek dijital deneyim")

    matrix_2x2(
        slide,
        Inches(0.6),
        Inches(1.8),
        Inches(7.25),
        Inches(4.75),
        [
            ("Öğrenci", "Kampüsü keşfeder, paylaşır, etkinliğe katılır ve topluluklarla bağ kurar."),
            ("Topluluk", "Resmi kimliğiyle duyuru, etkinlik, başvuru ve üye iletişimini yönetir."),
            ("Üniversite", "Doğrulanmış kampüs iletişimini görünür, düzenli ve ölçülebilir hale getirir."),
            ("Ekosistem", "Kariyer, sosyal yaşam, kültür ve spor aynı dijital kampüste buluşur."),
        ],
    )
    rounded_rect(slide, Inches(8.15), Inches(1.8), Inches(4.55), Inches(4.75), SOFT, line=LINE)
    add_textbox(
        slide,
        Inches(8.5),
        Inches(2.15),
        Inches(3.9),
        Inches(0.8),
        "Parçalı kampüs iletişiminin yerine",
        size=22,
        bold=True,
        color=NAVY2,
    )
    bullet_block(
        slide,
        Inches(8.5),
        Inches(3.15),
        Inches(3.85),
        [
            "Tek hesap",
            "Tek uygulama",
            "Doğrulanmış kimlikler",
            "Kampüse özel içerik",
            "Yönetilebilir dijital süreçler",
        ],
        size=15,
    )


def student_experience(prs, blank):
    slide = prs.slides.add_slide(blank)
    add_page_frame(slide, prs, 3, "02 · ÖĞRENCİ DENEYİMİ", "Kampüste olan her şey tek akışta")

    add_phone_panel(slide, "03_feed.png", Inches(0.75), Inches(1.7), Inches(3.05), Inches(4.95))
    add_phone_panel(slide, "04_story.png", Inches(4.05), Inches(1.7), Inches(3.05), Inches(4.95))
    add_phone_panel(slide, "05_search.png", Inches(7.35), Inches(1.7), Inches(3.05), Inches(4.95))

    rounded_rect(slide, Inches(10.65), Inches(1.7), Inches(2.0), Inches(4.95), NAVY2)
    add_multiline(
        slide,
        Inches(10.92),
        Inches(2.05),
        Inches(1.48),
        Inches(4.2),
        [
            "Akış",
            "Hikâyeler",
            "Duyurular",
            "Keşfet",
            "Arama",
            "Reels",
            "Kampüs gündemi",
        ],
        size=15,
        bold=True,
        color=WHITE,
        gap_pt=12,
    )


def events(prs, blank):
    slide = prs.slides.add_slide(blank)
    add_page_frame(slide, prs, 4, "03 · ETKİNLİK", "Duyurudan katılıma uçtan uca süreç")

    add_phone_panel(slide, "06_events.png", Inches(0.8), Inches(1.7), Inches(3.25), Inches(4.95))
    process_row(
        slide,
        Inches(4.45),
        Inches(2.0),
        Inches(8.1),
        [
            ("Yayınla", "Etkinlik bilgisi"),
            ("Duyur", "Kampüs erişimi"),
            ("Başvuru", "Kota ve kayıt"),
            ("Katılım", "Kontrollü süreç"),
        ],
    )
    rounded_rect(slide, Inches(4.45), Inches(3.65), Inches(8.1), Inches(2.55), SOFT, line=LINE)
    add_textbox(
        slide,
        Inches(4.8),
        Inches(4.0),
        Inches(7.4),
        Inches(0.4),
        "Topluluk ve üniversite için kazanım",
        size=20,
        bold=True,
        color=NAVY2,
    )
    bullet_block(
        slide,
        Inches(4.8),
        Inches(4.6),
        Inches(7.2),
        [
            "Dağınık form ve mesaj trafiğinin azalması",
            "Başvuru, kontenjan ve son tarih bilgisinin tek yerde olması",
            "Öğrencinin etkinlikleri kolayca keşfetmesi ve paylaşması",
        ],
        size=15,
    )


def communities(prs, blank):
    slide = prs.slides.add_slide(blank)
    add_page_frame(slide, prs, 5, "04 · TOPLULUKLAR", "Resmi toplulukların dijital merkezi")

    cards = [
        ("Doğrulanmış profil", "Topluluğun resmi kimliği, rozeti ve güvenilir iletişim kanalı."),
        ("İçerik yönetimi", "Gönderi, hikâye, duyuru ve etkinlik içeriklerinin tek noktadan yayını."),
        ("Başvuru süreçleri", "Üyelik ve etkinlik başvurularının daha düzenli yürütülmesi."),
        ("Görünürlük", "Yeni öğrencilerin ilgi alanlarına göre toplulukları keşfetmesi."),
        ("Ekip yönetimi", "Yetkilendirilmiş hesaplar ve topluluk yöneticileri için kontrollü erişim."),
        ("Kampüs ağı", "Topluluklar arası iş birliği ve ortak etkinliklerin kolaylaşması."),
    ]
    for i, (title, body) in enumerate(cards):
        col, row = i % 3, i // 3
        x = Inches(0.65 + col * 4.2)
        y = Inches(1.75 + row * 2.35)
        fill = NAVY2 if row == 0 else SOFT
        title_color = CYAN if row == 0 else NAVY2
        body_color = RGBColor(0xD5, 0xE4, 0xEE) if row == 0 else MUTED
        rounded_rect(slide, x, y, Inches(3.85), Inches(2.05), fill, line=None if row == 0 else LINE)
        add_textbox(
            slide, x + Inches(0.25), y + Inches(0.25), Inches(3.35), Inches(0.35),
            title, size=17, bold=True, color=title_color
        )
        add_textbox(
            slide, x + Inches(0.25), y + Inches(0.8), Inches(3.35), Inches(0.85),
            body, size=13, color=body_color
        )


def more_than_social(prs, blank):
    slide = prs.slides.add_slide(blank)
    add_page_frame(slide, prs, 6, "05 · TEK UYGULAMA", "Sosyal ağdan daha fazlası")

    add_phone_panel(slide, "07_profile.png", Inches(0.8), Inches(1.7), Inches(3.1), Inches(4.95))
    stack_layers(
        slide,
        Inches(4.35),
        Inches(1.85),
        Inches(8.15),
        [
            ("Sosyal kampüs", "Akış · hikâye · reels · mesajlaşma", NAVY2),
            ("Etkinlik merkezi", "Duyuru · başvuru · kota · bilet", TEAL),
            ("Kariyer araçları", "Staj-AI · CV-AI · firma fırsatları", NAVY3),
            ("Topluluk yönetimi", "Resmi profil · ekip · üye · etkinlik", RGBColor(0x17, 0x8A, 0x84)),
            ("Kişisel deneyim", "Çalışma odası · bildirim · gizlilik", NAVY2),
            ("Kurumsal katman", "Moderasyon · raporlama · yetkilendirme", TEAL),
        ],
    )


def governance(prs, blank):
    slide = prs.slides.add_slide(blank)
    add_page_frame(slide, prs, 7, "06 · SKS VE YÖNETİM", "Daha dinamik ve ölçülebilir kampüs süreçleri")

    rounded_rect(slide, Inches(0.7), Inches(1.8), Inches(5.8), Inches(4.65), NAVY2)
    add_textbox(
        slide, Inches(1.05), Inches(2.15), Inches(5.1), Inches(0.45),
        "KampüsteyimAPP katmanı", size=22, bold=True, color=CYAN
    )
    bullet_block(
        slide,
        Inches(1.05),
        Inches(2.9),
        Inches(5.0),
        [
            "Topluluk ve etkinlik görünürlüğü",
            "Başvuru ve kontenjan süreçleri",
            "Kültür–spor faaliyetlerinin dijital erişimi",
            "Öğrenci geri bildirimi ve duyurular",
            "Yetkilendirilmiş yönetim panelleri",
        ],
        size=15,
    )
    rounded_rect(slide, Inches(6.8), Inches(1.8), Inches(5.8), Inches(4.65), SOFT, line=LINE)
    add_textbox(
        slide, Inches(7.15), Inches(2.15), Inches(5.1), Inches(0.45),
        "Kurumsal fayda", size=22, bold=True, color=NAVY2
    )
    bullet_block(
        slide,
        Inches(7.15),
        Inches(2.9),
        Inches(5.0),
        [
            "Öğrenciye mobil ve güncel erişim",
            "Daha düzenli operasyon ve daha az parçalı iletişim",
            "Ölçülebilir katılım verileri",
            "Üniversite markasına uygun resmi dijital kanal",
            "Mevcut süreçlerle aşamalı entegrasyon olanağı",
        ],
        size=15,
    )


def trust(prs, blank):
    slide = prs.slides.add_slide(blank)
    add_page_frame(slide, prs, 8, "07 · GÜVEN VE SÜRDÜRÜLEBİLİRLİK", "Kurumsal kullanıma uygun yapı")

    matrix_2x2(
        slide,
        Inches(0.7),
        Inches(1.8),
        Inches(7.35),
        Inches(4.7),
        [
            ("Doğrulama", "Öğrenci, topluluk, firma ve resmi hesapları ayıran görünür kimlik katmanı."),
            ("Moderasyon", "Şikâyet, engelleme, içerik denetimi ve yönetim araçları."),
            ("Gizlilik", "Hesap görünürlüğü, iletişim ve bildirim tercihlerinin kullanıcı kontrolünde olması."),
            ("Yetkilendirme", "Yönetim işlevlerinin rol ve izin temelli kontrollü kullanımı."),
        ],
    )
    rounded_rect(slide, Inches(8.35), Inches(1.8), Inches(4.25), Inches(4.7), NAVY2)
    add_textbox(
        slide, Inches(8.75), Inches(2.15), Inches(3.45), Inches(0.75),
        "GAÜN’e özel kontrollü pilot", size=22, bold=True, color=CYAN
    )
    add_multiline(
        slide,
        Inches(8.75),
        Inches(3.2),
        Inches(3.35),
        Inches(2.6),
        [
            "1  Kapsamı belirle",
            "2  Toplulukları doğrula",
            "3  Pilot kullanımı başlat",
            "4  Geri bildirim topla",
            "5  Üniversite geneline yaygınlaştır",
        ],
        size=15,
        bold=True,
        color=WHITE,
        gap_pt=11,
    )


def close(prs, blank):
    slide = prs.slides.add_slide(blank)
    dark_background(slide, prs)
    add_textbox(
        slide,
        Inches(0.8),
        Inches(1.25),
        Inches(10.8),
        Inches(0.5),
        "KampüsteyimAPP",
        size=22,
        bold=True,
        color=CYAN,
    )
    add_textbox(
        slide,
        Inches(0.8),
        Inches(2.15),
        Inches(11.4),
        Inches(1.65),
        "GAÜN’den Türkiye’ye\nörnek bir dijital kampüs modeli",
        size=38,
        bold=True,
        color=WHITE,
    )
    add_textbox(
        slide,
        Inches(0.8),
        Inches(4.25),
        Inches(9.5),
        Inches(0.8),
        "Öğrenci deneyimi · Resmi topluluklar · Etkinlik yönetimi · "
        "SKS süreçleri · Güvenli kampüs iletişimi",
        size=18,
        color=RGBColor(0xD5, 0xE4, 0xEE),
    )
    rounded_rect(slide, Inches(0.8), Inches(5.55), Inches(4.5), Inches(0.72), TEAL)
    add_textbox(
        slide,
        Inches(1.0),
        Inches(5.75),
        Inches(4.1),
        Inches(0.32),
        "kampusteyim.app  ·  app.kampusteyim.app",
        size=13,
        bold=True,
        color=WHITE,
        align=PP_ALIGN.CENTER,
    )


def main():
    prs, blank = new_deck()
    cover(prs, blank)
    vision(prs, blank)
    student_experience(prs, blank)
    events(prs, blank)
    communities(prs, blank)
    more_than_social(prs, blank)
    governance(prs, blank)
    trust(prs, blank)
    close(prs, blank)
    prs.save(OUT)
    root_copy = HERE.parents[1] / OUT.name
    shutil.copy2(OUT, root_copy)
    print(f"OK: {OUT}")
    print(f"COPY: {root_copy}")


if __name__ == "__main__":
    main()
