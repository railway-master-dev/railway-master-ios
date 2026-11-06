import Foundation

public enum ProtectionSystemKind: String, Codable, CaseIterable, Equatable, Sendable {
    case atsS
    case atsP
    case atsPs
    case atc
    case ato
    case eb
    case deadman
}

struct ControllerEvaluation {
    let system: ProtectionSystemKind
    let permittedSpeedKmh: Double?
    let brakeCommanded: Bool
    let stateDescription: String
    let events: [SimulationEvent]
}

private func crossed(_ devicePositionM: Double, previous: TrainState?, current: TrainState) -> Bool {
    guard let previous, previous.trackID == current.trackID, previous.direction == current.direction else { return false }
    switch current.direction {
    case .increasingChainage:
        return previous.frontPositionM < devicePositionM && current.frontPositionM >= devicePositionM
    case .decreasingChainage:
        return previous.frontPositionM > devicePositionM && current.frontPositionM <= devicePositionM
    }
}

private func event(_ kind: SimulationEventKind, train: TrainState, system: ProtectionSystemKind,
                   time: Double, message: String, sourceID: String? = nil,
                   permittedSpeedKmh: Double? = nil) -> SimulationEvent {
    let millis = Int64((time * 1000).rounded())
    return SimulationEvent(
        id: "\(train.id):\(system.rawValue):\(kind.rawValue):\(millis)",
        kind: kind,
        timeSeconds: time,
        trainID: train.id,
        system: system.rawValue,
        sourceID: sourceID,
        message: message,
        speedKmh: train.speedKmh,
        permittedSpeedKmh: permittedSpeedKmh
    )
}

struct ATSSController {
    let acknowledgementTimeoutSeconds: Double
    private var deadlineByTrain: [String: Double] = [:]
    private var latchedTrains: Set<String> = []

    mutating func evaluate(train: TrainState, previous: TrainState?, devices: [RouteEquipment], input: OperatorInput, time: Double) -> ControllerEvaluation {
        var events: [SimulationEvent] = []
        let beacons = devices.filter { $0.trackID == train.trackID && $0.kind == .atsSBeacon }
        for beacon in beacons where crossed(beacon.positionM, previous: previous, current: train) {
            deadlineByTrain[train.id] = time + acknowledgementTimeoutSeconds
            events.append(event(.warning, train: train, system: .atsS, time: time,
                                message: "Fictional ATS-S-style beacon warning; operator acknowledgement is due.", sourceID: beacon.id))
        }
        if input.acknowledgeATSS, let deadline = deadlineByTrain[train.id], time <= deadline, !latchedTrains.contains(train.id) {
            deadlineByTrain.removeValue(forKey: train.id)
        }
        if let deadline = deadlineByTrain[train.id], time >= deadline {
            latchedTrains.insert(train.id)
        }
        let braking = latchedTrains.contains(train.id)
        if braking {
            events.append(event(.automaticBrake, train: train, system: .atsS, time: time,
                                message: "Fictional ATS-S-style acknowledgement timer expired; simulated brake command is latched."))
        }
        let description = braking ? "latched simulated brake" : (deadlineByTrain[train.id] == nil ? "standby / acknowledged" : "awaiting simulated acknowledgement")
        return ControllerEvaluation(system: .atsS, permittedSpeedKmh: nil, brakeCommanded: braking,
                                    stateDescription: description, events: events)
    }

    mutating func reset(trainID: String) {
        deadlineByTrain.removeValue(forKey: trainID)
        latchedTrains.remove(trainID)
    }
}

struct ATSPController {
    let virtualDecelerationMps2: Double
    let safetyMarginM: Double
    let overspeedToleranceKmh: Double
    private var latchedTrains: Set<String> = []

    mutating func evaluate(train: TrainState, devices: [RouteEquipment], time: Double) -> ControllerEvaluation {
        let targets = devices.filter { device in
            device.trackID == train.trackID && device.kind == .atsPProfileTarget &&
            (device.targetPositionM.map { train.distanceAhead(to: $0) >= 0 } ?? false)
        }.sorted { lhs, rhs in
            train.distanceAhead(to: lhs.targetPositionM ?? lhs.positionM) < train.distanceAhead(to: rhs.targetPositionM ?? rhs.positionM)
        }
        guard let target = targets.first, let targetPosition = target.targetPositionM,
              let targetSpeed = target.targetSpeedKmh else {
            return ControllerEvaluation(system: .atsP, permittedSpeedKmh: nil,
                                        brakeCommanded: latchedTrains.contains(train.id), stateDescription: "no active virtual target", events: [])
        }
        let distanceM = max(0, train.distanceAhead(to: targetPosition) - safetyMarginM)
        let targetMps = targetSpeed / 3.6
        let permitted = sqrt(targetMps * targetMps + 2 * virtualDecelerationMps2 * distanceM) * 3.6
        let overspeed = train.speedKmh > permitted + overspeedToleranceKmh
        if overspeed { latchedTrains.insert(train.id) }
        var events: [SimulationEvent] = []
        if overspeed {
            events.append(event(.overspeed, train: train, system: .atsP, time: time,
                                message: "Fictional continuous braking-envelope overspeed.", sourceID: target.id, permittedSpeedKmh: permitted))
        }
        if latchedTrains.contains(train.id) {
            events.append(event(.automaticBrake, train: train, system: .atsP, time: time,
                                message: "Fictional ATS-P-style profile brake command is latched.", sourceID: target.id, permittedSpeedKmh: permitted))
        }
        return ControllerEvaluation(system: .atsP, permittedSpeedKmh: permitted,
                                    brakeCommanded: latchedTrains.contains(train.id),
                                    stateDescription: overspeed ? "profile exceeded" : "continuous profile supervision", events: events)
    }

    mutating func reset(trainID: String) { latchedTrains.remove(trainID) }
}

struct ATSPSController {
    private struct ActiveLimit {
        let speedKmh: Double
        let endPositionM: Double
        let direction: TravelDirection
        let deviceID: String
    }
    let overspeedToleranceKmh: Double
    private var activeByTrain: [String: ActiveLimit] = [:]
    private var latchedTrains: Set<String> = []

    mutating func evaluate(train: TrainState, previous: TrainState?, devices: [RouteEquipment], time: Double) -> ControllerEvaluation {
        var events: [SimulationEvent] = []
        let beacons = devices.filter { $0.trackID == train.trackID && $0.kind == .atsPsSpeedBeacon }
        for beacon in beacons where crossed(beacon.positionM, previous: previous, current: train) {
            guard let speed = beacon.targetSpeedKmh, let distance = beacon.supervisionDistanceM else { continue }
            let end = beacon.positionM + (train.direction == .increasingChainage ? distance : -distance)
            activeByTrain[train.id] = ActiveLimit(speedKmh: speed, endPositionM: end, direction: train.direction, deviceID: beacon.id)
            events.append(event(.warning, train: train, system: .atsPs, time: time,
                                message: "Fictional point-beacon speed command activated for a bounded route window.", sourceID: beacon.id,
                                permittedSpeedKmh: speed))
        }
        if let active = activeByTrain[train.id] {
            let remaining = train.direction == .increasingChainage
                ? active.endPositionM - train.frontPositionM
                : train.frontPositionM - active.endPositionM
            if active.direction != train.direction || remaining < 0 {
                activeByTrain.removeValue(forKey: train.id)
            }
        }
        guard let active = activeByTrain[train.id] else {
            return ControllerEvaluation(system: .atsPs, permittedSpeedKmh: nil,
                                        brakeCommanded: latchedTrains.contains(train.id), stateDescription: "no active point-beacon window", events: events)
        }
        let overspeed = train.speedKmh > active.speedKmh + overspeedToleranceKmh
        if overspeed { latchedTrains.insert(train.id) }
        if overspeed {
            events.append(event(.overspeed, train: train, system: .atsPs, time: time,
                                message: "Fictional point-beacon speed limit exceeded within its configured window.", sourceID: active.deviceID,
                                permittedSpeedKmh: active.speedKmh))
        }
        if latchedTrains.contains(train.id) {
            events.append(event(.automaticBrake, train: train, system: .atsPs, time: time,
                                message: "Fictional ATS-Ps-style simulated brake command is latched.", sourceID: active.deviceID,
                                permittedSpeedKmh: active.speedKmh))
        }
        return ControllerEvaluation(system: .atsPs, permittedSpeedKmh: active.speedKmh,
                                    brakeCommanded: latchedTrains.contains(train.id),
                                    stateDescription: "point command active through \(active.endPositionM)m", events: events)
    }

    mutating func reset(trainID: String) {
        activeByTrain.removeValue(forKey: trainID)
        latchedTrains.remove(trainID)
    }
}

struct ATCController {
    let speedCommandsByClearBlocks: [Int: Double]
    let overspeedToleranceKmh: Double
    private var latchedTrains: Set<String> = []

    mutating func evaluate(train: TrainState, network: RailwayNetwork, occupancy: [String: Set<String>], devices: [RouteEquipment], time: Double) -> ControllerEvaluation {
        guard let track = network.track(train.trackID) else {
            return ControllerEvaluation(system: .atc, permittedSpeedKmh: 0, brakeCommanded: true, stateDescription: "unknown track", events: [])
        }
        let atTrackEnd = abs(train.frontPositionM - track.lengthM) <= 0.001
        let index = track.blocks.firstIndex { block in
            block.startM <= train.frontPositionM &&
                (train.frontPositionM < block.endM || (atTrackEnd && abs(block.endM - track.lengthM) <= 0.001))
        }
        var clearAhead = 0
        if let index {
            let candidateIndices: [Int] = train.direction == .increasingChainage
                ? Array((index + 1)..<track.blocks.count)
                : Array((0..<index).reversed())
            for blockIndex in candidateIndices {
                let block = track.blocks[blockIndex]
                let otherTrains = (occupancy[block.id] ?? []).subtracting([train.id])
                if !otherTrains.isEmpty { break }
                clearAhead += 1
            }
        }
        let baseSpeed = speedCommandsByClearBlocks.keys.filter { $0 <= clearAhead }.max().flatMap { speedCommandsByClearBlocks[$0] } ?? 0
        let activeZoneSpeeds = devices.compactMap { device -> Double? in
            guard device.trackID == train.trackID, device.kind == .atcCommandZone,
                  let start = device.zoneStartM, let end = device.zoneEndM,
                  train.frontPositionM >= start, train.frontPositionM <= end else { return nil }
            return device.targetSpeedKmh
        }
        let permitted = ([baseSpeed] + activeZoneSpeeds).min() ?? 0
        let overspeed = train.speedKmh > permitted + overspeedToleranceKmh
        if overspeed { latchedTrains.insert(train.id) }
        var events: [SimulationEvent] = []
        if overspeed {
            events.append(event(.overspeed, train: train, system: .atc, time: time,
                                message: "Fictional continuous block-command speed exceeded.", permittedSpeedKmh: permitted))
        }
        if latchedTrains.contains(train.id) {
            events.append(event(.automaticBrake, train: train, system: .atc, time: time,
                                message: "Fictional ATC-style simulated brake command is latched.", permittedSpeedKmh: permitted))
        }
        return ControllerEvaluation(system: .atc, permittedSpeedKmh: permitted,
                                    brakeCommanded: latchedTrains.contains(train.id),
                                    stateDescription: "continuous simulated block-speed command (\(clearAhead) clear blocks ahead)", events: events)
    }

    mutating func reset(trainID: String) { latchedTrains.remove(trainID) }
}

struct ATOController {
    let maximumSpeedKmh: Double
    let virtualDecelerationMps2: Double
    let accelerationGain: Double
    let brakeGain: Double

    func command(train: TrainState, devices: [RouteEquipment], routeAvailable: Bool, signalAspect: SignalAspect?) -> ATOCommand? {
        let targets = devices.filter { device in
            device.trackID == train.trackID && device.kind == .atoTarget &&
            (device.targetPositionM.map { train.distanceAhead(to: $0) >= 0 } ?? false)
        }.sorted { lhs, rhs in
            train.distanceAhead(to: lhs.targetPositionM ?? lhs.positionM) < train.distanceAhead(to: rhs.targetPositionM ?? rhs.positionM)
        }
        guard let target = targets.first, let targetPosition = target.targetPositionM,
              let targetSpeed = target.targetSpeedKmh else { return nil }
        let distance = max(0, train.distanceAhead(to: targetPosition))
        let targetMps = targetSpeed / 3.6
        let stopEnvelopeKmh = sqrt(targetMps * targetMps + 2 * virtualDecelerationMps2 * distance) * 3.6
        var commandedSpeed = min(maximumSpeedKmh, stopEnvelopeKmh)
        let mustHold = !routeAvailable || signalAspect == .stop
        if mustHold { commandedSpeed = 0 }
        let difference = commandedSpeed - train.speedKmh
        let traction = difference > 0.5 ? min(1, difference * accelerationGain) : 0
        let brake = difference < -0.5 ? min(1, -difference * brakeGain) : 0
        return ATOCommand(targetSpeedKmh: commandedSpeed, tractionFraction: traction,
                          brakeFraction: mustHold ? 1 : brake, holdForRoute: mustHold,
                          label: .fictionalSimulationOnly)
    }
}

struct DriverMonitorController {
    private struct DriverState {
        var lastActivityTime: Double?
        var ebWarningIssued = false
        var ebBrakeLatched = false
        var deadmanReleasedAt: Double?
        var deadmanWarningIssued = false
        var deadmanBrakeLatched = false
    }
    let activityWarningSeconds: Double
    let activityBrakeSeconds: Double
    let deadmanWarningSeconds: Double
    let deadmanBrakeSeconds: Double
    let minimumMonitoredSpeedKmh: Double
    private var stateByTrain: [String: DriverState] = [:]

    mutating func evaluate(train: TrainState, input: OperatorInput, time: Double) -> (eb: ControllerEvaluation, deadman: ControllerEvaluation) {
        var state = stateByTrain[train.id] ?? DriverState()
        var ebEvents: [SimulationEvent] = []
        var deadmanEvents: [SimulationEvent] = []
        if train.speedKmh >= minimumMonitoredSpeedKmh {
            if input.driverActivityPulse {
                state.lastActivityTime = time
                state.ebWarningIssued = false
            } else if state.lastActivityTime == nil {
                state.lastActivityTime = time
            }
            if let last = state.lastActivityTime {
                let elapsed = time - last
                if elapsed >= activityBrakeSeconds { state.ebBrakeLatched = true }
                if elapsed >= activityWarningSeconds && !state.ebWarningIssued {
                    state.ebWarningIssued = true
                    ebEvents.append(event(.warning, train: train, system: .eb, time: time,
                                         message: "Fictional EB inactivity timer warning."))
                }
            }
        } else if input.driverActivityPulse {
            state.lastActivityTime = time
            state.ebWarningIssued = false
        }

        if input.deadmanHeld {
            state.deadmanReleasedAt = nil
            state.deadmanWarningIssued = false
        } else {
            if state.deadmanReleasedAt == nil { state.deadmanReleasedAt = time }
            if let releasedAt = state.deadmanReleasedAt {
                let elapsed = time - releasedAt
                if elapsed >= deadmanBrakeSeconds { state.deadmanBrakeLatched = true }
                if elapsed >= deadmanWarningSeconds && !state.deadmanWarningIssued {
                    state.deadmanWarningIssued = true
                    deadmanEvents.append(event(.warning, train: train, system: .deadman, time: time,
                                               message: "Fictional deadman release timer warning."))
                }
            }
        }
        if state.ebBrakeLatched {
            ebEvents.append(event(.automaticBrake, train: train, system: .eb, time: time,
                                 message: "Fictional EB inactivity timer elapsed; simulated brake command is latched."))
        }
        if state.deadmanBrakeLatched {
            deadmanEvents.append(event(.automaticBrake, train: train, system: .deadman, time: time,
                                       message: "Fictional deadman release timer elapsed; simulated brake command is latched."))
        }
        stateByTrain[train.id] = state
        return (
            ControllerEvaluation(system: .eb, permittedSpeedKmh: nil, brakeCommanded: state.ebBrakeLatched,
                                 stateDescription: state.ebBrakeLatched ? "inactivity brake latched" : "activity monitoring", events: ebEvents),
            ControllerEvaluation(system: .deadman, permittedSpeedKmh: nil, brakeCommanded: state.deadmanBrakeLatched,
                                 stateDescription: state.deadmanBrakeLatched ? "release brake latched" : (input.deadmanHeld ? "held" : "released / timing"), events: deadmanEvents)
        )
    }

    mutating func reset(trainID: String) { stateByTrain.removeValue(forKey: trainID) }
}
