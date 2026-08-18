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
            command: .setGuardEnabled,
            password: "correct-horse-battery-staple",
            guardEnabled: false
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DaemonRequest.self, from: data)
        XCTAssertEqual(decoded.command, .setGuardEnabled)
        XCTAssertEqual(decoded.guardEnabled, false)
    }

    func testRootStateStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DaemonStateStore(fileURL: directory.appendingPathComponent("state.json"))
        let state = PersistentDaemonState(
            credential: nil,
            guardEnabled: false,
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
        XCTAssertFalse(state.guardEnabled)
        XCTAssertEqual(state.failedUnlockAttempts, 3)
    }

    func testTemporaryAuthorizationStateMigratesToGuardEnabled() throws {
        let credential = try PasswordCredential.create(
            password: "correct-horse-battery-staple",
            iterations: 10
        )
        let credentialData = try JSONEncoder().encode(credential)
        let credentialObject = try JSONSerialization.jsonObject(with: credentialData)
        let legacyState: [String: Any] = [
            "credential": credentialObject,
            "authorizedUntil": Date().addingTimeInterval(300).timeIntervalSinceReferenceDate,
            "failedUnlockAttempts": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyState)
        let state = try JSONDecoder().decode(PersistentDaemonState.self, from: data)
        XCTAssertTrue(state.guardEnabled)
    }

    func testSettingsProcessScanReturnsOnlyPositivePIDs() {
        let processIDs = SettingsProcessGuard().runningProcessIDs()
        XCTAssertTrue(processIDs.allSatisfy { $0 > 0 })
    }
}
