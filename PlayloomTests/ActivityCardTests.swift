import SwiftUI
import UIKit
import XCTest
@testable import Playloom

@MainActor
final class ActivityCardTests: XCTestCase {
    func testActiveCardShowsPlainSummaryAndRecordedDetails() throws {
        let runID = RunID()
        let activity = try XCTUnwrap(GenerationActivity(events: [
            event(runID: runID, kind: .runCreated, summary: "Run created", detail: nil, lifecycle: .foreground, stage: .planning),
            event(runID: runID, kind: .stageStarted, summary: "Generating your game", detail: "Contacting the selected provider.", lifecycle: .foreground, stage: .generating)
        ]))

        XCTAssertEqual(activity.collapsedSummary, "Generating your game")
        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(activity.events.count, 2)

        let host = UIHostingController(rootView: ActivityCard(activity: activity, onStop: {}))
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
    }

    func testCompletedCardShowsPlayableStateWithoutActiveControls() throws {
        let runID = RunID()
        let activity = try XCTUnwrap(GenerationActivity(events: [
            event(runID: runID, kind: .stageFinished, summary: "Basic runtime passed", detail: "The universal runtime checks passed.", lifecycle: .foreground, stage: .checking),
            event(runID: runID, kind: .completed, summary: "Playable", detail: "Basic runtime passed.", lifecycle: .completed, stage: .checking)
        ]))

        XCTAssertEqual(activity.collapsedSummary, "Playable")
        XCTAssertFalse(activity.isActive)

        let host = UIHostingController(rootView: ActivityCard(activity: activity, onStop: {}))
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
    }

    func testInterruptedCardIsNotPresentedAsStillRunning() throws {
        let runID = RunID()
        let activity = try XCTUnwrap(GenerationActivity(events: [
            event(runID: runID, kind: .lifecycleChanged, summary: "Generation status unknown after force-quit", detail: "The response could not be confirmed after force-quit.", lifecycle: .forceQuitUnknown, stage: .generating)
        ]))

        XCTAssertEqual(activity.collapsedSummary, "Generation status unknown after force-quit")
        XCTAssertFalse(activity.isActive)

        let host = UIHostingController(rootView: ActivityCard(activity: activity, onStop: {}))
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
    }

    private func event(
        runID: RunID,
        kind: GenerationEventKind,
        summary: String,
        detail: String?,
        lifecycle: RunLifecycle?,
        stage: GenerationStage?
    ) -> GenerationEvent {
        GenerationEvent(
            id: UUID(), timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            projectID: ProjectID(), runID: runID, candidateID: CandidateID(), operationID: OperationID(),
            baseRevisionID: BaseRevisionID(), kind: kind, lifecycle: lifecycle, stage: stage,
            summary: summary, detail: detail, check: nil, fileDiff: nil, retryRound: nil,
            durationMilliseconds: nil, usage: nil, backgroundTransfer: nil
        )
    }
}
