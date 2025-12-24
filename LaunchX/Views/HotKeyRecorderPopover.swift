import Carbon
import SwiftUI

// MARK: - 快捷键录制弹窗

struct HotKeyRecorderPopover: View {
    @Binding var hotKey: HotKeyConfig?
    let itemId: UUID
    @Binding var isPresented: Bool

    @State private var isRecording = true
    @State private var tempKeyCode: UInt32 = 0
    @State private var tempModifiers: UInt32 = 0
    @State private var conflictMessage: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 12) {
            // 示例提示
            HStack(spacing: 4) {
                Text("例子")
                    .foregroundColor(.secondary)
                KeyCapViewLarge(text: "⌘")
                KeyCapViewLarge(text: "⇧")
                KeyCapViewLarge(text: "SPACE")
            }
            .padding(.top, 8)

            // 提示文字或冲突信息
            if let conflict = conflictMessage {
                Text("快捷键已被「\(conflict)」使用")
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                Text("请输入快捷键...")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // 当前录制的快捷键或已设置的快捷键
            if tempModifiers != 0 || hotKey != nil {
                HStack(spacing: 4) {
                    // 显示当前按键组合
                    let displayModifiers =
                        tempModifiers != 0 ? tempModifiers : (hotKey?.modifiers ?? 0)
                    let displayKeyCode = tempKeyCode != 0 ? tempKeyCode : (hotKey?.keyCode ?? 0)

                    ForEach(
                        HotKeyService.modifierSymbols(for: displayModifiers), id: \.self
                    ) { symbol in
                        KeyCapViewLarge(text: symbol)
                    }

                    if displayKeyCode != 0 {
                        KeyCapViewLarge(text: HotKeyService.keyString(for: displayKeyCode))
                    }

                    // 删除按钮
                    Button(action: clearHotKey) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    conflictMessage != nil
                        ? Color.red.opacity(0.8)
                        : Color.accentColor
                )
                .cornerRadius(8)
            }

            // 操作按钮
            HStack(spacing: 12) {
                Button("取消") {
                    stopRecording()
                    isPresented = false
                }
                .buttonStyle(.bordered)

                if hotKey != nil {
                    Button("清除") {
                        clearHotKey()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .frame(width: 220)
        .onAppear {
            startRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - 录制逻辑

    private func startRecording() {
        isRecording = true
        tempKeyCode = 0
        tempModifiers = 0
        conflictMessage = nil

        // 监控本地按键事件
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [self] event in

            if event.type == .flagsChanged {
                // 只更新修饰键状态
                tempModifiers = HotKeyService.carbonModifiers(from: event.modifierFlags)
                return event
            }

            // keyDown 事件

            // Escape 取消录制
            if event.keyCode == kVK_Escape {
                stopRecording()
                isPresented = false
                return nil
            }

            // 必须有修饰键
            let modifiers = HotKeyService.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else {
                return event
            }

            let keyCode = UInt32(event.keyCode)

            // 检查冲突
            if let conflict = HotKeyService.shared.checkConflict(
                keyCode: keyCode,
                modifiers: modifiers,
                excludingItemId: itemId
            ) {
                conflictMessage = conflict
                tempKeyCode = keyCode
                tempModifiers = modifiers
                return nil
            }

            // 设置快捷键
            hotKey = HotKeyConfig(keyCode: keyCode, modifiers: modifiers)
            conflictMessage = nil
            stopRecording()
            isPresented = false
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func clearHotKey() {
        hotKey = nil
        tempKeyCode = 0
        tempModifiers = 0
        conflictMessage = nil
    }
}

// MARK: - 大号按键帽视图

struct KeyCapViewLarge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Text("测试")
    }
    .popover(isPresented: .constant(true)) {
        HotKeyRecorderPopover(
            hotKey: .constant(nil),
            itemId: UUID(),
            isPresented: .constant(true)
        )
    }
}
