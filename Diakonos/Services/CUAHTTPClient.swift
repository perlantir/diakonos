import Foundation

/// Thin client over the cuabot HTTP API exposed by `npx cuabot --serve`.
///
/// Verified surface (Phase 2 discovery):
///   GET  /status                 → {ok, ready, container, containerPort, playwright}
///   POST /bash       {command}   → {stdout, stderr}
///   POST /screenshot             → image bytes
///   POST /click,/type,/key,…     → GUI driving primitives
///
/// No PTY-stream endpoint exists — Diakonos uses `docker exec -it <container>`
/// against the underlying container for interactive shells. See PTYBridge.
struct CUAHTTPClient: Sendable {
    let baseURL: URL

    init(port: Int = 7842) {
        self.baseURL = URL(string: "http://localhost:\(port)")!
    }

    struct StatusResponse: Decodable, Sendable {
        let ok: Bool
        let ready: Bool
        let container: String?
        let containerPort: Int?
        let playwright: String?
    }

    func status() async throws -> StatusResponse {
        let url = baseURL.appendingPathComponent("status")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    /// Returns nil if the server is unreachable (used during startup polling).
    func tryStatus() async -> StatusResponse? {
        try? await status()
    }

    struct BashResponse: Decodable, Sendable {
        let stdout: String?
        let stderr: String?
        let error: String?
    }

    func runBash(_ command: String) async throws -> BashResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("bash"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["command": command])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(BashResponse.self, from: data)
    }
}
