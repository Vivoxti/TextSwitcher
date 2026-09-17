import AppKit
import SwiftUI
import ServiceManagement
import ApplicationServices
import TextSwitcherCore

final class SettingsModel: ObservableObject {
    @Published var first: KeyboardLayout { didSet { UserDefaults.standard.set(first.rawValue, forKey: "firstLayout") } }
    @Published var second: KeyboardLayout { didSet { UserDefaults.standard.set(second.rawValue, forKey: "secondLayout") } }
    @Published var shortcut: Shortcut
    @Published var message: String = ""
    @Published var trusted = AXIsProcessTrusted()
    @Published var launchEnabled = SMAppService.mainApp.status == .enabled
    @Published var recording = false
    var updateShortcut: ((Shortcut) -> Bool)?
    var recordingChanged: ((Bool) -> Void)?
    init() {
        let defaults = UserDefaults.standard
        first = KeyboardLayout(rawValue: defaults.string(forKey: "firstLayout") ?? "english") ?? .english
        second = KeyboardLayout(rawValue: defaults.string(forKey: "secondLayout") ?? "russian") ?? .russian
        shortcut = defaults.data(forKey: "automaticShortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .shift
    }
    var compatible: Bool { first.isCompatible(with: second) }
    func refresh() {
        trusted = AXIsProcessTrusted()
        launchEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    }
    func setLaunch(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refresh()
            if SMAppService.mainApp.status == .requiresApproval { message = "Подтвердите автозапуск в Системных настройках."; SMAppService.openSystemSettingsLoginItems() }
        } catch { refresh(); message = "Не удалось изменить автозапуск: \(error.localizedDescription)" }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func startRecording() { recording = true; message = ""; recordingChanged?(true) }
    func stopRecording() { recording = false; recordingChanged?(false) }
    func save(_ shortcut: Shortcut) {
        guard recording else { return }
        guard updateShortcut?(shortcut) == true else { message = "Не удалось назначить клавишу. Проверьте универсальный доступ или выберите другое сочетание."; return }
        self.shortcut = shortcut
        UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: "automaticShortcut")
        stopRecording()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "character.cursor.ibeam").font(.system(size: 29, weight: .medium)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TextSwitcher").font(.system(size: 22, weight: .semibold))
                    Text("Исправьте текст в другой раскладке").foregroundStyle(.secondary)
                }
            }
            GroupBox {
                VStack(spacing: 14) {
                    HStack {
                        Text("Раскладки").frame(width: 95, alignment: .leading)
                        Picker("Первая раскладка", selection: $model.first) { ForEach(KeyboardLayout.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                        Picker("Вторая раскладка", selection: $model.second) { ForEach(KeyboardLayout.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                    }
                    Divider()
                    HStack {
                        Text("Исправить раскладку")
                        Spacer()
                        Button(model.recording ? "Нажмите клавиши…" : model.shortcut.display) { model.startRecording() }
                            .font(.system(.body, design: .monospaced)).frame(minWidth: 140)
                            .accessibilityLabel("Изменить горячую клавишу")
                    }
                    Text("Есть выделение — меняется только оно. Нет выделения — всё активное поле.")
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(10)
            }
            if !model.compatible {
                Label("Выберите раскладки с разными алфавитами: иначе нельзя определить направление для каждой буквы.", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Запускать при входе в macOS", isOn: Binding(get: { model.launchEnabled }, set: { model.setLaunch($0) }))
                HStack {
                    Image(systemName: model.trusted ? "checkmark.circle.fill" : "lock.fill").foregroundStyle(model.trusted ? .green : .orange)
                    Text(model.trusted ? "Универсальный доступ разрешён" : "Нужен универсальный доступ").font(.callout)
                    Spacer()
                    if !model.trusted { Button("Разрешить…") { model.requestAccessibility() } }
                }
            }
            Text("Только буквы, с сохранением регистра. Цифры и знаки остаются как есть. Буквы на клавишах со знаками тоже не меняются.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.recording {
                Text("Нажмите и отпустите Shift, либо задайте сочетание с ⌘, ⌃, ⌥ или F1–F20. Esc — отмена.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if model.shortcut.isShift {
                Text("Shift срабатывает при коротком нажатии и отпускании. Набор заглавных букв и выделение с Shift не запускают замену.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Label("Всё обрабатывается на этом Mac", systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("1.1").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(26).frame(width: 560)
        .background(KeyRecorder(model: model).frame(width: 0, height: 0))
        .onReceive(timer) { _ in model.refresh() }
    }
}

struct KeyRecorder: NSViewRepresentable {
    let model: SettingsModel
    func makeNSView(context: Context) -> RecorderView { RecorderView(model: model) }
    func updateNSView(_ view: RecorderView, context: Context) {
        if model.recording { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
    }
    final class RecorderView: NSView {
        let model: SettingsModel
        var detector = ShiftTapDetector()
        init(model: SettingsModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            guard model.recording else { super.keyDown(with: event); return }
            detector.cancel()
            if event.keyCode == 53 { model.stopRecording(); return }
            if let shortcut = Shortcut.from(event) { model.save(shortcut) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard model.recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event); return true
        }
        override func flagsChanged(with event: NSEvent) {
            guard model.recording else { detector.cancel(); return }
            let flags = event.modifierFlags
            if detector.flagsChanged(keyCode: event.keyCode, shift: flags.contains(.shift), otherModifiers: !flags.intersection([.command, .control, .option, .function]).isEmpty, time: ProcessInfo.processInfo.systemUptime) {
                model.save(.shift)
            }
        }
    }
}
