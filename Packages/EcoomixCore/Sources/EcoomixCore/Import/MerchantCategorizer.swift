import Foundation

/// Yaygın Türk işyeri adlarından varsayılan kategori (seed anahtarı) tahmini.
/// Kullanıcının öğrettiği kurallar uygulamada bundan önce uygulanır.
public enum MerchantCategorizer {
    /// Marka ve tam ifade eşleşmeleri (kelime sınırında).
    static let keywords: [String: [String]] = [
        "market": ["MIGROS", "A101", "BIM", "SOK", "SOK MARKET", "CEPTE SOK", "CARREFOUR", "CARREFOURSA", "METRO GROSMARKET",
                   "MACROCENTER", "FILE MARKET", "HAKMAR", "ONUR MARKET", "KIM MARKET", "MOPAS", "GETIR", "GETIR BUYUK",
                   "BIZIM TOPTAN", "ISTEGELSIN", "BANABI", "TARIM KREDI", "BIRLIK MARKET", "EKOMINI", "UNLU MARKET"],
        "yemek": ["YEMEKSEPETI", "GETIR YEMEK", "TRENDYOL YEMEK", "MIGROS YEMEK", "STARBUCKS", "KAHVE DUNYASI",
                  "BURGER KING", "MCDONALDS", "DOMINOS", "PAPA JOHNS", "LITTLE CAESARS", "SBARRO", "SUBWAY", "ARBYS",
                  "CARLS JR", "POPEYES", "KFC", "SIMIT SARAYI", "TAVUK DUNYASI", "BAYDONER", "USTA DONERCI",
                  "KOFTECI YUSUF", "HD ISKENDER", "MADO", "ESPRESSOLAB", "GLORIA JEANS", "CAFFE NERO", "TCHIBO"],
        "ulasim": ["OPET", "SHELL", "BP", "PETROL OFISI", "TOTAL", "TOTALENERGIES", "AYTEMIZ", "LUKOIL", "MOIL", "ALPET",
                   "KADOIL", "ISTANBULKART", "BITAKSI", "UBER", "MARTI", "HGS", "OGS", "ISPARK", "PARKING", "TCDD",
                   "IETT", "OTOYOL"],
        "fatura": ["ENERJISA", "IGDAS", "ISKI", "TURKCELL", "VODAFONE", "TURK TELEKOM", "TURKTELEKOM", "SUPERONLINE",
                   "TURKNET", "CK ENERJI", "BEDAS", "AYEDAS", "BASKENTGAZ", "ASKI", "IZSU", "TTNET", "D SMART"],
        "abonelik": ["NETFLIX", "SPOTIFY", "YOUTUBE", "APPLE COM BILL", "ICLOUD", "DISNEY", "EXXEN", "BLUTV", "DIGITURK",
                     "AMAZON PRIME", "PRIME VIDEO", "GOOGLE ONE", "TABII", "GAIN", "MUBI", "CHATGPT", "OPENAI"],
        "giyim": ["ZARA", "H M", "LC WAIKIKI", "LCW", "KOTON", "MAVI", "DEFACTO", "BERSHKA", "PULL BEAR", "BOYNER",
                  "STRADIVARIUS", "MANGO", "COLINS", "FLO", "NIKE", "ADIDAS", "DECATHLON", "PENTI", "BEYMEN", "VAKKO",
                  "NETWORK", "IPEKYOL", "TWIST", "SKECHERS", "US POLO", "MARKS SPENCER", "INCI"],
        "saglik": ["ECZANE", "ECZ", "HASTANE", "HASTANESI", "MEDICAL", "ACIBADEM", "MEMORIAL", "MEDICANA", "DIS KLINIGI",
                   "MEDIPOL", "LIV HOSPITAL"],
        "elektronik": ["TEKNOSA", "MEDIAMARKT", "MEDIA MARKT", "VATAN BILGISAYAR", "APPLE STORE", "ITOPYA", "ARCELIK",
                       "VESTEL", "BEKO", "SAMSUNG", "XIAOMI", "GURGENCLER"],
        "eglence": ["STEAM", "PLAYSTATION", "XBOX", "NINTENDO", "EPIC GAMES", "BILETIX", "CINEMAXIMUM", "CINEVERSE",
                    "PASSO", "MOBILET", "BOWLING", "MACFIT"],
        "seyahat": ["PEGASUS", "THY", "TURK HAVA YOLLARI", "AJET", "ANADOLUJET", "OBILET", "BOOKING", "AIRBNB", "ENUYGUN",
                    "TATILSEPETI", "TATILBUDUR", "JOLLY", "ETS TUR", "SUNEXPRESS", "KAMIL KOC", "METRO TURIZM"],
        "ev": ["IKEA", "KOCTAS", "BAUHAUS", "ENGLISH HOME", "MADAME COCO", "KARACA", "TAC", "BELLONA", "ISTIKBAL",
               "PASABAHCE", "EVIDEA"],
        "bakim": ["GRATIS", "WATSONS", "ROSSMANN", "SEPHORA", "EVE SHOP", "FLORMAR", "GOLDEN ROSE", "MAC COSMETICS"],
        "egitim": ["UDEMY", "KITAPYURDU", "D R", "IDEFIX", "BKM KITAP", "COURSERA", "OKUL", "KURS"],
    ]

    /// Genel kelime kökleri: bir kelimenin başında geçerse yeter ("PASTANESI", "OTOPARKI", "ECZANESI").
    static let stems: [String: [String]] = [
        "market": ["MARKET", "KASAP", "MANAV", "BAKKAL", "SARKUTERI", "GIDA", "KURUYEMIS"],
        "yemek": ["YEMEK", "PASTANE", "FIRIN", "RESTORAN", "RESTAURANT", "LOKANTA", "KEBAP", "DONER", "PIDE", "KOFTE", "CAFE",
                  "KAFE", "KAHVE", "BURGER", "PIZZA", "BORACI", "SIMIT"],
        "ulasim": ["BENZIN", "PETROL", "AKARYAKIT", "OTOPARK", "TAKSI", "OTOGAR"],
        "saglik": ["ECZA", "HASTANE", "KLINIK", "OPTIK", "LABORATUVAR"],
        "giyim": ["TEKSTIL", "GIYIM", "AYAKKABI", "BUTIK", "KONFEKSIYON"],
        "egitim": ["KIRTASIYE", "KITAP", "KITABEVI", "DERSHANE"],
        "bakim": ["KUAFOR", "BERBER", "GUZELLIK", "KOZMETIK"],
        "ev": ["MOBILYA", "HIRDAVAT", "ZUCCACIYE"],
        "elektronik": ["ELEKTRONIK", "BILGISAYAR"],
        "eglence": ["SINEMA", "TIYATRO", "KONSER"],
        "seyahat": ["OTEL", "HOTEL", "PANSIYON", "HAVAYOLU", "TURIZM"],
    ]

    /// Eşleşen en uzun anahtar kelimenin ya da kelime kökünün kategorisi; eşleşme yoksa nil.
    /// Eşit uzunlukta marka eşleşmesi kökten önce gelir.
    public static func suggestedSeedKey(for merchant: String) -> String? {
        let normalized = MerchantNormalizer.normalize(merchant)
        let padded = " " + normalized + " "
        let words = normalized.split(separator: " ")
        var best: (key: String, length: Int, isBrand: Bool)?

        func consider(_ key: String, _ length: Int, brand: Bool) {
            guard let current = best else { best = (key, length, brand); return }
            if length > current.length || (length == current.length && brand && !current.isBrand) {
                best = (key, length, brand)
            }
        }
        for (key, phrases) in keywords {
            for phrase in phrases where padded.contains(" \(phrase) ") { consider(key, phrase.count, brand: true) }
        }
        for (key, list) in stems {
            for stem in list where words.contains(where: { $0.hasPrefix(stem) }) { consider(key, stem.count, brand: false) }
        }
        return best?.key
    }
}
