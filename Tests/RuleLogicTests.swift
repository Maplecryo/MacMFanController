import Foundation

private let minRPM = 1200
private let maxRPM = 7000

enum FanPreset: String {
    case p20 = "20%"
    case p40 = "40%"
    case p50 = "50%"
    case p80 = "80%"
    case max = "MAX"

    var rpm: Int {
        let percent: Int
        switch self {
        case .p20: percent = 20
        case .p40: percent = 40
        case .p50: percent = 50
        case .p80: percent = 80
        case .max: percent = 100
        }
        return minRPM + Int(Double(maxRPM - minRPM) * Double(percent) / 100.0)
    }
}

struct Temperatures {
    var cpuDie: Double?
    var gpuProximity: Double?
}

struct RuleConfig {
    let enabled: Bool
    let threshold: Int
    let preset: FanPreset
    let rpmText: String
}

struct RuleDecision {
    let preset: FanPreset
    let rpm: Int
    let reason: String
}

func ruleRPM(preset: FanPreset, rpmText: String) -> Int {
    let trimmed = rpmText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let rpm = Int(trimmed) else {
        return preset.rpm
    }
    return max(minRPM, min(maxRPM, rpm))
}

func clampedTemperature(_ text: String, fallback: Int) -> Int {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(trimmed) else {
        return fallback
    }
    return max(20, min(120, value))
}

func clampedRPM(_ text: String, fallback: Int) -> Int {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(trimmed) else {
        return max(minRPM, min(maxRPM, fallback))
    }
    return max(minRPM, min(maxRPM, value))
}

func ruleDecision(temperatures: Temperatures, gpu: RuleConfig, cpu: RuleConfig) -> RuleDecision? {
    if gpu.enabled, let value = temperatures.gpuProximity, value > Double(gpu.threshold) {
        return RuleDecision(
            preset: gpu.preset,
            rpm: ruleRPM(preset: gpu.preset, rpmText: gpu.rpmText),
            reason: "GPU Temp > \(gpu.threshold)C"
        )
    }

    if cpu.enabled, let value = temperatures.cpuDie, value > Double(cpu.threshold) {
        return RuleDecision(
            preset: cpu.preset,
            rpm: ruleRPM(preset: cpu.preset, rpmText: cpu.rpmText),
            reason: "CPU Die > \(cpu.threshold)C"
        )
    }

    return nil
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual != expected {
        fputs("FAIL: \(label). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertNil<T>(_ actual: T?, _ label: String) {
    if actual != nil {
        fputs("FAIL: \(label). Expected nil\n", stderr)
        exit(1)
    }
}

let gpuRule = RuleConfig(enabled: true, threshold: 70, preset: .p50, rpmText: "")
let cpuRule = RuleConfig(enabled: true, threshold: 90, preset: .max, rpmText: "")

let gpuDecision = ruleDecision(
    temperatures: Temperatures(cpuDie: 60, gpuProximity: 71),
    gpu: gpuRule,
    cpu: cpuRule
)
assertEqual(gpuDecision?.rpm, FanPreset.p50.rpm, "GPU preset rule uses preset RPM")
assertEqual(gpuDecision?.reason, "GPU Temp > 70C", "GPU rule reason")

let cpuDecision = ruleDecision(
    temperatures: Temperatures(cpuDie: 91, gpuProximity: 60),
    gpu: gpuRule,
    cpu: cpuRule
)
assertEqual(cpuDecision?.rpm, FanPreset.max.rpm, "CPU preset rule uses MAX RPM")
assertEqual(cpuDecision?.reason, "CPU Die > 90C", "CPU rule reason")

let rpmOverride = ruleDecision(
    temperatures: Temperatures(cpuDie: 60, gpuProximity: 75),
    gpu: RuleConfig(enabled: true, threshold: 70, preset: .p20, rpmText: "4200"),
    cpu: cpuRule
)
assertEqual(rpmOverride?.rpm, 4200, "manual RPM override wins")

assertEqual(ruleRPM(preset: .p40, rpmText: "9999"), maxRPM, "manual RPM clamps high")
assertEqual(ruleRPM(preset: .p40, rpmText: "10"), minRPM, "manual RPM clamps low")
assertEqual(clampedRPM("3600", fallback: 2500), 3600, "manual fan RPM accepts typed value")
assertEqual(clampedRPM("oops", fallback: 2500), 2500, "bad manual fan RPM keeps fallback")
assertEqual(clampedTemperature("140", fallback: 70), 120, "temperature clamps high")
assertEqual(clampedTemperature("oops", fallback: 70), 70, "bad temperature keeps fallback")

let noDecision = ruleDecision(
    temperatures: Temperatures(cpuDie: 70, gpuProximity: 65),
    gpu: gpuRule,
    cpu: cpuRule
)
assertNil(noDecision, "rules stay quiet below thresholds")

print("Rule logic tests passed")
