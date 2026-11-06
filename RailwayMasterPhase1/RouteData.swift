import Foundation

/// Status labels follow the route-data specification; they are never inferred from the presence of a number.
public enum RouteDataStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case verified = "VERIFIED"
    case measured = "MEASURED"
    case estimated = "ESTIMATED"
    case placeholder = "PLACEHOLDER"
    case unknown = "UNKNOWN"
}

/// Provenance is attached to a named field or field group so future real-route packages can be audited.
public struct RouteDataProvenance: Codable, Equatable, Sendable {
    public let field: String
    public let status: RouteDataStatus
    public let sourceName: String?
    public let sourceURL: String?
    public let retrievedAt: String?
    public let methodOrBasis: String?
    public let uncertaintyM: Double?
    public let confidence: String?
    public let licenseNote: String?

    public init(
        field: String,
        status: RouteDataStatus,
        sourceName: String? = nil,
        sourceURL: String? = nil,
        retrievedAt: String? = nil,
        methodOrBasis: String? = nil,
        uncertaintyM: Double? = nil,
        confidence: String? = nil,
        licenseNote: String? = nil
    ) {
        self.field = field
        self.status = status
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.retrievedAt = retrievedAt
        self.methodOrBasis = methodOrBasis
        self.uncertaintyM = uncertaintyM
        self.confidence = confidence
        self.licenseNote = licenseNote
    }
}

public enum RouteDataIssueSeverity: String, Codable, Equatable, Sendable {
    case information
    case warning
    case error
}

public struct RouteDataIssue: Codable, Equatable, Sendable {
    public let code: String
    public let severity: RouteDataIssueSeverity
    public let field: String
    public let message: String

    public init(code: String, severity: RouteDataIssueSeverity, field: String, message: String) {
        self.code = code
        self.severity = severity
        self.field = field
        self.message = message
    }
}

public extension RailwayRouteProfile {
    /// Basic deterministic quality checks. This validates the supplied package; it does not certify real-world accuracy.
    func validateData() -> [RouteDataIssue] {
        var issues: [RouteDataIssue] = []
        let ordered = sections.sorted { $0.startM < $1.startM }

        if ordered.isEmpty {
            issues.append(.init(code: "route.sections.empty", severity: .error, field: "sections", message: "区間データがありません。"))
        } else {
            if ordered[0].startM > 0.01 {
                issues.append(.init(code: "route.chainage.startGap", severity: .error, field: "sections[0].startM", message: "区間データが0 mから始まっていません。"))
            }
            for index in ordered.indices {
                let section = ordered[index]
                if !section.startM.isFinite || !section.endM.isFinite || section.endM <= section.startM {
                    issues.append(.init(code: "route.section.range", severity: .error, field: "sections[\(index)]", message: "区間の開始・終了キロ程が不正です。"))
                }
                if section.startM < -0.05 || section.endM > distanceM + 0.05 {
                    issues.append(.init(code: "route.section.outOfBounds", severity: .error, field: "sections[\(index)]", message: "区間が路線キロ程の範囲外です。"))
                }
                if !section.speedLimitKmh.isFinite || section.speedLimitKmh <= 0 {
                    issues.append(.init(code: "route.speedLimit.invalid", severity: .error, field: "sections[\(index)].speedLimitKmh", message: "速度制限が正の有限値ではありません。"))
                }
                if !section.gradientPermille.isFinite || !section.tunnelResistanceMultiplier.isFinite || section.tunnelResistanceMultiplier < 1 {
                    issues.append(.init(code: "route.section.conditionInvalid", severity: .error, field: "sections[\(index)]", message: "勾配または抵抗倍率が不正です。"))
                }
                if let radius = section.curveRadiusM, !radius.isFinite || radius <= 0 {
                    issues.append(.init(code: "route.curveRadius.invalid", severity: .error, field: "sections[\(index)].curveRadiusM", message: "曲線半径が正の有限値ではありません。"))
                }
                if let cant = section.cantMm, !cant.isFinite || abs(cant) > 500 {
                    issues.append(.init(code: "route.cant.invalid", severity: .error, field: "sections[\(index)].cantMm", message: "カント値が不正です。"))
                }
                if let direction = section.curveDirection, direction != -1 && direction != 1 {
                    issues.append(.init(code: "route.curveDirection.invalid", severity: .error, field: "sections[\(index)].curveDirection", message: "曲線方向は左(-1)・右(1)のどちらかです。"))
                }
                if let transition = section.curveTransition,
                   section.curveRadiusM == nil || !transition.isValid
                    || transition.startM < -0.05 || transition.endM > distanceM + 0.05
                    || transition.endM <= section.startM || transition.startM >= section.endM {
                    issues.append(.init(code: "route.curveTransition.invalid", severity: .error, field: "sections[\(index)].curveTransition", message: "緩和曲線の境界・半径・区間との交差が不正です。"))
                }
                if index > 0 {
                    let previous = ordered[index - 1]
                    if section.startM > previous.endM + 0.05 {
                        issues.append(.init(code: "route.chainage.gap", severity: .error, field: "sections[\(index)]", message: "区間間にキロ程の欠落があります。"))
                    } else if section.startM < previous.endM - 0.05 {
                        issues.append(.init(code: "route.chainage.overlap", severity: .error, field: "sections[\(index)]", message: "区間同士が重複しています。"))
                    }
                }
            }
            if let last = ordered.last, last.endM < distanceM - 0.05 {
                issues.append(.init(code: "route.chainage.endGap", severity: .error, field: "sections", message: "路線終端まで区間データがありません。"))
            }
        }

        if !trackGaugeMm.isFinite || trackGaugeMm <= 0 || trackGaugeMm > 3_000 {
            issues.append(.init(code: "route.trackGauge.invalid", severity: .error, field: "trackGaugeMm", message: "軌間が正の有限値ではありません。"))
        }

        if dataStatus == .verified && dataProvenance.isEmpty {
            issues.append(.init(code: "route.provenance.missing", severity: .error, field: "dataProvenance", message: "VERIFIEDの路線には出典情報が必要です。"))
        }
        if dataStatus == .placeholder && dataProvenance.isEmpty {
            issues.append(.init(code: "route.data.placeholder", severity: .information, field: "route", message: "PLACEHOLDER: 実在路線の根拠値として使用しないでください。"))
        }
        for record in dataProvenance {
            switch record.status {
            case .verified:
                if record.sourceName?.isEmpty != false || record.sourceURL?.isEmpty != false || record.retrievedAt?.isEmpty != false {
                    issues.append(.init(code: "route.provenance.verifiedIncomplete", severity: .error, field: record.field, message: "VERIFIEDデータには出典名・原資料URL・取得日が必要です。"))
                } else if let urlString = record.sourceURL, let url = URL(string: urlString), !["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    issues.append(.init(code: "route.provenance.urlInvalid", severity: .error, field: record.field, message: "出典URLはhttpまたはhttpsである必要があります。"))
                }
            case .measured:
                if record.methodOrBasis?.isEmpty != false {
                    issues.append(.init(code: "route.provenance.measurementMethodMissing", severity: .warning, field: record.field, message: "MEASUREDデータの測定方法が記録されていません。"))
                }
            case .estimated:
                if record.methodOrBasis?.isEmpty != false || record.uncertaintyM == nil || (record.uncertaintyM ?? 0) <= 0 {
                    issues.append(.init(code: "route.provenance.estimateIncomplete", severity: .warning, field: record.field, message: "ESTIMATEDデータには推定根拠と正の誤差幅が必要です。"))
                }
            case .placeholder:
                issues.append(.init(code: "route.data.placeholder", severity: .information, field: record.field, message: "PLACEHOLDER: 実在路線の根拠値として使用しないでください。"))
            case .unknown:
                issues.append(.init(code: "route.data.unknown", severity: .information, field: record.field, message: "UNKNOWN: 値が未確認です。推測で確定値にしないでください。"))
            }
        }
        return issues
    }
}
