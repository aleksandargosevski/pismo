import Foundation
import PismoCore

/// Loads ~/.config/pismo/rules.json and reloads it whenever it changes on disk.
/// An invalid file keeps the last valid config active and reports the error.
final class ConfigStore {
    enum State {
        case loaded(Config)
        case failed(Error, lastValid: Config?)
    }

    let fileURL: URL
    var onChange: ((State) -> Void)?
    private(set) var state: State = .failed(CocoaError(.fileNoSuchFile), lastValid: nil)

    var isValid: Bool {
        if case .loaded = state { return true }
        return false
    }

    var config: Config? {
        switch state {
        case .loaded(let config): config
        case .failed(_, let lastValid): lastValid
        }
    }

    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?
    private var lastLoadedData: Data?
    private let reloadDebounce: TimeInterval = 0.2

    private static let defaultContents = """
    {
      "default": "ABC",
      "apps": {}
    }

    """

    init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pismo/rules.json")
    }

    func start() {
        createDefaultFileIfMissing()
        reload(force: true)
        watchFiles()
    }

    func reload(force: Bool = false) {
        do {
            let data = try Data(contentsOf: fileURL)
            guard force || data != lastLoadedData else { return }
            lastLoadedData = data
            state = .loaded(try Config.parse(data))
        } catch {
            NSLog("Pismo: \(error.localizedDescription)")
            state = .failed(error, lastValid: config)
        }
        onChange?(state)
    }

    /// Applies an edit to the config file. Refuses to touch a file that currently fails to parse,
    /// so hand-written content is never overwritten.
    func update(_ edit: (inout ConfigDocument) throws -> Void) throws {
        let data = try Data(contentsOf: fileURL)
        var document = try ConfigDocument.parse(data)
        try edit(&document)
        _ = try document.compile()
        try document.serialized().write(to: fileURL, atomically: true, encoding: .utf8)
        reload(force: true)
    }

    private func createDefaultFileIfMissing() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.defaultContents.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Pismo: cannot create default config at \(fileURL.path): \(error.localizedDescription)")
        }
    }

    /// Some editors save by replacing the file (seen as a directory change), others write in place
    /// (seen on the file itself), so both are watched. The file watcher is re-created after each
    /// change because a replaced file has a new inode.
    private func watchFiles() {
        directoryWatcher = makeWatcher(path: fileURL.deletingLastPathComponent().path, events: .write)
        watchConfigFile()
    }

    private func watchConfigFile() {
        fileWatcher?.cancel()
        fileWatcher = makeWatcher(path: fileURL.path, events: [.write, .delete, .rename, .extend])
    }

    private func makeWatcher(path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("Pismo: cannot watch \(path); use Reload Config after editing")
            return nil
        }

        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        watcher.setEventHandler { [weak self] in self?.scheduleReload() }
        watcher.setCancelHandler { close(descriptor) }
        watcher.resume()
        return watcher
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.watchConfigFile()
            self?.reload()
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + reloadDebounce, execute: work)
    }
}
