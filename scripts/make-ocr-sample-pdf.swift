// Akbank düzeninde, metin katmanı olmayan (yalnızca görüntü) örnek PDF üretir: swift scripts/make-ocr-sample-pdf.swift
// İçerik uydurmadır; OCR yolunu UI testinde sınamak için kullanılır.
import CoreGraphics
import CoreText
import Foundation

let output = "EcoomixUITests/Fixtures/akbank-ornek-goruntu.pdf"
let lines = [
    "Axess Hesap Ozeti",
    "Hesap Kesim Tarihi 18/09/2026",
    "Islem Tarihi   Donem ici islemler   Borc Tutari (TL)   Kalan Borc / Taksit   Chip-para",
    "02/09/2026   AKBANK Internet Subesi Odeme Tesekkurler   5,000.00(-)",
    "03/09/2026   abc_kadikoy_yemek   245.50",
    "05/09/2026   TEKNOSA/teknosa.com.tr (2,970.00 TL) 3/2.taksit   990.00   990.00x1",
    "12/09/2026   MIGROS/ISTANBUL   1,234.56",
    "Genel Toplam   3,000.00   12,345.67   0.00",
]
let scale: CGFloat = 3, width: CGFloat = 595, height: CGFloat = 842
let bitmap = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                       bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
bitmap.fill(CGRect(x: 0, y: 0, width: width * scale, height: height * scale))
bitmap.scaleBy(x: scale, y: scale)
let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
for (index, line) in lines.enumerated() {
    let attributed = NSAttributedString(string: line, attributes: [.init(kCTFontAttributeName as String): font])
    bitmap.textPosition = CGPoint(x: 30, y: height - 60 - CGFloat(index) * 22)
    CTLineDraw(CTLineCreateWithAttributedString(attributed), bitmap)
}
let image = bitmap.makeImage()!
let data = NSMutableData()
var box = CGRect(x: 0, y: 0, width: width, height: height)
let pdf = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
pdf.beginPDFPage(nil)
pdf.draw(image, in: box)
pdf.endPDFPage()
pdf.closePDF()
try! (data as Data).write(to: URL(fileURLWithPath: output))
print("Yazıldı: \(output)")
