// AudioMicrophoneTestCard.swift
// SnapClick - 设置页"麦克风测试"卡片
// 内含：设备下拉、检测按钮、10 段实时电平计、输入音量、自动调整开关
// 视觉风格与现有 DesignCard / AudioRecordingSettingsView 完全一致

import SwiftUI

struct AudioMicrophoneTestCard: View {
    @ObservedObject private var engine = AudioMicrophoneTestEngine.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var testError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "麦克风测试".localized, icon: "waveform", color: .purple)

            DesignCard {
                VStack(spacing: 0) {

                    // ── 设备选择 + 检测按钮 ──────────────────────
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("麦克风".localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.customPrimaryText)
                            Text("Microphone Input")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.audioRecordMicrophone) {
                            Text("无".localized).tag("无")
                            ForEach(AudioRecordingEngine.availableMicrophones(), id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 180)
                        .disabled(engine.isTesting)

                        Button(action: toggleTest) {
                            Text(engine.isTesting
                                 ? "停止检测".localized
                                 : "检测麦克风".localized)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(engine.isTesting ? .red : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(engine.isTesting
                                              ? Color.red.opacity(0.10)
                                              : Color.purple.opacity(0.10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(engine.isTesting
                                                        ? Color.red.opacity(0.35)
                                                        : Color.purple.opacity(0.35),
                                                        lineWidth: 0.75)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DT.rowPadH)
                    .padding(.vertical, DT.rowPadV)

                    // 检测失败提示
                    if let err = testError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                            Spacer()
                            Button(action: { testError = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, DT.rowPadH)
                        .padding(.bottom, 8)
                    }

                    CardDivider()

                    // ── 输入等级（10 段独立格子）────────────────
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.purple)
                            Text("输入等级".localized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.customPrimaryText)
                        }
                        .frame(width: 92, alignment: .leading)

                        AudioLevelSegments(level: engine.currentLevel, segments: 10)
                            .frame(height: 14)
                    }
                    .padding(.horizontal, DT.rowPadH)
                    .padding(.vertical, DT.rowPadV)

                    CardDivider()

                    // ── 自动调整麦克风音量 ─────────────────────
                    ToggleRow(
                        title: "自动调整麦克风音量".localized,
                        description: "录制时自动调整增益，避免音量过小或爆音".localized,
                        isOn: $settings.audioRecordAutoAdjust
                    )
                }
            }
        }
        .onDisappear {
            // 离开设置页时自动停止检测
            if engine.isTesting {
                engine.stopTesting()
            }
        }
    }

    // MARK: - 动作

    private func toggleTest() {
        if engine.isTesting {
            engine.stopTesting()
            testError = nil
        } else {
            Task { @MainActor in
                do {
                    try await engine.startTesting(deviceName: settings.audioRecordMicrophone)
                    testError = nil
                } catch {
                    testError = error.localizedDescription
                }
            }
        }
    }
}
