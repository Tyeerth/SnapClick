// AudioLevelMeter.swift
// SnapClick - 通用电平柱状图 SwiftUI 组件
// 用于：HUD 实时电平显示、设置页预览卡静态展示
// 风格：仿录音软件 VU meter，三段彩色（绿/黄/红）

import SwiftUI

// MARK: - 音频电平柱

/// 单条电平柱（横向或纵向），自动根据 level 渲染绿/黄/红三段。
/// level 范围 0.0 ~ 1.0（-60dB ~ 0dB 归一化结果）
struct AudioLevelBar: View {
    let level: Float
    var orientation: Axis = .horizontal
    var trackColor: Color = Color.white.opacity(0.10)
    var segments: Int = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: orientation == .horizontal ? .leading : .bottom) {
                // 底色轨道
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(trackColor)

                // 进度段：按比例填充，绿/黄/红
                let clamped = max(0, min(1, CGFloat(level)))

                if orientation == .horizontal {
                    HStack(spacing: 1) {
                        ForEach(0..<segments, id: \.self) { idx in
                            Rectangle()
                                .fill(color(for: idx))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(0.5)
                    .mask(
                        HStack(spacing: 1) {
                            ForEach(0..<segments, id: \.self) { _ in
                                Rectangle()
                            }
                        }
                    )
                    .opacity(clamped <= 0 ? 0 : 1)
                    .frame(width: max(0, geo.size.width * clamped))
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                } else {
                    VStack(spacing: 1) {
                        ForEach((0..<segments).reversed(), id: \.self) { idx in
                            Rectangle()
                                .fill(color(for: idx))
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(0.5)
                    .frame(height: max(0, geo.size.height * clamped))
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    /// 根据段位置返回颜色：前 60% 绿、60-85% 黄、85% 后红
    private func color(for index: Int) -> Color {
        let progress = Double(index) / Double(max(1, segments - 1))
        if progress < 0.60 { return Color(red: 52/255,  green: 199/255, blue: 89/255) }
        if progress < 0.85 { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        return Color(red: 239/255, green: 68/255,  blue: 68/255)
    }
}

// MARK: - 段式电平（独立格子，逐段填满）

/// N 段独立的电平格子（永远显示完整网格，按 level 逐段填满）。
/// 与 AudioLevelBar 的"单条连续填充"不同：本组件适合检测麦克风这类需要"看到格子逐个亮起"的场景。
struct AudioLevelSegments: View {
    let level: Float
    var segments: Int = 10
    var trackColor: Color = Color.gray.opacity(0.18)
    var spacing: CGFloat = 2
    var cornerRadius: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let totalSpacing = spacing * CGFloat(max(0, segments - 1))
            let cellWidth = max(2, (geo.size.width - totalSpacing) / CGFloat(segments))
            let filledCount = max(0, min(segments, Int((CGFloat(max(0, min(1, level))) * CGFloat(segments)).rounded(.up))))

            HStack(spacing: spacing) {
                ForEach(0..<segments, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(idx < filledCount ? color(for: idx) : trackColor)
                        .frame(width: cellWidth)
                }
            }
        }
        .animation(.easeOut(duration: 0.10), value: level)
    }

    /// 段位置 → 颜色：前 60% 绿、60-85% 黄、85% 后红
    private func color(for index: Int) -> Color {
        let progress = Double(index) / Double(max(1, segments - 1))
        if progress < 0.60 { return Color(red: 52/255,  green: 199/255, blue: 89/255) }
        if progress < 0.85 { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        return Color(red: 239/255, green: 68/255,  blue: 68/255)
    }
}

// MARK: - 双声道电平柱

/// 左右声道电平柱（标签 + 柱体），HUD 和设置页预览卡共用
struct AudioLevelMeterView: View {
    let leftLevel: Float
    let rightLevel: Float
    var showLabels: Bool = true
    var labelLeft: String = "MIC"
    var labelRight: String = "SYS"

    var body: some View {
        HStack(spacing: 8) {
            channelRow(label: labelLeft, level: leftLevel)
            channelRow(label: labelRight, level: rightLevel)
        }
    }

    @ViewBuilder
    private func channelRow(label: String, level: Float) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if showLabels {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            AudioLevelBar(level: level)
                .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }
}
