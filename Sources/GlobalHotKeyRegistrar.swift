import Carbon
import Foundation

final class GlobalHotKeyRegistrar {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
    }

    @discardableResult
    func register(hotKey: GlobalHotKey) -> OSStatus {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let registrar = Unmanaged<GlobalHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
                let action = registrar.action

                Task { @MainActor in
                    action()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            return handlerStatus
        }

        let hotKeyID = EventHotKeyID(signature: FourCharCode("QKIE"), id: 1)
        let registrationStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registrationStatus != noErr {
            unregister()
        }

        return registrationStatus
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }

        hotKeyRef = nil
        eventHandler = nil
    }
}

private extension FourCharCode {
    init(_ string: String) {
        self = string.utf8.reduce(0) { partialResult, character in
            (partialResult << 8) + FourCharCode(character)
        }
    }
}
