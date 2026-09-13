import Foundation
import XCTest
@testable import Playloom

final class BackgroundHTTPClientTests: XCTestCase {
    func testTransferMetadataRoundTripsWithoutResponseBytes() throws {
        let store = MemoryTransferStore()
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 41, requestBodyURL: URL(fileURLWithPath: "/private/body"),
            responseURL: URL(fileURLWithPath: "/private/response"), projectID: ProjectID(), runID: RunID(),
            operationID: OperationID(), candidateID: CandidateID(), baseRevisionID: BaseRevisionID(),
            state: .completed, responseStatus: 200, responseHeaders: ["X-Test": "ok"], errorDescription: nil)
        try store.save([record])
        let restored = try XCTUnwrap(store.load().first)
        XCTAssertEqual(restored, record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.responseURL.path))
    }

    func testRecoveryMarksMissingBackgroundTaskInterrupted() async throws {
        let store = MemoryTransferStore()
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 99, requestBodyURL: URL(fileURLWithPath: "/private/body"),
            responseURL: URL(fileURLWithPath: "/private/response"), projectID: ProjectID(), runID: RunID(),
            operationID: OperationID(), candidateID: nil, baseRevisionID: BaseRevisionID(),
            state: .running, responseStatus: nil, responseHeaders: [:], errorDescription: nil)
        try store.save([record])
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        let metadata = try await client.recover()
        XCTAssertEqual(metadata.first?.taskIdentifier, 99)
        XCTAssertEqual(metadata.first?.state, .interrupted)
    }

    func testCompletedResponseStaysDurableUntilAcknowledged() async throws {
        let store = MemoryTransferStore()
        let bodyURL = temporaryURL("body")
        let responseURL = temporaryURL("response")
        defer {
            try? FileManager.default.removeItem(at: bodyURL)
            try? FileManager.default.removeItem(at: responseURL)
        }
        try Data("request".utf8).write(to: bodyURL)
        try Data("response".utf8).write(to: responseURL)
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 17, requestBodyURL: bodyURL, responseURL: responseURL,
            projectID: ProjectID(), runID: RunID(), operationID: OperationID(),
            candidateID: nil, baseRevisionID: BaseRevisionID(), state: .completed,
            responseStatus: 200, responseHeaders: [:], errorDescription: nil
        )
        try store.save([record])
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))

        let result = try await client.waitForTransfer(taskIdentifier: record.taskIdentifier)
        XCTAssertEqual(result.data, Data("response".utf8))
        XCTAssertEqual(try store.load(), [record])
        XCTAssertTrue(FileManager.default.fileExists(atPath: responseURL.path))

        try client.acknowledgeTransfer(taskIdentifier: record.taskIdentifier)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: responseURL.path))
    }

    func testCancelledReattachedWaitMarksTransferCancelled() async throws {
        let store = MemoryTransferStore()
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 23, requestBodyURL: temporaryURL("body"), responseURL: temporaryURL("response"),
            projectID: ProjectID(), runID: RunID(), operationID: OperationID(),
            candidateID: nil, baseRevisionID: BaseRevisionID(), state: .running,
            responseStatus: nil, responseHeaders: [:], errorDescription: nil
        )
        try store.save([record])
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        let waiter = Task {
            try await client.waitForTransfer(taskIdentifier: record.taskIdentifier)
        }
        await Task.yield()
        waiter.cancel()

        do {
            _ = try await waiter.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected cancellation path.
        }
        XCTAssertEqual(client.metadata(for: record.runID).first?.state, .cancelled)
    }

    func testUploadFailsBeforeResumeWhenTransferMetadataCannotPersist() async throws {
        let client = BackgroundHTTPClient(store: ThrowingTransferStore(), session: URLSession(configuration: .ephemeral))
        let context = GenerationRequest(
            operation: .generate, projectID: ProjectID(), runID: RunID(),
            operationID: OperationID(), baseRevisionID: BaseRevisionID(), prompt: "game"
        )
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.httpMethod = "POST"

        do {
            _ = try await client.upload(for: request, body: Data("body".utf8), context: context)
            XCTFail("Expected metadata persistence failure")
        } catch is BackgroundHTTPClient.Error {
            // The request must not be allowed to proceed without durable identity.
        }
    }

    func testTransferStoreLoadFailureDoesNotStartUnjournaledUpload() async throws {
        let store = FailingLoadTransferStore()
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        let context = GenerationRequest(
            operation: .generate, projectID: ProjectID(), runID: RunID(),
            operationID: OperationID(), baseRevisionID: BaseRevisionID(), prompt: "game"
        )
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.httpMethod = "POST"

        do {
            _ = try await client.upload(for: request, body: Data("body".utf8), context: context)
            XCTFail("Expected transfer-store load failure")
        } catch is BackgroundHTTPClient.Error {
            XCTAssertFalse(store.saveCalled)
        }
    }

    private func temporaryURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "playloom-transfer-\(label)-\(UUID().uuidString)")
    }
}

private final class MemoryTransferStore: BackgroundTransferStoring, @unchecked Sendable {
    private var records: [BackgroundHTTPClient.TransferRecord] = []
    func load() throws -> [BackgroundHTTPClient.TransferRecord] { records }
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws { self.records = records }
}

private struct ThrowingTransferStore: BackgroundTransferStoring {
    func load() throws -> [BackgroundHTTPClient.TransferRecord] { [] }
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws { throw BackgroundHTTPClient.Error.persistenceFailure }
}

private final class FailingLoadTransferStore: BackgroundTransferStoring, @unchecked Sendable {
    var saveCalled = false
    func load() throws -> [BackgroundHTTPClient.TransferRecord] { throw BackgroundHTTPClient.Error.persistenceFailure }
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws { saveCalled = true }
}
