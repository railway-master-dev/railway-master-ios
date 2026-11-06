import Foundation

struct LoadedRailwayRoute {
    let profile: RailwayRouteProfile
    let blockSystem: ThreeAspectBlockSystem
    let issues: [RouteDataIssue]
}

/// Strict, versioned loader for the bundled fictional RoutePackage.
/// The full 60 km mainline stays external JSON and serves only as a fallback if the canonical operations plan cannot load.
enum RailwayRoutePackageLoader {
    private struct Disclaimer: Decodable {
        let fictionalOnly: Bool
        let noRealWorldImitation: Bool
        let text: String
    }

    private struct Route: Decodable {
        let dataStatus: String
        let routeId: String
        let name: String
        let routeLengthM: Double
        let startChainageM: Double
        let endChainageM: Double
        let trackGaugeMm: Double
        let nominalMaxSpeedKmh: Double
    }

    private struct Station: Decodable {
        let stationId: String
        let name: String
        let chainageM: Double
    }

    private struct Segment: Decodable {
        let segmentId: String
        let startStationId: String
        let endStationId: String
        let startChainageM: Double
        let endChainageM: Double
        let distanceM: Double
    }

    private struct Curve: Decodable {
        let startChainageM: Double
        let endChainageM: Double
        let curveRadiusM: Double
        let curveDirection: String
        let cantMm: Double
        let trackIds: [String]
    }

    private struct Gradient: Decodable {
        let startChainageM: Double
        let endChainageM: Double
        let gradientPermille: Double
        let trackIds: [String]
    }

    private struct SpeedRestriction: Decodable {
        let startChainageM: Double
        let endChainageM: Double
        let limitKmh: Double
        let trackIds: [String]
    }

    private struct Block: Decodable {
        let blockId: String
        let trackId: String
        let startChainageM: Double
        let endChainageM: Double
    }

    private struct Document: Decodable {
        let packageType: String
        let schemaVersion: String
        let disclaimer: Disclaimer
        let route: Route
        let stations: [Station]
        let segments: [Segment]
        let curves: [Curve]
        let gradients: [Gradient]
        let speedRestrictions: [SpeedRestriction]
        let blocks: [Block]
    }

    static func load(data: Data, segmentIndex: Int = 0) throws -> LoadedRailwayRoute {
        let document = try JSONDecoder().decode(Document.self, from: data)
        try validate(document)
        guard document.segments.indices.contains(segmentIndex) else {
            throw RoutePackageLoadError.segmentIndexOutOfRange
        }
        let segment = document.segments[segmentIndex]
        guard let departure = document.stations.first(where: { $0.stationId == segment.startStationId }),
              let arrival = document.stations.first(where: { $0.stationId == segment.endStationId }) else {
            throw RoutePackageLoadError.stationReferenceMissing
        }
        let profile = try makeProfile(document: document, segment: segment, departure: departure, arrival: arrival)
        let blocks = try makeBlocks(document: document, segment: segment)
        let profileIssues = profile.validateData()
        guard profileIssues.allSatisfy({ $0.severity != .error }) else {
            throw RoutePackageLoadError.profileValidationFailed
        }
        let packageNotice = RouteDataIssue(
            code: "route.package.fictionalPlaceholder",
            severity: .information,
            field: "routePackage",
            message: "\(document.stations.count)駅・全長\(document.route.routeLengthM.formatted()) mの架空PLACEHOLDER本線fallbackを読み込みました。正本の運行計画が利用できない場合のためのものです。地理・実測・公式データではありません。"
        )
        return LoadedRailwayRoute(profile: profile, blockSystem: blocks, issues: [packageNotice] + profileIssues)
    }

    private static func validate(_ document: Document) throws {
        guard document.packageType == "RoutePackage", document.schemaVersion == "1.0.0" else {
            throw RoutePackageLoadError.unsupportedPackageVersion
        }
        guard document.disclaimer.fictionalOnly, document.disclaimer.noRealWorldImitation else {
            throw RoutePackageLoadError.fictionalDataRequired
        }
        guard document.route.routeId == "fictional_regional_mainline",
              document.route.dataStatus == RouteDataStatus.placeholder.rawValue,
              document.route.startChainageM == 0,
              document.route.routeLengthM.isFinite,
              document.route.endChainageM.isFinite,
              abs(document.route.endChainageM - document.route.routeLengthM) <= 0.01,
              document.route.trackGaugeMm.isFinite, document.route.trackGaugeMm > 0,
              document.route.nominalMaxSpeedKmh.isFinite, document.route.nominalMaxSpeedKmh > 0 else {
            throw RoutePackageLoadError.routeMetadataInvalid
        }
        guard document.stations.count >= 2, !document.segments.isEmpty else {
            throw RoutePackageLoadError.networkIncomplete
        }

        let stations = document.stations.sorted { $0.chainageM < $1.chainageM }
        guard stations.allSatisfy({ $0.chainageM.isFinite && !$0.stationId.isEmpty && !$0.name.isEmpty }),
              Set(stations.map(\.stationId)).count == stations.count,
              abs(stations.first!.chainageM - document.route.startChainageM) <= 0.01,
              abs(stations.last!.chainageM - document.route.endChainageM) <= 0.01 else {
            throw RoutePackageLoadError.stationChainageInvalid
        }

        let segments = document.segments.sorted { $0.startChainageM < $1.startChainageM }
        for index in segments.indices {
            let segment = segments[index]
            guard segment.startChainageM.isFinite, segment.endChainageM.isFinite,
                  segment.distanceM.isFinite, segment.startChainageM >= 0,
                  segment.endChainageM > segment.startChainageM,
                  abs(segment.distanceM - (segment.endChainageM - segment.startChainageM)) <= 0.01 else {
                throw RoutePackageLoadError.segmentRangeInvalid
            }
            if index > 0, abs(segment.startChainageM - segments[index - 1].endChainageM) > 0.01 {
                throw RoutePackageLoadError.segmentContinuityInvalid
            }
            guard stations.contains(where: { $0.stationId == segment.startStationId && abs($0.chainageM - segment.startChainageM) <= 0.01 }),
                  stations.contains(where: { $0.stationId == segment.endStationId && abs($0.chainageM - segment.endChainageM) <= 0.01 }) else {
                throw RoutePackageLoadError.stationReferenceMissing
            }
        }
        guard abs(segments.first!.startChainageM - document.route.startChainageM) <= 0.01,
              abs(segments.last!.endChainageM - document.route.endChainageM) <= 0.01 else {
            throw RoutePackageLoadError.segmentContinuityInvalid
        }

        let rangesAreValid = document.curves.allSatisfy { $0.startChainageM.isFinite && $0.endChainageM.isFinite && $0.endChainageM > $0.startChainageM && $0.curveRadiusM.isFinite && $0.curveRadiusM > 0 && $0.cantMm.isFinite && ["LEFT", "RIGHT"].contains($0.curveDirection) }
            && document.gradients.allSatisfy { $0.startChainageM.isFinite && $0.endChainageM.isFinite && $0.endChainageM > $0.startChainageM && $0.gradientPermille.isFinite }
            && document.speedRestrictions.allSatisfy { $0.startChainageM.isFinite && $0.endChainageM.isFinite && $0.endChainageM > $0.startChainageM && $0.limitKmh.isFinite && $0.limitKmh > 0 }
            && document.blocks.allSatisfy { !$0.blockId.isEmpty && !$0.trackId.isEmpty && $0.startChainageM.isFinite && $0.endChainageM.isFinite && $0.endChainageM > $0.startChainageM }
        guard rangesAreValid else { throw RoutePackageLoadError.infrastructureRangeInvalid }
    }

    private static func makeProfile(document: Document, segment: Segment, departure: Station, arrival: Station) throws -> RailwayRouteProfile {
        let start = segment.startChainageM
        let end = segment.endChainageM
        var boundaries = [start, end]
        let infrastructureRanges = document.curves.map { ($0.startChainageM, $0.endChainageM) }
            + document.gradients.map { ($0.startChainageM, $0.endChainageM) }
            + document.speedRestrictions.map { ($0.startChainageM, $0.endChainageM) }
        for range in infrastructureRanges {
            if range.0 > start && range.0 < end { boundaries.append(range.0) }
            if range.1 > start && range.1 < end { boundaries.append(range.1) }
        }
        boundaries.sort()
        var unique: [Double] = []
        for value in boundaries where unique.last.map({ abs($0 - value) > 0.01 }) ?? true {
            unique.append(value)
        }
        guard unique.count >= 2 else { throw RoutePackageLoadError.segmentRangeInvalid }

        var sections: [RouteSection] = []
        for index in 0..<(unique.count - 1) {
            let absoluteStart = unique[index]
            let absoluteEnd = unique[index + 1]
            let midpoint = (absoluteStart + absoluteEnd) * 0.5
            guard absoluteEnd > absoluteStart,
                  let speed = document.speedRestrictions.first(where: {
                      $0.trackIds.contains("T1") && midpoint >= $0.startChainageM && midpoint < $0.endChainageM
                  }) else { throw RoutePackageLoadError.speedRestrictionCoverageInvalid }
            let gradient = document.gradients.first(where: {
                $0.trackIds.contains("T1") && midpoint >= $0.startChainageM && midpoint < $0.endChainageM
            })?.gradientPermille ?? 0
            let curve = document.curves.first(where: {
                $0.trackIds.contains("T1") && midpoint >= $0.startChainageM && midpoint < $0.endChainageM
            })
            sections.append(RouteSection(
                startM: absoluteStart - start,
                endM: absoluteEnd - start,
                gradientPermille: gradient,
                curveRadiusM: curve?.curveRadiusM,
                curveDirection: curve.map { $0.curveDirection == "RIGHT" ? 1 : -1 },
                cantMm: curve?.cantMm,
                speedLimitKmh: speed.limitKmh,
                tunnelResistanceMultiplier: 1
            ))
        }

        let status = RouteDataStatus(rawValue: document.route.dataStatus) ?? .unknown
        let provenance = [RouteDataProvenance(
            field: "fictional-route-package",
            status: .placeholder,
            sourceName: "RAILWAY MASTER fictional RoutePackage",
            methodOrBasis: document.disclaimer.text,
            confidence: "実在情報との対応なし"
        )]
        return RailwayRouteProfile(
            lineName: document.route.name,
            departureStation: departure.name,
            arrivalStation: arrival.name,
            distanceM: segment.endChainageM - segment.startChainageM,
            stopMarkerM: arrival.chainageM - start,
            sections: sections,
            trackGaugeMm: document.route.trackGaugeMm,
            dataStatus: status,
            dataProvenance: provenance
        )
    }

    private static func makeBlocks(document: Document, segment: Segment) throws -> ThreeAspectBlockSystem {
        let tracks = ["T1", "T2"]
        var result: [RailwayBlock] = []
        for trackID in tracks {
            let matching = document.blocks.filter { $0.trackId == trackID }
                .sorted { $0.startChainageM < $1.startChainageM }
            var clipped: [(source: Block, start: Double, end: Double)] = []
            for block in matching where block.endChainageM > segment.startChainageM && block.startChainageM < segment.endChainageM {
                clipped.append((block, max(block.startChainageM, segment.startChainageM), min(block.endChainageM, segment.endChainageM)))
            }
            guard !clipped.isEmpty,
                  abs(clipped.first!.start - segment.startChainageM) <= 0.01,
                  abs(clipped.last!.end - segment.endChainageM) <= 0.01 else {
                throw RoutePackageLoadError.blockCoverageInvalid
            }
            for index in clipped.indices {
                if index > 0, abs(clipped[index].start - clipped[index - 1].end) > 0.01 {
                    throw RoutePackageLoadError.blockCoverageInvalid
                }
                let source = clipped[index].source
                result.append(try RailwayBlock(
                    identifier: source.blockId,
                    startM: clipped[index].start - segment.startChainageM,
                    endM: clipped[index].end - segment.startChainageM,
                    trackID: trackID
                ))
            }
        }
        return try ThreeAspectBlockSystem(blocks: result)
    }
}

enum RoutePackageLoadError: Error {
    case unsupportedPackageVersion
    case fictionalDataRequired
    case routeMetadataInvalid
    case networkIncomplete
    case stationChainageInvalid
    case segmentRangeInvalid
    case segmentContinuityInvalid
    case stationReferenceMissing
    case infrastructureRangeInvalid
    case speedRestrictionCoverageInvalid
    case blockCoverageInvalid
    case segmentIndexOutOfRange
    case profileValidationFailed
}
