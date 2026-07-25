// AudioRecordingPreviewCard.swift
// SnapClick - 音频录音设置页中的实时预览卡
// 仿录屏预览卡的暗色背景 + REC 闪烁 + 大号电平柱，
// 但中间内容改为左右声道电平柱 + 状态文字

import SwiftUI

struct AudioRecordingPreviewCard: View {
    @ObservedObject private var engine = AudioRecordingEngine.shared
    @State private var pulse = false

    var body: some View {
        ZStack {
            // 暗色渐变背景
            RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 30/255, green: 27/255, blue: 75/255),
                            Color(red: 49/255, green: 46/255, blue: 129/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                        .stroke(Color(red: 67/255, green: 56/255, blue: 202/255).opacity(0.4), lineWidth: 0.75)
                )

            // 半透明蒙层
            RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                .fill(Color.black.opacity(0.35))

            VStack(spacing: 14) {
                // 顶部标签行
                HStack {
                    Label("音频预览".localized, systemImage: "waveform.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 252/255, green: 165/255, blue: 165/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.15))
                                .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 0.5))
                        )
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulse && engine.isRecording ? 1.3 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: pulse && engine.isRecording
                            )
                        Text(statusText)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // 中央大号电平柱
                VStack(spacing: 8) {
                    AudioLevelMeterView(
                        leftLevel: engine.micLevel,
                        rightLevel: engine.systemLevel,
                        showLabels: true,
                        labelLeft: "MIC".localized,
                        labelRight: "SYS".localized
                    )
                    .frame(height: 30)
                }
                .padding(.horizontal, 28)

                Spacer()

                // 底部状态：计时器 + 配置
                HStack(spacing: 12) {
                    AudioPreviewInfoColumn(
                        label: "DURATION".localized,
                        value: formatDuration(engine.recordingDuration),
                        valueColor: engine.isRecording ? .white : .white.opacity(0.5)
                    )
                    AudioPreviewDivider()
                    AudioPreviewInfoColumn(
                        label: "FORMAT".localized,
                        value: "M4A",
                        valueColor: .white
                    )
                    AudioPreviewDivider()
                    AudioPreviewInfoColumn(
                        label: "RATE".localized,
                        value: "\(AppSettings.shared.audioRecordSampleRate / 1000) kHz",
                        valueColor: .white
                    )
                    AudioPreviewDivider()
                    Image(systemName: engine.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 12))
                        .foregroundStyle(engine.isRecording ? .white : .white.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.7))
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.75)
                        )
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous))
        .onAppear { pulse = true }
    }

    private var statusText: String {
        if engine.isRecording {
            return engine.isPaused ? "PAUSED" : "REC"
        }
        return "READY"
    }

    private var statusColor: Color {
        if engine.isRecording {
            return engine.isPaused ? .orange : .red
        }
        return .white.opacity(0.5)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - 预览卡信息列

private struct AudioPreviewInfoColumn: View {
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - 预览卡分隔线

private struct AudioPreviewDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 20)
    }
}
