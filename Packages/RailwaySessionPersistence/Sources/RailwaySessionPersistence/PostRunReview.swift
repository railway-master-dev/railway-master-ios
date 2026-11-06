import Foundation

/// One retained driving sample used to score and plot a finished run.
/// Values are game telemetry. They are not a measured brake curve or an official record.
public struct RunTraceSample: Equatable, Sendable {
    public var timeSeconds: Double
    public var distanceM: Double
    public var speedKmh: Double
    public var brakeNotch: Int
    public var emergencyBrake: Bool
    public var speedLimitKmh: Double?
    public var signalAspect: String?

    public init(
        timeSeconds: Double,
        distanceM: Double,
        speedKmh: Double,
        brakeNotch: Int,
        emergencyBrake: Bool,
        speedLimitKmh: Double? = nil,
        signalAspect: String? = nil
    ) {
        self.timeSeconds = timeSeconds
        self.distanceM = distanceM
        self.speedKmh = speedKmh
        self.brakeNotch = brakeNotch
        self.emergencyBrake = emergencyBrake
        self.speedLimitKmh = speedLimitKmh
        self.signalAspect = signalAspect
    }
}

/// A point on the post-run chart. Brake fraction is 0...1; emergency is drawn as 1.
public struct RunTracePoint: Equatable, Sendable {
    public var timeSeconds: Double
    public var distanceM: Double
    public var speedKmh: Double
    public var brakeFraction: Double
    public var speedLimitKmh: Double?
    public var restrictiveSignal: Bool

    public init(timeSeconds: Double, distanceM: Double, speedKmh: Double, brakeFraction: Double, speedLimitKmh: Double?, restrictiveSignal: Bool) {
        self.timeSeconds = timeSeconds
        self.distanceM = distanceM
        self.speedKmh = speedKmh
        self.brakeFraction = brakeFraction
        self.speedLimitKmh = speedLimitKmh
        self.restrictiveSignal = restrictiveSignal
    }
}

public struct RunTraceSeries: Equatable, Sendable {
    public var points: [RunTracePoint]
    public var acceptedSampleCount: Int
    public var rejectedSampleCount: Int
    /// Game plot only. Not a certified tachograph.
    public var dataStatus: String

    public init(points: [RunTracePoint], acceptedSampleCount: Int, rejectedSampleCount: Int) {
        self.points = points
        self.acceptedSampleCount = acceptedSampleCount
        self.rejectedSampleCount = rejectedSampleCount
        self.dataStatus = "PLACEHOLDER"
    }
}

/// Optional station results already produced by stop scoring. Missing fields stay unscored.
public struct StationRunFact: Equatable, Sendable {
    public var stationID: String
    public var displayName: String
    public var arrivalDeviationSeconds: Double?
    public var stopErrorMeters: Double?

    public init(stationID: String, displayName: String, arrivalDeviationSeconds: Double? = nil, stopErrorMeters: Double? = nil) {
        self.stationID = stationID
        self.displayName = displayName
        self.arrivalDeviationSeconds = arrivalDeviationSeconds
        self.stopErrorMeters = stopErrorMeters
    }
}

public struct PostRunScoreLine: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Nil means the run did not contain enough data. It is not a score of zero.
    public var score: Double?
    public var detail: String
    public var dataStatus: String

    public init(id: String, title: String, score: Double?, detail: String) {
        self.id = id
        self.title = title
        self.score = score
        self.detail = detail
        self.dataStatus = "PLACEHOLDER"
    }
}

public struct PostRunReview: Equatable, Sendable {
    public var lines: [PostRunScoreLine]
    public var trace: RunTraceSeries
    public var overallScore: Double?
    public var notes: [String]

    public init(lines: [PostRunScoreLine], trace: RunTraceSeries, overallScore: Double?, notes: [String]) {
        self.lines = lines
        self.trace = trace
        self.overallScore = overallScore
        self.notes = notes
    }
}

public enum PostRunReviewBuilder {
    /// Builds a game review from fixed-tick samples. Tolerances are PLACEHOLDER game values, not operator standards.
    public static func make(
        samples: [RunTraceSample],
        scheduledDurationSeconds: Double? = nil,
        punctualityToleranceSeconds: Double = 30,
        stopMarkerM: Double? = nil,
        stopToleranceM: Double = 5,
        stationFacts: [StationRunFact] = [],
        maximumPlotPoints: Int = 180
    ) -> PostRunReview {
        let trace = RunTraceSeriesBuilder.make(samples: samples, maximumPoints: maximumPlotPoints)
        let accepted = RunTraceSeriesBuilder.acceptedSamples(samples)
        let punctuality = punctualityLine(
            samples: accepted,
            scheduledDurationSeconds: scheduledDurationSeconds,
            toleranceSeconds: punctualityToleranceSeconds,
            stations: stationFacts
        )
        let stopping = stoppingLine(samples: accepted, stopMarkerM: stopMarkerM, toleranceM: stopToleranceM, stations: stationFacts)
        let speed = speedLine(samples: accepted)
        let signal = signalLine(samples: accepted)
        let lines = [punctuality, stopping, speed, signal]
        let scored = lines.compactMap(\.score)
        let overall = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        var notes = [
            "この総合点はゲーム用PLACEHOLDERです。事業者の運転評価・資格・安全判定ではありません。"
        ]
        if trace.rejectedSampleCount > 0 {
            notes.append("非有限値または時刻が戻ったサンプル\(trace.rejectedSampleCount)件は曲線と集計から除きました。")
        }
        if accepted.count > trace.points.count {
            notes.append("曲線は\(accepted.count)件の有効サンプルを\(trace.points.count)点に間引いて描きます。点は走行の端を残します。")
        }
        return PostRunReview(lines: lines, trace: trace, overallScore: overall, notes: notes)
    }

    private static func punctualityLine(
        samples: [RunTraceSample],
        scheduledDurationSeconds: Double?,
        toleranceSeconds: Double,
        stations: [StationRunFact]
    ) -> PostRunScoreLine {
        let deviations = stations.compactMap(\.arrivalDeviationSeconds).filter(\.isFinite)
        if !deviations.isEmpty {
            let mean = deviations.map(abs).reduce(0, +) / Double(deviations.count)
            let score = toleranceScore(excess: max(0, mean - toleranceSeconds), scale: max(toleranceSeconds, 30))
            return PostRunScoreLine(
                id: "punctuality",
                title: "定時性",
                score: score,
                detail: "停車\(deviations.count)駅の到着差の平均は\(format(mean))秒（ゲーム許容±\(format(toleranceSeconds))秒）。早い着も絶対値で見ます。公式遅延判定ではありません。"
            )
        }
        guard let scheduled = scheduledDurationSeconds, scheduled.isFinite, scheduled > 0,
              let first = samples.first, let last = samples.last, last.timeSeconds >= first.timeSeconds else {
            return PostRunScoreLine(id: "punctuality", title: "定時性", score: nil, detail: "駅の到着差も目標所要時間もないため、定時性は未採点です。")
        }
        let elapsed = last.timeSeconds - first.timeSeconds
        let excess = abs(elapsed - scheduled)
        let score = excess <= toleranceSeconds ? 100 : toleranceScore(excess: excess - toleranceSeconds, scale: max(scheduled, toleranceSeconds))
        let direction = elapsed >= scheduled ? "遅れ" : "早着"
        return PostRunScoreLine(
            id: "punctuality",
            title: "定時性",
            score: score,
            detail: "走行\(format(elapsed))秒、目標\(format(scheduled))秒、\(direction)\(format(excess))秒。ゲーム許容±\(format(toleranceSeconds))秒。"
        )
    }

    private static func stoppingLine(
        samples: [RunTraceSample],
        stopMarkerM: Double?,
        toleranceM: Double,
        stations: [StationRunFact]
    ) -> PostRunScoreLine {
        let errors = stations.compactMap(\.stopErrorMeters).filter(\.isFinite)
        if !errors.isEmpty {
            let mean = errors.map(abs).reduce(0, +) / Double(errors.count)
            let score = mean <= toleranceM ? max(0, 100 - 100 * mean / max(toleranceM, 0.1)) : max(0, 40 - mean)
            return PostRunScoreLine(
                id: "stopping",
                title: "停止精度",
                score: score,
                detail: "記録のある\(errors.count)駅の平均誤差は\(format(mean))m（ゲーム許容±\(format(toleranceM))m）。+は目標を越えた側です。"
            )
        }
        guard let marker = stopMarkerM, marker.isFinite, let nearest = samples.min(by: { abs($0.distanceM - marker) < abs($1.distanceM - marker) }) else {
            return PostRunScoreLine(id: "stopping", title: "停止精度", score: nil, detail: "停止目標も駅別の停止誤差もないため、停止精度は未採点です。")
        }
        let offset = nearest.distanceM - marker
        let stopped = nearest.speedKmh <= 1
        let score: Double? = stopped ? max(0, 100 - 100 * min(abs(offset), toleranceM * 2) / max(toleranceM, 0.1)) : nil
        let detail = stopped
            ? "終端目標\(format(marker))mに対し、最接近サンプルは\(formatSigned(offset))m、速度\(format(nearest.speedKmh))km/h。"
            : "終端目標付近のサンプルが停止速度まで落ちていないため、停止精度は未採点です（最接近\(formatSigned(offset))m）。"
        return PostRunScoreLine(id: "stopping", title: "停止精度", score: score, detail: detail)
    }

    private static func speedLine(samples: [RunTraceSample]) -> PostRunScoreLine {
        let limited = samples.compactMap { sample -> (Double, Double)? in
            guard let limit = sample.speedLimitKmh, limit.isFinite, limit > 0, sample.speedKmh.isFinite else { return nil }
            return (sample.speedKmh, limit)
        }
        guard !limited.isEmpty else {
            return PostRunScoreLine(id: "speed", title: "速度遵守", score: nil, detail: "速度制限がサンプルに無いため、速度遵守は未採点です。")
        }
        let violations = limited.filter { $0.0 > $0.1 + 0.1 }
        let peak = violations.map { $0.0 - $0.1 }.max() ?? 0
        let fraction = Double(violations.count) / Double(limited.count)
        let score = max(0, 100 - fraction * 70 - min(peak * 2, 30))
        let detail = violations.isEmpty
            ? "制限付き\(limited.count)件で、0.1km/hを超える超過はありません。"
            : "制限付き\(limited.count)件中\(violations.count)件が超過。最大約\(format(peak))km/h。サンプル間の瞬間超過は見ていません。"
        return PostRunScoreLine(id: "speed", title: "速度遵守", score: score, detail: detail)
    }

    private static func signalLine(samples: [RunTraceSample]) -> PostRunScoreLine {
        let restrictive = samples.filter(isRestrictiveSignal)
        guard !restrictive.isEmpty else {
            return PostRunScoreLine(id: "signal", title: "信号遵守", score: nil, detail: "停止現示のサンプルが無いため、信号遵守は未採点です。黄信号は減点していません。")
        }
        let moving = restrictive.filter { $0.speedKmh > 15 }
        let fraction = Double(moving.count) / Double(restrictive.count)
        let score = max(0, 100 - fraction * 100)
        return PostRunScoreLine(
            id: "signal",
            title: "信号遵守",
            score: score,
            detail: "停止現示\(restrictive.count)件のうち、15km/hを超えていたのは\(moving.count)件。ゲーム上の粗い見方で、実停止現示の扱いではありません。"
        )
    }

    static func isRestrictiveSignal(_ sample: RunTraceSample) -> Bool {
        guard let aspect = sample.signalAspect?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return aspect == "red" || aspect == "stop"
    }

    private static func toleranceScore(excess: Double, scale: Double) -> Double {
        max(0, 100 - 100 * excess / max(scale, 0.1))
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func formatSigned(_ value: Double) -> String {
        String(format: "%+.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

public enum RunTraceSeriesBuilder {
    public static func acceptedSamples(_ samples: [RunTraceSample]) -> [RunTraceSample] {
        var accepted: [RunTraceSample] = []
        var lastTime = -Double.infinity
        for sample in samples {
            guard sample.timeSeconds.isFinite, sample.distanceM.isFinite, sample.speedKmh.isFinite,
                  sample.timeSeconds >= lastTime else { continue }
            if sample.timeSeconds == lastTime, !accepted.isEmpty { continue }
            accepted.append(sample)
            lastTime = sample.timeSeconds
        }
        return accepted
    }

    public static func make(samples: [RunTraceSample], maximumPoints: Int = 180) -> RunTraceSeries {
        let limit = max(2, maximumPoints)
        let accepted = acceptedSamples(samples)
        let rejected = samples.count - accepted.count
        let chosen = decimate(accepted, maximumPoints: limit)
        let points = chosen.map { sample in
            let brake = sample.emergencyBrake ? 1 : min(1, max(0, Double(sample.brakeNotch) / 7))
            return RunTracePoint(
                timeSeconds: sample.timeSeconds,
                distanceM: sample.distanceM,
                speedKmh: max(0, sample.speedKmh),
                brakeFraction: brake,
                speedLimitKmh: sample.speedLimitKmh.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
                restrictiveSignal: PostRunReviewBuilder.isRestrictiveSignal(sample)
            )
        }
        return RunTraceSeries(points: points, acceptedSampleCount: accepted.count, rejectedSampleCount: rejected)
    }

    private static func decimate(_ samples: [RunTraceSample], maximumPoints: Int) -> [RunTraceSample] {
        guard samples.count > maximumPoints, maximumPoints >= 2 else { return samples }
        var indexes: [Int] = []
        let last = samples.count - 1
        for slot in 0..<maximumPoints {
            let index = Int((Double(slot) * Double(last) / Double(maximumPoints - 1)).rounded())
            if indexes.last != index { indexes.append(index) }
        }
        if indexes.last != last { indexes.append(last) }
        return indexes.map { samples[$0] }
    }
}
