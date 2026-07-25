// AudioRecordingSettingsView.swift
// SnapClick - 音频录音设置页
// 仿 RecordingSettingsView 的视觉语言：顶部预览卡 + 两列（音频源 / 输出格式）
// 在侧边栏点击 "音频录制" 时展示

import SwiftUI
import AppKit

struct AudioRecordingSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var availableMics: [String] = []
    @State private var micListRefreshed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {

            // ── 实时预览 ─────────────────────────────────────────────
            AudioRecordingPreviewCard()

            // ── 麦克风测试（full width，在两列布局之上） ─────────
            AudioMicrophoneTestCard()

            // ── 两列布局 ─────────────────────────────────────────────
            HStack(alignment: .top, spacing: 16) {

                // 左列 — 音频源
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "音频源".localized, icon: "mic.circle", color: .purple)

                    DesignCard {
                        VStack(spacing: 0) {

                            // 系统音频
                            ToggleRow(
                                title: "系统音频".localized,
                                description: systemAudioDescription,
                                isOn: $settings.audioRecordSystemAudio
                            )
                            .opacity(systemAudioAvailable ? 1.0 : 0.55)
                            .disabled(!systemAudioAvailable)

                            CardDivider()

                            // 倒计时
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("倒计时".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Countdown Timer")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.audioRecordCountdown) {
                                    Text("关闭".localized).tag(0)
                                    Text("3 秒").tag(3)
                                    Text("5 秒").tag(5)
                                    Text("10 秒").tag(10)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 80)
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // 右列 — 输出格式
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "输出格式".localized, icon: "waveform", color: .indigo)

                    DesignCard {
                        VStack(spacing: 0) {

                            // 格式（v1.0 锁死 M4A）
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("格式".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Output Format")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("M4A")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.customSecondaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(.customControlBg)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(DT.cardBorder, lineWidth: 0.75)
                                            )
                                    )
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 质量
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("质量".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Recording Quality")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.audioRecordQuality) {
                                    Text("经济").tag("经济")
                                    Text("标准").tag("标准")
                                    Text("高质量").tag("高质量")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 110)
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 采样率
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("采样率".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Sample Rate")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.audioRecordSampleRate) {
                                    Text("44.1 kHz").tag(44_100)
                                    Text("48 kHz").tag(48_000)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 110)
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 声道
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("声道".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Channels")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.audioRecordChannels) {
                                    Text("单声道").tag(1)
                                    Text("立体声").tag(2)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 110)
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 保存位置
                            VStack(alignment: .leading, spacing: 8) {
                                Text("保存位置".localized)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.purple)
                                        Text(URL(fileURLWithPath: settings.audioRecordSavePath).lastPathComponent)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(.customControlBg)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(DT.cardBorder, lineWidth: 0.5)
                                            )
                                    )

                                    Button("更改…".localized) {
                                        let panel = NSOpenPanel()
                                        panel.canChooseFiles = false
                                        panel.canChooseDirectories = true
                                        panel.allowsMultipleSelection = false
                                        if panel.runModal() == .OK, let url = panel.url {
                                            settings.audioRecordSavePath = url.path
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.top, DT.rowPadV)
                            .padding(.bottom, DT.rowPadV)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if !micListRefreshed {
                availableMics = AudioRecordingEngine.availableMicrophones()
                // 若选中的麦克风不存在于可用列表里，自动回退到第一个或"无"
                if settings.audioRecordMicrophone != "无",
                   !availableMics.contains(settings.audioRecordMicrophone) {
                    settings.audioRecordMicrophone = availableMics.first ?? "无"
                }
                micListRefreshed = true
            }
        }
    }

    private var systemAudioAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    private var systemAudioDescription: String {
        if systemAudioAvailable {
            return "录制系统内部声音（macOS 13+）".localized
        }
        return "需要 macOS 13 或更高版本".localized
    }
}
