#!/usr/bin/env python3
"""README görsellerini simülatör ekran görüntülerinden üretir: make readme-images

Girdi: build/screens (UI testleri) ve build/readme (simctl ile alınanlar), hepsi demo verisi.
Çıktı: docs/images/ altında kapak, tek tek telefon ekranları ve karanlık mod görseli. Gerekli: pip install pillow
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SCREENS, EXTRA, OUT = ROOT / "build/screens", ROOT / "build/readme", ROOT / "docs/images"
FONT = "/System/Library/Fonts/SFNS.ttf"

GREEN_DARK, GREEN, MINT = (8, 74, 58), (17, 140, 107), (52, 199, 140)
ISLAND = (415, 42, 790, 151)  # iPhone 16 Pro ekranında Dynamic Island (1206×2622)


def font(size, weight="Regular"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def phone(path, width):
    """Ekran görüntüsünü ince çerçeveli, yuvarlak köşeli telefona çevirir (saydam arka plan)."""
    shot = Image.open(path).convert("RGB")
    ImageDraw.Draw(shot).rounded_rectangle(ISLAND, radius=55, fill="black")
    bezel = 34
    w, h = shot.size
    body = Image.new("RGBA", (w + 2 * bezel, h + 2 * bezel), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, *body.size), radius=190, fill=(28, 28, 30, 255))
    ImageDraw.Draw(body).rounded_rectangle((3, 3, body.size[0] - 4, body.size[1] - 4), radius=187,
                                           outline=(70, 70, 74, 255), width=3)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *shot.size), radius=160, fill=255)
    body.paste(shot, (bezel, bezel), mask)
    scale = width / body.size[0]
    return body.resize((width, round(body.size[1] * scale)), Image.LANCZOS)


def with_shadow(canvas, item, xy, blur=40, offset=24, alpha=110):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    silhouette = Image.new("RGBA", item.size, (0, 0, 0, alpha))
    shadow.paste(silhouette, (xy[0], xy[1] + offset), item)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(item, xy)


def gradient(size, top, bottom):
    w, h = size
    base = Image.new("RGBA", size)
    draw = ImageDraw.Draw(base)
    for y in range(h):
        t = y / max(h - 1, 1)
        draw.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    return base


def banner():
    W, H = 2400, 1260
    canvas = gradient((W, H), GREEN_DARK, GREEN)
    # Hafif ışık halkası
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((1300, -500, 2900, 1100), fill=MINT + (90,))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(160)))

    draw = ImageDraw.Draw(canvas)
    draw.text((140, 300), "Economix", font=font(150, "Bold"), fill="white")
    draw.text((146, 480), "Kişisel gelir-gider, taksit ve\nabonelik takibi — iPhone için",
              font=font(54, "Medium"), fill=(220, 245, 236), spacing=18)
    bullets = ["Ekstre içe aktarma: Garanti · Yapı Kredi · Akbank",
               "Taksit planları ve kart hesap kesimi",
               "Bütçeler, bildirimler ve tasarruf önerileri",
               "iCloud senkronu · Gemini ile analiz"]
    for i, text in enumerate(bullets):
        y = 700 + i * 78
        draw.ellipse((150, y + 16, 172, y + 38), fill=MINT)
        draw.text((196, y), text, font=font(40), fill="white")

    side, center = phone(EXTRA / "raporlar.png", 440), phone(SCREENS / "01-ozet.png", 520)
    right = phone(SCREENS / "09-taksitler-liste.png", 440)
    with_shadow(canvas, side, (1230, 270))
    with_shadow(canvas, right, (1920, 270))
    with_shadow(canvas, center, (1560, 130), blur=50, offset=30, alpha=140)
    return canvas


def gallery(items, columns, phone_width=420, gap=60, title_size=34, background=(255, 255, 255, 0),
            label_color=(60, 60, 67)):
    phones = [(label, phone(path, phone_width)) for label, path in items]
    rows = (len(phones) + columns - 1) // columns
    ph = phones[0][1].size[1]
    W = columns * phone_width + (columns + 1) * gap
    H = rows * (ph + title_size + 40) + (rows + 1) * gap
    canvas = Image.new("RGBA", (W, H), background)
    draw = ImageDraw.Draw(canvas)
    for i, (label, image) in enumerate(phones):
        col, row = i % columns, i // columns
        x = gap + col * (phone_width + gap)
        y = gap + row * (ph + title_size + 40 + gap)
        text_w = draw.textlength(label, font=font(title_size, "Semibold"))
        draw.text((x + (phone_width - text_w) / 2, y), label, font=font(title_size, "Semibold"), fill=label_color)
        with_shadow(canvas, image, (x, y + title_size + 30), blur=24, offset=14, alpha=70)
    return canvas


def save(image, name, max_width):
    if image.size[0] > max_width:
        image = image.resize((max_width, round(image.size[1] * max_width / image.size[0])), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    image.save(OUT / name, optimize=True)
    print(f"{name}: {image.size[0]}×{image.size[1]}, {(OUT / name).stat().st_size // 1024} KB")


if __name__ == "__main__":
    save(banner().convert("RGB"), "banner.png", 1800)
    # Tek tek telefonlar: başlıklar README'de metin olarak durur (açık ve koyu temada okunur).
    for name, path in [("ozet", SCREENS / "01-ozet.png"), ("islemler", EXTRA / "islemler.png"),
                       ("raporlar", EXTRA / "raporlar.png"), ("dagilim", SCREENS / "02-ozet-dagilim.png"),
                       ("taksitler", SCREENS / "09-taksitler-liste.png"), ("abonelikler", EXTRA / "odemeler.png"),
                       ("oneriler", SCREENS / "04-oneriler.png"), ("ice-aktarma", SCREENS / "21-akbank-taksit.png")]:
        item = phone(path, 400)
        canvas = Image.new("RGBA", (item.size[0] + 40, item.size[1] + 50), (0, 0, 0, 0))
        with_shadow(canvas, item, (20, 10), blur=12, offset=10, alpha=60)
        save(canvas, f"ekran-{name}.png", 440)
    save(gallery([
        ("Özet", EXTRA / "ozet-koyu.png"),
        ("Raporlar", EXTRA / "raporlar-koyu.png"),
        ("İşlemler", EXTRA / "islemler-koyu.png"),
    ], columns=3, background=(18, 18, 20, 255), label_color=(235, 235, 245)), "karanlik-mod.png", 1500)
