import Foundation
import PDFKit
import Vision

/// Metin katmanı okunamayan PDF'leri (taranmış ya da eşleme tablosuz özel yazı tipli) görüntüden okur.
/// Cihazda çalışır; hiçbir yere gönderilmez.
public enum PDFOCRReader {
    /// Sayfalar bu ölçekte görüntüye çevrilir (A4 ≈ 1800×2500 piksel).
    static let scale: CGFloat = 3

    public static func lines(from data: Data) throws -> [String] {
        guard let document = PDFDocument(data: data) else { throw PDFTextReader.ReadError.notPDF }
        var result: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = render(page) else { continue }
            result += try lines(in: image)
        }
        guard !result.isEmpty else { throw PDFTextReader.ReadError.noText }
        return result
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func lines(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = supported.contains { $0.hasPrefix("tr") } ? ["tr-TR", "en-US"] : ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])

        let pieces: [(text: String, box: CGRect)] = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
        // Vision kutuları normalize ve alttan yukarıdır: yukarıdan aşağıya sırala, aynı yükseklikteki parçaları birleştir.
        var rows: [(midY: CGFloat, pieces: [(text: String, box: CGRect)])] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.last, abs(last.midY - piece.box.midY) <= piece.box.height * 0.5 {
                rows[rows.count - 1].pieces.append(piece)
            } else {
                rows.append((piece.box.midY, [piece]))
            }
        }
        return rows.map { row in row.pieces.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }
}
