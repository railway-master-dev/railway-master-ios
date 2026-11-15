import Foundation

/// batch98 (2026-11-16): CANONICAL tunnel table — the single
/// source of truth for where the tunnels are.
///
/// Before this file existed the project carried two divergent
/// answers: RegionalRouteFactory's section predicate (which
/// drives the physics resistance, the built tunnel shells, the
/// tunnel run bed / reverb and every other profile consumer)
/// and RailwaySceneView's hardcoded `isTunnelChainage`, which
/// additionally claimed a 24,000–25,846 m tunnel through
/// 東央千原 (S12) that has never existed in the built world,
/// disagreed with the built shells by 50–100 m at both real
/// tunnels' ends, and knew nothing of the branch tunnel.
/// Every producer now reads THIS table:
///
/// - RegionalRouteFactory stamps `resistanceMultiplier` onto
///   its 250 m sections from these design spans (a section is a
///   tunnel section when its midpoint falls inside a span).
///   Section midpoints sit at …+125 m on the 250 m grid and no
///   span boundary below is a multiple of 250 m offset by 125,
///   so the closed bounds here are exactly equivalent to the
///   strict inequalities the factory used before.
/// - RoutePackage's legacy fallback converter stamps the same
///   multiplier from the same table, so even a fallback run
///   agrees on where the tunnels are.
///
/// Consumers never copy the numbers: anything that needs the
/// tunnels of a built route derives them from the profile's
/// sections via `builtSpans(in:)` (the merge rule matches
/// RailwaySceneView.buildTunnels). RailwaySceneView's
/// `isTunnelChainage` joined in batch100: `rebuild` derives
/// its spans from `builtSpans(in:)` via
/// `computeTunnelChainageSpans` (mirrored into the
/// direction-independent chainage frame its callers pass,
/// widened ±15 m as portal clearance for buildTunnels' hill
/// mounds) — the phantom 24,000–25,846 span, the ±50–100 m
/// edge offsets and the missing branch case are gone. The
/// pinning test in RegionalIntegrationTests guards the
/// factory side.
enum TunnelSpans {
    /// Design spans on the mainline, in geographic chainage
    /// from 海袋 (S01), metres.
    static let mainline: [(startM: Double, endM: Double)] = [
        (17_800, 19_250),
        (42_100, 43_600)
    ]

    /// Design span on the branch, in branch-local chainage
    /// (metres from the branch's junction end). On the
    /// through-branch route axis this is 63,500–64,050 design
    /// (60,000 + local).
    static let branchLocal: [(startM: Double, endM: Double)] = [
        (3_500, 4_050)
    ]

    /// Resistance multiplier carried by tunnel sections
    /// (1.25 = +25% Davis resistance inside a tunnel).
    static let resistanceMultiplier = 1.25

    static func contains(mainlineChainage chainageM: Double) -> Bool {
        mainline.contains { chainageM >= $0.startM && chainageM <= $0.endM }
    }

    static func contains(branchLocalChainage chainageM: Double) -> Bool {
        branchLocal.contains { chainageM >= $0.startM && chainageM <= $0.endM }
    }

    /// The tunnel spans a built profile actually carries: the
    /// maximal runs of sections whose resistance multiplier is
    /// above 1, merged with the same 0.5 m tolerance
    /// RailwaySceneView.buildTunnels uses, in the profile's own
    /// coordinates (down profiles therefore report the mirrored
    /// spans). Because the factory quantizes the design spans
    /// onto its 250 m grid by section midpoint, the built spans
    /// differ from the design spans at the edges — mainline
    /// design 17,800–19,250 builds as 17,750–19,250, design
    /// 42,100–43,600 as 42,000–43,500, branch-local design
    /// 3,500–4,050 as 3,500–4,000.
    static func builtSpans(in profile: RailwayRouteProfile) -> [(startM: Double, endM: Double)] {
        var spans: [(startM: Double, endM: Double)] = []
        for section in profile.sections where section.tunnelResistanceMultiplier > 1 {
            if let last = spans.last, section.startM <= last.endM + 0.5 {
                spans[spans.count - 1].endM = section.endM
            } else {
                spans.append((startM: section.startM, endM: section.endM))
            }
        }
        return spans
    }
}
