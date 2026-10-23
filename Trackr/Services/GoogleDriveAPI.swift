import Foundation
import CryptoKit

struct DriveBackupFile: Codable, Identifiable {
    let id: String
    let name: String
    let createdTime: String?
    let size: String?
    var date: Date? {
        guard let createdTime else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdTime) ?? ISO8601DateFormatter().date(from: createdTime)
    }
}

enum DriveBackupPolicy {
    static let scope = "https://www.googleapis.com/auth/drive.appdata"
    static let maximumBytes = 25_000_000
    static let retainedVersions = 5

    /// Ignore export time and fetch ordering when detecting financial changes.
    static func fingerprint(_ data: Data) throws -> String {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FinanceError.invalid("Backup inválido.")
        }
        object.removeValue(forKey: "createdAt")
        for key in object.keys {
            if let rows = object[key] as? [[String: Any]] {
                object[key] = rows.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
            } else if let values = object[key] as? [String] { object[key] = values.sorted() }
        }
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
}

/// Uses only the app's private Drive space. Tokens are never persisted by this client.
struct GoogleDriveAPI {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private func send(_ url: URL, token: String, method: String = "GET", body: Data? = nil,
                      contentType: String? = nil, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw FinanceError.invalid("Resposta inválida do Drive.") }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401: throw FinanceError.invalid("Sua sessão expirou. Conecte o Google Drive novamente.")
        case 403: throw FinanceError.invalid("Drive sem permissão ou espaço disponível. Confira a conta e a configuração do Google Cloud.")
        case 404: throw FinanceError.invalid("Backup não encontrado no Google Drive.")
        default: throw FinanceError.invalid("O Drive não concluiu a operação (\(http.statusCode)). Tente novamente.")
        }
    }

    private func request(_ url: URL, token: String, method: String = "GET") async throws -> Data {
        try await send(url, token: token, method: method).0
    }

    func list(token: String) async throws -> [DriveBackupFile] {
        struct Page: Decodable { let files: [DriveBackupFile]; let nextPageToken: String? }
        var files: [DriveBackupFile] = [], page: String?
        repeat {
            var url = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            url.queryItems = [URLQueryItem(name: "spaces", value: "appDataFolder"),
                             URLQueryItem(name: "q", value: "trashed = false and appProperties has { key='trackrBackup' and value='1' }"),
                             URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,createdTime,size)"),
                             URLQueryItem(name: "orderBy", value: "createdTime desc"), URLQueryItem(name: "pageSize", value: "100")]
            if let page { url.queryItems?.append(URLQueryItem(name: "pageToken", value: page)) }
            let response = try JSONDecoder().decode(Page.self, from: try await request(url.url!, token: token))
            files += response.files; page = response.nextPageToken
        } while page != nil
        return files
    }

    func upload(_ data: Data, token: String) async throws -> DriveBackupFile {
        guard data.count <= DriveBackupPolicy.maximumBytes else { throw FinanceError.invalid("O backup deve ter até 25 MB.") }
        let formatter = ISO8601DateFormatter()
        let name = "Trackr-Backup-" + formatter.string(from: .now).replacingOccurrences(of: ":", with: "-") + ".json"
        let metadata: [String: Any] = ["name": name, "mimeType": "application/json", "parents": ["appDataFolder"],
                                       "appProperties": ["trackrBackup": "1"]]
        // A resumable session also supports backups larger than the 5 MB simple-upload recommendation.
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name,createdTime,size")!
        let (_, response) = try await send(url, token: token, method: "POST",
            body: JSONSerialization.data(withJSONObject: metadata), contentType: "application/json; charset=UTF-8",
            headers: ["X-Upload-Content-Type": "application/json", "X-Upload-Content-Length": String(data.count)])
        guard let location = response.value(forHTTPHeaderField: "Location"), let destination = URL(string: location),
              destination.scheme == "https", destination.host == "www.googleapis.com", destination.path.hasPrefix("/upload/drive/") else {
            throw FinanceError.invalid("O Drive não iniciou o envio. Tente novamente.")
        }
        let (result, _) = try await send(destination, token: token, method: "PUT", body: data, contentType: "application/json")
        return try JSONDecoder().decode(DriveBackupFile.self, from: result)
    }

    func download(_ file: DriveBackupFile, token: String) async throws -> Data {
        if let size = file.size.flatMap(Int.init), size > DriveBackupPolicy.maximumBytes {
            throw FinanceError.invalid("O backup excede 25 MB.")
        }
        let data = try await request(fileURL(file.id, download: true), token: token)
        guard data.count <= DriveBackupPolicy.maximumBytes else { throw FinanceError.invalid("O backup excede 25 MB.") }
        return data
    }

    func delete(_ file: DriveBackupFile, token: String) async throws {
        _ = try await request(fileURL(file.id), token: token, method: "DELETE")
    }

    private func fileURL(_ id: String, download: Bool = false) -> URL {
        var url = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        url.path += "/" + id
        if download { url.queryItems = [URLQueryItem(name: "alt", value: "media")] }
        return url.url!
    }
}
