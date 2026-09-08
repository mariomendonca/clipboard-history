import Carbon
import Foundation

enum GlobalShortcutOption: String, CaseIterable, Identifiable {
    static let defaultsKey = "globalShortcutOption"

    case controlOptionV
    case controlOptionH
    case controlOptionC

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .controlOptionV: "Control + Option + V"
        case .controlOptionH: "Control + Option + H"
        case .controlOptionC: "Control + Option + C"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .controlOptionV: UInt32(kVK_ANSI_V)
        case .controlOptionH: UInt32(kVK_ANSI_H)
        case .controlOptionC: UInt32(kVK_ANSI_C)
        }
    }

    static var current: GlobalShortcutOption {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey)
        return rawValue.flatMap(GlobalShortcutOption.init(rawValue:)) ?? .controlOptionV
    }
}

final class GlobalShortcutMonitor {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: () -> Void
    private(set) var isRegistered = false

    init(option: GlobalShortcutOption, action: @escaping () -> Void) {
        self.action = action
        isRegistered = register(option: option)
    }

    deinit {
        stop()
    }

    func stop() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func register(option: GlobalShortcutOption) -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    monitor.action()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        guard installStatus == noErr else { return false }

        let identifier = EventHotKeyID(signature: 0x43484B59, id: 1)
        let modifiers = UInt32(controlKey | optionKey)
        let registerStatus = RegisterEventHotKey(
            option.keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else {
            stop()
            return false
        }
        return true
    }
}
