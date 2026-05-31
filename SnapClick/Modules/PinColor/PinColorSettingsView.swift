// PinColorSettingsView.swift
// SnapClick - 贴图取色模块
// 贴图 & 取色设置页：快捷键配置、颜色格式、历史库

import SwiftUI
import AppKit

// MARK: - 颜色格式枚举

enum ColorFormat: String, CaseIterable, Identifiable {
    case hex  = "HEX"
    case rgb  = "RGB"
    case hsl  = "HSL"
    case swift = "Swift"
    case css  = "CSS"
    var id: String { rawValue }
}

// MARK: - 设置页主视图

struct PinColorSettingsView: View {

    @EnvironmentObject private var engine: ColorPickerEngine
    @EnvironmentObject private var pinManager: PinWindowManager

    /// 默认颜色格式
    @AppStorage("PinColor.defaultColorFormat") private var defaultFormat: String = ColorFormat.hex.rawValue
    /// 取色快捷键描述（仅展示，实际绑定在 AppDelegate/HotKey 层）
    @AppStorage("PinColor.pickerShortcut") private var pickerShortcut: String = "⌥⇧C"
    /// 贴图快捷键描述
    @AppStorage("PinColor.pinShortcut") private var pinShortcut: String = "⌥⇧P"

    @State private var selectedTab: SettingsTab = .colorPicker

    enum SettingsTab: String, CaseIterable {
        case colorPicker = "取色器"
        case pinBoard    = "贴图板"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标签切换
            Picker("".localized, selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // 内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .colorPicker:
                        colorPickerSection
                    case .pinBoard:
                        pinBoardSection
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - 取色器设置区域

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 快捷键设置
            GroupBox(label: Label("快捷键", systemImage: "command")) {
                HStack {
                    Text("启动取色".localized)
                        .frame(width: 100, alignment: .leading)
                    ShortcutDisplayField(shortcut: $pickerShortcut)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // 默认颜色格式
            GroupBox(label: Label("默认复制格式", systemImage: "doc.on.clipboard")) {
                Picker("格式", selection: $defaultFormat) {
                    ForEach(ColorFormat.allCases) { fmt in
                        Text(fmt.rawValue).tag(fmt.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }

            // 颜色历史记录
            GroupBox(label: Label("颜色历史（最近 20 个）", systemImage: "clock.arrow.circlepath")) {
                if engine.colorHistory.isEmpty {
                    Text("暂无历史记录".localized)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 10), spacing: 8) {
                        ForEach(Array(engine.colorHistory.enumerated()), id: \.offset) { _, color in
                            ColorHistoryCell(color: color, engine: engine)
                        }
                    }
                    .padding(.vertical, 8)

                    HStack {
                        Spacer()
                        Button("清空历史") {
                            engine.colorHistory.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    // MARK: - 贴图板设置区域

    private var pinBoardSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 快捷键设置
            GroupBox(label: Label("快捷键", systemImage: "command")) {
                HStack {
                    Text("贴图快捷键".localized)
                        .frame(width: 100, alignment: .leading)
                    ShortcutDisplayField(shortcut: $pinShortcut)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // 当前贴图操作
            GroupBox(label: Label("窗口控制", systemImage: "square.stack")) {
                HStack(spacing: 12) {
                    Button("显示全部") { pinManager.showAll() }
                    Button("隐藏全部") { pinManager.hideAll() }
                    Button("关闭全部") { pinManager.closeAll() }
                        .foregroundColor(.red)
                }
                .padding(.vertical, 4)
            }

            // 贴图历史库
            GroupBox(label: Label("贴图历史库（最近 \(pinManager.pinHistory.count) 张）", systemImage: "photo.stack")) {
                if pinManager.pinHistory.isEmpty {
                    Text("暂无历史记录".localized)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(pinManager.pinHistory) { item in
                                PinHistoryCell(item: item, manager: pinManager)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(height: 110)

                    HStack {
                        Spacer()
                        Button("清空历史") {
                            pinManager.clearHistory()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

// MARK: - 颜色历史单元格

struct ColorHistoryCell: View {
    let color: NSColor
    let engine: ColorPickerEngine

    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: color))
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5)
                )
                .shadow(radius: isHovered ? 3 : 0)

            if isHovered {
                Text("复制".localized)
                    .font(.system(size: 9))
                    .foregroundColor(.white)
                    .shadow(radius: 1)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture {
            let hex = engine.hexString(for: color)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
        }
        .help(engine.hexString(for: color))
    }
}

// MARK: - 贴图历史单元格

struct PinHistoryCell: View {
    let item: PinHistoryItem
    let manager: PinWindowManager

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = item.nsImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 90, height: 90)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }

            // 删除按钮（悬停显示）
            if isHovered {
                Button {
                    manager.removeHistory(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture {
            manager.pinFromHistory(item)
        }
        .help("点击重新钉上 · \(formattedDate(item.createdAt))")
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

// MARK: - 快捷键显示控件（只读展示）

struct ShortcutDisplayField: View {
    @Binding var shortcut: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcut.enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - 预览

#Preview {
    PinColorSettingsView()
        .environmentObject(ColorPickerEngine.shared)
        .environmentObject(PinWindowManager.shared)
}
