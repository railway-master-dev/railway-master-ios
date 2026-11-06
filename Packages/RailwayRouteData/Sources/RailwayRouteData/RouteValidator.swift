import Foundation

public enum ValidationSeverity: String, Codable, Sendable {
    case error = "ERROR"
    case warning = "WARNING"
    case info = "INFO"
}

public struct ValidationIssue: Codable, Sendable {
    public let severity: ValidationSeverity
    public let code: String
    public let entityID: String
    public let message: String
    public let suggestedFix: String
    public let evidence: [String]
}

public struct ValidationReport: Codable, Sendable {
    public let routeID: String
    public let issues: [ValidationIssue]
    public var errorCount: Int { issues.filter { $0.severity == .error }.count }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    public var infoCount: Int { issues.filter { $0.severity == .info }.count }
    public var isStructurallyValid: Bool { errorCount == 0 }
}

/// Read-only quality checks. Suggestions are advisory; this validator never mutates source data.
public enum RouteValidator {
    public static func validate(_ package: RoutePackage) -> ValidationReport {
        let route = package.route
        var issues: [ValidationIssue] = []
        let sourceIDs = Set(package.sources.map(\.sourceID))

        if package.schemaVersion.isEmpty {
            issues.append(issue(.error, "SCHEMA_VERSION_MISSING", package.packageID,
                                "Package schema version is empty.", "Set an explicit schema version before publishing."))
        }
        if package.packageID.isEmpty || route.routeID.isEmpty {
            issues.append(issue(.error, "IDENTIFIER_MISSING", route.routeID,
                                "Package or route identifier is empty.", "Assign stable, non-empty identifiers."))
        }
        if Set(package.sources.map(\.sourceID)).count != package.sources.count {
            issues.append(issue(.error, "DUPLICATE_SOURCE_ID", package.packageID,
                                "Source IDs are not unique.", "Give each source record a unique sourceID."))
        }
        for source in package.sources {
            if source.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue(.warning, "SOURCE_LICENSE_MISSING", source.sourceID,
                                    "Source usage or license terms are not recorded.", "Record the applicable license/terms and attribution; do not redistribute until rights are clear."))
            }
            if let rawURL = source.url, URL(string: rawURL)?.scheme == nil {
                issues.append(issue(.warning, "SOURCE_URL_INVALID", source.sourceID,
                                    "Source URL is not an absolute URL.", "Store the original public source URL or leave it null when none exists."))
            }
        }

        issues += audit(route.name, label: "route.name", entityID: route.routeID, sourceIDs: sourceIDs)
        issues += audit(route.totalLengthM, label: "route.totalLengthM", entityID: route.routeID, sourceIDs: sourceIDs)
        issues += audit(route.networkLengthM, label: "route.networkLengthM", entityID: route.routeID, sourceIDs: sourceIDs)
        issues += audit(route.officialCommercialDistanceM, label: "route.officialCommercialDistanceM", entityID: route.routeID, sourceIDs: sourceIDs)
        if let length = route.totalLengthM.value, (!length.isFinite || length <= 0) {
            issues.append(issue(.error, "ROUTE_LENGTH_INVALID", route.routeID,
                                "Route length must be finite and positive.", "Replace it with a sourced chainage extent or mark it UNKNOWN."))
        }
        if let commercial = route.officialCommercialDistanceM.value, !commercial.isFinite || commercial <= 0 {
            issues.append(issue(.error, "COMMERCIAL_DISTANCE_INVALID", route.routeID,
                                "Official commercial distance must be finite and positive.", "Check the operator's published unit and retain it separately from physical track chainage."))
        }
        if let networkLength = route.networkLengthM.value, !networkLength.isFinite || networkLength <= 0 {
            issues.append(issue(.error, "NETWORK_LENGTH_INVALID", route.routeID,
                                "Network length must be finite and positive.", "Check the unique physical-line length sum and keep it separate from main-line chainage."))
        }

        let trackIDs = Set(route.tracks.map(\.trackID))
        if !trackIDs.contains(route.mainTrackID) {
            issues.append(issue(.error, "MAIN_TRACK_MISSING", route.routeID,
                                "The designated main track does not exist.", "Set mainTrackID to a track in this route package."))
        }
        checkUnique(route.tracks.map(\.trackID), type: "track", issues: &issues, routeID: route.routeID)
        checkUnique(route.stations.map(\.stationID), type: "station", issues: &issues, routeID: route.routeID)
        checkUnique(route.speedRestrictions.map(\.restrictionID), type: "speed restriction", issues: &issues, routeID: route.routeID)
        checkUnique(route.signals.map(\.signalID), type: "signal", issues: &issues, routeID: route.routeID)
        checkUnique(route.blocks.map(\.blockID), type: "block", issues: &issues, routeID: route.routeID)
        checkUnique(route.switches.map(\.switchID), type: "switch", issues: &issues, routeID: route.routeID)
        checkUnique(route.structures.map(\.structureID), type: "structure", issues: &issues, routeID: route.routeID)
        checkUnique(route.levelCrossings.map(\.crossingID), type: "level crossing", issues: &issues, routeID: route.routeID)
        checkUnique(route.servicePatterns.map(\.servicePatternID), type: "service pattern", issues: &issues, routeID: route.routeID)
        checkUnique(route.operatingProfiles.map(\.profileID), type: "operating profile", issues: &issues, routeID: route.routeID)
        checkUnique(route.depots.map(\.depotID), type: "depot", issues: &issues, routeID: route.routeID)
        let allSignalIDs = Set(route.signals.map(\.signalID))
        let allSwitchIDs = Set(route.switches.map(\.switchID))
        let allBlockIDs = Set(route.blocks.map(\.blockID))

        for track in route.tracks {
            issues += audit(track.name, label: "track.name", entityID: track.trackID, sourceIDs: sourceIDs)
            issues += audit(track.direction, label: "track.direction", entityID: track.trackID, sourceIDs: sourceIDs)
            issues += audit(track.gaugeMM, label: "track.gaugeMM", entityID: track.trackID, sourceIDs: sourceIDs)
            issues += audit(track.centerSpacingMM, label: "track.centerSpacingMM", entityID: track.trackID, sourceIDs: sourceIDs)
            if let gauge = track.gaugeMM.value, gauge < 500 || gauge > 2000 {
                issues.append(issue(.warning, "TRACK_GAUGE_OUTLIER", track.trackID,
                                    "Track gauge \(gauge) mm is outside the broad sanity range 500–2000 mm.", "Verify the unit, track identity, and source."))
            }
            issues += validateTrack(track, routeLengthM: track.trackID == route.mainTrackID ? route.totalLengthM.value : nil,
                                    policy: route.validationPolicy, sourceIDs: sourceIDs)
        }
        if let declaredNetworkLength = route.networkLengthM.value {
            let trackLengthSum = route.tracks.compactMap { trackBounds($0).map { $0.end - $0.start } }.reduce(0, +)
            if trackLengthSum > 0 && abs(trackLengthSum - declaredNetworkLength) > max(10, declaredNetworkLength * 0.01) {
                issues.append(issue(.warning, "NETWORK_LENGTH_MISMATCH", route.routeID,
                                    "Sum of distinct track extents differs from networkLengthM by more than 10 m or 1%.",
                                    "Check whether track extents are unique route lengths or parallel-track duplicates before reconciling."))
            }
        }

        let platformIDs = route.stations.flatMap { $0.platforms.map(\.platformID) }
        checkUnique(platformIDs, type: "platform", issues: &issues, routeID: route.routeID)
        for station in route.stations {
            issues += audit(station.name, label: "station.name", entityID: station.stationID, sourceIDs: sourceIDs)
            issues += audit(station.chainageM, label: "station.chainageM", entityID: station.stationID, sourceIDs: sourceIDs)
            issues += audit(station.stopPositionChainageM, label: "station.stopPositionChainageM", entityID: station.stationID, sourceIDs: sourceIDs)
            issues += audit(station.location, label: "station.location", entityID: station.stationID, sourceIDs: sourceIDs)
            issues += audit(station.trackLayoutNotes, label: "station.trackLayoutNotes", entityID: station.stationID, sourceIDs: sourceIDs)
            for trackID in station.trackIDs where !trackIDs.contains(trackID) {
                issues.append(issue(.error, "STATION_TRACK_MISSING", station.stationID,
                                    "Station references missing track \(trackID).", "Correct the track ID or add the track to this route."))
            }
            if let stationChainage = station.chainageM.value,
               let length = route.totalLengthM.value,
               stationChainage < 0 || stationChainage > length {
                issues.append(issue(.error, "STATION_CHAINAGE_OUT_OF_RANGE", station.stationID,
                                    "Station chainage lies outside route extent.", "Check chainage datum and route limits."))
            }
            if let coord = station.location.value { issues += validateCoordinate(coord, entityID: station.stationID) }
            for platform in station.platforms {
                issues += audit(platform.trackSide, label: "platform.trackSide", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.alignment, label: "platform.alignment", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.startChainageM, label: "platform.startChainageM", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.endChainageM, label: "platform.endChainageM", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.lengthM, label: "platform.lengthM", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.widthM, label: "platform.widthM", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.heightAboveRailM, label: "platform.heightAboveRailM", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.gradientPermille, label: "platform.gradientPermille", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.hasPlatformDoors, label: "platform.hasPlatformDoors", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.roofType, label: "platform.roofType", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.stationBuildingPosition, label: "platform.stationBuildingPosition", entityID: platform.platformID, sourceIDs: sourceIDs)
                issues += audit(platform.equipmentNotes, label: "platform.equipmentNotes", entityID: platform.platformID, sourceIDs: sourceIDs)
                guard let start = platform.startChainageM.value, let end = platform.endChainageM.value else { continue }
                if end <= start {
                    issues.append(issue(.error, "PLATFORM_RANGE_INVALID", platform.platformID,
                                        "Platform end chainage must be greater than its start.", "Correct the endpoints or mark them UNKNOWN."))
                }
                if let length = platform.lengthM.value, abs((end - start) - length) > max(5, length * 0.05) {
                    issues.append(issue(.warning, "PLATFORM_LENGTH_MISMATCH", platform.platformID,
                                        "Platform length differs from its chainage extent by more than 5 m or 5%.", "Check the platform endpoints, unit, and source."))
                }
                if !trackIDs.contains(platform.trackID) {
                    issues.append(issue(.error, "PLATFORM_TRACK_MISSING", platform.platformID,
                                        "Platform references missing track \(platform.trackID).", "Correct the track ID or add the track."))
                }
                if let track = route.tracks.first(where: { $0.trackID == platform.trackID }),
                   let bounds = trackBounds(track),
                   start < bounds.start - 1 || end > bounds.end + 1 {
                    issues.append(issue(.error, "PLATFORM_OFF_TRACK", platform.platformID,
                                        "Platform chainage extends outside its associated track.", "Align platform endpoints with the track chainage and verify direction."))
                }
                if let stationChainage = station.chainageM.value,
                   stationChainage < start - 100 || stationChainage > end + 100 {
                    issues.append(issue(.warning, "PLATFORM_STATION_OFFSET", platform.platformID,
                                        "Station reference chainage is more than 100 m outside this platform range.", "Confirm the station reference point and platform chainage datum."))
                }
            }
        }

        for restriction in route.speedRestrictions {
            issues += audit(restriction.startChainageM, label: "restriction.startChainageM", entityID: restriction.restrictionID, sourceIDs: sourceIDs)
            issues += audit(restriction.endChainageM, label: "restriction.endChainageM", entityID: restriction.restrictionID, sourceIDs: sourceIDs)
            issues += audit(restriction.limitKmh, label: "restriction.limitKmh", entityID: restriction.restrictionID, sourceIDs: sourceIDs)
            issues += audit(restriction.kind, label: "restriction.kind", entityID: restriction.restrictionID, sourceIDs: sourceIDs)
            issues += audit(restriction.direction, label: "restriction.direction", entityID: restriction.restrictionID, sourceIDs: sourceIDs)
            issues += audit(restriction.signChainageM, label: "restriction.signChainageM", entityID: restriction.restrictionID, sourceIDs: sourceIDs)
            issues += audit(restriction.description, label: "restriction.description", entityID: restriction.restrictionID, sourceIDs: sourceIDs)
            if !trackIDs.contains(restriction.trackID) {
                issues.append(issue(.error, "RESTRICTION_TRACK_MISSING", restriction.restrictionID,
                                    "Speed restriction references missing track \(restriction.trackID).", "Correct its track ID."))
            }
            if let start = restriction.startChainageM.value, let end = restriction.endChainageM.value, end <= start {
                issues.append(issue(.error, "RESTRICTION_RANGE_INVALID", restriction.restrictionID,
                                    "Speed restriction end must be greater than start.", "Correct the chainage range."))
            }
            if let limit = restriction.limitKmh.value, !limit.isFinite || limit <= 0 || limit > 400 {
                issues.append(issue(.warning, "SPEED_LIMIT_OUTLIER", restriction.restrictionID,
                                    "Speed limit is not in the broad expected range (0, 400] km/h.", "Verify the value and unit; do not substitute an assumed operating limit."))
            }
            if let sign = restriction.signChainageM.value,
               let start = restriction.startChainageM.value,
               sign > start + 1 {
                issues.append(issue(.warning, "SPEED_SIGN_AFTER_EFFECTIVE_POINT", restriction.restrictionID,
                                    "The sign is recorded after the effective start of the restriction.", "Verify sign chainage, direction, and whether braking advance is represented separately."))
            }
        }
        checkRestrictionOverlaps(route.speedRestrictions, issues: &issues)

        for signal in route.signals {
            issues += audit(signal.chainageM, label: "signal.chainageM", entityID: signal.signalID, sourceIDs: sourceIDs)
            issues += audit(signal.coordinate, label: "signal.coordinate", entityID: signal.signalID, sourceIDs: sourceIDs)
            issues += audit(signal.kind, label: "signal.kind", entityID: signal.signalID, sourceIDs: sourceIDs)
            issues += audit(signal.direction, label: "signal.direction", entityID: signal.signalID, sourceIDs: sourceIDs)
            issues += audit(signal.sightSide, label: "signal.sightSide", entityID: signal.signalID, sourceIDs: sourceIDs)
            issues += audit(signal.protectionSystem, label: "signal.protectionSystem", entityID: signal.signalID, sourceIDs: sourceIDs)
            issues += audit(signal.notes, label: "signal.notes", entityID: signal.signalID, sourceIDs: sourceIDs)
            for aspect in signal.aspects { issues += audit(aspect, label: "signal.aspect", entityID: signal.signalID, sourceIDs: sourceIDs) }
            if !trackIDs.contains(signal.trackID) {
                issues.append(issue(.error, "SIGNAL_TRACK_MISSING", signal.signalID,
                                    "Signal references missing track \(signal.trackID).", "Correct its track ID."))
            }
            if let blockID = signal.linkedBlockID, !allBlockIDs.contains(blockID) {
                issues.append(issue(.warning, "SIGNAL_BLOCK_MISSING", signal.signalID,
                                    "Signal links to unknown block \(blockID).", "Add the block or correct the link."))
            }
            if let coord = signal.coordinate.value { issues += validateCoordinate(coord, entityID: signal.signalID) }
            if let chainage = signal.chainageM.value,
               let track = route.tracks.first(where: { $0.trackID == signal.trackID }),
               let bounds = trackBounds(track),
               chainage < bounds.start || chainage > bounds.end {
                issues.append(issue(.error, "SIGNAL_OFF_TRACK", signal.signalID,
                                    "Signal chainage is outside its track extent.", "Recheck the signal's measured chainage and track assignment."))
            }
            if let coord = signal.coordinate.value, let chainage = signal.chainageM.value {
                issues += compareCoordinate(coord, chainage: chainage, trackID: signal.trackID, package: package, entityID: signal.signalID)
            }
            if signal.protectionSystem.value == nil {
                issues.append(issue(.info, "PROTECTION_SYSTEM_UNSPECIFIED", signal.signalID,
                                    "Signal protection/ATS/ATC system is not established.", "Populate only from public/authorized source material; otherwise keep UNKNOWN."))
            }
        }

        for block in route.blocks {
            issues += audit(block.startChainageM, label: "block.startChainageM", entityID: block.blockID, sourceIDs: sourceIDs)
            issues += audit(block.endChainageM, label: "block.endChainageM", entityID: block.blockID, sourceIDs: sourceIDs)
            issues += audit(block.trackCircuit, label: "block.trackCircuit", entityID: block.blockID, sourceIDs: sourceIDs)
            issues += audit(block.controlSystem, label: "block.controlSystem", entityID: block.blockID, sourceIDs: sourceIDs)
            if !trackIDs.contains(block.trackID) {
                issues.append(issue(.error, "BLOCK_TRACK_MISSING", block.blockID,
                                    "Block references missing track \(block.trackID).", "Correct its track ID."))
            }
            if let start = block.startChainageM.value, let end = block.endChainageM.value, end <= start {
                issues.append(issue(.error, "BLOCK_RANGE_INVALID", block.blockID,
                                    "Block end must be greater than its start.", "Correct the block boundary chainages."))
            }
            if let entry = block.entrySignalID, !allSignalIDs.contains(entry) {
                issues.append(issue(.warning, "BLOCK_ENTRY_SIGNAL_MISSING", block.blockID,
                                    "Entry signal \(entry) is not present in the route signal list.", "Add the signal or correct the association."))
            }
            if let exit = block.exitSignalID, !allSignalIDs.contains(exit) {
                issues.append(issue(.warning, "BLOCK_EXIT_SIGNAL_MISSING", block.blockID,
                                    "Exit signal \(exit) is not present in the route signal list.", "Add the signal or correct the association."))
            }
        }
        issues += validateBlockCoverage(route: route)

        for sw in route.switches {
            issues += audit(sw.chainageM, label: "switch.chainageM", entityID: sw.switchID, sourceIDs: sourceIDs)
            issues += audit(sw.coordinate, label: "switch.coordinate", entityID: sw.switchID, sourceIDs: sourceIDs)
            issues += audit(sw.switchKind, label: "switch.switchKind", entityID: sw.switchID, sourceIDs: sourceIDs)
            issues += audit(sw.notes, label: "switch.notes", entityID: sw.switchID, sourceIDs: sourceIDs)
            if !trackIDs.contains(sw.trackID) {
                issues.append(issue(.error, "SWITCH_TRACK_MISSING", sw.switchID,
                                    "Switch references missing track \(sw.trackID).", "Correct its track ID."))
            }
            for linkedTrack in sw.connectedTrackIDs where !trackIDs.contains(linkedTrack) {
                issues.append(issue(.error, "SWITCH_CONNECTION_MISSING", sw.switchID,
                                    "Switch connects to unknown track \(linkedTrack).", "Add the connected track or correct the connection."))
            }
            if let interlockingID = sw.interlockingID,
               !route.interlockings.contains(where: { $0.interlockingID == interlockingID }) {
                issues.append(issue(.warning, "SWITCH_INTERLOCKING_MISSING", sw.switchID,
                                    "Switch references unknown interlocking \(interlockingID).", "Add the interlocking or correct the reference."))
            }
            if let coord = sw.coordinate.value { issues += validateCoordinate(coord, entityID: sw.switchID) }
            for switchRoute in sw.routes {
                issues += audit(switchRoute.destinationChainageM, label: "switchRoute.destinationChainageM", entityID: sw.switchID, sourceIDs: sourceIDs)
                issues += audit(switchRoute.divergingSpeedKmh, label: "switchRoute.divergingSpeedKmh", entityID: sw.switchID, sourceIDs: sourceIDs)
                if !trackIDs.contains(switchRoute.destinationTrackID) {
                    issues.append(issue(.error, "SWITCH_ROUTE_DESTINATION_MISSING", sw.switchID,
                                        "Switch route \(switchRoute.routeID) references unknown destination track.", "Correct the destination track ID."))
                } else if let destinationChainage = switchRoute.destinationChainageM.value,
                          let destinationTrack = route.tracks.first(where: { $0.trackID == switchRoute.destinationTrackID }),
                          let bounds = trackBounds(destinationTrack),
                          destinationChainage < bounds.start || destinationChainage > bounds.end {
                    issues.append(issue(.error, "SWITCH_DESTINATION_CHAINAGE_OUT_OF_RANGE", sw.switchID,
                                        "Switch route destination chainage lies outside its connected track.", "Check the destination track's local chainage and topology."))
                }
            }
        }
        for interlocking in route.interlockings {
            issues += audit(interlocking.systemDescription, label: "interlocking.systemDescription", entityID: interlocking.interlockingID, sourceIDs: sourceIDs)
            for signalID in interlocking.controlledSignalIDs where !allSignalIDs.contains(signalID) {
                issues.append(issue(.warning, "INTERLOCKING_SIGNAL_MISSING", interlocking.interlockingID,
                                    "Interlocking references unknown signal \(signalID).", "Correct the association or add the signal."))
            }
            for switchID in interlocking.controlledSwitchIDs where !allSwitchIDs.contains(switchID) {
                issues.append(issue(.warning, "INTERLOCKING_SWITCH_MISSING", interlocking.interlockingID,
                                    "Interlocking references unknown switch \(switchID).", "Correct the association or add the switch."))
            }
        }

        for structure in route.structures {
            issues += audit(structure.kind, label: "structure.kind", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.name, label: "structure.name", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.centerCoordinate, label: "structure.centerCoordinate", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.startChainageM, label: "structure.startChainageM", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.endChainageM, label: "structure.endChainageM", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.lengthM, label: "structure.lengthM", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.heightM, label: "structure.heightM", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.structureType, label: "structure.structureType", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.trackSurface, label: "structure.trackSurface", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.hasLighting, label: "structure.hasLighting", entityID: structure.structureID, sourceIDs: sourceIDs)
            issues += audit(structure.notes, label: "structure.notes", entityID: structure.structureID, sourceIDs: sourceIDs)
            if !trackIDs.contains(structure.trackID) {
                issues.append(issue(.error, "STRUCTURE_TRACK_MISSING", structure.structureID,
                                    "Structure references missing track \(structure.trackID).", "Correct its track ID."))
            }
            if let coordinate = structure.centerCoordinate.value {
                issues += validateCoordinate(coordinate, entityID: structure.structureID)
            }
            if let start = structure.startChainageM.value, let end = structure.endChainageM.value {
                if end <= start {
                    issues.append(issue(.error, "STRUCTURE_RANGE_INVALID", structure.structureID,
                                        "Structure end chainage must be greater than its start.", "Correct its chainage range."))
                }
                if let length = structure.lengthM.value, abs((end - start) - length) > max(5, length * 0.05) {
                    issues.append(issue(.warning, "STRUCTURE_LENGTH_MISMATCH", structure.structureID,
                                        "Structure length differs from chainage extent by more than 5 m or 5%.", "Check endpoints, definition of length, and units."))
                }
                if let coordinate = structure.centerCoordinate.value {
                    issues += compareCoordinate(coordinate, chainage: (start + end) / 2,
                                                trackID: structure.trackID, package: package,
                                                entityID: structure.structureID)
                }
            }
        }

        for crossing in route.levelCrossings {
            issues += audit(crossing.chainageM, label: "crossing.chainageM", entityID: crossing.crossingID, sourceIDs: sourceIDs)
            issues += audit(crossing.coordinate, label: "crossing.coordinate", entityID: crossing.crossingID, sourceIDs: sourceIDs)
            issues += audit(crossing.roadDescription, label: "crossing.roadDescription", entityID: crossing.crossingID, sourceIDs: sourceIDs)
            issues += audit(crossing.hasWarningBell, label: "crossing.hasWarningBell", entityID: crossing.crossingID, sourceIDs: sourceIDs)
            issues += audit(crossing.hasBarriers, label: "crossing.hasBarriers", entityID: crossing.crossingID, sourceIDs: sourceIDs)
            issues += audit(crossing.warningLeadTimeS, label: "crossing.warningLeadTimeS", entityID: crossing.crossingID, sourceIDs: sourceIDs)
            issues += audit(crossing.notes, label: "crossing.notes", entityID: crossing.crossingID, sourceIDs: sourceIDs)
            if !trackIDs.contains(crossing.trackID) {
                issues.append(issue(.error, "CROSSING_TRACK_MISSING", crossing.crossingID,
                                    "Crossing references missing track \(crossing.trackID).", "Correct its track ID."))
            }
            if let lead = crossing.warningLeadTimeS.value, lead < 0 || lead > 300 {
                issues.append(issue(.warning, "CROSSING_WARNING_TIME_OUTLIER", crossing.crossingID,
                                    "Crossing warning lead time is outside 0–300 seconds.", "Verify against documented equipment settings; do not infer real operating rules."))
            }
            if let coord = crossing.coordinate.value { issues += validateCoordinate(coord, entityID: crossing.crossingID) }
            if let coord = crossing.coordinate.value, let chainage = crossing.chainageM.value {
                issues += compareCoordinate(coord, chainage: chainage, trackID: crossing.trackID, package: package, entityID: crossing.crossingID)
            }
        }

        for landmark in route.landmarks {
            issues += audit(landmark.chainageM, label: "landmark.chainageM", entityID: landmark.landmarkID, sourceIDs: sourceIDs)
            issues += audit(landmark.coordinate, label: "landmark.coordinate", entityID: landmark.landmarkID, sourceIDs: sourceIDs)
            issues += audit(landmark.name, label: "landmark.name", entityID: landmark.landmarkID, sourceIDs: sourceIDs)
            issues += audit(landmark.landmarkKind, label: "landmark.landmarkKind", entityID: landmark.landmarkID, sourceIDs: sourceIDs)
            issues += audit(landmark.visibilityRangeM, label: "landmark.visibilityRangeM", entityID: landmark.landmarkID, sourceIDs: sourceIDs)
            if let id = landmark.trackID, !trackIDs.contains(id) {
                issues.append(issue(.warning, "LANDMARK_TRACK_MISSING", landmark.landmarkID,
                                    "Landmark references unknown track \(id).", "Correct the track reference or leave it unassigned."))
            }
            if let coord = landmark.coordinate.value { issues += validateCoordinate(coord, entityID: landmark.landmarkID) }
        }

        if route.validationPolicy.requireFullSpeedCoverage {
            issues += validateSpeedCoverage(route: route)
        }
        issues += validateOperations(route: route, sourceIDs: sourceIDs)

        let order: [ValidationSeverity: Int] = [.error: 0, .warning: 1, .info: 2]
        issues.sort {
            let left = order[$0.severity, default: 3]
            let right = order[$1.severity, default: 3]
            if left != right { return left < right }
            if $0.entityID != $1.entityID { return $0.entityID < $1.entityID }
            return $0.code < $1.code
        }
        return ValidationReport(routeID: route.routeID, issues: issues)
    }

    private static func validateOperations(route: Route, sourceIDs: Set<String>) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let trackIDs = Set(route.tracks.map(\.trackID))
        let stationByID = Dictionary(route.stations.map { ($0.stationID, $0) }, uniquingKeysWith: { first, _ in first })
        let patternByID = Dictionary(route.servicePatterns.map { ($0.servicePatternID, $0) }, uniquingKeysWith: { first, _ in first })
        let depotIDs = Set(route.depots.map(\.depotID))
        checkUnique(route.timetables.map(\.timetableID), type: "timetable", issues: &issues, routeID: route.routeID)
        checkUnique(route.timetables.flatMap { $0.trips.map(\.tripID) }, type: "timetable trip", issues: &issues, routeID: route.routeID)

        for pattern in route.servicePatterns {
            issues += audit(pattern.serviceClass, label: "servicePattern.serviceClass", entityID: pattern.servicePatternID, sourceIDs: sourceIDs)
            issues += audit(pattern.displayName, label: "servicePattern.displayName", entityID: pattern.servicePatternID, sourceIDs: sourceIDs)
            issues += audit(pattern.direction, label: "servicePattern.direction", entityID: pattern.servicePatternID, sourceIDs: sourceIDs)
            issues += audit(pattern.operationalDirection, label: "servicePattern.operationalDirection", entityID: pattern.servicePatternID, sourceIDs: sourceIDs)
            issues += audit(pattern.plannedRunTimeSeconds, label: "servicePattern.plannedRunTimeSeconds", entityID: pattern.servicePatternID, sourceIDs: sourceIDs)
            issues += audit(pattern.notes, label: "servicePattern.notes", entityID: pattern.servicePatternID, sourceIDs: sourceIDs)
            for trackID in pattern.trackIDs where !trackIDs.contains(trackID) {
                issues.append(issue(.error, "SERVICE_PATTERN_TRACK_MISSING", pattern.servicePatternID,
                                    "Service pattern references unknown track \(trackID).", "Correct the pattern's track IDs."))
            }
            for stationID in pattern.callingStationIDs where stationByID[stationID] == nil {
                issues.append(issue(.error, "SERVICE_PATTERN_STATION_MISSING", pattern.servicePatternID,
                                    "Service pattern references unknown calling station \(stationID).", "Add the station or correct the calling pattern."))
            }
            if pattern.isThroughService && pattern.trackIDs.isEmpty {
                issues.append(issue(.error, "THROUGH_SERVICE_WITHOUT_TRACK", pattern.servicePatternID,
                                    "Through service has no route track.", "Assign the main-line track or mark it as a non-through shuttle."))
            }
            if let runtime = pattern.plannedRunTimeSeconds.value {
                checkRuntime(runtime, serviceClass: pattern.serviceClass.value, isThrough: pattern.isThroughService,
                             entityID: pattern.servicePatternID, policy: route.validationPolicy, issues: &issues)
            } else if pattern.isThroughService {
                issues.append(issue(.warning, "SERVICE_RUNTIME_UNKNOWN", pattern.servicePatternID,
                                    "Through-service runtime is not known.", "Keep it UNKNOWN until a documented or explicitly fictional runtime is added."))
            }
        }

        for profile in route.operatingProfiles {
            issues += audit(profile.period, label: "operatingProfile.period", entityID: profile.profileID, sourceIDs: sourceIDs)
            issues += audit(profile.startTime, label: "operatingProfile.startTime", entityID: profile.profileID, sourceIDs: sourceIDs)
            issues += audit(profile.endTime, label: "operatingProfile.endTime", entityID: profile.profileID, sourceIDs: sourceIDs)
            issues += audit(profile.headwayMinutes, label: "operatingProfile.headwayMinutes", entityID: profile.profileID, sourceIDs: sourceIDs)
            issues += audit(profile.notes, label: "operatingProfile.notes", entityID: profile.profileID, sourceIDs: sourceIDs)
            if let headway = profile.headwayMinutes.value, !headway.isFinite || headway <= 0 || headway > 240 {
                issues.append(issue(.warning, "OPERATING_HEADWAY_OUTLIER", profile.profileID,
                                    "Headway is outside the broad expected range (0, 240] minutes.", "Verify the unit and retain PLACEHOLDER status for invented frequencies."))
            }
            let invalidProfileStart = profile.startTime.value.map { parseMinutes($0) == nil } ?? false
            let invalidProfileEnd = profile.endTime.value.map { parseMinutes($0) == nil } ?? false
            if invalidProfileStart || invalidProfileEnd {
                issues.append(issue(.warning, "OPERATING_PROFILE_TIME_INVALID", profile.profileID,
                                    "Operating-profile time is not a valid HH:mm value.", "Use a 24-hour clock string and preserve its provenance status."))
            }
            if let start = parseMinutes(profile.startTime.value), let end = parseMinutes(profile.endTime.value), start == end {
                issues.append(issue(.warning, "OPERATING_PERIOD_ZERO_LENGTH", profile.profileID,
                                    "Operating profile start and end times are identical.", "Check for midnight rollover or a missing time."))
            }
            for patternID in profile.servicePatternIDs where patternByID[patternID] == nil {
                issues.append(issue(.error, "OPERATING_PROFILE_PATTERN_MISSING", profile.profileID,
                                    "Operating profile references unknown service pattern \(patternID).", "Add the pattern or correct the profile reference."))
            }
        }

        for depot in route.depots {
            issues += audit(depot.name, label: "depot.name", entityID: depot.depotID, sourceIDs: sourceIDs)
            issues += audit(depot.chainageM, label: "depot.chainageM", entityID: depot.depotID, sourceIDs: sourceIDs)
            issues += audit(depot.notes, label: "depot.notes", entityID: depot.depotID, sourceIDs: sourceIDs)
            if !trackIDs.contains(depot.trackID) {
                issues.append(issue(.error, "DEPOT_TRACK_MISSING", depot.depotID,
                                    "Depot references unknown track \(depot.trackID).", "Correct its track ID."))
            }
            for linkedTrack in depot.connectedTrackIDs where !trackIDs.contains(linkedTrack) {
                issues.append(issue(.error, "DEPOT_CONNECTION_MISSING", depot.depotID,
                                    "Depot connects to unknown track \(linkedTrack).", "Add the connected track or correct the depot link."))
            }
            if let chainage = depot.chainageM.value,
               let track = route.tracks.first(where: { $0.trackID == depot.trackID }),
               let bounds = trackBounds(track), chainage < bounds.start || chainage > bounds.end {
                issues.append(issue(.error, "DEPOT_CHAINAGE_OUT_OF_RANGE", depot.depotID,
                                    "Depot chainage lies outside its associated track.", "Check the track-local chainage datum and facility connection point."))
            }
        }

        for timetable in route.timetables {
            for trip in timetable.trips {
                issues += audit(trip.movementKind, label: "trip.movementKind", entityID: trip.tripID, sourceIDs: sourceIDs)
                issues += audit(trip.operatingPeriod, label: "trip.operatingPeriod", entityID: trip.tripID, sourceIDs: sourceIDs)
                issues += audit(trip.direction, label: "trip.direction", entityID: trip.tripID, sourceIDs: sourceIDs)
                issues += audit(trip.operationalDirection, label: "trip.operationalDirection", entityID: trip.tripID, sourceIDs: sourceIDs)
                issues += audit(trip.startChainageM, label: "trip.startChainageM", entityID: trip.tripID, sourceIDs: sourceIDs)
                issues += audit(trip.endChainageM, label: "trip.endChainageM", entityID: trip.tripID, sourceIDs: sourceIDs)
                issues += audit(trip.startTime, label: "trip.startTime", entityID: trip.tripID, sourceIDs: sourceIDs)
                issues += audit(trip.endTime, label: "trip.endTime", entityID: trip.tripID, sourceIDs: sourceIDs)
                issues += audit(trip.plannedRunTimeSeconds, label: "trip.plannedRunTimeSeconds", entityID: trip.tripID, sourceIDs: sourceIDs)
                let pattern = patternByID[trip.servicePatternID]
                if pattern == nil {
                    issues.append(issue(.error, "TIMETABLE_PATTERN_MISSING", trip.tripID,
                                        "Trip references unknown service pattern \(trip.servicePatternID).", "Add the pattern or correct the trip reference."))
                }
                if !trackIDs.contains(trip.trackID) {
                    issues.append(issue(.error, "TIMETABLE_TRACK_MISSING", trip.tripID,
                                        "Timetable trip references unknown track \(trip.trackID).", "Correct the trip track ID."))
                }
                if let pattern, !pattern.trackIDs.contains(trip.trackID) {
                    issues.append(issue(.warning, "TRIP_TRACK_NOT_IN_PATTERN", trip.tripID,
                                        "Trip track is not listed by its service pattern.", "Align the trip and service-pattern track assignments."))
                }
                if let depotID = trip.depotID, !depotIDs.contains(depotID) {
                    issues.append(issue(.error, "TRIP_DEPOT_MISSING", trip.tripID,
                                        "Trip references unknown depot \(depotID).", "Add the depot or correct the trip reference."))
                }
                let movement = trip.movementKind.value
                if let serviceClass = pattern?.serviceClass.value {
                    let patternIsDepot = serviceClass == .depotMovement
                    let movementIsDepot = movement != .revenueService
                    if patternIsDepot != movementIsDepot {
                        issues.append(issue(.warning, "TRIP_MOVEMENT_CLASS_MISMATCH", trip.tripID,
                                            "Trip movement kind does not match whether its service pattern is depot/non-revenue.",
                                            "Align the movement kind and service class; keep depot moves out of passenger service patterns."))
                    }
                }
                if (movement == .depotOutbound || movement == .depotInbound || movement == .shunting || movement == .emptyStock), trip.depotID == nil {
                    issues.append(issue(.warning, "DEPOT_MOVEMENT_WITHOUT_DEPOT", trip.tripID,
                                        "Non-revenue/depot movement has no depot reference.", "Reference the relevant depot or explain its origin."))
                }
                if let runtime = trip.plannedRunTimeSeconds.value, let pattern {
                    checkRuntime(runtime, serviceClass: pattern.serviceClass.value, isThrough: pattern.isThroughService,
                                 entityID: trip.tripID, policy: route.validationPolicy, issues: &issues)
                }
                if let start = trip.startChainageM.value, let end = trip.endChainageM.value {
                    if let direction = trip.direction.value,
                       (direction == .increasingChainage && end < start || direction == .decreasingChainage && end > start) {
                        issues.append(issue(.error, "TRIP_DIRECTION_CHAINAGE_MISMATCH", trip.tripID,
                                            "Trip chainage order conflicts with its declared travel direction.", "Correct start/end chainage or the chainage direction."))
                    }
                    if let track = route.tracks.first(where: { $0.trackID == trip.trackID }),
                       let bounds = trackBounds(track), min(start, end) < bounds.start || max(start, end) > bounds.end {
                        issues.append(issue(.error, "TRIP_CHAINAGE_OUT_OF_RANGE", trip.tripID,
                                            "Trip endpoints lie outside the selected track extent.", "Check track-local chainage and the trip path."))
                    }
                }
                if let start = parseMinutes(trip.startTime.value), let end = parseMinutes(trip.endTime.value),
                   let runtime = trip.plannedRunTimeSeconds.value {
                    let endAdjusted = end < start ? end + 24 * 60 : end
                    let clockRuntime = Double(endAdjusted - start) * 60
                    if abs(clockRuntime - runtime) > 60 {
                        issues.append(issue(.warning, "TRIP_CLOCK_RUNTIME_MISMATCH", trip.tripID,
                                            "Start/end timetable clock times differ from declared runtime by more than 60 seconds.",
                                            "Check midnight rollover, clock precision, and whether dwell time is included.",
                                            ["clockRuntimeSeconds=\(clockRuntime)", "declaredRuntimeSeconds=\(runtime)"]))
                    }
                }
                if (trip.startTime.value != nil && parseMinutes(trip.startTime.value) == nil)
                    || (trip.endTime.value != nil && parseMinutes(trip.endTime.value) == nil) {
                    issues.append(issue(.warning, "TRIP_CLOCK_TIME_INVALID", trip.tripID,
                                        "Trip start or end time is not a valid HH:mm value.", "Use a valid 24-hour clock string and document midnight rollover."))
                }
                if let period = trip.operatingPeriod.value,
                   !route.operatingProfiles.contains(where: { $0.period.value == period && $0.servicePatternIDs.contains(trip.servicePatternID) }) {
                    issues.append(issue(.info, "TRIP_OUTSIDE_DECLARED_PROFILE", trip.tripID,
                                        "No operating profile lists this pattern for the trip's period.", "Add the pattern to the appropriate period profile or revise the trip period."))
                }
                var priorPosition: Double?
                for stop in trip.stops {
                    issues += audit(stop.arrivalTime, label: "timetableStop.arrivalTime", entityID: trip.tripID, sourceIDs: sourceIDs)
                    issues += audit(stop.departureTime, label: "timetableStop.departureTime", entityID: trip.tripID, sourceIDs: sourceIDs)
                    issues += audit(stop.stopPositionChainageM, label: "timetableStop.stopPositionChainageM", entityID: trip.tripID, sourceIDs: sourceIDs)
                    guard let station = stationByID[stop.stationID] else {
                        issues.append(issue(.error, "TIMETABLE_STATION_MISSING", trip.tripID,
                                            "Timetable stop references unknown station \(stop.stationID).", "Add the station or correct the stop reference."))
                        continue
                    }
                    if !station.trackIDs.isEmpty && !station.trackIDs.contains(trip.trackID) {
                        issues.append(issue(.warning, "TIMETABLE_STOP_TRACK_MISMATCH", trip.tripID,
                                            "Stop station is not assigned to the trip's track.", "Check the station/track relation or service path."))
                    }
                    if let position = stop.stopPositionChainageM.value {
                        if let previous = priorPosition, let direction = trip.direction.value,
                           (direction == .increasingChainage && position < previous || direction == .decreasingChainage && position > previous) {
                            issues.append(issue(.warning, "TIMETABLE_STOP_ORDER_MISMATCH", trip.tripID,
                                                "Calling-station chainages do not follow the declared direction.", "Reorder stops or correct their chainage/direction."))
                        }
                        priorPosition = position
                    }
                }
            }
        }

        for scenario in route.scenarios {
            issues += audit(scenario.startChainageM, label: "scenario.startChainageM", entityID: scenario.scenarioID, sourceIDs: sourceIDs)
            issues += audit(scenario.endChainageM, label: "scenario.endChainageM", entityID: scenario.scenarioID, sourceIDs: sourceIDs)
            issues += audit(scenario.direction, label: "scenario.direction", entityID: scenario.scenarioID, sourceIDs: sourceIDs)
            issues += audit(scenario.operationalDirection, label: "scenario.operationalDirection", entityID: scenario.scenarioID, sourceIDs: sourceIDs)
            issues += audit(scenario.movementKind, label: "scenario.movementKind", entityID: scenario.scenarioID, sourceIDs: sourceIDs)
            issues += audit(scenario.operatingPeriod, label: "scenario.operatingPeriod", entityID: scenario.scenarioID, sourceIDs: sourceIDs)
            issues += audit(scenario.expectedDurationSeconds, label: "scenario.expectedDurationSeconds", entityID: scenario.scenarioID, sourceIDs: sourceIDs)
            issues += audit(scenario.notes, label: "scenario.notes", entityID: scenario.scenarioID, sourceIDs: sourceIDs)
            if !trackIDs.contains(scenario.trackID) {
                issues.append(issue(.error, "SCENARIO_TRACK_MISSING", scenario.scenarioID,
                                    "Scenario references unknown track \(scenario.trackID).", "Correct the track reference."))
            }
            if let timetableID = scenario.timetableID,
               !route.timetables.contains(where: { $0.timetableID == timetableID }) {
                issues.append(issue(.warning, "SCENARIO_TIMETABLE_MISSING", scenario.scenarioID,
                                    "Scenario references unknown timetable \(timetableID).", "Add the timetable or clear the reference."))
            }
            if let start = scenario.startChainageM.value, let end = scenario.endChainageM.value {
                if let direction = scenario.direction.value,
                   (direction == .increasingChainage && end < start || direction == .decreasingChainage && end > start) {
                    issues.append(issue(.error, "SCENARIO_DIRECTION_CHAINAGE_MISMATCH", scenario.scenarioID,
                                        "Scenario chainage order conflicts with its declared direction.", "Correct its endpoints or direction."))
                }
                if let track = route.tracks.first(where: { $0.trackID == scenario.trackID }),
                   let bounds = trackBounds(track), min(start, end) < bounds.start || max(start, end) > bounds.end {
                    issues.append(issue(.error, "SCENARIO_CHAINAGE_OUT_OF_RANGE", scenario.scenarioID,
                                        "Scenario endpoints lie outside its selected track extent.", "Use the selected track's local chainage range."))
                }
            }
            if let patternID = scenario.servicePatternID, let pattern = patternByID[patternID],
               let runtime = scenario.expectedDurationSeconds.value {
                checkRuntime(runtime, serviceClass: pattern.serviceClass.value, isThrough: pattern.isThroughService,
                             entityID: scenario.scenarioID, policy: route.validationPolicy, issues: &issues)
            } else if let patternID = scenario.servicePatternID, patternByID[patternID] == nil {
                issues.append(issue(.warning, "SCENARIO_PATTERN_MISSING", scenario.scenarioID,
                                    "Scenario references unknown service pattern \(patternID).", "Add the pattern or clear the reference."))
            }
        }
        return issues
    }

    private static func checkRuntime(
        _ runtime: Double,
        serviceClass: ServiceClass?,
        isThrough: Bool,
        entityID: String,
        policy: ValidationPolicy,
        issues: inout [ValidationIssue]
    ) {
        if !runtime.isFinite || runtime <= 0 {
            issues.append(issue(.error, "SERVICE_RUNTIME_INVALID", entityID,
                                "Planned run time must be finite and positive.", "Correct its value/unit or mark it UNKNOWN."))
            return
        }
        if isThrough && runtime < policy.minimumThroughRunTimeSeconds {
            issues.append(issue(.error, "THROUGH_RUNTIME_BELOW_MINIMUM", entityID,
                                "Through-service runtime is shorter than the configured minimum of \(policy.minimumThroughRunTimeSeconds) seconds.",
                                "Review route extent and stop plan, or revise the policy with an explicit design reason."))
        }
        if serviceClass == .local && runtime > policy.maximumLocalRunTimeSeconds {
            issues.append(issue(.error, "LOCAL_RUNTIME_ABOVE_MAXIMUM", entityID,
                                "Local-service runtime exceeds the configured maximum of \(policy.maximumLocalRunTimeSeconds) seconds.",
                                "Review the timetable, stop plan, or declared route length."))
        }
    }

    private static func parseMinutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              hour >= 0, hour <= 47, (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private static func validateTrack(
        _ track: Track,
        routeLengthM: Double?,
        policy: ValidationPolicy,
        sourceIDs: Set<String>
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if track.segments.isEmpty {
            issues.append(issue(.error, "TRACK_SEGMENTS_MISSING", track.trackID,
                                "Track has no chainage segments; route position and alignment cannot be queried.",
                                "Add sourced segment bounds and properties, or keep this package explicitly metadata-only."))
        }
        if track.geometry.isEmpty {
            issues.append(issue(.warning, "TRACK_GEOMETRY_MISSING", track.trackID,
                                "Track has no geographic geometry samples.",
                                "Add licensed/sourced geometry with CRS and chainage calibration; do not derive precision from station names alone."))
        }
        for vertex in track.geometry {
            issues += audit(vertex.chainageM, label: "geometry.chainageM", entityID: track.trackID, sourceIDs: sourceIDs)
            issues += audit(vertex.coordinate, label: "geometry.coordinate", entityID: track.trackID, sourceIDs: sourceIDs)
            if let coordinate = vertex.coordinate.value { issues += validateCoordinate(coordinate, entityID: track.trackID) }
        }
        let vertices = track.geometry.compactMap { sample -> (Double, GeoCoordinate)? in
            guard let chainage = sample.chainageM.value, let coordinate = sample.coordinate.value else { return nil }
            return (chainage, coordinate)
        }.sorted { $0.0 < $1.0 }
        for pair in zip(vertices, vertices.dropFirst()) {
            let deltaChainage = pair.1.0 - pair.0.0
            if deltaChainage <= 0 {
                issues.append(issue(.error, "GEOMETRY_CHAINAGE_NOT_INCREASING", track.trackID,
                                    "Geometry vertex chainages must strictly increase in route order.", "Sort vertices and resolve duplicate or reversed chainage values."))
                continue
            }
            if deltaChainage > policy.maxGeometryGapM {
                issues.append(issue(.warning, "GEOMETRY_CHAINAGE_GAP", track.trackID,
                                    "Geometry samples are \(Int(deltaChainage.rounded())) m apart, exceeding the configured \(Int(policy.maxGeometryGapM.rounded())) m gap.", "Add sourced intermediate vertices; do not linearly extrapolate across long unsurveyed spans."))
            }
            let geoDistance = distanceMeters(pair.0.1, pair.1.1)
            if geoDistance > deltaChainage + max(20, deltaChainage * 0.1) {
                issues.append(issue(.warning, "GEOMETRY_DISTANCE_INCONSISTENT", track.trackID,
                                    "Straight-line distance between coordinate samples exceeds their chainage separation.", "Check coordinate order, CRS/datum, chainage calibration, and units.",
                                    ["chainageDeltaM=\(deltaChainage)", "geodesicChordM=\(geoDistance)"]))
            }
            if geoDistance > policy.maxCoordinateJumpM {
                issues.append(issue(.warning, "GEOMETRY_COORDINATE_JUMP", track.trackID,
                                    "Adjacent coordinates are farther apart than the configured continuity threshold.", "Inspect the source geometry for a discontinuity or add intermediate samples."))
            }
        }
        if vertices.count >= 3 {
            for index in 1..<(vertices.count - 1) {
                let before = bearingDegrees(vertices[index - 1].1, vertices[index].1)
                let after = bearingDegrees(vertices[index].1, vertices[index + 1].1)
                if let before, let after, angularDifference(before, after) > policy.maxHeadingChangeDegrees {
                    issues.append(issue(.warning, "GEOMETRY_HEADING_DISCONTINUITY", track.trackID,
                                        "Adjacent geometry legs change heading by more than the configured threshold.", "Verify point ordering and use sufficiently dense, licensed geometry; a real curve should not be replaced with a sharp corner."))
                }
            }
        }

        let segments = track.segments.compactMap { segment -> (TrackSegment, Double, Double)? in
            guard let start = segment.startChainageM.value, let end = segment.endChainageM.value else { return nil }
            return (segment, start, end)
        }.sorted { $0.1 < $1.1 }
        for segment in track.segments {
            issues += audit(segment.startChainageM, label: "segment.startChainageM", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.endChainageM, label: "segment.endChainageM", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.curveRadiusM, label: "segment.curveRadiusM", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.transitionLengthM, label: "segment.transitionLengthM", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.cantMM, label: "segment.cantMM", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.cantTransitionLengthM, label: "segment.cantTransitionLengthM", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.gradientPermille, label: "segment.gradientPermille", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.speedLimitKmh, label: "segment.speedLimitKmh", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.trackStructure, label: "segment.trackStructure", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.railProfile, label: "segment.railProfile", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.sleeperType, label: "segment.sleeperType", entityID: segment.segmentID, sourceIDs: sourceIDs)
            issues += audit(segment.longWeldedRail, label: "segment.longWeldedRail", entityID: segment.segmentID, sourceIDs: sourceIDs)
            if let start = segment.startChainageM.value, let end = segment.endChainageM.value {
                if !start.isFinite || !end.isFinite || end <= start {
                    issues.append(issue(.error, "SEGMENT_RANGE_INVALID", segment.segmentID,
                                        "Track segment must have finite chainage and end greater than start.", "Correct its chainage bounds."))
                }
            }
            issues += audit(segment.alignment, label: "segment.alignment", entityID: segment.segmentID, sourceIDs: sourceIDs)
            if segment.alignment.value == .tangent, let radius = segment.curveRadiusM.value, radius > 0 {
                issues.append(issue(.warning, "TANGENT_HAS_RADIUS", segment.segmentID,
                                    "A tangent segment has a positive curve radius.", "Use null/UNKNOWN for a straight alignment or select the appropriate curve type."))
            }
            if segment.alignment.value == .circularCurve || segment.alignment.value == .transitionCurve {
                if let radius = segment.curveRadiusM.value, !radius.isFinite || radius <= 0 || radius > 20_000 {
                    issues.append(issue(.warning, "CURVE_RADIUS_OUTLIER", segment.segmentID,
                                        "Curve radius is outside the broad sanity range (0, 20,000] m.", "Verify unit, transition/circular-curve definition, and source."))
                }
                if segment.alignment.value == .transitionCurve,
                   let length = segment.transitionLengthM.value, length <= 0 {
                    issues.append(issue(.warning, "TRANSITION_LENGTH_INVALID", segment.segmentID,
                                        "Transition curve length must be positive.", "Measure or source its length; do not copy the adjacent circular radius as transition length."))
                }
            }
            if let gradient = segment.gradientPermille.value, !gradient.isFinite || abs(gradient) > 80 {
                issues.append(issue(.warning, "GRADIENT_OUTLIER", segment.segmentID,
                                    "Gradient exceeds the broad sanity limit of ±80‰.", "Verify sign convention, per-mille units, and source."))
            }
            if let cant = segment.cantMM.value, !cant.isFinite || abs(cant) > 200 {
                issues.append(issue(.warning, "CANT_OUTLIER", segment.segmentID,
                                    "Cant exceeds the broad sanity limit of ±200 mm.", "Verify unit, sign convention, and whether this is actual or equilibrium cant."))
            }
            if segment.cantTransitionLengthM.value.map({ $0 <= 0 }) == true {
                issues.append(issue(.warning, "CANT_TRANSITION_LENGTH_INVALID", segment.segmentID,
                                    "Cant transition length must be positive when supplied.", "Check measurement and units."))
            }
            if let limit = segment.speedLimitKmh.value, !limit.isFinite || limit <= 0 || limit > 400 {
                issues.append(issue(.warning, "BASE_SPEED_OUTLIER", segment.segmentID,
                                    "Base segment speed is outside the broad expected range (0, 400] km/h.", "Verify its unit and whether the value is a line limit, vehicle limit, or scenario limit."))
            }
        }
        for pair in zip(segments, segments.dropFirst()) {
            let delta = pair.1.1 - pair.0.2
            if abs(delta) > 0.05 {
                let isGap = delta > 0
                issues.append(issue(.error, isGap ? "SEGMENT_CHAINAGE_GAP" : "SEGMENT_CHAINAGE_OVERLAP", pair.1.0.segmentID,
                                    isGap ? "Track segments have a chainage gap of \(delta) m." : "Track segments overlap by \(abs(delta)) m.",
                                    "Reconcile segment boundaries against the route chainage datum; do not silently stretch or trim geometry.",
                                    ["previousEndM=\(pair.0.2)", "nextStartM=\(pair.1.1)", "deltaM=\(delta)"]))
            }
        }
        if let first = segments.first, abs(first.1) > 0.05 {
            issues.append(issue(.warning, "TRACK_START_NOT_ZERO", track.trackID,
                                "First segment starts at \(first.1) m instead of route chainage 0.", "Confirm whether this track uses a local chainage datum and document any offset."))
        }
        if let routeLengthM, let last = segments.last, abs(last.2 - routeLengthM) > 0.05 {
            issues.append(issue(.warning, "TRACK_END_DIFFERS_FROM_ROUTE_LENGTH", track.trackID,
                                "Last segment end differs from route total length.", "Check route extent and each track's chainage calibration."))
        }
        return issues
    }

    private static func validateBlockCoverage(route: Route) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for track in route.tracks where track.blockCoverageRequired {
            guard let bounds = trackBounds(track) else {
                issues.append(issue(.warning, "BLOCK_COVERAGE_UNCHECKABLE", track.trackID,
                                    "Block coverage is required but track extent is unavailable.", "Provide continuous track chainage or disable the requirement until surveyed."))
                continue
            }
            let blocks = route.blocks.filter { $0.trackID == track.trackID }.compactMap { block -> (BlockSection, Double, Double)? in
                guard let start = block.startChainageM.value, let end = block.endChainageM.value else { return nil }
                return (block, min(start, end), max(start, end))
            }.sorted { $0.1 < $1.1 }
            if blocks.isEmpty {
                issues.append(issue(.error, "BLOCK_COVERAGE_MISSING", track.trackID,
                                    "Track requires block coverage but has no block sections.", "Add documented blocks or set blockCoverageRequired to false when block topology is unknown."))
                continue
            }
            if blocks[0].1 > bounds.start + 0.05 {
                issues.append(issue(.error, "BLOCK_COVERAGE_GAP", track.trackID,
                                    "No block covers the beginning of the track extent.", "Add the missing block only when its boundary is sourced; otherwise record the coverage as incomplete."))
            }
            for pair in zip(blocks, blocks.dropFirst()) where abs(pair.1.1 - pair.0.2) > 0.05 {
                let gap = pair.1.1 - pair.0.2
                issues.append(issue(.error, gap > 0 ? "BLOCK_COVERAGE_GAP" : "BLOCK_OVERLAP", pair.1.0.blockID,
                                    gap > 0 ? "Adjacent block sections leave a \(gap) m gap." : "Adjacent block sections overlap by \(abs(gap)) m.",
                                    "Verify block boundaries and track assignment against authorized signal plans."))
            }
            if let last = blocks.last, last.2 < bounds.end - 0.05 {
                issues.append(issue(.error, "BLOCK_COVERAGE_GAP", track.trackID,
                                    "No block covers the end of the track extent.", "Add a sourced final block boundary or record incomplete topology."))
            }
        }
        return issues
    }

    private static func validateSpeedCoverage(route: Route) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for track in route.tracks {
            let segments = track.segments.compactMap { segment -> (TrackSegment, Double, Double)? in
                guard let start = segment.startChainageM.value, let end = segment.endChainageM.value else { return nil }
                return (segment, min(start, end), max(start, end))
            }
            for (segment, _, _) in segments where segment.speedLimitKmh.value == nil {
                issues.append(issue(.warning, "SPEED_COVERAGE_UNKNOWN", segment.segmentID,
                                    "Full speed coverage is required but this base segment has no known speed value.", "Keep UNKNOWN until an authoritative speed profile is available; do not invent a service limit."))
            }
        }
        return issues
    }

    private static func checkRestrictionOverlaps(_ restrictions: [SpeedRestriction], issues: inout [ValidationIssue]) {
        for i in restrictions.indices {
            for j in restrictions.indices where j > i {
                let a = restrictions[i]
                let b = restrictions[j]
                guard a.trackID == b.trackID,
                      let aStart = a.startChainageM.value, let aEnd = a.endChainageM.value,
                      let bStart = b.startChainageM.value, let bEnd = b.endChainageM.value,
                      max(min(aStart, aEnd), min(bStart, bEnd)) < min(max(aStart, aEnd), max(bStart, bEnd)) else { continue }
                let overlapStart = max(min(aStart, aEnd), min(bStart, bEnd))
                let overlapEnd = min(max(aStart, aEnd), max(bStart, bEnd))
                let directionA = a.direction.value ?? .unknown
                let directionB = b.direction.value ?? .unknown
                let sameDirection = directionA == directionB || directionA == .both || directionB == .both || directionA == .unknown || directionB == .unknown
                let sameVehicleScope = a.appliesToVehicleIDs.isEmpty || b.appliesToVehicleIDs.isEmpty || !Set(a.appliesToVehicleIDs).isDisjoint(with: b.appliesToVehicleIDs)
                guard sameDirection && sameVehicleScope else { continue }
                let conflict = a.limitKmh.value != b.limitKmh.value
                issues.append(issue(.warning, conflict ? "SPEED_RESTRICTION_CONFLICT" : "SPEED_RESTRICTION_OVERLAP",
                                    "\(a.restrictionID),\(b.restrictionID)",
                                    conflict ? "Applicable speed restrictions overlap with different limits." : "Applicable speed restrictions overlap.",
                                    "Confirm whether overlap is intentional and define the governing-limit rule; preserve both sources.",
                                    ["overlapStartM=\(overlapStart)", "overlapEndM=\(overlapEnd)",
                                     "limitA_kmh=\(a.limitKmh.value.map { String($0) } ?? "UNKNOWN")",
                                     "limitB_kmh=\(b.limitKmh.value.map { String($0) } ?? "UNKNOWN")"]))
            }
        }
    }

    private static func audit<Value: Codable & Sendable>(
        _ evidence: Evidence<Value>,
        label: String,
        entityID: String,
        sourceIDs: Set<String>
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let missing = evidence.sourceIDs.filter { !sourceIDs.contains($0) }
        if !missing.isEmpty {
            issues.append(issue(.error, "SOURCE_REFERENCE_MISSING", entityID,
                                "\(label) refers to absent source IDs: \(missing.joined(separator: ", ")).",
                                "Add matching SourceMetadata records or correct the source IDs."))
        }
        if (evidence.status == .verified || evidence.status == .measured) && evidence.sourceIDs.isEmpty {
            issues.append(issue(.warning, "PROVENANCE_MISSING", entityID,
                                "\(label) is \(evidence.status.rawValue) but has no source reference.",
                                "Attach an official source (VERIFIED) or measurement record (MEASURED), including date and method."))
        }
        if evidence.status == .estimated && (evidence.uncertainty == nil || evidence.note?.isEmpty != false) {
            issues.append(issue(.warning, "ESTIMATE_BASIS_INCOMPLETE", entityID,
                                "\(label) is ESTIMATED without both an uncertainty range and a stated basis.",
                                "Record the estimation basis and absolute uncertainty; otherwise use UNKNOWN."))
        }
        if evidence.status == .placeholder && evidence.note?.isEmpty != false {
            issues.append(issue(.info, "PLACEHOLDER_NOT_EXPLAINED", entityID,
                                "\(label) is PLACEHOLDER without an explanatory note.",
                                "State that it is synthetic/test-only and not a real railway fact."))
        }
        if evidence.status == .unknown {
            issues.append(issue(.info, "UNCONFIRMED_DATA", entityID,
                                "\(label) is UNKNOWN; this item is not confirmed.",
                                "Keep it unknown until verified; do not treat nil as zero or as an operating rule."))
        } else if evidence.value == nil {
            issues.append(issue(.warning, "VALUE_MISSING_FOR_STATUS", entityID,
                                "\(label) is marked \(evidence.status.rawValue) but has no value.",
                                "Provide a supported value or change its status to UNKNOWN."))
        }
        if let uncertainty = evidence.uncertainty, !uncertainty.isFinite || uncertainty < 0 {
            issues.append(issue(.warning, "UNCERTAINTY_INVALID", entityID,
                                "\(label) has a negative or non-finite uncertainty.",
                                "Use a non-negative uncertainty in the same unit as the value."))
        }
        return issues
    }

    private static func validateCoordinate(_ coordinate: GeoCoordinate, entityID: String) -> [ValidationIssue] {
        guard coordinate.latitudeDeg.isFinite, coordinate.longitudeDeg.isFinite,
              (-90...90).contains(coordinate.latitudeDeg), (-180...180).contains(coordinate.longitudeDeg) else {
            return [issue(.error, "COORDINATE_INVALID", entityID,
                          "Latitude/longitude is non-finite or outside valid geographic bounds.",
                          "Check coordinate order, CRS, and datum before correcting the values.")]
        }
        if let elevation = coordinate.elevationM, !elevation.isFinite {
            return [issue(.warning, "ELEVATION_INVALID", entityID,
                          "Elevation is non-finite.", "Verify the vertical datum and elevation units.")]
        }
        return []
    }

    private static func compareCoordinate(
        _ coordinate: GeoCoordinate,
        chainage: Double,
        trackID: String,
        package: RoutePackage,
        entityID: String
    ) -> [ValidationIssue] {
        guard package.route.tracks.contains(where: { $0.trackID == trackID }),
              let calculated = RouteQuery.position(at: chainage, trackID: trackID, in: package)?.coordinate?.value else { return [] }
        let distance = distanceMeters(coordinate, calculated)
        guard distance > 25 else { return [] }
        return [issue(.warning, "FEATURE_TRACK_POSITION_MISMATCH", entityID,
                      "Feature coordinate is about \(Int(distance.rounded())) m from the track geometry at its chainage.",
                      "Check the feature's track ID, chainage, coordinate datum, and source; do not snap it automatically.",
                      ["featureCoordinate=\(coordinate.latitudeDeg),\(coordinate.longitudeDeg)",
                       "trackCoordinate=\(calculated.latitudeDeg),\(calculated.longitudeDeg)",
                       "separationM=\(distance)"])]
    }

    private static func trackBounds(_ track: Track) -> (start: Double, end: Double)? {
        let ranges = track.segments.compactMap { segment -> (Double, Double)? in
            guard let start = segment.startChainageM.value, let end = segment.endChainageM.value else { return nil }
            return (min(start, end), max(start, end))
        }
        guard let first = ranges.map(\.0).min(), let last = ranges.map(\.1).max() else { return nil }
        return (first, last)
    }

    private static func checkUnique(_ ids: [String], type: String, issues: inout [ValidationIssue], routeID: String) {
        let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        for id in duplicates {
            issues.append(issue(.error, "DUPLICATE_ENTITY_ID", id,
                                "Duplicate \(type) identifier \(id).", "Assign unique IDs within the \(type) namespace."))
        }
    }

    private static func distanceMeters(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let radius = 6_371_000.0
        let radians = Double.pi / 180
        let lat1 = a.latitudeDeg * radians
        let lat2 = b.latitudeDeg * radians
        let dLat = (b.latitudeDeg - a.latitudeDeg) * radians
        let dLon = (b.longitudeDeg - a.longitudeDeg) * radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    private static func bearingDegrees(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double? {
        let radians = Double.pi / 180
        let lat1 = a.latitudeDeg * radians
        let lat2 = b.latitudeDeg * radians
        let dLon = (b.longitudeDeg - a.longitudeDeg) * radians
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        guard x.isFinite, y.isFinite, abs(x) + abs(y) > 1e-12 else { return nil }
        return (atan2(y, x) / radians + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }

    private static func issue(
        _ severity: ValidationSeverity,
        _ code: String,
        _ entityID: String,
        _ message: String,
        _ suggestedFix: String,
        _ evidence: [String] = []
    ) -> ValidationIssue {
        ValidationIssue(severity: severity, code: code, entityID: entityID,
                        message: message, suggestedFix: suggestedFix, evidence: evidence)
    }
}
