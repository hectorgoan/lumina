import Foundation

/// A city a world clock can show.
struct WorldClockCity: Identifiable, Hashable {
    /// The city's code, unique in the catalog. Metropolitan area codes
    /// (NYC, LON, TYO) where they exist, otherwise the main airport's.
    let code: String
    let name: String
    /// ISO 3166 country code, used for the flag.
    let countryCode: String
    let timeZoneID: String

    var id: String { code }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .current
    }

    var country: String {
        Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
    }

    /// The country's flag emoji, built from its regional indicator letters.
    var flag: String {
        countryCode.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

extension WorldClockCity {
    static func city(withCode code: String) -> WorldClockCity? {
        all.first { $0.code == code }
    }

    /// Shown in the picker before the user types.
    static let suggestedCodes = ["NYC", "LON", "PAR", "TYO", "LAX", "MAD", "SIN", "SYD", "DXB", "MEX"]

    /// Cities whose name, country or code matches the query.
    static func search(_ query: String) -> [WorldClockCity] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func starts(_ text: String) -> Bool { text.range(of: query, options: options.union(.anchored)) != nil }
        /// Matches the start of any word, so "york" finds New York.
        func wordStarts(_ text: String) -> Bool { text.split(separator: " ").contains { starts(String($0)) } }

        // An exact code first, then names that start with the query, then
        // other word, country and code matches.
        let ranked = all.compactMap { city -> (WorldClockCity, Int)? in
            if city.code.caseInsensitiveCompare(query) == .orderedSame { return (city, 0) }
            if starts(city.name) { return (city, 1) }
            if wordStarts(city.name) || wordStarts(city.country) || starts(city.code) { return (city, 2) }
            return nil
        }
        return ranked
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name < $1.0.name }
            .map(\.0)
    }

    static let all: [WorldClockCity] = [
        // Europe
        .init(code: "MAD", name: "Madrid", countryCode: "ES", timeZoneID: "Europe/Madrid"),
        .init(code: "BCN", name: "Barcelona", countryCode: "ES", timeZoneID: "Europe/Madrid"),
        .init(code: "LIS", name: "Lisbon", countryCode: "PT", timeZoneID: "Europe/Lisbon"),
        .init(code: "LON", name: "London", countryCode: "GB", timeZoneID: "Europe/London"),
        .init(code: "DUB", name: "Dublin", countryCode: "IE", timeZoneID: "Europe/Dublin"),
        .init(code: "PAR", name: "Paris", countryCode: "FR", timeZoneID: "Europe/Paris"),
        .init(code: "BRU", name: "Brussels", countryCode: "BE", timeZoneID: "Europe/Brussels"),
        .init(code: "AMS", name: "Amsterdam", countryCode: "NL", timeZoneID: "Europe/Amsterdam"),
        .init(code: "BER", name: "Berlin", countryCode: "DE", timeZoneID: "Europe/Berlin"),
        .init(code: "MUC", name: "Munich", countryCode: "DE", timeZoneID: "Europe/Berlin"),
        .init(code: "ZRH", name: "Zurich", countryCode: "CH", timeZoneID: "Europe/Zurich"),
        .init(code: "VIE", name: "Vienna", countryCode: "AT", timeZoneID: "Europe/Vienna"),
        .init(code: "ROM", name: "Rome", countryCode: "IT", timeZoneID: "Europe/Rome"),
        .init(code: "MIL", name: "Milan", countryCode: "IT", timeZoneID: "Europe/Rome"),
        .init(code: "CPH", name: "Copenhagen", countryCode: "DK", timeZoneID: "Europe/Copenhagen"),
        .init(code: "STO", name: "Stockholm", countryCode: "SE", timeZoneID: "Europe/Stockholm"),
        .init(code: "OSL", name: "Oslo", countryCode: "NO", timeZoneID: "Europe/Oslo"),
        .init(code: "HEL", name: "Helsinki", countryCode: "FI", timeZoneID: "Europe/Helsinki"),
        .init(code: "REK", name: "Reykjavík", countryCode: "IS", timeZoneID: "Atlantic/Reykjavik"),
        .init(code: "WAW", name: "Warsaw", countryCode: "PL", timeZoneID: "Europe/Warsaw"),
        .init(code: "PRG", name: "Prague", countryCode: "CZ", timeZoneID: "Europe/Prague"),
        .init(code: "BUD", name: "Budapest", countryCode: "HU", timeZoneID: "Europe/Budapest"),
        .init(code: "ATH", name: "Athens", countryCode: "GR", timeZoneID: "Europe/Athens"),
        .init(code: "IEV", name: "Kyiv", countryCode: "UA", timeZoneID: "Europe/Kyiv"),
        .init(code: "IST", name: "Istanbul", countryCode: "TR", timeZoneID: "Europe/Istanbul"),
        .init(code: "MOW", name: "Moscow", countryCode: "RU", timeZoneID: "Europe/Moscow"),
        // Africa and Middle East
        .init(code: "CAS", name: "Casablanca", countryCode: "MA", timeZoneID: "Africa/Casablanca"),
        .init(code: "LOS", name: "Lagos", countryCode: "NG", timeZoneID: "Africa/Lagos"),
        .init(code: "CAI", name: "Cairo", countryCode: "EG", timeZoneID: "Africa/Cairo"),
        .init(code: "NBO", name: "Nairobi", countryCode: "KE", timeZoneID: "Africa/Nairobi"),
        .init(code: "JNB", name: "Johannesburg", countryCode: "ZA", timeZoneID: "Africa/Johannesburg"),
        .init(code: "CPT", name: "Cape Town", countryCode: "ZA", timeZoneID: "Africa/Johannesburg"),
        .init(code: "TLV", name: "Tel Aviv", countryCode: "IL", timeZoneID: "Asia/Jerusalem"),
        .init(code: "RUH", name: "Riyadh", countryCode: "SA", timeZoneID: "Asia/Riyadh"),
        .init(code: "DOH", name: "Doha", countryCode: "QA", timeZoneID: "Asia/Qatar"),
        .init(code: "DXB", name: "Dubai", countryCode: "AE", timeZoneID: "Asia/Dubai"),
        // Asia
        .init(code: "KHI", name: "Karachi", countryCode: "PK", timeZoneID: "Asia/Karachi"),
        .init(code: "DEL", name: "New Delhi", countryCode: "IN", timeZoneID: "Asia/Kolkata"),
        .init(code: "BOM", name: "Mumbai", countryCode: "IN", timeZoneID: "Asia/Kolkata"),
        .init(code: "BLR", name: "Bengaluru", countryCode: "IN", timeZoneID: "Asia/Kolkata"),
        .init(code: "KTM", name: "Kathmandu", countryCode: "NP", timeZoneID: "Asia/Kathmandu"),
        .init(code: "DAC", name: "Dhaka", countryCode: "BD", timeZoneID: "Asia/Dhaka"),
        .init(code: "BKK", name: "Bangkok", countryCode: "TH", timeZoneID: "Asia/Bangkok"),
        .init(code: "SGN", name: "Ho Chi Minh City", countryCode: "VN", timeZoneID: "Asia/Ho_Chi_Minh"),
        .init(code: "JKT", name: "Jakarta", countryCode: "ID", timeZoneID: "Asia/Jakarta"),
        .init(code: "KUL", name: "Kuala Lumpur", countryCode: "MY", timeZoneID: "Asia/Kuala_Lumpur"),
        .init(code: "SIN", name: "Singapore", countryCode: "SG", timeZoneID: "Asia/Singapore"),
        .init(code: "MNL", name: "Manila", countryCode: "PH", timeZoneID: "Asia/Manila"),
        .init(code: "HKG", name: "Hong Kong", countryCode: "HK", timeZoneID: "Asia/Hong_Kong"),
        .init(code: "TPE", name: "Taipei", countryCode: "TW", timeZoneID: "Asia/Taipei"),
        .init(code: "SHA", name: "Shanghai", countryCode: "CN", timeZoneID: "Asia/Shanghai"),
        .init(code: "BJS", name: "Beijing", countryCode: "CN", timeZoneID: "Asia/Shanghai"),
        .init(code: "SZX", name: "Shenzhen", countryCode: "CN", timeZoneID: "Asia/Shanghai"),
        .init(code: "SEL", name: "Seoul", countryCode: "KR", timeZoneID: "Asia/Seoul"),
        .init(code: "TYO", name: "Tokyo", countryCode: "JP", timeZoneID: "Asia/Tokyo"),
        .init(code: "OSA", name: "Osaka", countryCode: "JP", timeZoneID: "Asia/Tokyo"),
        // Oceania
        .init(code: "PER", name: "Perth", countryCode: "AU", timeZoneID: "Australia/Perth"),
        .init(code: "ADL", name: "Adelaide", countryCode: "AU", timeZoneID: "Australia/Adelaide"),
        .init(code: "BNE", name: "Brisbane", countryCode: "AU", timeZoneID: "Australia/Brisbane"),
        .init(code: "SYD", name: "Sydney", countryCode: "AU", timeZoneID: "Australia/Sydney"),
        .init(code: "MEL", name: "Melbourne", countryCode: "AU", timeZoneID: "Australia/Melbourne"),
        .init(code: "AKL", name: "Auckland", countryCode: "NZ", timeZoneID: "Pacific/Auckland"),
        .init(code: "HNL", name: "Honolulu", countryCode: "US", timeZoneID: "Pacific/Honolulu"),
        // North America
        .init(code: "ANC", name: "Anchorage", countryCode: "US", timeZoneID: "America/Anchorage"),
        .init(code: "YVR", name: "Vancouver", countryCode: "CA", timeZoneID: "America/Vancouver"),
        .init(code: "SEA", name: "Seattle", countryCode: "US", timeZoneID: "America/Los_Angeles"),
        .init(code: "SFO", name: "San Francisco", countryCode: "US", timeZoneID: "America/Los_Angeles"),
        .init(code: "LAX", name: "Los Angeles", countryCode: "US", timeZoneID: "America/Los_Angeles"),
        .init(code: "LAS", name: "Las Vegas", countryCode: "US", timeZoneID: "America/Los_Angeles"),
        .init(code: "PHX", name: "Phoenix", countryCode: "US", timeZoneID: "America/Phoenix"),
        .init(code: "DEN", name: "Denver", countryCode: "US", timeZoneID: "America/Denver"),
        .init(code: "DFW", name: "Dallas", countryCode: "US", timeZoneID: "America/Chicago"),
        .init(code: "HOU", name: "Houston", countryCode: "US", timeZoneID: "America/Chicago"),
        .init(code: "CHI", name: "Chicago", countryCode: "US", timeZoneID: "America/Chicago"),
        .init(code: "MEX", name: "Mexico City", countryCode: "MX", timeZoneID: "America/Mexico_City"),
        .init(code: "GDL", name: "Guadalajara", countryCode: "MX", timeZoneID: "America/Mexico_City"),
        .init(code: "MTY", name: "Monterrey", countryCode: "MX", timeZoneID: "America/Monterrey"),
        .init(code: "CUN", name: "Cancún", countryCode: "MX", timeZoneID: "America/Cancun"),
        .init(code: "YTO", name: "Toronto", countryCode: "CA", timeZoneID: "America/Toronto"),
        .init(code: "YMQ", name: "Montreal", countryCode: "CA", timeZoneID: "America/Toronto"),
        .init(code: "ATL", name: "Atlanta", countryCode: "US", timeZoneID: "America/New_York"),
        .init(code: "MIA", name: "Miami", countryCode: "US", timeZoneID: "America/New_York"),
        .init(code: "WAS", name: "Washington, D.C.", countryCode: "US", timeZoneID: "America/New_York"),
        .init(code: "NYC", name: "New York", countryCode: "US", timeZoneID: "America/New_York"),
        .init(code: "BOS", name: "Boston", countryCode: "US", timeZoneID: "America/New_York"),
        // Central and South America, Caribbean
        .init(code: "SJO", name: "San José", countryCode: "CR", timeZoneID: "America/Costa_Rica"),
        .init(code: "PTY", name: "Panama City", countryCode: "PA", timeZoneID: "America/Panama"),
        .init(code: "HAV", name: "Havana", countryCode: "CU", timeZoneID: "America/Havana"),
        .init(code: "SJU", name: "San Juan", countryCode: "PR", timeZoneID: "America/Puerto_Rico"),
        .init(code: "BOG", name: "Bogotá", countryCode: "CO", timeZoneID: "America/Bogota"),
        .init(code: "UIO", name: "Quito", countryCode: "EC", timeZoneID: "America/Guayaquil"),
        .init(code: "LIM", name: "Lima", countryCode: "PE", timeZoneID: "America/Lima"),
        .init(code: "CCS", name: "Caracas", countryCode: "VE", timeZoneID: "America/Caracas"),
        .init(code: "SCL", name: "Santiago", countryCode: "CL", timeZoneID: "America/Santiago"),
        .init(code: "BUE", name: "Buenos Aires", countryCode: "AR", timeZoneID: "America/Argentina/Buenos_Aires"),
        .init(code: "MVD", name: "Montevideo", countryCode: "UY", timeZoneID: "America/Montevideo"),
        .init(code: "SAO", name: "São Paulo", countryCode: "BR", timeZoneID: "America/Sao_Paulo"),
        .init(code: "RIO", name: "Rio de Janeiro", countryCode: "BR", timeZoneID: "America/Sao_Paulo"),
    ]
}
