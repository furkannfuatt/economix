// UI testindeki örnek PDF ekstreyi üretir: swift scripts/make-sample-pdf.swift
// Sütunlar ayrı ayrı çizilir (bazı banka PDF'leri metni böyle saklar).
import CoreGraphics
import CoreText
import Foundation

let output = "EcoomixUITests/Fixtures/garanti-ornek.pdf"
let rows: [(date: String, text: String, installment: String, bonus: String, amount: String)] = [
    ("02.10.2026", "MIGROS SANAL MARKET ISTANBUL", "", "3,20", "1.234,56"),
    ("04.10.2026", "STARBUCKS NISANTASI", "", "0,50", "185,00"),
    ("06.10.2026", "VATAN BILGISAYAR", "3/6", "0,00", "2.500,00"),
    ("08.10.2026", "NETFLIX.COM", "", "0,00", "229,99"),
    ("10.10.2026", "OPET PETROLCULUK", "", "5,00", "2.050,00"),
    ("11.10.2026", "ABC TEKSTIL LTD STI", "", "0,00", "640,00"),
    ("12.10.2026", "ÖDEMENİZ İÇİN TEŞEKKÜR EDERİZ", "", "", "-15.000,00"),
    ("14.10.2026", "ZARA IADE", "", "", "-299,90"),
]

let data = NSMutableData()
var box = CGRect(x: 0, y: 0, width: 595, height: 842)
let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
context.beginPDFPage(nil)

func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 9, bold: Bool = false) {
    let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    let attributed = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font])
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
}

draw("Garanti BBVA Bonus Kart Ekstresi", x: 40, y: 790, size: 14, bold: true)
draw("Hesap Kesim Tarihi: 15.10.2026", x: 40, y: 768)
draw("Son Ödeme Tarihi: 25.10.2026", x: 300, y: 768)
draw("Önceki dönem borcu 14.500,00 TL", x: 40, y: 752)
let columns: [(title: String, x: CGFloat)] = [("Tarih", 40), ("İşlem", 110), ("Taksit", 330), ("Bonus", 390), ("Tutar (TL)", 470)]
for column in columns { draw(column.title, x: column.x, y: 720, bold: true) }

// Sütun sütun çiz
let ys = rows.indices.map { CGFloat(700 - $0 * 18) }
for (row, y) in zip(rows, ys) { draw(row.date, x: 40, y: y) }
for (row, y) in zip(rows, ys) { draw(row.text, x: 110, y: y) }
for (row, y) in zip(rows, ys) where !row.installment.isEmpty { draw(row.installment, x: 330, y: y) }
for (row, y) in zip(rows, ys) where !row.bonus.isEmpty { draw(row.bonus, x: 390, y: y) }
for (row, y) in zip(rows, ys) { draw(row.amount, x: 470, y: y) }
draw("Dönem toplamı 7.039,55 TL", x: 40, y: ys.last! - 30, bold: true)

context.endPDFPage()
context.closePDF()
try! (data as Data).write(to: URL(fileURLWithPath: output))
print("Yazıldı: \(output)")
