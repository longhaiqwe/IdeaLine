import Foundation
import Combine

struct Idea: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var color: Int = 0
    var createdAt = Date()
    var updatedAt = Date()
    var archived = false
}
struct Draft: Codable, Equatable {
    var id: UUID?
    var text = ""
    var color = 0
}
struct SavedState: Codable {
    var ideas: [Idea] = []
    var draft = Draft()
}
final class IdeaStore: ObservableObject {
    @Published private(set) var state = SavedState()
    @Published var error: String?
    let url: URL
    private var loadFailed = false
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IdeaLine/ideas.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: self.url)) }
            catch { self.error = "无法读取选题文件，原文件已保留：\(error.localizedDescription)"; loadFailed = true }
        }
    }
    var active: [Idea] { state.ideas.filter { !$0.archived } }
    @discardableResult func moveActive(_ id: UUID, to destination: Int) -> Bool {
        var ordered = active
        guard let source = ordered.firstIndex(where: { $0.id == id }),
              ordered.indices.contains(destination) else { return false }
        guard source != destination else { return true }
        ordered.insert(ordered.remove(at: source), at: destination)
        var next = state
        // Reorder only active slots; archived notes and the draft stay intact.
        let slots = next.ideas.indices.filter { !next.ideas[$0].archived }
        for (slot, idea) in zip(slots, ordered) { next.ideas[slot] = idea }
        return commit(next)
    }
    @discardableResult private func commit(_ next: SavedState) -> Bool {
        guard !loadFailed else { error = "请先备份并修复选题文件，再重新启动；当前不会覆盖原文件。"; return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: url, options: .atomic)
            state = next; error = nil; return true
        } catch { self.error = "保存失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func draft(_ draft: Draft) -> Bool {
        var next = state; next.draft = draft; return commit(next)
    }
    @discardableResult func hang(_ draft: Draft) -> Bool {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        var next = state
        if let id = draft.id, let i = next.ideas.firstIndex(where: { $0.id == id }) {
            next.ideas[i].text = text; next.ideas[i].color = draft.color; next.ideas[i].updatedAt = Date()
        } else { next.ideas.insert(Idea(text: text, color: draft.color), at: 0) }
        next.draft = Draft(); return commit(next)
    }
    @discardableResult func archive(_ id: UUID, _ value: Bool) -> Bool {
        var next = state
        guard let i = next.ideas.firstIndex(where: { $0.id == id }) else { return false }
        next.ideas[i].archived = value; return commit(next)
    }
    func markdown() -> String {
        "# 灵感晾台\n\n" + state.ideas.map { "## \($0.createdAt.formatted(date: .abbreviated, time: .shortened))\($0.archived ? " · 已收纳" : "")\n\n\($0.text)" }.joined(separator: "\n\n---\n\n")
    }
}
