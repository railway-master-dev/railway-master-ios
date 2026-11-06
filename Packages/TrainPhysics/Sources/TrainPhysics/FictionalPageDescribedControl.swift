import Foundation

/// Qualitative control traits taken from public BVE fan-pack pages.
///
/// These are page-described behaviors, not manufacturer data and not a copy of any addon.
/// No vehicle.txt, sound, panel, plugin, or archive from those packs is included.
///
/// - VVVF cruise: https://moribayashi80.tsuyushiba.com/Entry/15/
///   つきさぶ５条１６丁目, 2022-02-11. Variants named on the page: TJ51001F, TJ51002F, TJ50090-C.
///   Hold notch 1 for a few seconds, then notch 2, and the page says speed holds at 20 km/h.
///   Notch 2 at or above 20 km/h holds the current speed. Plugins such as ats.dll stay third-party.
/// - Field chopper: https://sigf.sakura.ne.jp/bve_sb2000.html
///   循環車線 / shallow-field, re-released 2026-10-01. The page says vehicle_8.txt is the 8-car file
///   and that vehicle_6.txt / vehicle_10.txt are extras which differ from the real cars in places.
///   After the cam reaches parallel final, “0A control” re-accelerates sooner in the mid/high range.
///   Regenerative brake works in that state, and does not build if the cam has not reached
///   parallel final or speed has fallen too far. Lamp names on the page: 直列 / 並列 / 最終 / 界磁弱メ / 回生制動.
/// - Resistance: https://sigf.sakura.ne.jp/bve_sb4000.html
///   Same author, published 2016-12-21. The page lists Vehicle_4.txt (4-car, one-man) and
///   Vehicle_8.txt (8-car, with a conductor). Returning the master to notch 1 stops cam progression.
///   Reversing the master applies dynamic holding brake. The early-type motor is described as low-tone;
///   this project synthesizes a low pitch and does not copy that recording.
///   A 10-car 4000 set is not described on that page.
///
/// https://sigf.sakura.ne.jp/bve.html says screenshots, driving videos, and naming the addon are free.
/// Any other secondary use of those addons needs prior consultation. This module does not redistribute them.
public enum FictionalPageDescribedControl: String, Equatable, Sendable {
    case none
    case vvvfCruise
    case fieldChopperCam
    case resistanceCam

    /// Formation profiles only. The older JSON archetypes stay on `.none`.
    public static func kind(forProfileIdentifier identifier: String) -> FictionalPageDescribedControl {
        switch identifier {
        case "fictional-vvvf-form-8", "fictional-vvvf-form-10":
            return .vvvfCruise
        case "fictional-chopper-form-8", "fictional-chopper-form-10":
            return .fieldChopperCam
        case "fictional-resistance-form-8", "fictional-resistance-form-10":
            return .resistanceCam
        default:
            return .none
        }
    }
}

/// Live cab-lamp and cruise readout. Thresholds below the published 20 km/h cruise are PLACEHOLDER.
public struct FictionalControlIndicators: Equatable, Sendable {
    public var camProgress: Double
    public var parallelFinalReached: Bool
    public var cruiseTargetKmh: Double?
    /// True while a resistance master sits in notch 1 and cam progression is frozen.
    public var notchProgressHeld: Bool
    public var seriesLamp: Bool
    public var parallelLamp: Bool
    public var finalStageLamp: Bool
    public var fieldWeakeningLamp: Bool
    public var regenerativeLamp: Bool

    public static let dark = FictionalControlIndicators(
        camProgress: 0,
        parallelFinalReached: false,
        cruiseTargetKmh: nil,
        notchProgressHeld: false,
        seriesLamp: false,
        parallelLamp: false,
        finalStageLamp: false,
        fieldWeakeningLamp: false,
        regenerativeLamp: false
    )
}
