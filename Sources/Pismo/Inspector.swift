import Foundation
import PismoCore

enum InspectorReport {
    private static let maxValueLength = 80
    private static let maxSummaryLength = 60

    static func describe(_ context: FocusContext, decision: LayoutDecision?) -> String {
        let target = decision.map { "→ \($0.layout) (\(describe($0.reason)))" } ?? "→ no config"
        var lines = ["\(context.appName) (\(context.bundleIdentifier ?? "no bundle id")) \(target)"]

        guard let element = context.element else {
            lines.append("  focused element: unavailable")
            return lines.joined(separator: "\n")
        }

        lines.append("  ▶ " + describe(element.attributes))
        for (index, ancestor) in element.ancestors.enumerated() {
            lines.append("  ↑\(index + 1) " + describe(ancestor))
        }
        return lines.joined(separator: "\n")
    }

    static func summarize(_ context: FocusContext) -> String {
        let attributes = context.element?.attributes
        let parts = [
            context.appName,
            attributes?.role ?? "no element",
            attributes?.placeholder ?? attributes?.description ?? attributes?.title,
        ].compactMap { $0 }
        return truncate(parts.joined(separator: " · "), to: maxSummaryLength)
    }

    static func describe(_ reason: LayoutDecision.Reason) -> String {
        switch reason {
        case .field(let name): "field \"\(name)\""
        case .app: "app rule"
        case .globalDefault: "default"
        }
    }

    static func describeLayouts(_ layouts: [InputSource]) -> String {
        let list = layouts.map { "  \($0.name) — \($0.id)" }.joined(separator: "\n")
        return "Available keyboard layouts:\n\(list)"
    }

    private static func describe(_ attributes: ElementAttributes) -> String {
        let pairs: [(String, String?)] = [
            ("role", attributes.role),
            ("subrole", attributes.subrole),
            ("roleDesc", attributes.roleDescription.map(quote)),
            ("title", attributes.title.map(quote)),
            ("desc", attributes.description.map(quote)),
            ("placeholder", attributes.placeholder.map(quote)),
            ("help", attributes.help.map(quote)),
            ("id", attributes.identifier),
            ("dom.id", attributes.domIdentifier),
            ("dom.class", attributes.domClasses.isEmpty ? nil : "[\(attributes.domClasses.joined(separator: " "))]"),
        ]
        return pairs
            .compactMap { key, value in value.map { "\(key)=\(truncate($0, to: maxValueLength))" } }
            .joined(separator: " ")
    }

    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\n", with: " "))\""
    }

    private static func truncate(_ value: String, to length: Int) -> String {
        value.count > length ? String(value.prefix(length - 1)) + "…" : value
    }
}

/// Appends inspector reports to ~/Library/Logs/Pismo/inspector.log, skipping consecutive duplicates.
final class InspectorLog {
    let fileURL: URL
    private var lastEntry: String?
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Pismo", isDirectory: true)
        fileURL = logsDirectory.appendingPathComponent("inspector.log")

        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("Pismo: cannot create log directory \(logsDirectory.path): \(error.localizedDescription)")
        }
    }

    func write(_ entry: String) {
        guard entry != lastEntry else { return }
        lastEntry = entry

        let line = "[\(timestampFormatter.string(from: Date()))] \(entry)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL)
                return
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("Pismo: cannot write inspector log: \(error.localizedDescription)")
        }
    }
}
