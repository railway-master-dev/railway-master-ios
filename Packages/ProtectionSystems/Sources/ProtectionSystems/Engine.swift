import Foundation

/// Tunable fictional defaults. None of these values are specifications for a real railway system.
public struct ProtectionEngineConfiguration: Equatable, Sendable {
    public let approachRadiusM: Double
    public let atssAcknowledgementTimeoutSeconds: Double
    public let atspVirtualDecelerationMps2: Double
    public let atspSafetyMarginM: Double
    public let overspeedToleranceKmh: Double
    public let atcSpeedCommandsByClearBlocks: [Int: Double]
    public let driverActivityWarningSeconds: Double
    public let driverActivityBrakeSeconds: Double
    public let deadmanWarningSeconds: Double
    public let deadmanBrakeSeconds: Double
    public let atoMaximumSpeedKmh: Double
    public let atoVirtualDecelerationMps2: Double
    public let atoAccelerationGain: Double
    public let atoBrakeGain: Double
    public let prcDispatchLeadSeconds: Double

    public init(
        approachRadiusM: Double = 300,
        atssAcknowledgementTimeoutSeconds: Double = 4,
        atspVirtualDecelerationMps2: Double = 0.8,
        atspSafetyMarginM: Double = 8,
        overspeedToleranceKmh: Double = 0,
        atcSpeedCommandsByClearBlocks: [Int: Double] = [0: 0, 1: 25, 2: 50, 3: 80],
        driverActivityWarningSeconds: Double = 8,
        driverActivityBrakeSeconds: Double = 12,
        deadmanWarningSeconds: Double = 2,
        deadmanBrakeSeconds: Double = 4,
        atoMaximumSpeedKmh: Double = 75,
        atoVirtualDecelerationMps2: Double = 1.0,
        atoAccelerationGain: Double = 0.08,
        atoBrakeGain: Double = 0.15,
        prcDispatchLeadSeconds: Double = 30
    ) throws {
        let nonnegative = [approachRadiusM, atspSafetyMarginM, overspeedToleranceKmh]
        let positive = [atssAcknowledgementTimeoutSeconds, atspVirtualDecelerationMps2,
                        driverActivityWarningSeconds, driverActivityBrakeSeconds,
                        deadmanWarningSeconds, deadmanBrakeSeconds, atoMaximumSpeedKmh,
                        atoVirtualDecelerationMps2, atoAccelerationGain, atoBrakeGain]
        guard nonnegative.allSatisfy({ $0.isFinite && $0 >= 0 }),
              positive.allSatisfy({ $0.isFinite && $0 > 0 }),
              driverActivityBrakeSeconds >= driverActivityWarningSeconds,
              deadmanBrakeSeconds >= deadmanWarningSeconds,
              prcDispatchLeadSeconds.isFinite && prcDispatchLeadSeconds >= 0,
              !atcSpeedCommandsByClearBlocks.isEmpty,
              atcSpeedCommandsByClearBlocks.allSatisfy({ $0.key >= 0 && $0.value.isFinite && $0.value >= 0 }) else {
            throw ProtectionPackageError.invalidValue("fictional engine configuration")
        }
        self.approachRadiusM = approachRadiusM
        self.atssAcknowledgementTimeoutSeconds = atssAcknowledgementTimeoutSeconds
        self.atspVirtualDecelerationMps2 = atspVirtualDecelerationMps2
        self.atspSafetyMarginM = atspSafetyMarginM
        self.overspeedToleranceKmh = overspeedToleranceKmh
        self.atcSpeedCommandsByClearBlocks = atcSpeedCommandsByClearBlocks
        self.driverActivityWarningSeconds = driverActivityWarningSeconds
        self.driverActivityBrakeSeconds = driverActivityBrakeSeconds
        self.deadmanWarningSeconds = deadmanWarningSeconds
        self.deadmanBrakeSeconds = deadmanBrakeSeconds
        self.atoMaximumSpeedKmh = atoMaximumSpeedKmh
        self.atoVirtualDecelerationMps2 = atoVirtualDecelerationMps2
        self.atoAccelerationGain = atoAccelerationGain
        self.atoBrakeGain = atoBrakeGain
        self.prcDispatchLeadSeconds = prcDispatchLeadSeconds
    }
}

/// Stateful host-facing API. Call `step` once per monotonically increasing fixed simulation tick.
/// The host physics remains authoritative; ATO/brake outputs are commands/events, not train motion.
public struct ProtectionSystemEngine: Sendable {
    public let network: RailwayNetwork
    public let systemsByTrain: [String: Set<ProtectionSystemKind>]
    public let configuration: ProtectionEngineConfiguration

    private var atsS = ATSSController(acknowledgementTimeoutSeconds: 4)
    private var atsP: ATSPController
    private var atsPs: ATSPSController
    private var atc: ATCController
    private var ato: ATOController
    private var driverMonitor: DriverMonitorController
    private var lastFrame: SimulationFrame?

    public init(
        network: RailwayNetwork,
        systemsByTrain: [String: Set<ProtectionSystemKind>],
        configuration: ProtectionEngineConfiguration = try! ProtectionEngineConfiguration()
    ) {
        self.network = network
        self.systemsByTrain = systemsByTrain
        self.configuration = configuration
        self.atsS = ATSSController(acknowledgementTimeoutSeconds: configuration.atssAcknowledgementTimeoutSeconds)
        self.atsP = ATSPController(virtualDecelerationMps2: configuration.atspVirtualDecelerationMps2,
                                   safetyMarginM: configuration.atspSafetyMarginM,
                                   overspeedToleranceKmh: configuration.overspeedToleranceKmh)
        self.atsPs = ATSPSController(overspeedToleranceKmh: configuration.overspeedToleranceKmh)
        self.atc = ATCController(speedCommandsByClearBlocks: configuration.atcSpeedCommandsByClearBlocks,
                                 overspeedToleranceKmh: configuration.overspeedToleranceKmh)
        self.ato = ATOController(maximumSpeedKmh: configuration.atoMaximumSpeedKmh,
                                 virtualDecelerationMps2: configuration.atoVirtualDecelerationMps2,
                                 accelerationGain: configuration.atoAccelerationGain,
                                 brakeGain: configuration.atoBrakeGain)
        self.driverMonitor = DriverMonitorController(
            activityWarningSeconds: configuration.driverActivityWarningSeconds,
            activityBrakeSeconds: configuration.driverActivityBrakeSeconds,
            deadmanWarningSeconds: configuration.deadmanWarningSeconds,
            deadmanBrakeSeconds: configuration.deadmanBrakeSeconds,
            minimumMonitoredSpeedKmh: 0.5
        )
    }

    public mutating func step(_ frame: SimulationFrame) throws -> SimulationResult {
        if let previous = lastFrame {
            guard frame.fixedTick > previous.fixedTick, frame.timeSeconds > previous.timeSeconds else {
                throw ProtectionPackageError.timeMustIncrease
            }
        }

        // PRC-like planning only proposes requests. The interlocking evaluates every proposal.
        let prc = try PRCController(dispatchLeadSeconds: configuration.prcDispatchLeadSeconds)
        let proposals = prc.proposedRouteRequests(frame: frame, network: network)
        var requests = frame.routeRequests
        for (trainID, routeID) in proposals where requests[trainID] == nil {
            requests[trainID] = routeID
        }
        let evaluatedFrame = try SimulationFrame(
            fixedTick: frame.fixedTick,
            timeSeconds: frame.timeSeconds,
            trains: frame.trains,
            switchPositions: frame.switchPositions,
            routeRequests: requests,
            operatorInputs: frame.operatorInputs,
            timetableAssignments: frame.timetableAssignments
        )
        for train in evaluatedFrame.trains {
            if evaluatedFrame.operatorInputs[train.id]?.resetProtectionAtStop == true && train.speedKmh > 0.1 {
                throw ProtectionPackageError.invalidValue("fictional protection reset requires a stopped train")
            }
        }
        let interlocking = try InterlockingEvaluator(network: network).evaluate(evaluatedFrame)
        let previousTrains = Dictionary(uniqueKeysWithValues: (lastFrame?.trains ?? []).map { ($0.id, $0) })
        let grantsByTrain = Dictionary(uniqueKeysWithValues: interlocking.routeGrants.map { ($0.trainID, $0) })
        var events: [SimulationEvent] = []
        var protectionStates: [SystemProtectionState] = []
        var atoCommands: [String: ATOCommand] = [:]

        for (trainID, routeID) in proposals.sorted(by: { $0.key < $1.key }) {
            guard let train = evaluatedFrame.trains.first(where: { $0.id == trainID }) else { continue }
            events.append(SimulationEvent(id: "prc:\(trainID):\(evaluatedFrame.fixedTick)", kind: .timetableRouteProposed,
                                          timeSeconds: frame.timeSeconds, trainID: trainID, system: "PRC",
                                          sourceID: routeID, message: "Fictional timetable controller proposed a route; interlocking approval is still required."))
        }
        for grant in interlocking.routeGrants {
            events.append(SimulationEvent(id: "route:\(grant.id):\(evaluatedFrame.fixedTick)",
                                          kind: grant.granted ? .routeGranted : .routeDenied,
                                          timeSeconds: frame.timeSeconds, trainID: grant.trainID, system: "INTERLOCKING",
                                          sourceID: grant.routeID,
                                          message: grant.granted ? "Fictional route request granted." : (grant.denialReason ?? "Fictional route request denied.")))
        }

        for train in evaluatedFrame.trains.sorted(by: { $0.id < $1.id }) {
            let previous = previousTrains[train.id]
            let input = evaluatedFrame.operatorInputs[train.id] ?? OperatorInput()
            let enabled = systemsByTrain[train.id] ?? []
            let mounted = network.equipment.filter { $0.trackID == train.trackID }

            if input.resetProtectionAtStop {
                atsS.reset(trainID: train.id)
                atsP.reset(trainID: train.id)
                atsPs.reset(trainID: train.id)
                atc.reset(trainID: train.id)
                driverMonitor.reset(trainID: train.id)
                events.append(SimulationEvent(id: "reset:\(train.id):\(evaluatedFrame.fixedTick)",
                                              kind: .protectionReset, timeSeconds: frame.timeSeconds,
                                              trainID: train.id, system: "PROTECTION",
                                              message: "Fictional model latches were explicitly reset after the train stopped."))
            }

            for device in mounted {
                let distance = train.distanceAhead(to: device.positionM)
                let previousDistance = previous.map { $0.distanceAhead(to: device.positionM) }
                let enteredApproach = distance >= 0 && distance <= configuration.approachRadiusM &&
                    (previousDistance == nil || previousDistance! > configuration.approachRadiusM)
                if enteredApproach {
                    events.append(SimulationEvent(id: "approach:\(train.id):\(device.id):\(evaluatedFrame.fixedTick)",
                                                  kind: .equipmentApproach, timeSeconds: frame.timeSeconds,
                                                  trainID: train.id, system: device.kind.rawValue, sourceID: device.id,
                                                  message: "Train entered the fictional approach radius of route-mounted equipment."))
                }
            }

            if enabled.contains(.atsS) {
                let result = atsS.evaluate(train: train, previous: previous, devices: mounted, input: input, time: frame.timeSeconds)
                protectionStates.append(status(train, result))
                events.append(contentsOf: result.events)
            }
            if enabled.contains(.atsP) {
                let result = atsP.evaluate(train: train, devices: mounted, time: frame.timeSeconds)
                protectionStates.append(status(train, result))
                events.append(contentsOf: result.events)
            }
            if enabled.contains(.atsPs) {
                let result = atsPs.evaluate(train: train, previous: previous, devices: mounted, time: frame.timeSeconds)
                protectionStates.append(status(train, result))
                events.append(contentsOf: result.events)
            }
            if enabled.contains(.atc) {
                let result = atc.evaluate(train: train, network: network,
                                          occupancy: interlocking.occupiedTrainIDsByBlock,
                                          devices: mounted, time: frame.timeSeconds)
                protectionStates.append(status(train, result))
                events.append(contentsOf: result.events)
            }
            if enabled.contains(.eb) || enabled.contains(.deadman) {
                let monitored = driverMonitor.evaluate(train: train, input: input, time: frame.timeSeconds)
                if enabled.contains(.eb) {
                    protectionStates.append(status(train, monitored.eb))
                    events.append(contentsOf: monitored.eb.events)
                }
                if enabled.contains(.deadman) {
                    protectionStates.append(status(train, monitored.deadman))
                    events.append(contentsOf: monitored.deadman.events)
                }
            }
            if enabled.contains(.ato), let command = ato.command(
                train: train,
                devices: mounted,
                routeAvailable: grantsByTrain[train.id]?.granted ?? true,
                signalAspect: nextSignalAspect(for: train, signals: interlocking.signals)
            ) {
                atoCommands[train.id] = command
                protectionStates.append(SystemProtectionState(trainID: train.id, system: ProtectionSystemKind.ato.rawValue,
                                                              permittedSpeedKmh: command.targetSpeedKmh,
                                                              brakeCommanded: command.brakeFraction > 0,
                                                              stateDescription: command.holdForRoute ? "automatic command held for route/signal" : "fictional automatic speed/stop command"))
            }
        }

        let ctc = CTCController().summaries(frame: evaluatedFrame, routeGrants: interlocking.routeGrants)
        events.sort { lhs, rhs in
            if lhs.timeSeconds != rhs.timeSeconds { return lhs.timeSeconds < rhs.timeSeconds }
            return lhs.id < rhs.id
        }
        protectionStates.sort { $0.id < $1.id }
        lastFrame = evaluatedFrame
        return SimulationResult(fixedTick: evaluatedFrame.fixedTick, timeSeconds: evaluatedFrame.timeSeconds,
                                 blockOccupancy: interlocking.blockOccupancy, routeGrants: interlocking.routeGrants,
                                 signals: interlocking.signals, protectionStates: protectionStates,
                                 atoCommands: atoCommands, ctcTrains: ctc, events: events,
                                 label: .fictionalSimulationOnly)
    }

    private func status(_ train: TrainState, _ result: ControllerEvaluation) -> SystemProtectionState {
        SystemProtectionState(trainID: train.id, system: result.system.rawValue,
                              permittedSpeedKmh: result.permittedSpeedKmh,
                              brakeCommanded: result.brakeCommanded,
                              stateDescription: result.stateDescription)
    }

    private func nextSignalAspect(for train: TrainState, signals: [SignalState]) -> SignalAspect? {
        let definitionsByID = Dictionary(uniqueKeysWithValues: network.signals.map { ($0.id, $0) })
        return signals.compactMap { state -> (Double, SignalAspect)? in
            guard let definition = definitionsByID[state.id], definition.trackID == train.trackID else { return nil }
            let distance = train.distanceAhead(to: definition.positionM)
            guard distance >= 0 else { return nil }
            return (distance, state.aspect)
        }.min(by: { $0.0 < $1.0 })?.1
    }
}
