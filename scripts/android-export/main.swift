import Foundation

// Writes the Android port's reference data and its parity fixture from the
// iOS sources themselves, so nothing in either file is transcribed by hand.
// Run through scripts/sync-android-parity.sh.

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: export <reference.json> <parity.json>\n".data(using: .utf8)!)
    exit(2)
}

func day(_ date: Date?) -> Any { date.map(DateOnly.dayKey) ?? NSNull() }

func write(_ object: Any, to path: String, pretty: Bool = true) {
    let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    let data = try! JSONSerialization.data(withJSONObject: object, options: options)
    try! data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Reference data (shipped in the app)

func startJSON(_ start: StartAdvice) -> [String: Any] {
    switch start {
    case .straightAway: return ["kind": "straightAway"]
    case .afterDays(let days, let because): return ["kind": "afterDays", "days": days, "because": because]
    case .after(let key, let because): return ["kind": "after", "key": key, "because": because]
    }
}

func sourcingJSON(_ sourcing: RuleSourcing) -> [String: Any] {
    switch sourcing {
    case .cite(let key, let subject): return ["cite": key, "subject": subject.rawValue]
    case .none(let reason): return ["noneReason": reason]
    }
}

let rules: [[String: Any]] = RequirementCatalog.all.map { rule in
    [
        "key": rule.key,
        "title": rule.title,
        "shortTitle": rule.shortTitle,
        "category": rule.category.rawValue,
        "sortWeight": rule.sortWeight,
        "sourcing": sourcingJSON(rule.sourcing),
        "documents": rule.documents.map { ["key": $0.key, "title": $0.title, "detail": $0.detail] },
        "isPostedAway": rule.isPostedAway,
        "start": startJSON(rule.start)
    ]
}

let sources: [[String: Any]] = SourceManifest.all.map { entry in
    [
        "key": entry.key,
        "title": entry.title,
        "agency": entry.agency,
        "urlString": entry.urlString,
        "subjects": entry.subjects.map(\.rawValue).sorted(),
        "reviewedOn": DateOnly.dayKey(entry.reviewedOn),
        "status": entry.status.rawValue,
        "limitations": entry.limitations
    ]
}

let offices: [[String: Any]] = StateVitalRecords.allOffices.map { office in
    [
        "stateCode": office.stateCode,
        "officeName": office.officeName,
        "urlString": office.urlString,
        "orderingNote": office.orderingNote,
        "verifiedOn": day(office.verifiedOn),
        "check": office.check.rawValue
    ]
}

let reference: [String: Any] = [
    "states": USState.all.map { ["code": $0.code, "name": $0.name] },
    "rules": rules,
    "ssnWarning": RequirementCatalog.ssnWarning,
    "sources": sources,
    "vitalRecords": [
        "federalDirectoryURL": StateVitalRecords.federalDirectoryURL,
        "offices": offices
    ],
    "counties": USCounties.all
]
write(reference, to: args[1])

// MARK: - Parity fixture (tests only)

/// Deterministic, so the fixture only changes when a rule does.
struct LCG {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
    mutating func pick<T>(_ values: [T]) -> T { values[next(values.count)] }
}

var strings: [String] = []
var stringIndex: [String: Int] = [:]
func s(_ value: String) -> Int {
    if let index = stringIndex[value] { return index }
    strings.append(value)
    stringIndex[value] = strings.count - 1
    return strings.count - 1
}

let birthDays = ["2024-11-30", "2025-01-01", "2026-03-08", "2026-10-20", "2026-12-31", "2028-06-15", "2029-01-02"]
let stateCodes = ["", "CA", "OH", "NY", "TX", "GU", "PR", "WY", "DC"]
let names = ["", "Rosa", "  Theo  ", "Ana María"]
let planNames = ["", "Acme PPO", "  Kaiser HMO "]
let contacts = ["", "HR line 555-0100", "  benefits@acme.example "]

var rng = LCG(state: 20261020)
var cases: [[String: Any]] = []
for index in 0..<240 {
    var input = RuleInput()
    input.childName = rng.pick(names)
    let birthKey = rng.pick(birthDays)
    input.birthDate = DateOnly.date(from: birthKey)!
    input.birthStateCode = rng.pick(stateCodes)
    input.isUSCitizen = rng.next(5) != 0
    input.ssnStatus = rng.pick(SSNStatus.allCases)
    input.hasSSN = input.ssnStatus == .cardReceived
    input.hasBirthCertificate = rng.next(2) == 0
    input.residenceStateCode = rng.pick(stateCodes)
    input.parentage = rng.pick(ParentageSituation.allCases)
    input.secondParentOnRecord = rng.next(2) == 0
    input.insuranceKind = index < 5 ? InsuranceKind.allCases[index] : rng.pick(InsuranceKind.allCases)
    input.marketplaceKind = rng.pick(MarketplaceKind.allCases)
    input.hasDependentCareFSA = rng.next(2) == 0
    input.wantsPassport = rng.next(2) == 0
    input.wants529 = rng.next(2) == 0
    input.wantsNewbornAccount = rng.next(3) != 0
    input.parentalLeaveTakers = rng.pick(ParentalLeaveTakers.allCases)
    input.employerPlanName = rng.pick(planNames)
    input.benefitsContactNote = rng.pick(contacts)

    var results: [[String: Any]] = []
    for rule in RequirementCatalog.all {
        let deadline = rule.deadline(input)
        let link = rule.link(input)
        results.append([
            "key": rule.key,
            "applies": rule.applies(input),
            "title": s(rule.title(for: input)),
            "detail": s(rule.detail(input)),
            "due": day(deadline.date),
            "kind": deadline.kind.rawValue,
            "basis": s(deadline.basis),
            "linkLabel": link.map { s($0.label) } ?? -1,
            "linkURL": link.map { s($0.urlString) } ?? -1
        ])
    }
    cases.append([
        "input": [
            "childName": input.childName,
            "birthDate": birthKey,
            "birthStateCode": input.birthStateCode,
            "isUSCitizen": input.isUSCitizen,
            "ssnStatus": input.ssnStatus.rawValue,
            "hasBirthCertificate": input.hasBirthCertificate,
            "residenceStateCode": input.residenceStateCode,
            "parentage": input.parentage.rawValue,
            "secondParentOnRecord": input.secondParentOnRecord,
            "insuranceKind": input.insuranceKind.rawValue,
            "marketplaceKind": input.marketplaceKind.rawValue,
            "hasDependentCareFSA": input.hasDependentCareFSA,
            "wantsPassport": input.wantsPassport,
            "wants529": input.wants529,
            "wantsNewbornAccount": input.wantsNewbornAccount,
            "parentalLeaveTakers": input.parentalLeaveTakers.rawValue,
            "employerPlanName": input.employerPlanName,
            "benefitsContactNote": input.benefitsContactNote
        ],
        "rules": results
    ])
}

let namespace = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
let ids: [[String: String]] = ["task:ssn_card", "task:insurance_employer", "doc:proof_of_birth", ""].map { name in
    ["namespace": namespace.uuidString, "name": name, "id": DeterministicID.v5(namespace: namespace, name: name).uuidString]
}

let sensitiveSamples = [
    "123-45-6789", "123 45 6789", "123456789", "SSN 123.45.6789 here", "1234567890",
    "phone 555-0100", "Acme PPO", "card 0123-45-6789-0", "ID 987654321.", "12-345-6789"
]
let sensitive: [[String: Any]] = sensitiveSamples.map {
    ["text": $0, "contains": PlanSeed.containsSocialSecurityNumber($0), "safe": PlanSeed.safeExternalText($0)]
}

let seed = PlanSeed(
    childID: namespace,
    name: "Rosa",
    birthDate: DateOnly.date(from: "2026-09-01")!,
    birthStateCode: "CA",
    birthCounty: "Alameda County",
    isUSCitizen: true,
    residenceStateCode: "CA",
    parentage: ParentageSituation.unmarriedBothParents.rawValue,
    secondParentOnRecord: false,
    insuranceKind: InsuranceKind.employer.rawValue,
    marketplaceKind: MarketplaceKind.unknown.rawValue,
    employerPlanName: "Acme PPO",
    benefitsContactNote: "HR line",
    hasDependentCareFSA: true,
    wantsPassport: false,
    wants529: true,
    wantsNewbornAccount: true,
    takingParentalLeave: true,
    parentalLeaveTakers: ParentalLeaveTakers.bothParents.rawValue
)

let parity: [String: Any] = [
    "ruleKeys": RequirementCatalog.all.map(\.key),
    "reviewedOn": DateOnly.dayKey(RequirementCatalog.reviewedOn),
    "verifiedStateCodes": StateVitalRecords.verifiedStateCodes,
    "fullyReadStateCodes": StateVitalRecords.fullyReadStateCodes,
    "countyCount": USCounties.all.values.reduce(0) { $0 + $1.count },
    "canonicalCounties": [
        ["raw": "Alameda", "state": "CA", "match": USCounties.canonicalName(matching: "Alameda", inStateCode: "CA") ?? ""],
        ["raw": "st. louis", "state": "MO", "match": USCounties.canonicalName(matching: "st. louis", inStateCode: "MO") ?? ""],
        ["raw": "Nowhere", "state": "OH", "match": USCounties.canonicalName(matching: "Nowhere", inStateCode: "OH") ?? ""]
    ],
    "strings": strings,
    "cases": cases,
    "deterministicIDs": ids,
    "sensitive": sensitive,
    "seedPayload": seed.encoded()!,
    "seedURL": seed.shareURL()!.absoluteString
]
write(parity, to: args[2], pretty: false)
print("rules \(RequirementCatalog.all.count), cases \(cases.count), strings \(strings.count)")
