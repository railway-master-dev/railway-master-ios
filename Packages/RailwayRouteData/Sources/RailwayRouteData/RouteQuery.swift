import Foundation

public struct EntityReference<Entity: Sendable>: Sendable {
    public let entity: Entity
    public let distanceM: Double
}

public struct RoutePosition: Sendable {
    public let trackID: String
    public let chainageM: Double
    public let segmentID: String?
    public let coordinate: Evidence<GeoCoordinate>?
    /// Initial bearing clockwise from true north, in degrees, when coordinate samples allow it.
    public let headingDegrees: Double?
    public let curveRadiusM: Evidence<Double>?
    public let cantMM: Evidence<Double>?
    public let gradientPermille: Evidence<Double>?
    public let baseSpeedLimitKmh: Evidence<Double>?
    public let activeSpeedRestrictions: [SpeedRestriction]
    public let governingSpeedLimitKmh: Double?
    public let currentBlockID: String?
    public let nextStation: EntityReference<Station>?
    public let nextSignal: EntityReference<Signal>?
    public let nextSwitch: EntityReference<Switch>?
    public let nextStructure: EntityReference<RailwayStructure>?
    public let nextLevelCrossing: EntityReference<LevelCrossing>?
}

/// Chainage-first route lookup. Geographic coordinates are interpolated between surveyed/reference vertices;
/// route chainage remains the primary continuous position and GPS is not used as the simulation clock.
public enum RouteQuery {
    public static func position(
        at chainageM: Double,
        trackID: String,
        in package: RoutePackage,
        towardIncreasingChainage: Bool = true
    ) -> RoutePosition? {
        guard chainageM.isFinite,
              let track = package.route.tracks.first(where: { $0.trackID == trackID }) else { return nil }
        let segments = track.segments.compactMap { segment -> (TrackSegment, Double, Double)? in
            guard let start = segment.startChainageM.value, let end = segment.endChainageM.value,
                  start.isFinite, end.isFinite, end >= start else { return nil }
            return (segment, start, end)
        }.sorted { $0.1 < $1.1 }
        guard let boundsStart = segments.first?.1, let boundsEnd = segments.last?.2,
              chainageM >= boundsStart - 1e-6, chainageM <= boundsEnd + 1e-6 else { return nil }
        let chosen = segments.first(where: { chainageM >= $0.1 - 1e-6 && chainageM <= $0.2 + 1e-6 })
            ?? segments.last(where: { $0.1 <= chainageM + 1e-6 })
        let segment = chosen?.0

        let geometry = interpolatedCoordinate(at: chainageM, samples: track.geometry)
        let activeRestrictions = package.route.speedRestrictions.filter { restriction in
            guard restriction.trackID == trackID,
                  let start = restriction.startChainageM.value,
                  let end = restriction.endChainageM.value,
                  chainageM >= min(start, end) - 1e-6,
                  chainageM <= max(start, end) + 1e-6 else { return false }
            switch restriction.direction.value ?? .unknown {
            case .both, .unknown: return true
            case .increasingChainage: return towardIncreasingChainage
            case .decreasingChainage: return !towardIncreasingChainage
            }
        }
        let candidateLimits = ([segment?.speedLimitKmh].compactMap { $0 } + activeRestrictions.map(\.limitKmh))
            .compactMap { evidence -> (Double, Evidence<Double>)? in
                guard let value = evidence.value, value.isFinite, value >= 0 else { return nil }
                return (value, evidence)
            }
        let governingLimit = candidateLimits.min(by: { $0.0 < $1.0 })?.0

        let stationRef = nearest(
            in: package.route.stations.filter { $0.trackIDs.isEmpty || $0.trackIDs.contains(trackID) },
            chainage: chainageM,
            towardIncreasing: towardIncreasingChainage,
            location: { $0.stopPositionChainageM.value ?? $0.chainageM.value }
        )
        let signalRef = nearest(
            in: package.route.signals.filter { $0.trackID == trackID && directionApplies($0.direction.value ?? .unknown, towardIncreasingChainage) },
            chainage: chainageM,
            towardIncreasing: towardIncreasingChainage,
            location: { $0.chainageM.value }
        )
        let switchRef = nearest(
            in: package.route.switches.filter { $0.trackID == trackID },
            chainage: chainageM,
            towardIncreasing: towardIncreasingChainage,
            location: { $0.chainageM.value }
        )
        let structureRef = nearest(
            in: package.route.structures.filter { $0.trackID == trackID },
            chainage: chainageM,
            towardIncreasing: towardIncreasingChainage,
            location: { structure in
                towardIncreasingChainage ? structure.startChainageM.value : structure.endChainageM.value
            }
        )
        let crossingRef = nearest(
            in: package.route.levelCrossings.filter { $0.trackID == trackID },
            chainage: chainageM,
            towardIncreasing: towardIncreasingChainage,
            location: { $0.chainageM.value }
        )
        let currentBlock = package.route.blocks.first(where: { block in
            guard block.trackID == trackID,
                  let start = block.startChainageM.value,
                  let end = block.endChainageM.value else { return false }
            return chainageM >= min(start, end) - 1e-6 && chainageM <= max(start, end) + 1e-6
        })?.blockID

        return RoutePosition(
            trackID: trackID,
            chainageM: chainageM,
            segmentID: segment?.segmentID,
            coordinate: geometry?.coordinate,
            headingDegrees: geometry?.headingDegrees,
            curveRadiusM: segment?.curveRadiusM,
            cantMM: segment?.cantMM,
            gradientPermille: segment?.gradientPermille,
            baseSpeedLimitKmh: segment?.speedLimitKmh,
            activeSpeedRestrictions: activeRestrictions,
            governingSpeedLimitKmh: governingLimit,
            currentBlockID: currentBlock,
            nextStation: stationRef,
            nextSignal: signalRef,
            nextSwitch: switchRef,
            nextStructure: structureRef,
            nextLevelCrossing: crossingRef
        )
    }

    private static func directionApplies(_ direction: TravelDirection, _ towardIncreasing: Bool) -> Bool {
        switch direction {
        case .both, .unknown: return true
        case .increasingChainage: return towardIncreasing
        case .decreasingChainage: return !towardIncreasing
        }
    }

    private static func nearest<Entity: Sendable>(
        in entities: [Entity],
        chainage: Double,
        towardIncreasing: Bool,
        location: (Entity) -> Double?
    ) -> EntityReference<Entity>? {
        let candidates = entities.compactMap { entity -> (Entity, Double, Double)? in
            guard let position = location(entity), position.isFinite else { return nil }
            let distance = towardIncreasing ? position - chainage : chainage - position
            guard distance >= -1e-6 else { return nil }
            return (entity, max(0, distance), position)
        }
        guard let closest = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        return EntityReference(entity: closest.0, distanceM: closest.1)
    }

    private static func interpolatedCoordinate(
        at chainage: Double,
        samples: [PositionSample]
    ) -> (coordinate: Evidence<GeoCoordinate>, headingDegrees: Double?)? {
        let points = samples.compactMap { sample -> (Double, Evidence<GeoCoordinate>)? in
            guard let chainage = sample.chainageM.value,
                  let coordinate = sample.coordinate.value,
                  chainage.isFinite,
                  coordinate.latitudeDeg.isFinite,
                  coordinate.longitudeDeg.isFinite else { return nil }
            return (chainage, sample.coordinate)
        }.sorted { $0.0 < $1.0 }
        guard let first = points.first, let last = points.last,
              chainage >= first.0 - 1e-6, chainage <= last.0 + 1e-6 else { return nil }
        if let exact = points.first(where: { abs($0.0 - chainage) <= 1e-6 }) {
            let nextIndex = points.firstIndex(where: { abs($0.0 - chainage) <= 1e-6 })!
            let next = nextIndex + 1 < points.count ? points[nextIndex + 1] : points[max(0, nextIndex - 1)]
            let bearing = next.0 >= chainage ? bearingDegrees(from: exact.1.value!, to: next.1.value!) : bearingDegrees(from: next.1.value!, to: exact.1.value!)
            return (exact.1, bearing)
        }
        guard let upperIndex = points.firstIndex(where: { $0.0 > chainage }), upperIndex > 0 else { return nil }
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let span = upper.0 - lower.0
        guard span > 0 else { return nil }
        let fraction = min(1, max(0, (chainage - lower.0) / span))
        let start = lower.1.value!
        let end = upper.1.value!
        let coordinate = slerp(start, end, fraction: fraction)
        let elevation: Double?
        if let a = start.elevationM, let b = end.elevationM { elevation = a + (b - a) * fraction }
        else { elevation = nil }
        let status = conservativeStatus(lower.1.status, upper.1.status)
        let uncertainty: Double?
        if let a = lower.1.uncertainty, let b = upper.1.uncertainty { uncertainty = max(a, b) }
        else { uncertainty = lower.1.uncertainty ?? upper.1.uncertainty }
        let evidence = Evidence<GeoCoordinate>(
            value: GeoCoordinate(latitudeDeg: coordinate.latitude, longitudeDeg: coordinate.longitude, elevationM: elevation),
            status: status,
            sourceIDs: Array(Set(lower.1.sourceIDs + upper.1.sourceIDs)).sorted(),
            uncertainty: uncertainty,
            confidence: lower.1.confidence == upper.1.confidence ? lower.1.confidence : .unrated,
            note: "Interpolated by chainage between adjacent route geometry samples."
        )
        return (evidence, bearingDegrees(from: start, to: end))
    }

    private static func conservativeStatus(_ lhs: AccuracyStatus, _ rhs: AccuracyStatus) -> AccuracyStatus {
        let rank: [AccuracyStatus: Int] = [.verified: 0, .measured: 1, .estimated: 2, .placeholder: 3, .unknown: 4]
        return (rank[lhs] ?? 4) >= (rank[rhs] ?? 4) ? lhs : rhs
    }

    private static func slerp(_ a: GeoCoordinate, _ b: GeoCoordinate, fraction t: Double) -> (latitude: Double, longitude: Double) {
        let radians = Double.pi / 180
        let lat1 = a.latitudeDeg * radians
        let lon1 = a.longitudeDeg * radians
        let lat2 = b.latitudeDeg * radians
        let lon2 = b.longitudeDeg * radians
        let v1 = (x: cos(lat1) * cos(lon1), y: cos(lat1) * sin(lon1), z: sin(lat1))
        let v2 = (x: cos(lat2) * cos(lon2), y: cos(lat2) * sin(lon2), z: sin(lat2))
        let dot = min(1, max(-1, v1.x * v2.x + v1.y * v2.y + v1.z * v2.z))
        let omega = acos(dot)
        let xyz: (Double, Double, Double)
        if omega < 1e-10 {
            xyz = (v1.x + (v2.x - v1.x) * t, v1.y + (v2.y - v1.y) * t, v1.z + (v2.z - v1.z) * t)
        } else {
            let denominator = sin(omega)
            let w1 = sin((1 - t) * omega) / denominator
            let w2 = sin(t * omega) / denominator
            xyz = (w1 * v1.x + w2 * v2.x, w1 * v1.y + w2 * v2.y, w1 * v1.z + w2 * v2.z)
        }
        let latitude = atan2(xyz.2, sqrt(xyz.0 * xyz.0 + xyz.1 * xyz.1)) / radians
        let longitude = atan2(xyz.1, xyz.0) / radians
        return (latitude, longitude)
    }

    private static func bearingDegrees(from a: GeoCoordinate, to b: GeoCoordinate) -> Double? {
        let radians = Double.pi / 180
        let lat1 = a.latitudeDeg * radians
        let lat2 = b.latitudeDeg * radians
        let deltaLon = (b.longitudeDeg - a.longitudeDeg) * radians
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        guard x.isFinite, y.isFinite, abs(x) + abs(y) > 1e-12 else { return nil }
        let degrees = atan2(y, x) / radians
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
