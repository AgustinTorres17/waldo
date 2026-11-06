import CryptoKit
import Foundation
import os

/// Downloads, verifies and deletes curated models. One download at a time.
@MainActor
final class ModelDownloader: ObservableObject {
    enum State: Equatable {
        case notInstalled
        case downloading(Double)
        case verifying
        case installed
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]
    private var task: Task<Void, Never>?
    private let log = Logger(subsystem: "com.agustintorres.waldo", category: "models")

    /// Called after a model is installed or deleted.
    var onChange: (() -> Void)?

    init() {
        refresh()
    }

    func state(of model: ModelInfo) -> State {
        states[model.id] ?? .notInstalled
    }

    var isBusy: Bool {
        states.values.contains { if case .downloading = $0 { true } else { $0 == .verifying } }
    }

    func refresh() {
        for model in ModelCatalog.all + ModelCatalog.projectors where !isActive(states[model.id]) {
            states[model.id] = ModelCatalog.isInstalled(model) ? .installed : .notInstalled
        }
    }

    func download(_ model: ModelInfo) {
        guard !isBusy else { return }
        states[model.id] = .downloading(0)
        task = Task { [weak self] in
            do {
                try await self?.performDownload(model)
                self?.states[model.id] = .installed
                self?.onChange?()
            } catch is CancellationError {
                self?.states[model.id] = .notInstalled
            } catch let error as URLError where error.code == .cancelled {
                self?.states[model.id] = .notInstalled
            } catch {
                self?.log.error("Download of \(model.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                self?.states[model.id] = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func delete(_ model: ModelInfo) {
        try? FileManager.default.removeItem(at: ModelCatalog.fileURL(for: model))
        states[model.id] = .notInstalled
        onChange?()
    }

    private func isActive(_ state: State?) -> Bool {
        switch state {
        case .downloading, .verifying: true
        default: false
        }
    }

    private func performDownload(_ model: ModelInfo) async throws {
        let directory = ModelCatalog.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(model.fileName + ".partial")
        try? FileManager.default.removeItem(at: partial)

        let transfer = Transfer(url: model.downloadURL, destination: partial) { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.states[model.id] else { return }
                self.states[model.id] = .downloading(fraction)
            }
        }
        do {
            try await withTaskCancellationHandler {
                try await transfer.run()
            } onCancel: {
                transfer.cancel()
            }
            try await verifyAndInstall(model, partial: partial)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    private func verifyAndInstall(_ model: ModelInfo, partial: URL) async throws {
        states[model.id] = .verifying
        let hashing = Task.detached(priority: .utility) { try Self.sha256(of: partial) }
        let digest = try await withTaskCancellationHandler { try await hashing.value } onCancel: { hashing.cancel() }
        guard digest == model.sha256 else { throw DownloadError.checksumMismatch }
        let destination = ModelCatalog.fileURL(for: model)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        log.info("Installed \(model.id, privacy: .public)")
    }

    /// Streams the file in 8 MB chunks so a multi-GB model isn't read into memory.
    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 * 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    enum DownloadError: LocalizedError {
        case server(Int)
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .server(let status): "The server answered with status \(status)."
            case .checksumMismatch: "The downloaded file is corrupted (checksum mismatch). Try again."
            }
        }
    }
}

/// One URLSession download into `destination`, reporting progress in 0.5% steps.
private final class Transfer: @unchecked Sendable {
    private let url: URL
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var isCancelled = false

    init(url: URL, destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.url = url
        self.destination = destination
        self.onProgress = onProgress
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let destination = destination
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                if let error { return continuation.resume(throwing: error) }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let location else {
                    return continuation.resume(throwing: ModelDownloader.DownloadError.server(status))
                }
                // The system deletes `location` when this handler returns.
                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            var lastReported = -1.0
            let onProgress = onProgress
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let fraction = progress.fractionCompleted
                guard fraction - lastReported >= 0.005 || fraction >= 1 else { return }
                lastReported = fraction
                onProgress(fraction)
            }
            let cancelledEarly = lock.withLock {
                self.task = task
                self.observation = observation
                return isCancelled
            }
            cancelledEarly ? task.cancel() : task.resume()
        }
        lock.withLock { observation = nil }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            return task
        }?.cancel()
    }
}
