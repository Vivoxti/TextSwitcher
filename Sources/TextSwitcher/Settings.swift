import AppKit
import SwiftUI
import ServiceManagement
import ApplicationServices
import TextSwitcherCore

final class SettingsModel: ObservableObject {
    @Published var layouts: [KeyboardLayout] = []
    @Published var unsupportedNames: [String] = []
    @Published var first: String { didSet { UserDefaults.standard.set(first, forKey: "firstSourceID") } }
    @Published var second: String { didSet { UserDefaults.standard.set(second, forKey: "secondSourceID") } }
    @Published var shortcut: Shortcut
    @Published var message: String = ""
    @Published var trusted = AXIsProcessTrusted()
    @Published var launchEnabled = SMAppService.mainApp.status == .enabled
    @Published var recording = false
    var updateShortcut: ((Shortcut) -> Bool)?
    var recordingChanged: ((Bool) -> Void)?
    private var sourcesObserver: NSObjectProtocol?
    init() {
        let defaults = UserDefaults.standard
        first = defaults.string(forKey: "firstSourceID") ?? ""
        second = defaults.string(forKey: "secondSourceID") ?? ""
        shortcut = defaults.data(forKey: "automaticShortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .shift
        refreshLayouts()
        sourcesObserver = DistributedNotificationCenter.default().addObserver(forName: SystemLayouts.changeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshLayouts() }
    }
    deinit { if let sourcesObserver { DistributedNotificationCenter.default().removeObserver(sourcesObserver) } }
    var compatible: Bool { first != second && layouts.contains { $0.id == first } && layouts.contains { $0.id == second } }
    func refreshLayouts() {
        let snapshot = SystemLayouts.enabled()
        if layouts != snapshot.layouts { layouts = snapshot.layouts }
        if unsupportedNames != snapshot.unsupportedNames { unsupportedNames = snapshot.unsupportedNames }
        let ids = Set(layouts.map(\.id))
        if !ids.contains(first) {
            first = layouts.first { $0.id == SystemLayouts.currentID && $0.id != second }?.id ?? layouts.first { $0.id != second }?.id ?? layouts.first?.id ?? ""
        }
        if !ids.contains(second) { second = layouts.first { $0.id != first }?.id ?? "" }
    }
    func converter() -> LayoutConverter? {
        refreshLayouts()
        guard compatible, let a = layouts.first(where: { $0.id == first }), let b = layouts.first(where: { $0.id == second }) else {
            message = L10n.text(.chooseTwoLayouts); return nil
        }
        let active = SystemLayouts.currentID
        let converter = LayoutConverter(first: a, second: b, activeSourceID: active)
        guard !converter.requiresDirection || active == first || active == second else { message = L10n.text(.activeLayoutRequired); return nil }
        return converter
    }
    func refresh() {
        trusted = AXIsProcessTrusted()
        launchEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    }
    func setLaunch(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refresh()
            if SMAppService.mainApp.status == .requiresApproval { message = L10n.text(.loginApproval); SMAppService.openSystemSettingsLoginItems() }
        } catch { refresh(); message = L10n.text(.loginFailed) + " " + error.localizedDescription }
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
        guard updateShortcut?(shortcut) == true else { message = L10n.text(.shortcutFailed); return }
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
                    Text(L10n.text(.subtitle)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            GroupBox {
                VStack(spacing: 14) {
                    HStack {
                        Text(L10n.text(.layouts)).fixedSize().frame(minWidth: 75, alignment: .leading)
                        Picker(L10n.text(.firstLayout), selection: $model.first) {
                            if model.first.isEmpty { Text("—").tag("") }
                            ForEach(model.layouts) { Text($0.title).tag($0.id) }
                        }.labelsHidden()
                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                        Picker(L10n.text(.secondLayout), selection: $model.second) {
                            if model.second.isEmpty { Text("—").tag("") }
                            ForEach(model.layouts) { Text($0.title).tag($0.id) }
                        }.labelsHidden()
                    }
                    Text(L10n.text(.systemLayoutsHint)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    HStack {
                        Text(L10n.text(.convert)).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(model.recording ? L10n.text(.recordShortcut) : model.shortcut.display) { model.startRecording() }
                            .font(.system(.body, design: .monospaced)).frame(minWidth: 140)
                            .accessibilityLabel(L10n.text(.changeShortcut))
                    }
                    Text(L10n.text(.automaticHint))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(10)
            }
            if !model.compatible {
                Label(L10n.text(.chooseTwoLayouts), systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !model.unsupportedNames.isEmpty {
                Text(L10n.text(.unsupportedSources) + " " + model.unsupportedNames.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L10n.text(.launchAtLogin), isOn: Binding(get: { model.launchEnabled }, set: { model.setLaunch($0) }))
                HStack {
                    Image(systemName: model.trusted ? "checkmark.circle.fill" : "lock.fill").foregroundStyle(model.trusted ? .green : .orange)
                    Text(model.trusted ? L10n.text(.accessibilityAllowed) : L10n.text(.accessibilityRequired)).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !model.trusted { Button(L10n.text(.allow)) { model.requestAccessibility() } }
                }
            }
            Text(L10n.text(.lettersHint))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.recording {
                Text(L10n.text(.recordingHint)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if model.shortcut.isShift {
                Text(L10n.text(.shiftHint)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Label(L10n.text(.localOnly), systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0").font(.caption).foregroundStyle(.tertiary)
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
