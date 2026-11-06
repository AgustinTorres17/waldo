import AppKit
import Foundation
import os
import UniformTypeIdentifiers

/// Saved chats, on this Mac only: one folder per chat with `chat.json` and its
/// captures as PNGs, in ~/Library/Application Support/Waldo/Chats.
struct ChatStore: Sendable {
    let directory: URL
    private let log = Logger(subsystem: "com.agustintorres.waldo", category: "chats")

    static let standard = ChatStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Waldo/Chats", isDirectory: true))

    private func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func imageURL(_ id: UUID, in chat: UUID) -> URL {
        folder(for: chat).appendingPathComponent("\(id.uuidString).png")
    }

    /// Every chat without its captures (they load when a chat is opened), newest first.
    func loadAll() -> [ChatConversation] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        let chats = folders.compactMap { folder -> ChatConversation? in
            let file = folder.appendingPathComponent("chat.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            do {
                return try decoder.decode(ChatConversation.self, from: data)
            } catch {
                log.error("Couldn't read \(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return chats.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The chat with its captures loaded; a capture that can't be read stays nil.
    func loadImages(of chat: ChatConversation) -> ChatConversation {
        var chat = chat
        for index in chat.turns.indices where chat.turns[index].image == nil {
            guard let id = chat.turns[index].imageID,
                  let source = CGImageSourceCreateWithURL(imageURL(id, in: chat.id) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            chat.turns[index].image = ChatImage(image, id: id)
        }
        return chat
    }

    /// Writes the chat and any capture not saved yet.
    func save(_ chat: ChatConversation) {
        let folder = folder(for: chat.id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for turn in chat.turns {
                guard let image = turn.image else { continue }
                let url = imageURL(image.id, in: chat.id)
                guard !FileManager.default.fileExists(atPath: url.path),
                      let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
                else { continue }
                CGImageDestinationAddImage(destination, image.preview, nil)
                CGImageDestinationFinalize(destination)
            }
            let data = try JSONEncoder().encode(chat)
            try data.write(to: folder.appendingPathComponent("chat.json"), options: .atomic)
        } catch {
            log.error("Couldn't save chat: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
