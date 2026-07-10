import Foundation
import CoreServices

/// A minimal FSEvents-based directory watcher. We watch the config file's *parent
/// directory* (not the file) so that atomic saves — write-temp-then-rename, the way most
/// editors save — are reliably caught, which a bare kqueue on the file would miss.
///
/// FSEvents is push-based: zero cost when nothing changes. This is the efficiency pillar
/// applied even to config reloading.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let directory: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.fadeo.filewatcher")

    init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }
        let paths = [directory.path] as CFArray
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,  // latency: coalesce bursts of writes into one callback
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
