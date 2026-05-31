// PinWindowController.swift
// SnapClick - 贴图取色模块
// 单个贴图窗口控制器：浮动面板、透明度调节、工具条、右键菜单

import AppKit
import SwiftUI

// MARK: - 贴图窗口控制器

final class PinWindowController: NSWindowController {

    // MARK: - 属性

    let pinnedImage: NSImage

    // MARK: - 初始化

    init(image: NSImage, screenFrame: CGRect? = nil) {
        self.pinnedImage = image
        let imgSize = image.size
        
        let frame: CGRect
        if let screenFrame = screenFrame {
            frame = screenFrame
        } else {
            // 默认窗口大小与图片一致，最大不超过 800×600
            let winWidth  = min(imgSize.width,  800)
            let winHeight = min(imgSize.height, 600)
            frame = CGRect(
                x: 200, y: 200,
                width: max(winWidth, 100),
                height: max(winHeight, 80)
            )
        }

        let panel = PinPanel(contentRect: frame)
        super.init(window: panel)

        // 设置内容视图
        let hostingView = NSHostingView(
            rootView: PinContentView(image: image, controller: self, initialSize: frame.size)
        )
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setFrame(frame, display: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard 初始化") }

    // MARK: - 公开方法

    func show() {
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    override func close() {
        PinWindowManager.shared.remove(self)
        super.close()
    }
}

// MARK: - 自定义浮动面板

final class PinPanel: NSPanel {

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            // 无边框、可调整大小、非激活面板
            styleMask: [.nonactivatingPanel, .resizable, .borderless],
            backing: .buffered,
            defer: false
        )
        // 始终浮动在最上层
        level = .floating
        // 加入所有 Space
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 移动鼠标时不激活此面板
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        // 允许移动到边缘之外
        isMovableByWindowBackground = true
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    // 允许成为 key window 以便响应快捷键
    override var canBecomeKey: Bool { true }
}

// MARK: - 贴图内容 SwiftUI 视图

struct PinContentView: View {
    let image: NSImage
    /// 持有 controller 的弱引用（通过 class + ObservableObject 桥接）
    weak var controller: PinWindowController?
    let initialSize: CGSize
    
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 图片显示
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 50, idealWidth: initialSize.width, maxWidth: .infinity,
                       minHeight: 50, idealHeight: initialSize.height, maxHeight: .infinity)
                .background(Color.clear)
                .onTapGesture(count: 2) {
                    controller?.close()
                }
                
            if isHovered {
                Button(action: {
                    controller?.close()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity)
            }
        }
        .background(Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            // 右键菜单
            Button("复制图片".localized) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
            }
            Button("存储到历史".localized) {
                PinWindowManager.shared.saveToHistory(image)
            }
            Divider()
            Button("关闭贴图".localized) {
                controller?.close()
            }
        }
    }
}


