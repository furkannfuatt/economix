import Foundation

/// Yaygın Türk işyeri adlarından varsayılan kategori (seed anahtarı) tahmini.
/// Kullanıcının öğrettiği kurallar uygulamada bundan önce uygulanır.
public enum MerchantCategorizer {
    static let keywords: [String: [String]] = [
        "market": ["MIGROS", "A101", "BIM", "SOK", "SOK MARKET", "CARREFOUR", "CARREFOURSA", "METRO", "MACROCENTER",
                   "FILE MARKET", "HAKMAR", "ONUR MARKET", "KIM MARKET", "MOPAS", "GETIR BUYUK", "BIZIM TOPTAN"],
        "yemek": ["YEMEKSEPETI", "GETIR YEMEK", "TRENDYOL YEMEK", "STARBUCKS", "KAHVE DUNYASI", "BURGER KING",
                  "MCDONALDS", "DOMINOS", "SIMIT SARAYI", "POPEYES", "KFC", "LITTLE CAESARS", "ESPRESSOLAB",
                  "CAFE", "KAFE", "RESTORAN", "RESTAURANT", "LOKANTA", "PIZZA", "KEBAP", "DONER"],
        "ulasim": ["OPET", "SHELL", "BP", "PETROL OFISI", "TOTAL", "TOTALENERGIES", "AYTEMIZ", "ISTANBULKART",
                   "BITAKSI", "UBER", "MARTI", "HGS", "OGS", "OTOPARK", "ISPARK", "PARKING", "TCDD", "IETT"],
        "fatura": ["ENERJISA", "IGDAS", "ISKI", "TURKCELL", "VODAFONE", "TURK TELEKOM", "TURKTELEKOM", "SUPERONLINE",
                   "CK ENERJI", "BEDAS", "AYEDAS", "BASKENTGAZ", "ASKI", "IZSU", "TTNET"],
        "abonelik": ["NETFLIX", "SPOTIFY", "YOUTUBE", "APPLE COM BILL", "ICLOUD", "DISNEY", "EXXEN", "BLUTV",
                     "AMAZON PRIME", "PRIME VIDEO", "GOOGLE ONE", "TABII", "GAIN", "MUBI", "CHATGPT", "OPENAI"],
        "giyim": ["ZARA", "H M", "LC WAIKIKI", "KOTON", "MAVI", "DEFACTO", "BERSHKA", "PULL BEAR", "BOYNER",
                  "STRADIVARIUS", "MANGO", "COLINS", "FLO", "NIKE", "ADIDAS", "DECATHLON"],
        "saglik": ["ECZANE", "ECZ", "HASTANE", "HASTANESI", "MEDICAL", "ACIBADEM", "MEMORIAL", "MEDICANA", "DIS KLINIGI"],
        "elektronik": ["TEKNOSA", "MEDIAMARKT", "MEDIA MARKT", "VATAN BILGISAYAR", "APPLE STORE", "ITOPYA"],
        "eglence": ["STEAM", "PLAYSTATION", "BILETIX", "CINEMAXIMUM", "CINEVERSE", "PASSO", "BOWLING", "MACFIT"],
        "seyahat": ["PEGASUS", "THY", "TURK HAVA YOLLARI", "AJET", "OBILET", "BOOKING", "AIRBNB", "HOTEL", "OTEL",
                    "ENUYGUN", "TATILSEPETI", "SUNEXPRESS"],
        "ev": ["IKEA", "KOCTAS", "BAUHAUS", "ENGLISH HOME", "MADAME COCO", "KARACA", "TAC", "BELLONA", "ISTIKBAL"],
        "bakim": ["KUAFOR", "BERBER", "GRATIS", "WATSONS", "ROSSMANN", "SEPHORA", "EVE SHOP"],
        "egitim": ["UDEMY", "KITAPYURDU", "D R", "IDEFIX", "OKUL", "KURS", "COURSERA"],
    ]

    /// Eşleşen en uzun anahtar kelimenin kategorisi; eşleşme yoksa nil.
    public static func suggestedSeedKey(for merchant: String) -> String? {
        let normalized = " " + MerchantNormalizer.normalize(merchant) + " "
        var best: (key: String, length: Int)?
        for (key, words) in keywords {
            for word in words where normalized.contains(" \(word) ") {
                if word.count > (best?.length ?? 0) { best = (key, word.count) }
            }
        }
        return best?.key
    }
}
