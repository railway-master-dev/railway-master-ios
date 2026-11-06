import XCTest
@testable import RailwayAudioEnhancements

final class AudioEnhancementTests: XCTestCase {
    func testSchedulerIsSimulationClockDrivenAndOrdersTiesDeterministically() throws {
        let scheduler = AudioEventScheduler()
        XCTAssertEqual(scheduler.schedule(event("later", at: 4)), .scheduled)
        XCTAssertEqual(scheduler.schedule(event("zeta", at: 2, priority: 1)), .scheduled)
        XCTAssertEqual(scheduler.schedule(event("beta", at: 2, priority: 1)), .scheduled)
        XCTAssertEqual(scheduler.schedule(event("urgent", at: 2, priority: 8)), .scheduled)

        XCTAssertTrue(try scheduler.advance(to: 1.99).isEmpty)
        let due = try scheduler.advance(to: 2)
        XCTAssertEqual(due.map(\.id), ["urgent", "beta", "zeta"])
        XCTAssertTrue(try scheduler.advance(to: 2).isEmpty)
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(try scheduler.advance(to: 4).map(\.id), ["later"])
    }

    func testSchedulerDeduplicatesByIDAndSemanticKeyIncludingDeliveredEvents() throws {
        let scheduler = AudioEventScheduler()
        XCTAssertEqual(scheduler.schedule(event("arrival-1", at: 1, key: "next:station-7")), .scheduled)
        XCTAssertEqual(scheduler.schedule(event("arrival-2", at: 2, key: "next:station-7")), .duplicateKey("next:station-7"))
        XCTAssertEqual(scheduler.schedule(event("arrival-1", at: 3)), .duplicateEventID)
        _ = try scheduler.advance(to: 1)
        XCTAssertEqual(scheduler.schedule(event("arrival-3", at: 1, key: "next:station-7")), .duplicateKey("next:station-7"))
    }

    func testCancelReleasesIDAndDedupeKeyAndResetSupportsReplay() throws {
        let scheduler = AudioEventScheduler()
        XCTAssertEqual(scheduler.schedule(event("cancel-me", at: 5, key: "doors:5")), .scheduled)
        XCTAssertTrue(scheduler.cancel(eventID: "cancel-me"))
        XCTAssertFalse(scheduler.cancel(eventID: "cancel-me"))
        XCTAssertEqual(scheduler.schedule(event("cancel-me", at: 6, key: "doors:5")), .scheduled)

        scheduler.reset(to: 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(scheduler.schedule(event("cancel-me", at: 1, key: "doors:5")), .scheduled)
        XCTAssertEqual(try scheduler.advance(to: 1).map(\.id), ["cancel-me"])
    }

    func testSchedulerRejectsInvalidPastAndBackwardTimes() throws {
        let scheduler = AudioEventScheduler(startTime: 10)
        XCTAssertEqual(scheduler.schedule(event("nan", at: .nan)), .invalidTime)
        XCTAssertEqual(scheduler.schedule(event("past", at: 9.99)), .eventInPast)
        XCTAssertThrowsError(try scheduler.advance(to: .infinity))
        XCTAssertThrowsError(try scheduler.advance(to: 9)) { error in
            XCTAssertEqual(error as? AudioEventSchedulerError, .clockMovedBackwards(current: 10, requested: 9))
        }
    }

    func testJapaneseAndEnglishAnnouncementTemplatesProduceSpeechInstructions() throws {
        let japanese = AnnouncementRequest(
            template: .nextStation,
            locale: .japanese,
            context: .init(stationName: "青葉台"),
            channel: .onboardAutomated
        )
        let english = AnnouncementRequest(
            template: .transfer,
            locale: .english,
            context: .init(destination: "Central"),
            channel: .stationPublicAddress
        )

        let ja = try XCTUnwrap(AnnouncementRenderer.render(japanese))
        XCTAssertEqual(ja.text, "次は、青葉台です。")
        XCTAssertEqual(ja.languageTag, "ja-JP")
        XCTAssertEqual(ja.audioBus, .onboardAnnouncement)

        let en = try XCTUnwrap(AnnouncementRenderer.render(english))
        XCTAssertEqual(en.text, "Please change here for services towards Central.")
        XCTAssertEqual(en.languageTag, "en-GB")
        XCTAssertEqual(en.audioBus, .stationPublicAddress)
    }

    func testAnnouncementWithoutRequiredSubstitutionIsNotRendered() {
        let request = AnnouncementRequest(template: .approachingStation, locale: .english)
        XCTAssertNil(AnnouncementRenderer.render(request))
        let blank = AnnouncementRequest(
            template: .transfer,
            locale: .japanese,
            context: .init(destination: "   ")
        )
        XCTAssertNil(AnnouncementRenderer.render(blank))
    }

    func testInteriorExteriorStationAndTunnelHaveDistinctMixPolicies() {
        let cab = AudioMixMatrix.parameters(for: .cabInterior, in: .cabInterior)
        let outside = AudioMixMatrix.parameters(for: .exterior, in: .exterior)
        let stationPA = AudioMixMatrix.parameters(for: .stationPublicAddress, in: .station)
        let tunnel = AudioMixMatrix.parameters(for: .tunnelReflection, in: .tunnel)

        XCTAssertGreaterThan(cab.gain, AudioMixMatrix.parameters(for: .cabInterior, in: .exterior).gain)
        XCTAssertEqual(stationPA.gain, 1)
        XCTAssertGreaterThan(tunnel.reverbSend, cab.reverbSend)
        XCTAssertLessThan(tunnel.lowPassCutoffHz, outside.lowPassCutoffHz)
        XCTAssertEqual(AudioMixMatrix.parameters(for: .exterior, in: .station, masterGain: 2).gain, 0.38)
        XCTAssertEqual(AudioMixMatrix.parameters(for: .exterior, in: .station, masterGain: .nan).gain, 0)
    }

    func testControlSignaturesAreDeterministicFiniteBoundedAndDistinct() {
        let state = ControlSignalState(
            speedMetersPerSecond: 18,
            motorRPM: 1_500,
            tractionLoad: 0.72,
            accelerationMetersPerSecondSquared: 0.4,
            powerNotch: 5,
            fieldWeakeningRatio: 0.6,
            regenerativeBrakeRatio: 0.2
        )
        let signals = TractionControlMode.allCases.map {
            ControlModeSignatureRenderer.render(mode: $0, state: state, frameCount: 4_096, sampleRate: 48_000)
        }
        XCTAssertEqual(signals.count, 6)
        XCTAssertTrue(signals.allSatisfy { $0.count == 4_096 && $0.allSatisfy(\.isFinite) })
        XCTAssertTrue(signals.allSatisfy { ($0.map(abs).max() ?? 0) <= 0.90 })
        for first in signals.indices {
            for second in signals.indices where second > first {
                XCTAssertNotEqual(signals[first], signals[second], "Profiles \(first) and \(second) must have distinct conceptual signatures")
            }
        }
        let repeatRender = ControlModeSignatureRenderer.render(
            mode: .vvvfIGBTVariableCarrier,
            state: state,
            frameCount: 4_096,
            sampleRate: 48_000
        )
        XCTAssertEqual(signals[4], repeatRender)
        XCTAssertEqual(TractionControlMode.vvvfIGBT.representationLabel, "CONCEPTUAL / VIRTUAL — synthesized signature, not an authentic train sound")
    }

    func testSignalRendererCanRenderStableChunksAndRejectsInvalidDimensions() {
        let state = ControlSignalState(speedMetersPerSecond: 20, tractionLoad: 0.8)
        let whole = ControlModeSignatureRenderer.render(mode: .fieldChopperDC, state: state, frameCount: 256, sampleRate: 48_000)
        let first = ControlModeSignatureRenderer.render(mode: .fieldChopperDC, state: state, frameCount: 128, sampleRate: 48_000)
        let second = ControlModeSignatureRenderer.render(mode: .fieldChopperDC, state: state, frameCount: 128, sampleRate: 48_000, sampleOffset: 128)
        XCTAssertEqual(Array(whole.prefix(128)), first)
        XCTAssertEqual(Array(whole.suffix(128)), second)
        XCTAssertTrue(ControlModeSignatureRenderer.render(mode: .rheostaticDC, state: state, frameCount: 0, sampleRate: 48_000).isEmpty)
        XCTAssertTrue(ControlModeSignatureRenderer.render(mode: .rheostaticDC, state: state, frameCount: 8, sampleRate: .nan).isEmpty)
    }

    func testRendererDefensivelyNormalizesMutatedState() {
        var state = ControlSignalState(speedMetersPerSecond: 10, tractionLoad: 0.5)
        state.speedMetersPerSecond = .nan
        state.motorRPM = .infinity
        state.tractionLoad = .infinity
        state.fieldWeakeningRatio = .nan
        state.regenerativeBrakeRatio = .infinity
        let pcm = ControlModeSignatureRenderer.render(mode: .vvvfIGBT, state: state, frameCount: 512, sampleRate: 48_000)
        XCTAssertEqual(pcm.count, 512)
        XCTAssertTrue(pcm.allSatisfy(\.isFinite))
    }

    func testControlStateNormalizesUntrustedInputs() {
        let state = ControlSignalState(
            speedMetersPerSecond: .infinity,
            motorRPM: -30,
            tractionLoad: 4,
            accelerationMetersPerSecondSquared: .nan,
            powerNotch: 99,
            fieldWeakeningRatio: -1,
            regenerativeBrakeRatio: 0.5
        )
        XCTAssertEqual(state.speedMetersPerSecond, 0)
        XCTAssertEqual(state.motorRPM, 0)
        XCTAssertEqual(state.tractionLoad, 1)
        XCTAssertEqual(state.accelerationMetersPerSecondSquared, 0)
        XCTAssertEqual(state.powerNotch, 12)
        XCTAssertEqual(state.fieldWeakeningRatio, 0)
    }

    private func event(_ id: String, at time: TimeInterval, priority: Int = 0, key: String? = nil) -> AudioScheduledEvent {
        AudioScheduledEvent(
            id: id,
            scheduledTime: time,
            priority: priority,
            deduplicationKey: key,
            bus: .effects,
            payload: .speakerTone(.attentionChime)
        )
    }
}
