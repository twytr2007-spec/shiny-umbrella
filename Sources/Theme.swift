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
    enum Role { case keyword, string, comment, number, builtin, function, brace }

    let id: String
    let name: String
    let isDark: Bool
    let bg: UInt32
    let panel: UInt32
    let tabBar: UInt32
    let tabInactive: UInt32
    let border: UInt32
    let text: UInt32
    let keyword: UInt32
    let string: UInt32
    let comment: UInt32
    let number: UInt32
    let builtin: UInt32
    let function: UInt32
    let accent: UInt32
    let status: UInt32
    let error: UInt32

    var bgColor: Color { Color(hex: bg) }
    var panelColor: Color { Color(hex: panel) }
    var tabBarColor: Color { Color(hex: tabBar) }
    var tabInactiveColor: Color { Color(hex: tabInactive) }
    var borderColor: Color { Color(hex: border) }
    var textColor: Color { Color(hex: text) }
    var commentColor: Color { Color(hex: comment) }
    var accentColor: Color { Color(hex: accent) }
    var statusColor: Color { Color(hex: status) }
    var errorColor: Color { Color(hex: error) }
    var builtinColor: Color { Color(hex: builtin) }
    var keywordColor: Color { Color(hex: keyword) }
    var stringColor: Color { Color(hex: string) }
    var functionColor: Color { Color(hex: function) }

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
        case .brace: return isDark ? 0xFFD700 : 0x0431FA
        }
    }

    static let dark = Theme(
        id: "dark", name: "Dark+", isDark: true,
        bg: 0x1E1E1E, panel: 0x252526, tabBar: 0x252526, tabInactive: 0x2D2D2D, border: 0x3C3C3C,
        text: 0xD4D4D4, keyword: 0x569CD6, string: 0xCE9178, comment: 0x6A9955, number: 0xB5CEA8,
        builtin: 0x4EC9B0, function: 0xDCDCAA, accent: 0x007ACC, status: 0x007ACC, error: 0xF44747)

    static let light = Theme(
        id: "light", name: "Light+", isDark: false,
        bg: 0xFFFFFF, panel: 0xF3F3F3, tabBar: 0xF3F3F3, tabInactive: 0xECECEC, border: 0xD4D4D4,
        text: 0x1F1F1F, keyword: 0x0000FF, string: 0xA31515, comment: 0x008000, number: 0x098658,
        builtin: 0x267F99, function: 0x795E26, accent: 0x007ACC, status: 0x007ACC, error: 0xE51400)

    static let monokai = Theme(
        id: "monokai", name: "Monokai", isDark: true,
        bg: 0x272822, panel: 0x1E1F1C, tabBar: 0x1E1F1C, tabInactive: 0x34352F, border: 0x3E3D32,
        text: 0xF8F8F2, keyword: 0xF92672, string: 0xE6DB74, comment: 0x75715E, number: 0xAE81FF,
        builtin: 0x66D9EF, function: 0xA6E22E, accent: 0xA6E22E, status: 0x3E3D32, error: 0xF92672)

    static let dracula = Theme(
        id: "dracula", name: "Dracula", isDark: true,
        bg: 0x282A36, panel: 0x21222C, tabBar: 0x21222C, tabInactive: 0x343746, border: 0x44475A,
        text: 0xF8F8F2, keyword: 0xFF79C6, string: 0xF1FA8C, comment: 0x6272A4, number: 0xBD93F9,
        builtin: 0x8BE9FD, function: 0x50FA7B, accent: 0xBD93F9, status: 0x44475A, error: 0xFF5555)

    static let solar = Theme(
        id: "solar", name: "Solarized", isDark: true,
        bg: 0x002B36, panel: 0x00212B, tabBar: 0x00212B, tabInactive: 0x073642, border: 0x0A4150,
        text: 0x93A1A1, keyword: 0x859900, string: 0x2AA198, comment: 0x586E75, number: 0xD33682,
        builtin: 0x268BD2, function: 0xB58900, accent: 0x2AA198, status: 0x073642, error: 0xDC322F)

    static let all: [Theme] = [dark, light, monokai, dracula, solar]

    static func byID(_ id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? dark
    }
}
