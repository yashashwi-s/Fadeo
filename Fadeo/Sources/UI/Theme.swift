import SwiftUI

/// Brand palette, sampled from the logo: teal accent on slate.
enum Brand {
    static let teal = Color(red: 0x67/255, green: 0xE4/255, blue: 0xD2/255)   // #67E4D2
    static let slate = Color(red: 0x5A/255, green: 0x6A/255, blue: 0x7A/255)  // #5A6A7A
    static let slateDeep = Color(red: 0x3C/255, green: 0x48/255, blue: 0x55/255)

    static func swatch(_ hex: String?) -> Color {
        guard let hex, let c = Color(hexString: hex) else { return teal }
        return c
    }
}

extension Color {
    /// Parse "#RRGGBB" / "RRGGBB".
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
