import XCTest

final class FrictionBlockerTests: XCTestCase {
    func testPasswordLengthAndVerification() throws {
        XCTAssertThrowsError(try PasswordCredential.create(password: "too-short", iterations: 10))
        let password = "correct-horse-battery-staple"
        let credential = try PasswordCredential.create(password: password, iterations: 10)
        XCTAssertTrue(credential.verifies(password))
        XCTAssertFalse(credential.verifies("wrong-password-that-is-long"))
    }

    func testGeneratedPasswordMeetsLengthRequirement() throws {
        let password = try PasswordPolicy.generate()
        XCTAssertEqual(password.count, PasswordPolicy.generatedLength)
        XCTAssertTrue(PasswordPolicy.validate(password))
    }

    func testDaemonProtocolRoundTrip() throws {
        let request = DaemonRequest(
            command: .authorizeSettings,
            password: "correct-horse-battery-staple",
            durationSeconds: 300
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DaemonRequest.self, from: data)
        XCTAssertEqual(decoded.command, .authorizeSettings)
        XCTAssertEqual(decoded.durationSeconds, 300)
    }

    func testRootStateStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DaemonStateStore(fileURL: directory.appendingPathComponent("state.json"))
        let state = PersistentDaemonState(
            credential: nil,
            authorizedUntil: Date().addingTimeInterval(300),
            failedUnlockAttempts: 2,
            nextUnlockAttempt: Date().addingTimeInterval(4)
        )
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
    }

    func testLegacyPFStateCanMigrateWithoutPolicyField() throws {
        let json = """
        {
          "credential": null,
          "failedUnlockAttempts": 3,
          "nextUnlockAttempt": null,
          "policy": { "isEnabled": false }
        }
        """
        let state = try JSONDecoder().decode(PersistentDaemonState.self, from: Data(json.utf8))
        XCTAssertNil(state.authorizedUntil)
        XCTAssertEqual(state.failedUnlockAttempts, 3)
    }

    func testSettingsProcessScanReturnsOnlyPositivePIDs() {
        let processIDs = SettingsProcessGuard().runningProcessIDs()
        XCTAssertTrue(processIDs.allSatisfy { $0 > 0 })
    }
}
