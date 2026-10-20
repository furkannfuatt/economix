import Foundation

/// IBM EBCDIC Latin-1 (kod sayfası 1140 = 037 + €). Ana bilgisayardan (AFP) üretilen banka PDF'leri metni bu tabloyla yazar;
/// PDF'te Unicode karşılığı olmadığı için PDFKit bu metni anlamsız karakterlere çevirir.
/// Tabloda olmayan Türkçe harfler (ı İ ş Ş ğ Ğ) ayrı bir yazı tipinde durur, bkz. `TurkishGlyphs`.
public enum EBCDIC {
    public static func decode(_ bytes: some Sequence<UInt8>) -> String {
        String(bytes.map(character))
    }

    public static func character(_ code: UInt8) -> Character { table[Int(code)] }

    /// Boşluk (0x40) ve rakamlar (0xF0–0xF9) EBCDIC'in ayırt edici kodlarıdır.
    public static let space: UInt8 = 0x40
    public static let digits: ClosedRange<UInt8> = 0xF0...0xF9

    static let table: [Character] = [
        "\u{0}", "\u{1}", "\u{2}", "\u{3}", "\u{9C}", "\u{9}", "\u{86}", "\u{7F}", "\u{97}", "\u{8D}", "\u{8E}", "\u{B}", "\u{C}", "\u{D}", "\u{E}", "\u{F}",  // 00
        "\u{10}", "\u{11}", "\u{12}", "\u{13}", "\u{9D}", "\u{85}", "\u{8}", "\u{87}", "\u{18}", "\u{19}", "\u{92}", "\u{8F}", "\u{1C}", "\u{1D}", "\u{1E}", "\u{1F}",  // 10
        "\u{80}", "\u{81}", "\u{82}", "\u{83}", "\u{84}", "\u{A}", "\u{17}", "\u{1B}", "\u{88}", "\u{89}", "\u{8A}", "\u{8B}", "\u{8C}", "\u{5}", "\u{6}", "\u{7}",  // 20
        "\u{90}", "\u{91}", "\u{16}", "\u{93}", "\u{94}", "\u{95}", "\u{96}", "\u{4}", "\u{98}", "\u{99}", "\u{9A}", "\u{9B}", "\u{14}", "\u{15}", "\u{9E}", "\u{1A}",  // 30
        "\u{20}", "\u{A0}", "â", "ä", "à", "á", "ã", "å", "ç", "ñ", "¢", ".", "<", "(", "+", "|",  // 40
        "&", "é", "ê", "ë", "è", "í", "î", "ï", "ì", "ß", "!", "$", "*", ")", ";", "¬",  // 50
        "-", "/", "Â", "Ä", "À", "Á", "Ã", "Å", "Ç", "Ñ", "¦", ",", "%", "_", ">", "?",  // 60
        "ø", "É", "Ê", "Ë", "È", "Í", "Î", "Ï", "Ì", "`", ":", "#", "@", "'", "=", "\"",  // 70
        "Ø", "a", "b", "c", "d", "e", "f", "g", "h", "i", "«", "»", "ð", "ý", "þ", "±",  // 80
        "°", "j", "k", "l", "m", "n", "o", "p", "q", "r", "ª", "º", "æ", "¸", "Æ", "€",  // 90
        "µ", "~", "s", "t", "u", "v", "w", "x", "y", "z", "¡", "¿", "Ð", "Ý", "Þ", "®",  // A0
        "^", "£", "¥", "·", "©", "§", "¶", "¼", "½", "¾", "[", "]", "¯", "¨", "´", "×",  // B0
        "{", "A", "B", "C", "D", "E", "F", "G", "H", "I", "\u{AD}", "ô", "ö", "ò", "ó", "õ",  // C0
        "}", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "¹", "û", "ü", "ù", "ú", "ÿ",  // D0
        "\\", "÷", "S", "T", "U", "V", "W", "X", "Y", "Z", "²", "Ô", "Ö", "Ò", "Ó", "Õ",  // E0
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "³", "Û", "Ü", "Ù", "Ú", "\u{9F}",  // F0
    ]
}
