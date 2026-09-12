import Foundation
import ShazamKit
import XCTest
@testable import OfflineShazam

@MainActor
final class DeliveryTests: XCTestCase {
    func testConnectionIsStoredAndUpdatedInKeychain() throws {
        let key = "test-" + UUID().uuidString
        let store = ConnectionStore(service: key)
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: key] as CFDictionary) }
        XCTAssertNil(try store.load())
        try store.save(DeliveryConfiguration(endpoint: "https://example.com/capture", token: "first"))
        XCTAssertEqual(try ConnectionStore(service: key).load()?.token, "first")
        try store.save(DeliveryConfiguration(endpoint: "https://example.com/capture", token: "second"))
        XCTAssertEqual(try ConnectionStore(service: key).load()?.token, "second")
    }

    func testActualUploadResponseDrivesPersistentAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        let record = CaptureRecord()
        store.context.insert(record)
        try store.matched(record, metadata: MatchMetadata(title: "Example Song", artist: "Example Artist"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CaptureHTTPStub.self]
        let received = expectation(description: "persisted receipt")
        CaptureHTTPStub.reply = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.httpMethod, "POST")
            return Data("{\"ok\":true,\"capture_id\":\"\(record.id)\",\"isrc\":\"XX0000000001\"}".utf8)
        }
        let service = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"),
                                      connection: { try DeliveryConfiguration(endpoint: "https://example.com/capture", token: "test-token") },
                                      sessionConfiguration: configuration)
        service.onChange = { if record.state == .delivered { received.fulfill() } }
        try await service.enqueue()
        await fulfillment(of: [received], timeout: 5)
        XCTAssertEqual(record.state, .delivered)
        let reopened = try CaptureStore(directory: directory)
        XCTAssertEqual(try reopened.records().first?.state, .delivered)
        service.session.finishTasksAndInvalidate()
    }
}

import Security

final class CaptureHTTPStub: URLProtocol, @unchecked Sendable {
    static var reply: ((URLRequest) -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.reply!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
