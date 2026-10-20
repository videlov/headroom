import Foundation

/// The read-only parts of claude.ai's internal web API that its usage page uses.
struct ClaudeAPI {
    /// The whole Cookie header as copied from the browser, not just sessionKey.
    let cookie: String

    enum Failure: Error, Equatable {
        case network                              // no connection, timeout
        case sessionEnded                         // 401, or a 403 from claude.ai itself: the cookie no longer works
        case http(Int)                            // any other status but 200 and 429, such as a 403 from Cloudflare
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

    /// The limits and the usage-limit resets. claude.ai's usage page reads the resets from
    /// /usage with `cedar_ember=1`; that answer has the same limits as plain /usage, and
    /// `skip_spend=1` leaves out the spend, which comes from /overage_spend_limit.
    func usage(org: String) async throws -> (snapshot: UsageSnapshot, resets: LimitResets) {
        let json = try await get("/api/organizations/\(org)/usage?cedar_ember=1&skip_spend=1")
        return (UsageSnapshot(json: json), LimitResets(json: json["cedar_ember"]))
    }

    func extraUsage(org: String) async throws -> ExtraUsage {
        ExtraUsage(json: try await get("/api/organizations/\(org)/overage_spend_limit"))
    }

    func freeCredits(org: String) async throws -> FreeCredits {
        FreeCredits(json: try await get("/api/organizations/\(org)/prepaid/credits"))
    }

    /// A cookie's value from a whole Cookie header ("a=1; lastActiveOrg=…; b=2").
    static func cookieValue(named name: String, in header: String) -> String? {
        header.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(name + "=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }

    /// What an answer other than 200 means. claude.ai answers an ended session with 403 and
    /// a JSON error (`account_session_invalid`); a 403 without one, such as a Cloudflare
    /// page, says nothing about the cookie.
    static func failure(status: Int, body: Data, retryAfter: String? = nil) -> Failure? {
        switch status {
        case 200:
            return nil
        case 401:
            return .sessionEnded
        case 403:
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            return json?["error"] != nil ? .sessionEnded : .http(403)
        case 429:
            return .rateLimited(retryAfter: retryAfter.flatMap { TimeInterval($0) })
        default:
            return .http(status)
        }
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
            (data, response) = try await HTTP.session.data(for: request)
        } catch {
            throw Failure.network
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if let failure = Self.failure(status: http.statusCode, body: data,
                                      retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
            throw failure
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalidResponse
        }
        return json
    }
}
