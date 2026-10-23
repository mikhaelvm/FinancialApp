import XCTest
@testable import Trackr

private final class DriveURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class GoogleDriveBackupTests: XCTestCase {
    private func api() -> GoogleDriveAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DriveURLProtocol.self]
        return GoogleDriveAPI(session: URLSession(configuration: config))
    }
    override func tearDown() { DriveURLProtocol.handler = nil; super.tearDown() }

    func testFingerprintIgnoresExportDateAndRecordOrderButDetectsEdits() throws {
        let first = Data(#"{"createdAt":1,"transactions":[{"id":"b","amountCents":20},{"id":"a","amountCents":10}],"dismissedPayments":["b","a"]}"#.utf8)
        let second = Data(#"{"createdAt":2,"dismissedPayments":["a","b"],"transactions":[{"amountCents":10,"id":"a"},{"id":"b","amountCents":20}]}"#.utf8)
        let edited = Data(#"{"transactions":[{"id":"b","amountCents":21},{"id":"a","amountCents":10}],"dismissedPayments":["a","b"]}"#.utf8)
        XCTAssertEqual(try DriveBackupPolicy.fingerprint(first), try DriveBackupPolicy.fingerprint(second))
        XCTAssertNotEqual(try DriveBackupPolicy.fingerprint(first), try DriveBackupPolicy.fingerprint(edited))
    }

    func testListUsesOnlyPrivateAppSpaceAndFollowsPagination() async throws {
        var calls = 0
        DriveURLProtocol.handler = { request in
            calls += 1
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains { $0.name == "spaces" && $0.value == "appDataFolder" })
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-token")
            if calls == 1 { return (200, [:], Data(#"{"files":[{"id":"a","name":"Backup A"}],"nextPageToken":"next"}"#.utf8)) }
            XCTAssertTrue(query.contains { $0.name == "pageToken" && $0.value == "next" })
            return (200, [:], Data(#"{"files":[{"id":"b","name":"Backup B"}]}"#.utf8))
        }
        let files = try await api().list(token: "fake-token")
        XCTAssertEqual(files.map(\.id), ["a", "b"])
        XCTAssertEqual(calls, 2)
    }

    func testResumableUploadCreatesPrivateMetadataThenSendsJSON() async throws {
        var methods: [String] = []
        DriveURLProtocol.handler = { request in
            methods.append(request.httpMethod!)
            if request.httpMethod == "POST" {
                XCTAssertTrue(request.url!.absoluteString.contains("uploadType=resumable"))
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Upload-Content-Length"), "2")
                return (200, ["Location": "https://www.googleapis.com/upload/drive/v3/files?upload_id=fake"], Data())
            }
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (200, [:], Data(#"{"id":"backup","name":"Trackr.json","size":"2"}"#.utf8))
        }
        let file = try await api().upload(Data("{}".utf8), token: "fake-token")
        XCTAssertEqual(file.id, "backup")
        XCTAssertEqual(methods, ["POST", "PUT"])
    }

    func testUploadDoesNotSendCredentialsToUntrustedLocation() async throws {
        var calls = 0
        DriveURLProtocol.handler = { _ in
            calls += 1
            return (200, ["Location": "https://untrusted.example/upload"], Data())
        }
        do { _ = try await api().upload(Data("{}".utf8), token: "fake-token"); XCTFail("Expected invalid upload destination") }
        catch { XCTAssertEqual(calls, 1) }
    }

    func testOversizedDownloadIsRejectedBeforeNetworkAccess() async throws {
        DriveURLProtocol.handler = { _ in XCTFail("No network request expected"); return (200, [:], Data()) }
        let file = DriveBackupFile(id: "a", name: "big.json", createdTime: nil, size: "25000001")
        do { _ = try await api().download(file, token: "fake-token"); XCTFail("Expected size rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("25 MB")) }
    }

    func testAuthorizationFailureDoesNotExposeRemoteResponse() async throws {
        DriveURLProtocol.handler = { _ in (401, [:], Data("private-server-message".utf8)) }
        do { _ = try await api().list(token: "fake-token"); XCTFail("Expected authorization error") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("novamente"))
            XCTAssertFalse(error.localizedDescription.contains("private-server-message"))
        }
    }

    func testDriveTimestampSupportsFractionalSeconds() {
        XCTAssertNotNil(DriveBackupFile(id: "a", name: "backup", createdTime: "2026-10-23T12:00:00.123Z", size: nil).date)
        XCTAssertNotNil(DriveBackupFile(id: "a", name: "backup", createdTime: "2026-10-23T12:00:00Z", size: nil).date)
    }

    func testSyncDocumentsAreListedSeparatelyFromBackupVersions() async throws {
        DriveURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let filter = query.first { $0.name == "q" }?.value ?? ""
            XCTAssertTrue(filter.contains("trackrSync"))
            XCTAssertFalse(filter.contains("trackrBackup"))
            return (200, [:], Data(#"{"files":[]}"#.utf8))
        }
        _ = try await api().list(token: "fake-token", synchronization: true)
    }

    func testSyncUpdatesItsOwnDocumentWithPatchInsteadOfCreatingAnotherBackup() async throws {
        var methods: [String] = []
        DriveURLProtocol.handler = { request in
            methods.append(request.httpMethod!)
            if request.httpMethod == "PATCH" {
                XCTAssertEqual(request.url?.path, "/upload/drive/v3/files/own-document")
                return (200, ["Location": "https://www.googleapis.com/upload/drive/v3/files?upload_id=fake"], Data())
            }
            return (200, [:], Data(#"{"id":"own-document","name":"Trackr-Sync.json"}"#.utf8))
        }
        _ = try await api().upload(Data("{}".utf8), token: "fake-token", device: UUID(), updating: "own-document")
        XCTAssertEqual(methods, ["PATCH", "PUT"])
    }
}
