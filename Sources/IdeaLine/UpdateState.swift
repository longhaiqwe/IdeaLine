import Foundation

struct UpdateConfiguration {
    let problem: String?
    var isReady: Bool { problem == nil }

    init(info: [String: Any]) {
        guard let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty else {
            problem = "此版本尚未接入更新服务。请等待提供更新服务的发行版；现有选题和草稿仍可正常使用。"
            return
        }
        guard let url = URLComponents(string: feed), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.url != nil, let bytes = Data(base64Encoded: key), bytes.count == 32 else {
            problem = "此版本的更新配置无效，请联系发布者获取修复后的安装包。"
            return
        }
        problem = nil
    }
}

struct UpdateMenuState {
    var isReady: Bool
    var canCheck = true
    var automaticChecks = false
    var automaticDownloads = false
    var allowsAutomaticUpdates = false
    var availableVersion: String?

    var canSelectCheck: Bool { !isReady || canCheck || availableVersion != nil }
    var canToggleChecks: Bool { isReady }
    var canToggleDownloads: Bool { isReady && automaticChecks && allowsAutomaticUpdates }
    var actionTitle: String { availableVersion.map { "更新至 \($0)…" } ?? "检查更新…" }
    var symbolName: String { availableVersion == nil ? "wind" : "arrow.down.circle" }
}
