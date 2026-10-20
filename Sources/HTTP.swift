import Foundation

/// The network session for all of Headroom's requests. It keeps nothing on disk:
/// URLSession.shared stored claude.ai's Set-Cookie session keys in ~/Library/HTTPStorages
/// and cached each request, its Cookie header included, in ~/Library/Caches, outside the
/// Keychain. The Cookie header is set by hand, so no cookie storage is needed.
enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Deletes what URLSession.shared stored for earlier versions. Nothing writes there
    /// anymore, so after the first launch this finds nothing.
    static func removeLegacyStorage() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        for path in ["Caches/\(id)", "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies"] {
            try? FileManager.default.removeItem(at: library.appendingPathComponent(path))
        }
    }
}
