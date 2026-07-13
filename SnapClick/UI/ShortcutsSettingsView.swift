// ShortcutsSettingsView.swift
// SnapClick — 快捷键设置汇总页

import SwiftUI

// MARK: - 快捷键设置汇总页

struct ShortcutsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // ── 截图分组 ─────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "截图".localized, icon: "camera.viewfinder", color: .blue)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ShortcutCard(
                            icon: "crop",
                            iconColor: .blue,
                            title: "智能截图".localized,
                            subtitle: "点击截取窗口 · 拖拽选择区域".localized,
                            hotkey: $settings.hotkeyAreaScreenshot
                        )
                        ShortcutCard(
                            icon: "arrow.up.and.down",
                            iconColor: .purple,
                            title: "长截图".localized,
                            subtitle: "滚动截取全屏".localized,
                            hotkey: $settings.hotkeyLongScreenshot
                        )
                        // 占位，保持三列对齐
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            // ── 录制分组 ─────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "录制".localized, icon: "record.circle", color: .red)

                HStack(spacing: 12) {
                    ShortcutCard(
                        icon: "crop",
                        iconColor: .red,
                        title: "选区录制".localized,
                        subtitle: "选取矩形录制区域".localized,
                        hotkey: $settings.hotkeyRecordArea
                    )
                    ShortcutCard(
                        icon: "display",
                        iconColor: Color(red: 99/255, green: 102/255, blue: 241/255),
                        title: "全屏录制".localized,
                        subtitle: "立即录制全屏".localized,
                        hotkey: $settings.hotkeyRecordScreen
                    )
                    ShortcutCard(
                        icon: "stop.circle.fill",
                        iconColor: Color(red: 239/255, green: 68/255, blue: 68/255),
                        title: "停止录制".localized,
                        subtitle: "停止并保存录制文件".localized,
                        hotkey: $settings.hotkeyStopRecording
                    )
                }
            }

            // ── 贴图 & 取色分组 ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "贴图 & 取色".localized, icon: "pin.circle", color: .indigo)

                HStack(spacing: 12) {
                    ShortcutCard(
                        icon: "eyedropper.halffull",
                        iconColor: .orange,
                        title: "取色器".localized,
                        subtitle: "在屏幕任意位置拾取颜色".localized,
                        hotkey: $settings.hotkeyColorPicker
                    )
                    ShortcutCard(
                        icon: "pin.fill",
                        iconColor: .indigo,
                        title: "剪贴板贴图".localized,
                        subtitle: "将剪贴板图片钉在屏幕上".localized,
                        hotkey: $settings.hotkeyPin
                    )
                    // 占位，保持三列对齐
                    Color.clear
                        .frame(maxWidth: .infinity)
                }
            }

            // ── 提示横幅 ─────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DT.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("修改后立即生效".localized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.customPrimaryText)
                    Text("点击快捷键区域后，按下目标组合键即可完成录制，更改会实时应用到全局监听。".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                    .fill(DT.infoBannerBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                            .stroke(DT.infoBannerBorder, lineWidth: 0.75)
                    )
            )
        }
    }
}

// MARK: - 预览

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            SettingsPageHeader(title: "快捷键")
            ShortcutsSettingsView()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 680, height: 600)
}
