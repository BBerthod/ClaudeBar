import Foundation

/// Watches a file on disk for write events using a kernel-level
/// `DispatchSourceFileSystemObject`. Calls the provided closure on the
/// main queue whenever the file is written.
///
/// Usage:
/// ```swift
/// let watcher = FileWatcher()
/// watcher.watch(path: "/path/to/file") {
///     // reload the file
/// }
/// // When done:
/// watcher.stop()
/// ```
@Observable
final class FileWatcher {

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    // MARK: - Public API

    /// Starts watching `path` for write events.
    ///
    /// Calling `watch` while already watching stops the previous watch first.
    /// `onChange` is always dispatched to the **main queue**.
    func watch(path: String, onChange: @escaping () -> Void) {
        stop()

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )

        src.setEventHandler {
            DispatchQueue.main.async {
                onChange()
            }
        }

        src.setCancelHandler { [weak self] in
            if let self, self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source = src
        src.resume()
    }

    /// Stops watching and closes the file descriptor.
    func stop() {
        source?.cancel()
        source = nil
        // The cancel handler closes the fd.
    }

    deinit {
        stop()
    }
}
