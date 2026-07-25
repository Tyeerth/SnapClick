// AudioQualitySettings.swift
// SnapClick - 音频录音质量档位定义
// 仿照 RecordQualitySettings 的视频档位设计，三档质量对应不同 AAC 编码比特率
// 声道与采样率独立可选，组合后喂给 AVAssetWriter 的 audioSettings

import AVFoundation
import Foundation

// MARK: - 音频质量档位

/// 音频录音质量档位。
/// - 经济：64 kbps，语音备忘 / 会议归档，体积最小
/// - 标准：128 kbps，通用推荐，兼顾音质与体积
/// - 高质量：256 kbps，接近 CD 音质的 AAC 上限
enum AudioQuality: String, CaseIterable, Codable {
    case economy
    case standard
    case high

    var displayName: String {
        switch self {
        case .economy:  return "经济"
        case .standard: return "标准"
        case .high:     return "高质量"
        }
    }

    var description: String {
        switch self {
        case .economy:  return "体积最小，语音为主"
        case .standard: return "均衡推荐，兼容性好"
        case .high:     return "接近 CD 音质，体积较大"
        }
    }

    /// AAC 编码目标码率（bps）
    var bitrate: Int {
        switch self {
        case .economy:  return 64_000
        case .standard: return 128_000
        case .high:     return 256_000
        }
    }
}

// MARK: - 采样率档位

/// 录音采样率
enum AudioSampleRate: Int, CaseIterable, Codable {
    case rate44100 = 44_100
    case rate48000 = 48_000

    var displayName: String {
        switch self {
        case .rate44100: return "44.1 kHz"
        case .rate48000: return "48 kHz"
        }
    }
}

// MARK: - 声道档位

/// 录音声道数
enum AudioChannels: Int, CaseIterable, Codable {
    case mono    = 1
    case stereo  = 2

    var displayName: String {
        switch self {
        case .mono:   return "单声道"
        case .stereo: return "立体声"
        }
    }
}
