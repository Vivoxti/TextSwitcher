import AppKit
import SwiftUI
import ServiceManagement
import TextSwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SettingsModel()
    private let hotkeys = HotkeyManager()
    private let replacement = TextReplacement()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var dismissObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var errorPanel: NSPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: "TextSwitcher")
        let menu = NSMenu()
        let title = NSMenuItem(title: "TextSwitcher", action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Завершить TextSwitcher", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        hotkeys.onPress = { [weak self] _ in
            guard let self, !self.model.recording,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            guard self.model.compatible else { self.model.message = "Выберите раскладки с разными алфавитами."; self.showSettings(); return }
            let converter = LayoutConverter(first: self.model.first, second: self.model.second)
            Task { @MainActor in
                do {
                    try await self.replacement.replace(converter: converter)
                    self.model.message = ""
                    self.statusItem.button?.toolTip = "TextSwitcher · \(self.model.shortcut.display)"
                }
                catch {
                    self.model.message = error.localizedDescription
                    self.statusItem.button?.toolTip = error.localizedDescription
                    self.model.refresh()
                    self.showError(error.localizedDescription)
                    if !self.model.trusted { self.showSettings() }
                }
            }
        }
        model.updateShortcut = { [weak self] shortcut in self?.hotkeys.register(shortcut, id: 1) ?? false }
        model.recordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording { self.hotkeys.suspend() } else { self.registerShortcuts() }
        }
        deactivateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            if self?.model.recording == true { self?.model.stopRecording() }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.hotkeys.retryShiftMonitor() }
        registerShortcuts()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            model.setLaunch(true)
            showSettings()
        } else if !model.trusted || !model.message.isEmpty || CommandLine.arguments.contains("--settings") { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    private func registerShortcuts() {
        if !hotkeys.register(model.shortcut, id: 1) {
            model.message = "Не удалось зарегистрировать горячую клавишу. Проверьте разрешение или выберите свободное сочетание."
        }
    }
    private func showError(_ message: String) {
        errorPanel?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 90), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView: HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(width: 420).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)))
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 440, y: screen.visibleFrame.maxY - 110))
        }
        panel.orderFrontRegardless()
        errorPanel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak panel] in panel?.orderOut(nil) }
    }
    @objc func showSettings() {
        model.refresh()
        if settingsWindow == nil {
            let view = NSHostingView(rootView: SettingsView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Настройки TextSwitcher"
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
            dismissObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.model.stopRecording() }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
