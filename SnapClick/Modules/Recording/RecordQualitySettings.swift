// RecordQualitySettings.swift
// SnapClick - 录制质量档位与编码参数计算
// 参考 Snapzy 项目的 VideoQuality / RecordingVideoEncodingSettings 设计：
//   - 三档质量：标清 / 超清 / 原画
//   - 每档用 bitsPerPixelPerFrame × width × height × fps 计算目标码率
//   - clamp 到 [minBitrate, maxBitrate] 区间，避免超高清屏上码率爆炸 / 低分辨率上糊字
//   - 原画档在 Apple Silicon 上使用 HEVC（更小体积、画质相当）

import AVFoundation
import Foundation

// MARK: - 视频质量档位

/// 录制质量档位。
/// - 标清：偏省体积，UI/文字仍清晰，适合聊天/教学分享
/// - 超清：均衡，画质与体积兼顾，日常通用
/// - 原画：尽量贴近屏幕原始效果，H.264 High 档位；Apple Silicon 上 .mov 走 HEVC
enum VideoQuality: String, CaseIterable, Codable {
    case standard      // 标清
    case high          // 超清
    case original      // 原画

    /// 中文显示名
    var displayName: String {
        switch self {
        case .standard: return "标清"
        case .high:     return "超清"
        case .original: return "原画"
        }
    }

    /// 副标题/简介
    var description: String {
        switch self {
        case .standard: return "体积小，文字清晰"
        case .high:     return "均衡，画质细腻"
        case .original: return "原始画质，体积较大"
        }
    }

    /// 码率密度（bit per pixel per frame）
    /// 屏幕内容运动幅度小，0.08~0.20 已经能拿到非常好的主观画质
    var bitsPerPixelPerFrame: Double {
        switch self {
        case .standard: return 0.08
        case .high:     return 0.13
        case .original: return 0.20
        }
    }

    /// 最低码率（bps），保证文字/UI 清晰
    var minBitrate: Int {
        switch self {
        case .standard: return 1_000_000
        case .high:     return 1_600_000
        case .original: return 2_500_000
        }
    }

    /// 最高码率（bps），避免超高分辨率屏上码率爆炸、编辑器卡顿
    var maxBitrate: Int {
        switch self {
        case .standard: return 20_000_000
        case .high:     return 35_000_000
        case .original: return 60_000_000
        }
    }

    /// H.264 profile level
    var h264ProfileLevel: String {
        switch self {
        case .standard: return AVVideoProfileLevelH264BaselineAutoLevel
        case .high:     return AVVideoProfileLevelH264MainAutoLevel
        case .original: return AVVideoProfileLevelH264HighAutoLevel
        }
    }
}

// MARK: - 编码参数计算

/// 录制视频编码参数计算器。
/// 仿 Snapzy `RecordingVideoEncodingSettings`：把 (宽, 高, 帧率, 质量, 编码) 组合映射成
/// AVAssetWriterInput 期望的 [String: Any] 字典。
enum RecordingVideoEncodingSettings {

    /// 根据容器格式与质量档位挑选最合适的编码器。
    /// - MP4 容器 → 统一 H.264（兼容性最好）
    /// - MOV + 原画 + Apple Silicon → HEVC（高码率下体积与画质更优）
    /// - 其他情况 → H.264
    static func preferredCodec(formatIsMOV: Bool, quality: VideoQuality) -> AVVideoCodecType {
        guard formatIsMOV else { return .h264 }
        guard quality == .original else { return .h264 }
        #if arch(arm64)
        return .hevc
        #else
        return .h264
        #endif
    }

    /// 计算目标码率：
    /// 基础 = 宽 × 高 × 帧率 × 质量.bitsPerPixelPerFrame
    /// HEVC 编码效率更高，整体再乘 0.9
    /// 最后 clamp 到 [minBitrate, maxBitrate]
    static func calculatedBitrate(
        width: Int,
        height: Int,
        fps: Int,
        quality: VideoQuality,
        codec: AVVideoCodecType
    ) -> Int {
        let base = Double(width) * Double(height) * Double(fps) * quality.bitsPerPixelPerFrame
        let codecAdjusted = (codec == .hevc) ? base * 0.90 : base
        let clamped = min(max(codecAdjusted, Double(quality.minBitrate)), Double(quality.maxBitrate))
        return Int(clamped.rounded())
    }

    /// 生成 AVAssetWriterInput 期望的视频输出设置字典
    static func makeVideoSettings(
        width: Int,
        height: Int,
        fps: Int,
        quality: VideoQuality,
        codec: AVVideoCodecType,
        bitrate: Int
    ) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps,
        ]
        // H.264 才设置 profile level；HEVC 用自己的 profile，不在此处指定
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = quality.h264ProfileLevel
        }
        // 颜色属性：统一 Rec.709，与 sRGB 显示器输出对齐，避免偏色
        let colorProperties: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: colorProperties,
        ]
    }
}
