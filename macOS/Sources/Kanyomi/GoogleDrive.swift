import Foundation
import AppKit
import Security
import CryptoKit
import Network

struct Keychain {
    static func get(_ key: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "SimpleReaderMac", kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }; return result as? Data
    }
    static func set(_ key: String, data: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "SimpleReaderMac", kSecAttrAccount as String: key]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound { var add = query; add[kSecValueData as String] = data; guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw ReaderError.message("Could not save Google credentials in Keychain") } }
        else if status != errSecSuccess { throw ReaderError.message("Keychain error: \(status)") }
    }
    static func remove(_ key: String) { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "SimpleReaderMac", kSecAttrAccount as String: key] as CFDictionary) }
}
struct GoogleToken: Codable { var access: String; var refresh: String; var expiry: Date }
@MainActor final class GoogleAuthorization: ObservableObject {
    @Published var clientID: String
    @Published var clientSecret: String
    @Published var connected = false
    private var token: GoogleToken?
    private var callback: OAuthLoopback?
    init() {
        clientID = UserDefaults.standard.string(forKey: "SimpleReaderGoogleClient") ?? ""
        clientSecret = ""
        // Credentials are read only on a user-initiated connection or sync.
    }
    func loadCredentials() { if token == nil, let data = Keychain.get("GoogleToken"), let value = try? JSONDecoder().decode(GoogleToken.self, from: data) { token = value; connected = true }; if clientSecret.isEmpty, let data = Keychain.get("GoogleSecret") { clientSecret = String(data: data, encoding: .utf8) ?? "" } }
    func connect() async throws {
        guard !clientID.trimmingCharacters(in: .whitespaces).isEmpty else { throw ReaderError.message("Enter a Google OAuth Desktop client ID") }
        UserDefaults.standard.set(clientID, forKey: "SimpleReaderGoogleClient")
        if !clientSecret.isEmpty { try Keychain.set("GoogleSecret", data: Data(clientSecret.utf8)) }
        var random = [UInt8](repeating: 0, count: 32); guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw ReaderError.message("Could not generate authorization verifier") }
        let verifier = base64URL(Data(random)); let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = UUID().uuidString
        let loop = OAuthLoopback(); callback = loop; defer { callback = nil }
        let redirect = try await loop.start()
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = ["client_id": clientID, "redirect_uri": redirect, "response_type": "code", "scope": "https://www.googleapis.com/auth/drive.file", "access_type": "offline", "prompt": "consent", "code_challenge": challenge, "code_challenge_method": "S256", "state": state].map { URLQueryItem(name: $0.key, value: $0.value) }
        let code = try await loop.authorize(url.url!, state: state)
        let obj = try await exchange(["client_id": clientID, "client_secret": clientSecret, "code": code, "code_verifier": verifier, "redirect_uri": redirect, "grant_type": "authorization_code"])
        guard let access = obj["access_token"] as? String, let refresh = obj["refresh_token"] as? String else { throw ReaderError.message("Google did not return offline credentials") }
        token = GoogleToken(access: access, refresh: refresh, expiry: Date().addingTimeInterval(obj["expires_in"] as? Double ?? 3600)); try persist(); connected = true
    }
    func cancel() { callback?.cancel() }
    func disconnect() { cancel(); token = nil; connected = false; Keychain.remove("GoogleToken"); Keychain.remove("GoogleSecret"); clientSecret = "" }
    func accessToken(force: Bool = false) async throws -> String {
        loadCredentials()
        guard let token else { throw ReaderError.message("Connect Google Drive first") }
        if !force && token.expiry.timeIntervalSinceNow > 60 { return token.access }
        let obj = try await exchange(["client_id": clientID, "client_secret": clientSecret, "refresh_token": token.refresh, "grant_type": "refresh_token"])
        guard let access = obj["access_token"] as? String else { throw ReaderError.message("Google access token refresh failed. Reconnect Google Drive.") }
        self.token = GoogleToken(access: access, refresh: token.refresh, expiry: Date().addingTimeInterval(obj["expires_in"] as? Double ?? 3600)); try persist(); return access
    }
    private func persist() throws { if let token { try Keychain.set("GoogleToken", data: JSONEncoder().encode(token)) } }
    private func exchange(_ fields: [String: String]) async throws -> [String: Any] {
        var query = URLComponents(); query.queryItems = fields.filter { !$0.value.isEmpty }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!); request.httpMethod = "POST"; request.timeoutInterval = 30; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = Data((query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ReaderError.message(obj["error_description"] as? String ?? "Google authorization failed") }; return obj
    }
    private func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
@MainActor final class OAuthLoopback {
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<String, Error>?
    private var authContinuation: CheckedContinuation<String, Error>?
    private var state = ""
    private var timeout: Task<Void, Never>?
    func start() async throws -> String {
        let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters); self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
        listener.stateUpdateHandler = { [weak self] status in Task { @MainActor in
            guard let self else { return }
            if case .ready = status, let port = self.listener?.port { self.startContinuation?.resume(returning: "http://127.0.0.1:\(port.rawValue)/oauth"); self.startContinuation = nil }
            if case .failed(let error) = status { self.startContinuation?.resume(throwing: error); self.startContinuation = nil; self.finish(.failure(error)) }
        } }
        return try await withCheckedThrowingContinuation { continuation in startContinuation = continuation; listener.start(queue: .main) }
    }
    func authorize(_ url: URL, state: String) async throws -> String {
        self.state = state
        timeout = Task { try? await Task.sleep(nanoseconds: 180_000_000_000); if !Task.isCancelled { finish(.failure(ReaderError.message("Google sign-in timed out"))) } }
        return try await withCheckedThrowingContinuation { continuation in authContinuation = continuation; NSWorkspace.shared.open(url) }
    }
    func cancel() { finish(.failure(ReaderError.message("Google sign-in cancelled"))) }
    private func finish(_ result: Result<String, Error>) { authContinuation?.resume(with: result); authContinuation = nil; listener?.cancel(); listener = nil; timeout?.cancel(); timeout = nil }
    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in Task { @MainActor in
            guard let self, let data, let request = String(data: data, encoding: .utf8), let first = request.components(separatedBy: "\r\n").first else { connection.cancel(); return }
            let pieces = first.split(separator: " ")
            guard pieces.count >= 2, pieces[0] == "GET", let url = URLComponents(string: "http://127.0.0.1" + pieces[1]), url.path == "/oauth" else { connection.cancel(); return }
            let values = (url.queryItems ?? []).reduce(into: [String: String]()) { $0[$1.name] = $1.value ?? "" }
            guard values["state"] == self.state else { connection.cancel(); return }
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><body><h2>Return to Kanyomi</h2>You can close this window.</body></html>"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if let code = values["code"] { self.finish(.success(code)) } else { self.finish(.failure(ReaderError.message(values["error"] ?? "Google sign-in failed"))) }
        } }
    }
}
struct DriveFile: Codable, Identifiable, Hashable { var id: String; var name: String }
struct DriveFilePage: Decodable { var files: [DriveFile]; var nextPageToken: String? }
struct GoogleDriveClient {
    let auth: GoogleAuthorization
    func request(_ url: URL, method: String = "GET", body: Data? = nil, contentType: String? = nil, retry: Bool = true) async throws -> Data {
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 90
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReaderError.message("Invalid Google Drive response") }
        if http.statusCode == 401 && retry { _ = try await auth.accessToken(force: true); return try await self.request(url, method: method, body: body, contentType: contentType, retry: false) }
        guard (200..<300).contains(http.statusCode) else { let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]; let error = obj?["error"] as? [String: Any]; throw ReaderError.message(error?["message"] as? String ?? "Google Drive HTTP \(http.statusCode)") }; return data
    }
    func list(_ query: String) async throws -> [DriveFile] {
        var token: String?; var files: [DriveFile] = []
        repeat {
            var url = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!; url.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "fields", value: "nextPageToken,files(id,name)"), URLQueryItem(name: "pageSize", value: "1000")]
            if let token { url.queryItems?.append(URLQueryItem(name: "pageToken", value: token)) }
            let page = try JSONDecoder().decode(DriveFilePage.self, from: await request(url.url!)); files += page.files; token = page.nextPageToken
        } while token != nil
        return files
    }
    func folder(_ name: String, parent: String = "root", create: Bool = true) async throws -> String {
        func escaped(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") }
        let files = try await list("trashed=false and '\(escaped(parent))' in parents and mimeType='application/vnd.google-apps.folder' and name='\(escaped(name))'")
        if let file = files.first { return file.id }
        guard create else { throw ReaderError.message("No ッツ folder found for \(name)") }
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [parent]])
        let data = try await request(URL(string: "https://www.googleapis.com/drive/v3/files")!, method: "POST", body: body, contentType: "application/json")
        return try JSONDecoder().decode(DriveFile.self, from: data).id
    }
    func children(_ folder: String) async throws -> [DriveFile] { try await list("trashed=false and '\(folder)' in parents and mimeType!='application/vnd.google-apps.folder'") }
    func download(_ file: DriveFile) async throws -> Data { try await request(URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!) }
    func upload(_ data: Data, name: String, mime: String, folder: String, replacing: DriveFile? = nil) async throws {
        let boundary = UUID().uuidString
        let metadata: [String: Any] = replacing == nil ? ["name": name, "parents": [folder]] : ["name": name]
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=utf-8\r\n\r\n".utf8)
        body.append(try JSONSerialization.data(withJSONObject: metadata)); body.append(Data("\r\n--\(boundary)\r\nContent-Type: \(mime)\r\n\r\n".utf8)); body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let path = replacing.map { "/\($0.id)" } ?? ""
        _ = try await request(URL(string: "https://www.googleapis.com/upload/drive/v3/files\(path)?uploadType=multipart")!, method: replacing == nil ? "POST" : "PATCH", body: body, contentType: "multipart/related; boundary=\(boundary)")
    }
}
