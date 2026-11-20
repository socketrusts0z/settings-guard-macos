import XCTest
import Vision
import CoreImage

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
            command: .setBlockedApps,
            blockedApps: [BlockedApp(name: "WhatsApp", bundlePath: "/Applications/WhatsApp.app",
                                     executablePath: "/Applications/WhatsApp.app/Contents/MacOS/WhatsApp")]
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DaemonRequest.self, from: data)
        XCTAssertEqual(decoded.command, .setBlockedApps)
        XCTAssertEqual(decoded.blockedApps, request.blockedApps)
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
            nextUnlockAttempt: Date().addingTimeInterval(4),
            blockedApps: [BlockedApp(name: "WhatsApp", bundlePath: "/Applications/WhatsApp.app",
                                     executablePath: "/Applications/WhatsApp.app/Contents/MacOS/WhatsApp")]
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
        XCTAssertTrue(state.blockedApps.isEmpty)
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
    private func date(_ hour: Int, _ minute: Int = 0, zone: String = "America/Los_Angeles") -> (Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return (calendar.date(from: DateComponents(year: 2026, month: 11, day: 19,
                                                   hour: hour, minute: minute))!, calendar)
    }

    func testNightlyScheduleBoundaries() {
        for (hour, minute, expected) in [(21, 59, false), (22, 0, true), (23, 59, true),
                                          (0, 0, true), (5, 59, true), (6, 0, false), (12, 0, false)] {
            let (instant, calendar) = date(hour, minute)
            XCTAssertEqual(GuardSchedule.nightly.contains(instant, calendar: calendar), expected)
        }
    }

    func testDaytimeAndInvalidSchedules() {
        let schedule = GuardSchedule(enabled: true, startMinute: 9 * 60, endMinute: 17 * 60)
        for (hour, expected) in [(8, false), (9, true), (16, true), (17, false), (23, false)] {
            let (instant, calendar) = date(hour)
            XCTAssertEqual(schedule.contains(instant, calendar: calendar), expected)
        }
        XCTAssertFalse(GuardSchedule(enabled: true, startMinute: 0, endMinute: 0).isValid)
        XCTAssertFalse(GuardSchedule(enabled: true, startMinute: -1, endMinute: 360).isValid)
        XCTAssertFalse(GuardSchedule(enabled: true, startMinute: 1320, endMinute: 1440).isValid)
    }

    func testProtectionCatchesUpAtCurrentTimeAndRespectsManualMode() throws {
        let credential = try PasswordCredential.create(password: "correct-horse-battery-staple", iterations: 10)
        var state = PersistentDaemonState(credential: credential, guardEnabled: false,
                                          failedUnlockAttempts: 0, nextUnlockAttempt: nil)
        let (night, calendar) = date(23)
        let (morning, _) = date(6)
        XCTAssertTrue(state.protectionActive(at: night, calendar: calendar))
        XCTAssertFalse(state.protectionActive(at: morning, calendar: calendar))
        state.schedule.enabled = false
        XCTAssertFalse(state.protectionActive(at: night, calendar: calendar))
        state.guardEnabled = true
        XCTAssertTrue(state.protectionActive(at: morning, calendar: calendar))
        state.credential = nil
        XCTAssertFalse(state.protectionActive(at: night, calendar: calendar))
    }

    func testLegacyStateAdoptsNightlyScheduleAndPersistsCustomSchedule() throws {
        let legacy = Data("{\"guardEnabled\":true,\"failedUnlockAttempts\":0}".utf8)
        var state = try JSONDecoder().decode(PersistentDaemonState.self, from: legacy)
        XCTAssertEqual(state.schedule, .nightly)
        state.schedule = GuardSchedule(enabled: false, startMinute: 23 * 60, endMinute: 7 * 60)
        XCTAssertEqual(try JSONDecoder().decode(PersistentDaemonState.self,
                                               from: JSONEncoder().encode(state)), state)
    }

    func testScheduleUsesSuppliedTimeZoneAndDSTWallClock() {
        let (instant, _) = date(22)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertTrue(GuardSchedule.nightly.contains(instant, calendar: calendar))
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        XCTAssertFalse(GuardSchedule.nightly.contains(instant, calendar: calendar))
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // Both occurrences of 1:30 a.m. during the fall-back transition are protected.
        for hourUTC in [8, 9] {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let repeated = utc.date(from: DateComponents(year: 2026, month: 11, day: 1,
                                                         hour: hourUTC, minute: 30))!
            XCTAssertTrue(GuardSchedule.nightly.contains(repeated, calendar: calendar))
        }
    }

    private func qrState(token: String) throws -> PersistentDaemonState {
        PersistentDaemonState(
            credential: try PasswordCredential.create(password: "correct-horse-battery-staple", iterations: 10),
            guardEnabled: true, failedUnlockAttempts: 0, nextUnlockAttempt: nil,
            qrCredential: try PasswordCredential.create(password: BarcodeUnlockPayload.credentialInput(for: token), iterations: 10))
    }

    func testQRTokensAreRandomAndStrictlyValidated() throws {
        let first = try QRUnlockToken.generate()
        let second = try QRUnlockToken.generate()
        XCTAssertTrue(QRUnlockToken.isValid(first))
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(QRUnlockToken.isValid(first + "\n"))
        XCTAssertFalse(QRUnlockToken.isValid("https://example.com"))
        XCTAssertFalse(QRUnlockToken.isValid(QRUnlockToken.prefix + String(repeating: "z", count: 64)))
        XCTAssertFalse(QRUnlockToken.isValid(String(first.dropLast())))
    }

    func testQRUnlockMatchesPasswordWithoutTimerAndSurvivesRelaunch() throws {
        let token = try QRUnlockToken.generate()
        var qr = try qrState(token: token)
        var password = qr
        try qr.disableProtection(using: .qr(token))
        try password.disableProtection(using: .password("correct-horse-battery-staple"))
        XCTAssertEqual(qr, password)
        XCTAssertFalse(qr.guardEnabled)
        XCTAssertFalse(qr.schedule.enabled)
        let restored = try JSONDecoder().decode(PersistentDaemonState.self, from: JSONEncoder().encode(qr))
        let (tomorrowNight, calendar) = date(23)
        XCTAssertFalse(restored.protectionActive(at: tomorrowNight, calendar: calendar))
        XCTAssertNotNil(restored.qrCredential)
    }

    func testWrongQRAndPasswordSharePersistedCooldown() throws {
        let token = try QRUnlockToken.generate()
        var state = try qrState(token: token)
        let now = Date()
        XCTAssertThrowsError(try state.disableProtection(using: .qr(try QRUnlockToken.generate()), at: now))
        XCTAssertTrue(state.guardEnabled)
        XCTAssertTrue(state.schedule.enabled)
        XCTAssertEqual(state.failedUnlockAttempts, 1)
        XCTAssertEqual(state.nextUnlockAttempt, now.addingTimeInterval(2))
        state = try JSONDecoder().decode(PersistentDaemonState.self, from: JSONEncoder().encode(state))
        XCTAssertThrowsError(try state.disableProtection(using: .password("correct-horse-battery-staple"), at: now))
        XCTAssertEqual(state.failedUnlockAttempts, 1)
        try state.disableProtection(using: .qr(token), at: now.addingTimeInterval(2))
        XCTAssertEqual(state.failedUnlockAttempts, 0)
        XCTAssertNil(state.nextUnlockAttempt)
    }

    func testQRSetupRequiresPasswordAndRotationRevokesOldCode() throws {
        let old = try QRUnlockToken.generate()
        let replacement = "012345678905"
        var state = try qrState(token: old)
        let original = state.qrCredential
        let now = Date()
        XCTAssertThrowsError(try state.configureQR(token: replacement, password: "incorrect-password-that-is-long", at: now))
        XCTAssertEqual(state.qrCredential, original)
        try state.configureQR(token: replacement, password: "correct-horse-battery-staple", at: now.addingTimeInterval(2))
        XCTAssertFalse(state.qrCredential!.verifies(old))
        XCTAssertTrue(state.qrCredential!.verifies(BarcodeUnlockPayload.credentialInput(for: replacement)))
        let encoded = try JSONEncoder().encode(state)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(replacement))
        try state.configureQR(token: nil, password: "correct-horse-battery-staple", at: now.addingTimeInterval(3))
        XCTAssertNil(state.qrCredential)
        XCTAssertThrowsError(try state.disableProtection(using: .qr(replacement), at: now.addingTimeInterval(4)))
    }

    func testInvalidOrUnenrolledQRDoesNotUnlock() throws {
        var state = PersistentDaemonState.initial
        XCTAssertThrowsError(try state.disableProtection(using: .qr(try QRUnlockToken.generate())))
        state.credential = try PasswordCredential.create(password: "correct-horse-battery-staple", iterations: 10)
        state.guardEnabled = true
        XCTAssertThrowsError(try state.disableProtection(using: .qr(nil)))
        XCTAssertTrue(state.guardEnabled)
        XCTAssertThrowsError(try state.configureQR(token: "", password: "correct-horse-battery-staple"))
        XCTAssertNil(state.qrCredential)
    }

    func testQRProtocolAndLegacyMigration() throws {
        let token = try QRUnlockToken.generate()
        let request = DaemonRequest(command: .unlockWithQR, qrToken: token)
        let restored = try JSONDecoder().decode(DaemonRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(restored.command, .unlockWithQR)
        XCTAssertEqual(restored.qrToken, token)
        let legacy = Data("{\"guardEnabled\":true}".utf8)
        XCTAssertNil(try JSONDecoder().decode(PersistentDaemonState.self, from: legacy).qrCredential)
    }

    func testExistingQRContentsDecodeAtReducedSize() throws {
        let token = "https://example.com/a-code-already-on-a-card"
        let image = try XCTUnwrap(QRCodeImage.make(token))
        let png = try XCTUnwrap(QRCodeImage.png(image))
        let decoded = try XCTUnwrap(CIImage(data: png))
        let smaller = decoded.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(ciImage: smaller, options: [:]).perform([request])
        } catch {
            let nsError = error as NSError
            if nsError.domain == "com.apple.Vision", nsError.code == 9,
               nsError.localizedDescription.contains("entitlements") {
                throw XCTSkip("Vision inference is unavailable in this sandbox. Run this image-decoding check outside the restricted test runner, then test the webcam in QR setup.")
            }
            throw error
        }
        XCTAssertEqual(request.results?.first?.payloadStringValue, token)
    }

    func testExistingBarcodeAndQRValuesCanUnlock() throws {
        for value in ["7", "012345678905", "9780140449136", "https://example.com", "A card\nwith text", "本 📚"] {
            XCTAssertTrue(BarcodeUnlockPayload.isValid(value))
            var state = try qrState(token: value)
            let (now, _) = date(23)
            try state.disableProtection(using: .qr(value), at: now)
            XCTAssertFalse(state.guardEnabled)
            XCTAssertFalse(state.schedule.enabled)
        }
    }

    func testExistingCodeMustMatchExactly() throws {
        let value = "012345678905"
        let now = Date()
        for mismatch in ["012345678906", "12345678905", "012345678905 ", "", "another code"] {
            var state = try qrState(token: value)
            XCTAssertThrowsError(try state.disableProtection(using: .qr(mismatch), at: now))
            XCTAssertTrue(state.guardEnabled)
            XCTAssertEqual(state.failedUnlockAttempts, 1)
        }
        XCTAssertNotEqual(BarcodeUnlockPayload.credentialInput(for: "ABC"),
                          BarcodeUnlockPayload.credentialInput(for: "abc"))
        XCTAssertFalse(BarcodeUnlockPayload.isValid(""))
        XCTAssertTrue(BarcodeUnlockPayload.isValid(String(repeating: "a", count: 8192)))
        XCTAssertFalse(BarcodeUnlockPayload.isValid(String(repeating: "a", count: 8193)))
    }

    func testOriginalGeneratedQRCodeRemainsCompatible() throws {
        let legacy = try QRUnlockToken.generate()
        XCTAssertEqual(BarcodeUnlockPayload.credentialInput(for: legacy), legacy)
        var state = PersistentDaemonState(credential: try PasswordCredential.create(
            password: "correct-horse-battery-staple", iterations: 10), guardEnabled: true,
            failedUnlockAttempts: 0, nextUnlockAttempt: nil,
            qrCredential: try PasswordCredential.create(password: legacy, iterations: 10))
        state = try JSONDecoder().decode(PersistentDaemonState.self, from: JSONEncoder().encode(state))
        try state.disableProtection(using: .qr(legacy))
        XCTAssertFalse(state.guardEnabled)
    }

    func testScannerSupportsCommonExistingBarcodeFormats() throws {
        let formats = try VNDetectBarcodesRequest().supportedSymbologies()
        XCTAssertTrue(formats.contains(.qr))
        XCTAssertTrue(formats.contains(.code128))
        XCTAssertTrue(formats.contains(.ean13))
        XCTAssertTrue(formats.contains(.upce))
    }

    func testExistingCode128BarcodeDecodes() throws {
        let payload = "BOOK-123456"
        let filter = try XCTUnwrap(CIFilter(name: "CICode128BarcodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let image = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        let request = VNDetectBarcodesRequest()
        request.symbologies = try request.supportedSymbologies()
        do {
            try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        } catch {
            let nsError = error as NSError
            if nsError.domain == "com.apple.Vision", nsError.code == 9,
               nsError.localizedDescription.contains("entitlements") {
                throw XCTSkip("Vision inference is unavailable in this sandbox. Test the barcode with the webcam during setup.")
            }
            throw error
        }
        XCTAssertEqual(request.results?.first?.payloadStringValue, payload)
    }

}
