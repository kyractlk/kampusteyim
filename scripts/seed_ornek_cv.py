# -*- coding: utf-8 -*-
"""Örnek CV: Firestore kaydı + ATS PDF çıktısı."""
from __future__ import annotations

import os
from datetime import datetime

from google.cloud import firestore
from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import HRFlowable, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT_PDF = os.path.join(ROOT, 'docs', 'marketing', 'ornek_cv_ats_kampusteyim.pdf')

font_regular = 'Helvetica'
font_bold = 'Helvetica-Bold'
try:
    pdfmetrics.registerFont(TTFont('ArialTR', r'C:\Windows\Fonts\arial.ttf'))
    pdfmetrics.registerFont(TTFont('ArialTR-Bold', r'C:\Windows\Fonts\arialbd.ttf'))
    font_regular = 'ArialTR'
    font_bold = 'ArialTR-Bold'
except Exception as e:
    print('font_fallback', e)

cv_data = {
    'personal_info': {
        'name': 'Elif Yılmaz',
        'email': 'elif.yilmaz@ornek.kampusteyim.app',
        'phone': '+90 532 000 00 00',
        'address': 'Gaziantep, Türkiye',
        'linkedin': 'linkedin.com/in/elif-yilmaz',
        'github': 'github.com/elifyilmaz',
        'website': '',
        'about': (
            'Gaziantep Üniversitesi Bilgisayar Mühendisliği öğrencisi. '
            'Mobil uygulama geliştirme, kampüs ürünleri ve kullanıcı deneyimine odaklanıyor. '
            'Takım çalışması ve temiz kod pratiklerine önem veriyor.'
        ),
        'motivation_letter': (
            'KampüsteyimAPP ürün ekibinde staj yaparak gerçek kullanıcı etkisi olan '
            'mobil özellikler geliştirmek istiyorum. Flutter ve Firebase ile öğrendiklerimi '
            'kurumsal bir ürün ortamında derinleştirmek ve GAÜN kampüs dijitalleşmesine katkı '
            'sunmak temel motivasyonumdur.'
        ),
        'department': 'Bilgisayar Mühendisliği',
        'class': '3. Sınıf',
        'studentNo': '2021123456',
        'photoUrl': '',
        'headline': 'Bilgisayar Mühendisliği Öğrencisi · Flutter Geliştirici Adayı',
    },
    'education': [
        {
            'id': 'edu1',
            'school': 'Gaziantep Üniversitesi',
            'degree': 'Lisans',
            'field': 'Bilgisayar Mühendisliği',
            'startDate': '2021',
            'endDate': 'Devam',
            'gpa': '3.42',
            'description': 'Mobil sistemler, veri yapıları ve yazılım mühendisliği derslerinde aktif.',
        }
    ],
    'experiences': [
        {
            'id': 'exp1',
            'company': 'Mühendislik Topluluğu',
            'position': 'Yazılım Komitesi Üyesi',
            'startDate': '2024-09',
            'endDate': 'Devam',
            'description': (
                'Etkinlik kayıt ve duyuru süreçlerinde dijital araç desteği verdi.\n'
                'Hackathon organizasyonunda teknik lojistik ve mentör koordinasyonuna katkı sundu.'
            ),
        }
    ],
    'projects': [
        {
            'id': 'prj1',
            'name': 'Kampüs Etkinlik Takip Prototipi',
            'description': 'Flutter ile etkinlik listesi, başvuru ve hatırlatma prototipi geliştirdi.',
            'technologies': 'Flutter, Firebase, Dart',
            'link': '',
        }
    ],
    'skills': [
        {'id': 's1', 'name': 'Flutter', 'level': 'İleri düzey'},
        {'id': 's2', 'name': 'Dart', 'level': 'İleri düzey'},
        {'id': 's3', 'name': 'Firebase', 'level': 'Orta düzey'},
        {'id': 's4', 'name': 'Git', 'level': 'Orta düzey'},
        {'id': 's5', 'name': 'UI/UX', 'level': 'Orta düzey'},
    ],
    'languages': [
        {'id': 'l1', 'language': 'Türkçe', 'level': 'Ana dil'},
        {'id': 'l2', 'language': 'İngilizce', 'level': 'B2'},
    ],
    'raw_notes': '',
}


def write_firestore() -> str:
    db = firestore.Client(project='ayskampuss')
    doc_id = 'ornek_cv_elif_yilmaz'
    db.collection('cvs').document(doc_id).set(
        {
            'user_id': doc_id,
            'stableId': doc_id,
            'cv_data': cv_data,
            'has_cv': True,
            'updated_at': datetime.now().isoformat(),
            'sample': True,
            'label': 'Örnek CV · sunum / demo',
        },
        merge=True,
    )
    return doc_id


def write_pdf() -> str:
    os.makedirs(os.path.dirname(OUT_PDF), exist_ok=True)
    navy = HexColor('#2F4B66')
    accent = HexColor('#3DB8A8')
    ink = HexColor('#243B53')
    muted = HexColor('#6B7C8A')

    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name='Name', fontName=font_bold, fontSize=18, textColor=white, leading=22
        )
    )
    styles.add(
        ParagraphStyle(
            name='Headline',
            fontName=font_regular,
            fontSize=10,
            textColor=HexColor('#D5E4EE'),
            leading=13,
        )
    )
    styles.add(
        ParagraphStyle(
            name='Contact', fontName=font_regular, fontSize=8.5, textColor=white, leading=11
        )
    )
    styles.add(
        ParagraphStyle(
            name='H2',
            fontName=font_bold,
            fontSize=11,
            textColor=navy,
            spaceBefore=10,
            spaceAfter=4,
        )
    )
    styles.add(
        ParagraphStyle(
            name='Body', fontName=font_regular, fontSize=9.5, textColor=ink, leading=13
        )
    )
    styles.add(
        ParagraphStyle(
            name='Meta', fontName=font_regular, fontSize=8.5, textColor=muted, leading=11
        )
    )
    styles.add(
        ParagraphStyle(
            name='CvBullet',
            fontName=font_regular,
            fontSize=9.5,
            textColor=ink,
            leading=12,
            leftIndent=10,
        )
    )

    doc = SimpleDocTemplate(
        OUT_PDF,
        pagesize=A4,
        leftMargin=14 * mm,
        rightMargin=14 * mm,
        topMargin=0,
        bottomMargin=14 * mm,
    )
    story = []
    pi = cv_data['personal_info']

    header = Table(
        [
            [Paragraph(pi['name'], styles['Name'])],
            [Paragraph(pi['headline'], styles['Headline'])],
            [
                Paragraph(
                    f"{pi['email']}  ·  {pi['phone']}  ·  {pi['address']}<br/>"
                    f"{pi['linkedin']}  ·  {pi['github']}",
                    styles['Contact'],
                )
            ],
        ],
        colWidths=[182 * mm],
    )
    header.setStyle(
        TableStyle(
            [
                ('BACKGROUND', (0, 0), (-1, -1), navy),
                ('LEFTPADDING', (0, 0), (-1, -1), 12),
                ('RIGHTPADDING', (0, 0), (-1, -1), 12),
                ('TOPPADDING', (0, 0), (0, 0), 14),
                ('BOTTOMPADDING', (0, -1), (-1, -1), 12),
                ('TOPPADDING', (0, 1), (-1, -1), 2),
            ]
        )
    )
    story.append(header)
    story.append(Spacer(1, 8))

    def section(title: str) -> None:
        story.append(Paragraph(title, styles['H2']))
        story.append(HRFlowable(width='100%', thickness=1.2, color=accent, spaceAfter=6))

    section('Profesyonel Özet')
    story.append(Paragraph(pi['about'], styles['Body']))
    section('Motivasyon Mektubu')
    story.append(Paragraph(pi['motivation_letter'], styles['Body']))
    section('Eğitim')
    for e in cv_data['education']:
        story.append(
            Paragraph(
                f"<b>{e['school']}</b> — {e['degree']}, {e['field']}", styles['Body']
            )
        )
        story.append(
            Paragraph(
                f"{e['startDate']} – {e['endDate']}  ·  GPA {e['gpa']}", styles['Meta']
            )
        )
        story.append(Paragraph(e['description'], styles['Body']))
    section('Deneyim')
    for e in cv_data['experiences']:
        story.append(
            Paragraph(f"<b>{e['position']}</b> · {e['company']}", styles['Body'])
        )
        story.append(Paragraph(f"{e['startDate']} – {e['endDate']}", styles['Meta']))
        for line in e['description'].split('\n'):
            story.append(Paragraph(f'• {line}', styles['CvBullet']))
    section('Projeler')
    for p in cv_data['projects']:
        story.append(Paragraph(f"<b>{p['name']}</b>", styles['Body']))
        story.append(Paragraph(p['description'], styles['Body']))
        story.append(Paragraph(p['technologies'], styles['Meta']))
    section('Temel Yetkinlikler')
    story.append(
        Paragraph(
            ' · '.join(f"{s['name']} ({s['level']})" for s in cv_data['skills']),
            styles['Body'],
        )
    )
    section('Dil Yeterlilikleri')
    story.append(
        Paragraph(
            ' · '.join(f"{l['language']} ({l['level']})" for l in cv_data['languages']),
            styles['Body'],
        )
    )
    story.append(Spacer(1, 16))
    story.append(
        Paragraph(
            'KampüsteyimAPP CV-AI · Örnek ATS çıktısı · Sunum demosu', styles['Meta']
        )
    )
    doc.build(story)
    return OUT_PDF


if __name__ == '__main__':
    try:
        print('firestore_ok', write_firestore())
    except Exception as e:
        print('firestore_err', type(e).__name__, e)
    print('pdf_ok', write_pdf())
