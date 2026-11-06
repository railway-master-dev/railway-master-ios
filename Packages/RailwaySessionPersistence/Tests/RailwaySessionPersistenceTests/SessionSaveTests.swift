import Foundation
import XCTest
@testable import RailwaySessionPersistence

final class SessionSaveTests: XCTestCase {
    func testCurrentSchemaRoundTripsCompleteCoreState() throws {
        let state = makeState()
        let savedAt = ISO8601DateFormatter().date(from: "2026-11-05T18:42:12Z")!

        let data = try SessionSaveCodec.encode(state, savedAt: savedAt)
        let loaded = try SessionSaveCodec.decode(data)

        XCTAssertEqual(loaded.state, state)
        XCTAssertEqual(loaded.savedAt, savedAt)
        XCTAssertNil(loaded.migratedFromVersion)
        XCTAssertTrue(loaded.migrationMessages.isEmpty)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, VersionedSaveEnvelope.currentSchemaVersion)
    }

    func testV1MigratesExplicitlyAndPreservesAvailableFields() throws {
        let data = try legacyV1Data()
        let loaded = try SessionSaveCodec.decode(data)

        XCTAssertEqual(loaded.migratedFromVersion, 1)
        XCTAssertEqual(loaded.state.route.routeID, "fictional-throughBranch-local-up")
        XCTAssertEqual(loaded.state.vehicle.profileID, "fictional-field-chopper-t01")
        XCTAssertEqual(loaded.state.physics.positionM, 1_250)
        XCTAssertEqual(loaded.state.physics.speedMps, 12.5)
        XCTAssertEqual(loaded.state.simulation.simulationTimeSeconds, 123.5)
        XCTAssertTrue(loaded.state.simulation.isPaused)
        XCTAssertEqual(loaded.state.environment.dayPeriodID, "day")
        XCTAssertEqual(loaded.state.mode?.modeID, "driver")
        XCTAssertFalse(loaded.migrationMessages.isEmpty)
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyV1Data()) as? [String: Any])
        root["schemaVersion"] = 99
        let data = try JSONSerialization.data(withJSONObject: root)
        XCTAssertThrowsError(try SessionSaveCodec.decode(data)) { error in
            XCTAssertEqual(error as? SessionSaveCodecError, .unsupportedVersion(99))
        }
    }

    func testWrongSchemaIsRejected() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyV1Data()) as? [String: Any])
        root["schema"] = "unrelated.save"
        let data = try JSONSerialization.data(withJSONObject: root)
        XCTAssertThrowsError(try SessionSaveCodec.decode(data)) { error in
            XCTAssertEqual(error as? SessionSaveCodecError, .unsupportedSchema("unrelated.save"))
        }
    }

    func testNonFiniteOrOutOfRangePhysicsStateCannotBeSavedOrRestored() throws {
        var state = makeState()
        state.physics.speedMps = .infinity
        XCTAssertThrowsError(try SessionSaveCodec.encode(state)) { error in
            XCTAssertEqual(error as? SessionSaveCodecError, .invalidState(.invalidField("physics.speedMps")))
        }
    }

    func testEnvironmentAndPositionRangesAreValidated() throws {
        var state = makeState()
        state.environment.windDirectionDegrees = 360
        XCTAssertThrowsError(try state.validate()) { error in
            XCTAssertEqual(error as? SaveValidationError, .invalidField("environment.windDirectionDegrees"))
        }

        state = makeState()
        state.physics.positionM = state.route.distanceM + 1_001
        XCTAssertThrowsError(try state.validate()) { error in
            XCTAssertEqual(error as? SaveValidationError, .invalidField("physics.positionM"))
        }
    }

    func testBoundedTerminalOvershootAndPhysicsRemainderArePersistable() throws {
        var state = makeState()
        state.simulation.runPhaseID = "overshot"
        state.physics.positionM = state.route.distanceM + 12
        state.physics.physicsAccumulatorSeconds = 0.003

        let restored = try SessionSaveCodec.decode(SessionSaveCodec.encode(state)).state
        XCTAssertEqual(restored.physics.positionM, state.physics.positionM)
        XCTAssertEqual(restored.physics.physicsAccumulatorSeconds, state.physics.physicsAccumulatorSeconds)
    }

    func testImportMigratesLegacyFileToCurrentSchemaOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileSaveStore(directoryURL: root)

        let imported = try store.importData(legacyV1Data(), toSlot: "legacy")
        XCTAssertEqual(imported.migratedFromVersion, 1)
        XCTAssertNil(try store.load(slot: "legacy").migratedFromVersion)
        let onDisk = try JSONSerialization.jsonObject(with: store.exportData(fromSlot: "legacy")) as? [String: Any]
        XCTAssertEqual(onDisk?["schemaVersion"] as? Int, VersionedSaveEnvelope.currentSchemaVersion)
    }

    func testJSONExtensionPreservesUnknownFutureSubsystemFields() throws {
        var state = makeState()
        state.subsystemStates["future.dispatch.v3"] = .object([
            "taskSequence": .integer(8),
            "assignment": .array([.string("fictional-duty-A"), .bool(true)])
        ])

        let restored = try SessionSaveCodec.decode(SessionSaveCodec.encode(state)).state
        XCTAssertEqual(restored.subsystemStates["future.dispatch.v3"], state.subsystemStates["future.dispatch.v3"])
    }

    func testPortableExportImportAndAtomicSlotStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try FileSaveStore(directoryURL: root.appendingPathComponent("source", isDirectory: true))
        let destination = try FileSaveStore(directoryURL: root.appendingPathComponent("destination", isDirectory: true))
        let state = makeState()

        let savedURL = try source.save(state, toSlot: "autosave_1", savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertEqual(try source.load(slot: "autosave_1").state, state)

        let portable = try source.exportData(fromSlot: "autosave_1")
        let imported = try destination.importData(portable, toSlot: "migrated-device")
        XCTAssertEqual(imported.state, state)
        XCTAssertEqual(try destination.load(slot: "migrated-device").state, state)
        XCTAssertEqual(try destination.listSlots().map(\.id), ["migrated-device"])

        try destination.delete(slot: "migrated-device")
        XCTAssertThrowsError(try destination.load(slot: "migrated-device"))
    }

    func testSlotTraversalIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileSaveStore(directoryURL: root)

        XCTAssertThrowsError(try store.save(makeState(), toSlot: "../escape")) { error in
            XCTAssertEqual(error as? FileSaveStoreError, .invalidSlotID)
        }
        XCTAssertThrowsError(try store.load(slot: "contains/slash")) { error in
            XCTAssertEqual(error as? FileSaveStoreError, .invalidSlotID)
        }
    }

    func testInvalidPortableImportDoesNotOverwriteExistingSlot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileSaveStore(directoryURL: root)
        let original = makeState()
        try store.save(original, toSlot: "slot")

        XCTAssertThrowsError(try store.importData(Data("not json".utf8), toSlot: "slot"))
        XCTAssertEqual(try store.load(slot: "slot").state, original)
    }

    func testOversizedDataIsRejectedBeforeDecode() {
        let data = Data(repeating: 0x20, count: SessionSaveCodec.maximumEncodedBytes + 1)
        XCTAssertThrowsError(try SessionSaveCodec.decode(data)) { error in
            XCTAssertEqual(error as? SessionSaveCodecError, .dataTooLarge)
        }
    }

    private func legacyV1Data() throws -> Data {
        let object: [String: Any] = [
            "schema": VersionedSaveEnvelope.schemaIdentifier,
            "schemaVersion": 1,
            "savedAt": "2026-11-05T18:00:00Z",
            "payload": [
                "saveName": "Legacy run",
                "sessionID": "00000000-0000-0000-0000-000000000111",
                "routeID": "fictional-throughBranch-local-up",
                "routeLengthM": 68_000.0,
                "vehicleProfileID": "fictional-field-chopper-t01",
                "carCount": 6,
                "positionM": 1_250.0,
                "speedMps": 12.5,
                "simulationTimeSeconds": 123.5,
                "passengerLoadFactor": 0.7,
                "modeID": "driver",
                "calendarID": "WEEKDAY_PLACEHOLDER",
                "initialDelayMinutes": 3
            ] as [String: Any]
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func makeState() -> SimulationSaveState {
        let route = RouteProgressSnapshot(
            routeID: "fictional-throughBranch-local-up",
            routeRevision: "fictional-route-v1",
            variantID: "throughBranch",
            directionID: "up",
            distanceM: 68_000,
            stopMarkerM: 68_000,
            nextStopIndex: 4,
            completedStopIDs: ["FIC-STA-01", "FIC-STA-02"]
        )
        return SimulationSaveState(
            saveName: "架空本線テスト走行",
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000222")!,
            simulation: SimulationClockSnapshot(
                simulationTimeSeconds: 180.25,
                fixedTick: 21_630,
                fixedStepRemainderSeconds: 0.002,
                isPaused: true,
                runPhaseID: "running",
                arrivalDwellSeconds: 0.25
            ),
            route: route,
            vehicle: PlayerVehicleSnapshot(
                vehicleID: "PLAYER",
                profileID: "fictional-field-chopper-t01",
                soundProfileID: "fictional-chopper-synth",
                carCount: 6,
                directionID: "forward",
                carPositionsM: [1_220, 1_224, 1_228, 1_232, 1_236, 1_240]
            ),
            otherVehicles: [VehiclePositionSnapshot(
                id: "NPC-01",
                routeID: route.routeID,
                trackID: "FIC-TRACK-UP",
                vehicleProfileID: "fictional-vvvf-t03",
                directionID: "forward",
                positionM: 2_400,
                speedMps: 15,
                lengthM: 117
            )],
            controls: ControlStateSnapshot(throttleNotch: 2, brakeNotch: 0),
            physics: PhysicsStateSnapshot(
                modelID: "fictional-longitudinal-v1",
                modelVersion: 1,
                positionM: 1_250,
                speedMps: 12.5,
                accelerationMps2: 0.12,
                passengerLoadFactor: 0.7,
                appliedBrakeFraction: 0,
                commandedTractionForceN: 48_000,
                antiSlipScale: 0.98,
                lastTractionForceN: 47_000,
                lastRollingResistanceN: 2_100
            ),
            mode: ModeSessionSnapshot(
                modeID: "driver",
                playStyleID: "standard",
                statusID: "active",
                startedAtSimulationSeconds: 0,
                hintCount: 1,
                progress: .object([
                    "departureConfirmed": .bool(true),
                    "visitedStopIDs": .array([.string("FIC-STA-01")]),
                    "overspeedSamples": .integer(0)
                ])
            ),
            timetable: TimetableStateSnapshot(
                calendarID: "WEEKDAY_PLACEHOLDER",
                daypartID: "morningRush",
                serviceCategoryID: "local",
                directionID: "up",
                serviceID: "FIC-LOCAL-101",
                initialDelayMinutes: 2,
                departureDelaySeconds: 120,
                settingsPendingRestart: false,
                stops: [TimetableStopSnapshot(
                    id: "evt-FIC-STA-01",
                    stationID: "FIC-STA-01",
                    positionM: 0,
                    scheduledArrivalSeconds: 0,
                    scheduledDepartureSeconds: 15,
                    actualDepartureSeconds: 135,
                    departureDelaySeconds: 120
                )]
            ),
            environment: EnvironmentStateSnapshot(
                weatherID: "rainyDusk",
                precipitationID: "rain",
                fogDensity: 0.12,
                windSpeedMps: 5,
                windDirectionDegrees: 225,
                visibilityM: 4_000,
                adhesionCoefficient: 0.17,
                ambientIlluminanceLux: 300,
                headlightIntensity: 0.65,
                wiperStateID: "low",
                seasonID: "autumn",
                dayPeriodID: "dusk",
                timeOfDayHours: 18.4
            ),
            preferences: UserPreferencesSnapshot(
                cameraPresetID: "chase",
                renderQualityID: "medium",
                masterVolume: 0.9,
                musicVolume: 0.35,
                effectsVolume: 0.8,
                voiceVolume: 0.9,
                controlLayoutID: "left-handed",
                hapticsEnabled: false
            ),
            drivingLog: .object(["sampleCount": .integer(4)]),
            subsystemStates: [
                "signals": .object(["lastProtectedBlockID": .string("FIC-BLOCK-12")]),
                "traffic": .object(["seed": .integer(4242)])
            ],
            compatibility: SaveCompatibilitySnapshot(
                appBuildID: "fictional-build-42",
                routeCatalogRevision: "fictional-routes-2026a",
                vehicleCatalogRevision: "fictional-vehicles-1",
                subsystemStateRevision: 1
            )
        )
    }
}
