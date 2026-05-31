// ColorPickerOverlay.swift
// SnapClick - 贴图取色模块
// 取色模式全屏覆盖层：放大镜、颜色预览、十字准星、HEX 标签

import AppKit
import SwiftUI

// MARK: - 覆盖层窗口控制器

final class ColorPickerOverlayWindowController: NSWindowController {

    convenience init() {
        // 获取所有屏幕的包围矩形
        let unionFrame = NSScreen.screens.reduce(CGRect.zero) { $0.union($1.frame) }
        let window = ColorPickerOverlayWindow(contentRect: unionFrame)
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // 将鼠标换为十字准星
        NSCursor.crosshair.push()
    }

    override func close() {
        NSCursor.pop()
        super.close()
    }
}

// MARK: - 覆盖层窗口

final class ColorPickerOverlayWindow: NSWindow {

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // 置顶显示（高于所有普通窗口）
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        // 载入 SwiftUI 覆盖层视图
        contentViewController = NSHostingController(
            rootView: ColorPickerOverlayView()
                .environmentObject(ColorPickerEngine.shared)
        )
    }

    // 允许窗口成为 key，以便捕获键盘事件
    override var canBecomeKey: Bool { true }
}

// MARK: - SwiftUI 覆盖层视图

struct ColorPickerOverlayView: View {
    @EnvironmentObject private var engine: ColorPickerEngine

    /// 放大镜圆形直径（pt）
    private let magnifierSize: CGFloat = 160
    /// 十字准星臂长
    private let crosshairArm: CGFloat = 20
    /// 十字准星间隙（中心空白半径）
    private let crosshairGap: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 极淡蓝色半透明遮罩（提示用户正处于取色模式）
                Color.blue.opacity(0.04)
                    .ignoresSafeArea()

                // 放大镜跟随鼠标
                MagnifierView(
                    image: engine.magnifierImage,
                    color: engine.currentColor,
                    hexString: engine.hexString(for: engine.currentColor),
                    size: magnifierSize
                )
                .position(magnifierPosition(in: geo.size))

                // 底部操作提示
                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        Label("点击取色", systemImage: "cursorarrow.click.2")
                        Label("ESC 取消", systemImage: "escape")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
                }
            }
        }
    }

    /// 计算放大镜应显示的位置（避免超出屏幕边缘）
    private func magnifierPosition(in containerSize: CGSize) -> CGPoint {
        // 在全屏视图中，需要从 NSEvent.mouseLocation 获取鼠标位置
        // SwiftUI 中无法直接获取全局鼠标位置，所以依赖 engine.magnifierImage 更新时重绘
        // 使用 NSScreen.main 的信息换算位置
        let mouse = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? containerSize.height

        // 将 AppKit 坐标（左下原点）转换为 SwiftUI 坐标（左上原点）
        var x = mouse.x
        var y = screenHeight - mouse.y

        // 放大镜偏移（显示在光标右上方）
        let offset: CGFloat = 30
        x += offset
        y -= offset

        // 边界夹紧，防止超出屏幕
        let halfSize = magnifierSize / 2
        x = max(halfSize, min(containerSize.width  - halfSize, x))
        y = max(halfSize, min(containerSize.height - halfSize, y))

        return CGPoint(x: x, y: y)
    }
}

// MARK: - 放大镜组件

struct MagnifierView: View {
    let image: NSImage?
    let color: NSColor
    let hexString: String
    let size: CGFloat

    /// 圆形描边宽度
    private let borderWidth: CGFloat = 3
    /// 中心十字准星臂长
    private let crosshairLen: CGFloat = 14

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // 放大的截图内容（圆形裁剪）
                Group {
                    if let img = image {
                        Image(nsImage: img)
                            .interpolation(.none) // 保持像素锐利
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())

                // 白色圆形边框
                Circle()
                    .stroke(Color.white, lineWidth: borderWidth)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)

                // 十字准星
                CrosshairShape(armLength: crosshairLen, gap: 4)
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: size, height: size)

                CrosshairShape(armLength: crosshairLen, gap: 4)
                    .stroke(Color.black.opacity(0.5), lineWidth: 0.75)
                    .frame(width: size, height: size)
            }

            // 颜色预览块 + HEX 标签
            HStack(spacing: 8) {
                // 当前颜色色块
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: color))
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )

                // HEX 字符串
                Text(hexString)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(6)
            }
        }
    }
}

// MARK: - 十字准星 Shape

struct CrosshairShape: Shape {
    let armLength: CGFloat
    let gap: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY

        // 水平左臂
        path.move(to:   CGPoint(x: cx - gap - armLength, y: cy))
        path.addLine(to: CGPoint(x: cx - gap,             y: cy))
        // 水平右臂
        path.move(to:   CGPoint(x: cx + gap,              y: cy))
        path.addLine(to: CGPoint(x: cx + gap + armLength,  y: cy))
        // 垂直上臂
        path.move(to:   CGPoint(x: cx, y: cy - gap - armLength))
        path.addLine(to: CGPoint(x: cx, y: cy - gap))
        // 垂直下臂
        path.move(to:   CGPoint(x: cx, y: cy + gap))
        path.addLine(to: CGPoint(x: cx, y: cy + gap + armLength))

        return path
    }
}
