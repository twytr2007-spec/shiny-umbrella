import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0)
    }
}

struct Theme: Identifiable {
    enum Role { case keyword, string, comment, number, builtin, function }

    let id: String
    let name: String
    let isDark: Bool
    let bg: UInt32
    let panel: UInt32
    let text: UInt32
    let keyword: UInt32
    let string: UInt32
    let comment: UInt32
    let number: UInt32
    let builtin: UInt32
    let function: UInt32
    let accent: UInt32
    let error: UInt32

    var bgColor: Color { Color(hex: bg) }
    var panelColor: Color { Color(hex: panel) }
    var textColor: Color { Color(hex: text) }
    var commentColor: Color { Color(hex: comment) }
    var accentColor: Color { Color(hex: accent) }
    var errorColor: Color { Color(hex: error) }
    var builtinColor: Color { Color(hex: builtin) }

    func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0)
    }

    func hex(for role: Role) -> UInt32 {
        switch role {
        case .keyword: return keyword
        case .string: return string
        case .comment: return comment
        case .number: return number
        case .builtin: return builtin
        case .function: return function
        }
    }

    static let dark = Theme(id: "dark", name: "Midnight", isDark: true,
        bg: 0x1B1D23, panel: 0x14161A, text: 0xD7DAE0, keyword: 0xFF7AB2, string: 0xFC6A5D,
        comment: 0x7F8C98, number: 0xD9C97C, builtin: 0x4EB0CC, function: 0x67B7A4,
        accent: 0x30D158, error: 0xFF5F56)

    static let light = Theme(id: "light", name: "Daylight", isDark: false,
        bg: 0xFFFFFF, panel: 0xF2F2F7, text: 0x1C1C1E, keyword: 0xAD3DA4, string: 0xD12F1B,
        comment: 0x6C7986, number: 0x272AD8, builtin: 0x0F68A0, function: 0x326D74,
        accent: 0x1E9E3F, error: 0xD70015)

    static let dracula = Theme(id: "dracula", name: "Dracula", isDark: true,
        bg: 0x282A36, panel: 0x1E1F29, text: 0xF8F8F2, keyword: 0xFF79C6, string: 0xF1FA8C,
        comment: 0x6272A4, number: 0xBD93F9, builtin: 0x8BE9FD, function: 0x50FA7B,
        accent: 0x50FA7B, error: 0xFF5555)

    static let solar = Theme(id: "solar", name: "Solarized", isDark: true,
        bg: 0x002B36, panel: 0x00212B, text: 0x93A1A1, keyword: 0x859900, string: 0x2AA198,
        comment: 0x586E75, number: 0xD33682, builtin: 0x268BD2, function: 0xB58900,
        accent: 0x2AA198, error: 0xDC322F)

    static let all: [Theme] = [dark, light, dracula, solar]

    static func byID(_ id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? dark
    }
}
