import XCTest
@testable import OuraApp

final class ModuleTests: XCTestCase {
    private func manifest(_ changes: [String: Any] = [:]) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ModuleManifest.exampleJSON.utf8)) as? [String: Any])
        object.merge(changes) { _, new in new }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testManifestDecodesDocumentedFormat() throws {
        let result = try ModuleManifest.decode(Data(ModuleManifest.exampleJSON.utf8))
        XCTAssertEqual(result.id, "community.example.ring")
        XCTAssertEqual(result.permissions, [.bluetooth, .localStorage])
    }

    func testManifestRejectsBuiltinIdentityAndPathLikeIdentifiers() throws {
        for id in [ModuleManifest.ouraID, "../../oura", "Community.Ring", "ring", "https://ring.example"] {
            XCTAssertThrowsError(try ModuleManifest.decode(manifest(["id": id])), id)
        }
    }

    func testManifestRejectsUnknownAndDuplicatePermissions() throws {
        XCTAssertThrowsError(try ModuleManifest.decode(manifest(["permissions": ["execute-code"]])))
        XCTAssertThrowsError(try ModuleManifest.decode(manifest(["permissions": ["bluetooth", "bluetooth"]])))
        // Network is declarative metadata to inspect, never an executable permission.
        let network = try ModuleManifest.decode(manifest(["permissions": ["network"]]))
        XCTAssertEqual(network.permissions, [.network])
    }

    func testManifestRejectsUnsupportedSchemaAndVersions() throws {
        XCTAssertThrowsError(try ModuleManifest.decode(manifest(["schemaVersion": 2])))
        for version in ["latest", "1", "1.0", "1.0.0-beta", "1.0.0/../../code", "99999.0.0"] {
            XCTAssertThrowsError(try ModuleManifest.decode(manifest(["version": version])), version)
        }
    }

    func testManifestRejectsOversizedAndUnexpectedFields() throws {
        let oversized = Data(repeating: 0x20, count: ModuleManifest.maximumBytes + 1)
        XCTAssertThrowsError(try ModuleManifest.decode(oversized))
        XCTAssertThrowsError(try ModuleManifest.decode(manifest(["entrypoint": "https://example.com/code.js"])))
        XCTAssertThrowsError(try ModuleManifest.decode(manifest(["name": String(repeating: "x", count: 81)])))
        XCTAssertThrowsError(try ModuleManifest.decode(manifest(["description": " "])))
        XCTAssertThrowsError(try ModuleManifest.decode(manifest(["author": "someone\u{0}else"])))
    }

    @MainActor
    func testModuleChoiceRequiresOptInAndPersistsWithoutActivatingImportedManifests() throws {
        let suite = "ModuleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleStore(defaults: defaults)
        XCTAssertFalse(store.ouraEnabled)
        let imported = try store.importManifest(data: manifest())
        XCTAssertFalse(store.ouraEnabled)
        XCTAssertThrowsError(try store.importManifest(data: manifest()))
        store.ouraEnabled = true
        let restored = ModuleStore(defaults: defaults)
        XCTAssertTrue(restored.ouraEnabled)
        XCTAssertEqual(restored.manifests, [imported])
        restored.remove(id: imported.id)
        XCTAssertTrue(ModuleStore(defaults: defaults).manifests.isEmpty)
    }

    @MainActor
    func testModuleLibraryHasBoundedCapacity() throws {
        let suite = "ModuleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleStore(defaults: defaults)
        for index in 0..<20 {
            _ = try store.importManifest(data: manifest(["id": "community.ring\(index)"]))
        }
        XCTAssertThrowsError(try store.importManifest(data: manifest(["id": "community.one-more"])))
        XCTAssertEqual(store.manifests.count, 20)
    }
}

final class SummaryRefreshPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day = "2026-10-21"
    private let offset = -10_800

    private func needs(_ policy: SummaryRefreshPolicy, after seconds: TimeInterval,
                       hasSummary: Bool = true, day: String = "2026-10-21", offset: Int = -10_800) -> Bool {
        policy.needsRefresh(hasSummary: hasSummary, now: start.addingTimeInterval(seconds),
                            day: day, utcOffsetSeconds: offset)
    }

    func testDiskCacheIsRevalidatedOncePerLaunch() {
        XCTAssertTrue(needs(SummaryRefreshPolicy(), after: 0))
    }

    func testFreshSnapshotSurvivesRepeatedForegroundNotifications() {
        var policy = SummaryRefreshPolicy()
        policy.recordAttempt(now: start, day: day, utcOffsetSeconds: offset)
        policy.recordSuccess(now: start, day: day, utcOffsetSeconds: offset)
        for elapsed in [0.0, 1, 10, 15, 60, 179] { XCTAssertFalse(needs(policy, after: elapsed)) }
        XCTAssertTrue(needs(policy, after: 180))
    }

    func testFailedAttemptIsRetriedWithoutANotificationStorm() {
        var policy = SummaryRefreshPolicy()
        policy.recordAttempt(now: start, day: day, utcOffsetSeconds: offset)
        XCTAssertFalse(needs(policy, after: 1, hasSummary: false))
        XCTAssertFalse(needs(policy, after: 14, hasSummary: false))
        XCTAssertTrue(needs(policy, after: 15, hasSummary: false))
    }

    func testNewLocalDayRefreshesEvenInsideCooldown() {
        var policy = SummaryRefreshPolicy()
        policy.recordAttempt(now: start, day: day, utcOffsetSeconds: offset)
        policy.recordSuccess(now: start, day: day, utcOffsetSeconds: offset)
        XCTAssertTrue(needs(policy, after: 1, day: "2026-10-22"))
    }

    func testTimezoneChangeRefreshesEvenInsideCooldown() {
        var policy = SummaryRefreshPolicy()
        policy.recordAttempt(now: start, day: day, utcOffsetSeconds: offset)
        policy.recordSuccess(now: start, day: day, utcOffsetSeconds: offset)
        XCTAssertTrue(needs(policy, after: 1, offset: 3_600))
    }

    func testMissingSnapshotIsNotTreatedAsFresh() {
        var policy = SummaryRefreshPolicy()
        policy.recordSuccess(now: start, day: day, utcOffsetSeconds: offset)
        XCTAssertTrue(needs(policy, after: 1, hasSummary: false))
    }

    func testClockRollbackCannotKeepSnapshotFreshIndefinitely() {
        var policy = SummaryRefreshPolicy()
        policy.recordAttempt(now: start, day: day, utcOffsetSeconds: offset)
        policy.recordSuccess(now: start, day: day, utcOffsetSeconds: offset)
        XCTAssertTrue(needs(policy, after: -10))
    }

    func testCancellationOrRestoreCanInvalidateTheCooldown() {
        var policy = SummaryRefreshPolicy()
        policy.recordAttempt(now: start, day: day, utcOffsetSeconds: offset)
        policy.recordSuccess(now: start, day: day, utcOffsetSeconds: offset)
        policy.invalidate()
        XCTAssertTrue(needs(policy, after: 1))
    }
}

final class ModelProgressTests: XCTestCase {
    @MainActor
    func testDuplicateAndStaleProgressDoNotInvalidateTheUI() {
        let progress = ModelProgress()
        var notifications = 0
        let subscription = progress.objectWillChange.sink { notifications += 1 }
        progress.begin(1)
        progress.report(1, "Analizando")
        progress.report(1, "Analizando")
        progress.report(0, "Obsoleto")
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(progress.label, "Analizando")
        progress.report(1, nil)
        progress.report(1, nil)
        XCTAssertEqual(notifications, 2)
        subscription.cancel()
    }
}

final class HealthRingMotionTests: XCTestCase {
    @MainActor
    private func motion() -> HealthRingMotion {
        let motion = HealthRingMotion()
        motion.viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        motion.update([0: CGRect(x: 140, y: 120, width: 230, height: 230)])
        return motion
    }

    @MainActor
    func testReducedMotionAndOffscreenSourcesDoNotHideTheProduct() {
        let motion = motion()
        motion.begin(from: 0, to: 1, reducedMotion: true)
        XCTAssertNil(motion.flight)
        motion.update([0: CGRect(x: 140, y: -500, width: 230, height: 230)])
        motion.begin(from: 0, to: 1, reducedMotion: false)
        XCTAssertNil(motion.flight)
    }

    @MainActor
    func testDestinationLayoutStartsTravelAndCancellationRestoresPlacements() async throws {
        let motion = motion()
        motion.begin(from: 0, to: 1, reducedMotion: false)
        XCTAssertNotNil(motion.flight)
        XCTAssertNil(motion.flight?.destination)
        let target = CGRect(x: 86, y: 150, width: 218, height: 218)
        motion.update([1: target])
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(motion.flight?.destination, target)
        XCTAssertEqual(motion.progress, 1)
        motion.update([1: target.offsetBy(dx: 0, dy: -60)])
        XCTAssertNil(motion.flight)
        XCTAssertEqual(motion.progress, 0)
    }

    @MainActor
    func testRapidTabChangeRejectsThePreviousScheduledAnimation() async throws {
        let motion = motion()
        motion.begin(from: 0, to: 1, reducedMotion: false)
        motion.update([1: CGRect(x: 86, y: 150, width: 218, height: 218)])
        motion.begin(from: 1, to: 2, reducedMotion: false)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(motion.flight?.to, 2)
        XCTAssertEqual(motion.progress, 0)
        motion.cancel()
    }

    @MainActor
    func testMissingDestinationCannotLeaveTheRingHidden() async throws {
        let motion = motion()
        motion.begin(from: 0, to: 2, reducedMotion: false)
        try await Task.sleep(for: .milliseconds(1050))
        XCTAssertNil(motion.flight)
        XCTAssertEqual(motion.progress, 0)
    }
}


final class HealthRingGeometryTests: XCTestCase {
    func testHomeFitsNarrowPhonesWidePhonesAndTabletRows() {
        for screenWidth: CGFloat in [320, 375, 390, 393, 402, 428, 440, 768, 1024] {
            let rowWidth = screenWidth - 40
            let ringSize = HealthRingGeometry.homeSize(availableWidth: rowWidth)
            XCTAssertLessThanOrEqual(ringSize, 218)
            XCTAssertGreaterThanOrEqual(rowWidth - 24 - ringSize, 110,
                                       "The score/date column must retain readable space at \(screenWidth)pt")
            XCTAssertLessThanOrEqual(ringSize, 232, "The product must stay above the statistics row")
        }
    }

    func testAnimationEndsOnTheExactDestinationAcrossViewportSizes() {
        // Points are already resolved inside the overlay; status/nav/tab bars
        // and display scale must never be added a second time.
        for width: CGFloat in [320, 375, 390, 428, 768] {
            for topInset: CGFloat in [0, 44, 59, 96] {
                let size = HealthRingGeometry.homeSize(availableWidth: width - 40)
                let home = CGRect(x: width - 22 - size, y: 70 + topInset, width: size, height: size)
                let ring = CGRect(x: (width - 218) / 2, y: 145 + topInset, width: 218, height: 218)
                let settings = CGRect(x: width - 174, y: 110 + topInset, width: 154, height: 154)
                for (from, to) in [(home, ring), (ring, settings), (settings, home)] {
                    XCTAssertEqual(HealthRingGeometry.interpolate(from: from, to: to, progress: 0), from)
                    XCTAssertEqual(HealthRingGeometry.interpolate(from: from, to: to, progress: 1), to)
                }
            }
        }
    }

    @MainActor
    func testIncomingLayoutSettlesBeforeTheFlightStarts() async throws {
        let motion = HealthRingMotion()
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        motion.update([0: CGRect(x: 190, y: 100, width: 176, height: 176)], viewport: viewport)
        motion.begin(from: 0, to: 1, reducedMotion: false)
        motion.update([1: CGRect(x: 86, y: 300, width: 218, height: 218)])
        try await Task.sleep(for: .milliseconds(10))
        let final = CGRect(x: 86, y: 150, width: 218, height: 218)
        motion.update([1: final])
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(motion.flight?.destination, final)
        XCTAssertEqual(motion.progress, 1)
        motion.cancel()
    }

    @MainActor
    func testViewportResizeDropsStaleFramesAndRestoresTheImage() {
        let motion = HealthRingMotion()
        motion.update([0: CGRect(x: 190, y: 100, width: 176, height: 176)],
                      viewport: CGRect(x: 0, y: 0, width: 390, height: 844))
        motion.begin(from: 0, to: 1, reducedMotion: false)
        XCTAssertNotNil(motion.flight)
        motion.update([1: CGRect(x: 213, y: 100, width: 218, height: 218)],
                      viewport: CGRect(x: 0, y: 0, width: 844, height: 390))
        XCTAssertNil(motion.flight)
        motion.begin(from: 0, to: 1, reducedMotion: false)
        XCTAssertNil(motion.flight, "A source measured before rotation must not be reused")
    }
}
