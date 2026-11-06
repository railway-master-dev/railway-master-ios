import Foundation

public enum OperationsScoreCategory: String, Codable, CaseIterable, Sendable {
    case schedule
    case stoppingAccuracy
    case smoothness
    case ruleBasedSkills
}

public enum OperationsScoreMetric: String, Codable, CaseIterable, Sendable {
    case arrivalPunctuality
    case departurePunctuality
    case stopOffset
    case overshoot
    case peakJerk
    case harshAcceleration
    case harshBraking
    case signalCompliance
    case speedLimitCompliance
    case workflowSequence
    case pointingCalling
    case disruptionResponse
}

public struct OperationsScoringConfiguration: Codable, Equatable, Sendable {
    public let punctualityToleranceSeconds: Double
    public let punctualityZeroScoreAtSeconds: Double
    public let stopZeroScoreDistanceM: Double
    public let comfortableAccelerationMps2: Double
    public let comfortableBrakingMps2: Double
    public let comfortableJerkMps3: Double

    public init(punctualityToleranceSeconds: Double = 30, punctualityZeroScoreAtSeconds: Double = 300, stopZeroScoreDistanceM: Double = 10, comfortableAccelerationMps2: Double = 0.8, comfortableBrakingMps2: Double = 0.9, comfortableJerkMps3: Double = 0.8) throws {
        guard punctualityToleranceSeconds.isFinite, punctualityToleranceSeconds >= 0,
              punctualityZeroScoreAtSeconds.isFinite, punctualityZeroScoreAtSeconds > punctualityToleranceSeconds,
              stopZeroScoreDistanceM.isFinite, stopZeroScoreDistanceM > 0,
              comfortableAccelerationMps2.isFinite, comfortableAccelerationMps2 > 0,
              comfortableBrakingMps2.isFinite, comfortableBrakingMps2 > 0,
              comfortableJerkMps3.isFinite, comfortableJerkMps3 > 0 else {
            throw OperationsError.invalidValue("scoring configuration")
        }
        self.punctualityToleranceSeconds = punctualityToleranceSeconds
        self.punctualityZeroScoreAtSeconds = punctualityZeroScoreAtSeconds
        self.stopZeroScoreDistanceM = stopZeroScoreDistanceM
        self.comfortableAccelerationMps2 = comfortableAccelerationMps2
        self.comfortableBrakingMps2 = comfortableBrakingMps2
        self.comfortableJerkMps3 = comfortableJerkMps3
    }

    public static var gameDefaults: OperationsScoringConfiguration {
        // Constants are scoring-game defaults, not recommended operating limits.
        try! OperationsScoringConfiguration()
    }
}

public struct DisruptionResponseOutcome: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let matchedGameChoice: Bool

    public init(id: String, matchedGameChoice: Bool) throws {
        guard !id.isEmpty else { throw OperationsError.invalidValue("disruption response id") }
        self.id = id
        self.matchedGameChoice = matchedGameChoice
    }
}

public struct OperationsScoringInput: Codable, Equatable, Sendable {
    public let scheduleObservations: [ScheduleObservation]
    public let stopAssessments: [StopAssessment]
    public let motionSamples: [MotionSample]
    public let ruleOutcomes: [GameRuleOutcome]
    public let pointingCallingRecords: [PointingCallingRecord]
    public let disruptionResponses: [DisruptionResponseOutcome]

    public init(scheduleObservations: [ScheduleObservation] = [], stopAssessments: [StopAssessment] = [], motionSamples: [MotionSample] = [], ruleOutcomes: [GameRuleOutcome] = [], pointingCallingRecords: [PointingCallingRecord] = [], disruptionResponses: [DisruptionResponseOutcome] = []) {
        self.scheduleObservations = scheduleObservations
        self.stopAssessments = stopAssessments
        self.motionSamples = motionSamples
        self.ruleOutcomes = ruleOutcomes
        self.pointingCallingRecords = pointingCallingRecords
        self.disruptionResponses = disruptionResponses
    }
}

public struct OperationsMetricScore: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let metric: OperationsScoreMetric
    public let score: Double?
    public let measuredValue: Double?
    public let unit: String
    public let explanation: String

    public init(id: String, metric: OperationsScoreMetric, score: Double?, measuredValue: Double? = nil, unit: String = "", explanation: String) {
        self.id = id
        self.metric = metric
        self.score = score.map { min(100, max(0, $0)) }
        self.measuredValue = measuredValue
        self.unit = unit
        self.explanation = explanation
    }
}

public struct OperationsCategoryScore: Codable, Equatable, Sendable, Identifiable {
    public var id: String { category.rawValue }
    public let category: OperationsScoreCategory
    public let score: Double?
    public let metrics: [OperationsMetricScore]
    public let explanation: String
}

public struct OperationsScorecard: Codable, Equatable, Sendable {
    public let categories: [OperationsCategoryScore]
    public let overallScore: Double?
    public let label: OperationsContentLabel

    public func score(for category: OperationsScoreCategory) -> Double? {
        categories.first(where: { $0.category == category })?.score
    }
}

/// Scores only the game's fictional schedule, stop, comfort and rule checks.
public enum OperationsScorer {
    public static func evaluate(
        _ input: OperationsScoringInput,
        mode: TrainingMode,
        configuration: OperationsScoringConfiguration = .gameDefaults
    ) -> OperationsScorecard {
        let toleranceScale = mode.profile.toleranceMultiplier
        let categories = [
            scheduleScores(input, configuration: configuration, toleranceScale: toleranceScale),
            stopScores(input, configuration: configuration, toleranceScale: toleranceScale),
            smoothnessScores(input, configuration: configuration),
            ruleScores(input, mode: mode)
        ]
        let evaluated = categories.compactMap(\.score)
        let overall = evaluated.isEmpty ? nil : evaluated.reduce(0, +) / Double(evaluated.count)
        return OperationsScorecard(categories: categories, overallScore: overall, label: .gameOnlyNotSafetyTraining)
    }

    private static func scheduleScores(_ input: OperationsScoringInput, configuration: OperationsScoringConfiguration, toleranceScale: Double) -> OperationsCategoryScore {
        let arrivals = input.scheduleObservations.filter { $0.kind == .arrival }
        let departures = input.scheduleObservations.filter { $0.kind == .departure }
        var metrics: [OperationsMetricScore] = []
        if !arrivals.isEmpty {
            let scores = arrivals.map { punctualityScore(abs($0.deviationSeconds), configuration: configuration, toleranceScale: toleranceScale) }
            let meanDeviation = arrivals.map { abs($0.deviationSeconds) }.reduce(0, +) / Double(arrivals.count)
            metrics.append(OperationsMetricScore(id: "arrival", metric: .arrivalPunctuality, score: mean(scores), measuredValue: meanDeviation, unit: "s", explanation: "到着予定との差の平均絶対値"))
        }
        if !departures.isEmpty {
            let scores = departures.map { punctualityScore(abs($0.deviationSeconds), configuration: configuration, toleranceScale: toleranceScale) }
            let meanDeviation = departures.map { abs($0.deviationSeconds) }.reduce(0, +) / Double(departures.count)
            metrics.append(OperationsMetricScore(id: "departure", metric: .departurePunctuality, score: mean(scores), measuredValue: meanDeviation, unit: "s", explanation: "出発予定との差の平均絶対値"))
        }
        return category(.schedule, metrics: metrics, explanation: "到着・出発時刻のゲーム内ダイヤ差")
    }

    private static func stopScores(_ input: OperationsScoringInput, configuration: OperationsScoringConfiguration, toleranceScale: Double) -> OperationsCategoryScore {
        guard !input.stopAssessments.isEmpty else { return category(.stoppingAccuracy, metrics: [], explanation: "停車データなし") }
        let offsetScores = input.stopAssessments.map { stop -> Double in
            guard stop.stopped else { return 0 }
            return distanceScore(abs(stop.positionErrorM), tolerance: stop.toleranceM * toleranceScale, zeroAt: configuration.stopZeroScoreDistanceM * toleranceScale)
        }
        let overshootScores = input.stopAssessments.map { stop -> Double in
            distanceScore(stop.overshootM, tolerance: stop.toleranceM * toleranceScale, zeroAt: configuration.stopZeroScoreDistanceM * toleranceScale)
        }
        let meanOffset = input.stopAssessments.map { abs($0.positionErrorM) }.reduce(0, +) / Double(input.stopAssessments.count)
        let meanOvershoot = input.stopAssessments.map(\.overshootM).reduce(0, +) / Double(input.stopAssessments.count)
        let metrics = [
            OperationsMetricScore(id: "offset", metric: .stopOffset, score: mean(offsetScores), measuredValue: meanOffset, unit: "m", explanation: "停止目標からの平均絶対距離"),
            OperationsMetricScore(id: "overshoot", metric: .overshoot, score: mean(overshootScores), measuredValue: meanOvershoot, unit: "m", explanation: "目標を通過した平均距離")
        ]
        return category(.stoppingAccuracy, metrics: metrics, explanation: "停止位置と通過量。向きはキロ程増加方向のゲーム路線を基準")
    }

    private static func smoothnessScores(_ input: OperationsScoringInput, configuration: OperationsScoringConfiguration) -> OperationsCategoryScore {
        let samples = input.motionSamples.sorted { $0.simulationTimeSeconds < $1.simulationTimeSeconds }
        guard !samples.isEmpty else { return category(.smoothness, metrics: [], explanation: "運動サンプルなし") }
        var peakJerk: Double?
        if samples.count > 1 {
            var largest = 0.0
            for index in 1..<samples.count {
                let dt = samples[index].simulationTimeSeconds - samples[index - 1].simulationTimeSeconds
                guard dt > 0 else { continue }
                largest = max(largest, abs(samples[index].accelerationMps2 - samples[index - 1].accelerationMps2) / dt)
            }
            peakJerk = largest
        }
        let accelRatio = Double(samples.filter { $0.accelerationMps2 > configuration.comfortableAccelerationMps2 }.count) / Double(samples.count)
        let brakeRatio = Double(samples.filter { $0.accelerationMps2 < -configuration.comfortableBrakingMps2 }.count) / Double(samples.count)
        var metrics = [
            OperationsMetricScore(id: "high-acceleration", metric: .harshAcceleration, score: ratioScore(accelRatio), measuredValue: accelRatio, unit: "ratio", explanation: "設定したゲーム内快適加速度を超えたサンプル比率"),
            OperationsMetricScore(id: "hard-braking", metric: .harshBraking, score: ratioScore(brakeRatio), measuredValue: brakeRatio, unit: "ratio", explanation: "設定したゲーム内快適減速度を超えたサンプル比率")
        ]
        if let peakJerk {
            let score = max(0, min(100, 100 * (1 - max(0, peakJerk - configuration.comfortableJerkMps3) / (configuration.comfortableJerkMps3 * 4))))
            metrics.append(OperationsMetricScore(id: "peak-jerk", metric: .peakJerk, score: score, measuredValue: peakJerk, unit: "m/s³", explanation: "隣接する加速度サンプルから算出した最大ジャーク"))
        } else {
            metrics.append(OperationsMetricScore(id: "peak-jerk", metric: .peakJerk, score: nil, measuredValue: nil, unit: "m/s³", explanation: "ジャーク計算には時刻の異なる2件以上のサンプルが必要"))
        }
        return category(.smoothness, metrics: metrics, explanation: "加速度・制動・ジャークを使うゲーム内の乗り心地評価")
    }

    private static func ruleScores(_ input: OperationsScoringInput, mode: TrainingMode) -> OperationsCategoryScore {
        var metrics: [OperationsMetricScore] = []
        for kind in [GameRuleKind.signalCompliance, .speedLimitCompliance, .workflowSequence] {
            let values = input.ruleOutcomes.filter { $0.kind == kind }
            guard !values.isEmpty else { continue }
            let score = max(0, 100 - values.filter { !$0.passed }.map(\.deductionPoints).reduce(0, +))
            let metric: OperationsScoreMetric = kind == .signalCompliance ? .signalCompliance : (kind == .speedLimitCompliance ? .speedLimitCompliance : .workflowSequence)
            metrics.append(OperationsMetricScore(id: kind.rawValue, metric: metric, score: score, measuredValue: Double(values.filter { !$0.passed }.count), unit: "game events", explanation: "架空ゲーム規則の判定結果"))
        }

        if !input.pointingCallingRecords.isEmpty {
            let correct = input.pointingCallingRecords.filter { $0.result == .correct }.count
            let score = 100 * Double(correct) / Double(input.pointingCallingRecords.count)
            metrics.append(OperationsMetricScore(id: "pointing-calling", metric: .pointingCalling, score: score, measuredValue: Double(input.pointingCallingRecords.count - correct), unit: "miss/incorrect", explanation: "ゲーム内チェックポイントで正しいコールだった割合"))
        }

        if mode == .disruptionTraining, !input.disruptionResponses.isEmpty {
            let correct = input.disruptionResponses.filter(\.matchedGameChoice).count
            let score = 100 * Double(correct) / Double(input.disruptionResponses.count)
            metrics.append(OperationsMetricScore(id: "disruption-response", metric: .disruptionResponse, score: score, measuredValue: Double(input.disruptionResponses.count - correct), unit: "mismatch", explanation: "架空イベントに対するゲーム選択肢の一致率。実務判断の評価ではない"))
        }
        return category(.ruleBasedSkills, metrics: metrics, explanation: "手順・信号・速度・指差喚呼・イベントのゲーム内ルール評価")
    }

    private static func punctualityScore(_ absoluteDeviation: Double, configuration: OperationsScoringConfiguration, toleranceScale: Double) -> Double {
        let tolerance = configuration.punctualityToleranceSeconds * toleranceScale
        let zeroAt = configuration.punctualityZeroScoreAtSeconds * toleranceScale
        if absoluteDeviation <= tolerance { return 100 }
        return max(0, min(100, 100 * (zeroAt - absoluteDeviation) / (zeroAt - tolerance)))
    }

    private static func distanceScore(_ distance: Double, tolerance: Double, zeroAt: Double) -> Double {
        if distance <= tolerance { return 100 }
        guard zeroAt > tolerance else { return 0 }
        return max(0, min(100, 100 * (zeroAt - distance) / (zeroAt - tolerance)))
    }

    private static func ratioScore(_ ratio: Double) -> Double {
        max(0, min(100, 100 * (1 - ratio * 2)))
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func category(_ category: OperationsScoreCategory, metrics: [OperationsMetricScore], explanation: String) -> OperationsCategoryScore {
        let scores = metrics.compactMap(\.score)
        let score = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        return OperationsCategoryScore(category: category, score: score, metrics: metrics, explanation: explanation)
    }
}
