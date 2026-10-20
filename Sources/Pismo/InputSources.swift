import Carbon

struct InputSource: Equatable {
    let id: String
    let name: String

    /// Config files may refer to a layout by its display name or its input source id.
    func matches(_ reference: String) -> Bool {
        reference == id || reference == name
    }
}

enum InputSourceError: LocalizedError {
    case notFound(String)
    case selectionFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .notFound(let reference): "Keyboard layout \"\(reference)\" is not enabled in System Settings"
        case .selectionFailed(let reference, let status): "Cannot switch to \"\(reference)\" (error \(status))"
        }
    }
}

enum InputSources {
    static func selectableKeyboardLayouts() -> [InputSource] {
        selectableSources().compactMap(makeInputSource)
    }

    static func current() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return makeInputSource(source)
    }

    /// Selects the layout unless it is already active. Returns true when the layout changed.
    @discardableResult
    static func select(_ reference: String) throws -> Bool {
        if let current = current(), current.matches(reference) { return false }

        guard let source = selectableSources().first(where: { makeInputSource($0)?.matches(reference) == true }) else {
            throw InputSourceError.notFound(reference)
        }

        let status = TISSelectInputSource(source)
        guard status == noErr else { throw InputSourceError.selectionFailed(reference, status) }
        return true
    }

    private static func selectableSources() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    private static func makeInputSource(_ source: TISInputSource) -> InputSource? {
        guard let id = stringProperty(source, kTISPropertyInputSourceID),
              let name = stringProperty(source, kTISPropertyLocalizedName) else { return nil }
        return InputSource(id: id, name: name)
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
