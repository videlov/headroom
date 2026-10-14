import Foundation

/// The read-only parts of claude.ai's internal web API that its usage page uses.
struct ClaudeAPI {
    /// The whole Cookie header as copied from the browser, not just sessionKey.
    let cookie: String

    enum Failure: Error {
        case network                              // no connection, timeout
        case http(Int)                            // any status but 200 and 429
        case rateLimited(retryAfter: TimeInterval?)
        case invalidResponse                      // not HTTP, or not a JSON object
        case noOrganization                       // neither the cookie nor /api/bootstrap names one
    }

    /// The organization from the cookie's `lastActiveOrg`, else from /api/bootstrap.
    func organizationID() async throws -> String {
        if let id = Self.cookieValue(named: "lastActiveOrg", in: cookie), !id.isEmpty {
            return id
        }
        let json = try await get("/api/bootstrap")
        guard let account = json["account"] as? [String: Any],
              let id = account["lastActiveOrgId"] as? String else { throw Failure.noOrganization }
        return id
    }

    func usage(org: String) async throws -> UsageSnapshot {
        UsageSnapshot(json: try await get("/api/organizations/\(org)/usage"))
    }

    func extraUsage(org: String) async throws -> ExtraUsage {
        ExtraUsage(json: try await get("/api/organizations/\(org)/overage_spend_limit"))
    }

    func freeCredits(org: String) async throws -> FreeCredits {
        FreeCredits(json: try await get("/api/organizations/\(org)/prepaid/credits"))
    }

    /// claude.ai's usage page reads the resets from /usage with `cedar_ember=1`.
    func limitResets(org: String) async throws -> LimitResets {
        LimitResets(json: try await get("/api/organizations/\(org)/usage?cedar_ember=1&skip_spend=1")["cedar_ember"])
    }

    /// A cookie's value from a whole Cookie header ("a=1; lastActiveOrg=…; b=2").
    static func cookieValue(named name: String, in header: String) -> String? {
        header.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(name + "=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private func get(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://claude.ai" + path) else { throw Failure.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.network
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if http.statusCode == 429 {
            throw Failure.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) })
        }
        guard http.statusCode == 200 else { throw Failure.http(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalidResponse
        }
        return json
    }
}
