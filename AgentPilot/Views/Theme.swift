import SwiftUI

// MARK: - Color hex 初始化

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - WorkBuddy / CodeBuddy 设计系统配色

enum Palette {
    // 品牌强调色（WorkBuddy 紫）
    static let accent = Color(hex: 0x6C4DFF)
    static let accentLight = Color(hex: 0x8B6DFF)
    static let accentGradient2 = Color(hex: 0x7C5CFF)

    // 状态色
    static let success = Color(hex: 0x28B894)   // 绿
    static let danger = Color(hex: 0xE5484D)    // 红
    static let warning = Color(hex: 0xF5A623)   // 橙
    static let info = Color(hex: 0x4D9FFF)      // 蓝

    // 深色背景体系
    static let bgBase = Color(hex: 0x0E0E0E)      // 最底层
    static let bgSurface = Color(hex: 0x141416)   // 侧栏/主区
    static let bgPanel = Color(hex: 0x191A23)     // 面板
    static let bgElevated = Color(hex: 0x232330)  // 卡片/气泡
    static let bgInput = Color(hex: 0x1C1C26)     // 输入框

    // 文字
    static let textPrimary = Color(hex: 0xEFEEEC)
    static let textSecondary = Color(hex: 0xB8B8C4)
    static let textTertiary = Color(hex: 0x6E6E7E)

    // 气泡
    static let bubbleIncoming = Color(hex: 0x232330)
    static let bubbleOutgoing = Color(hex: 0x6C4DFF)
}
