import Foundation

private let minRPM = 1200
private let maxRPM = 7000

struct Temperatures {
    var cpuDie: Double?
    var gpuProximity: Double?
}

struct RuleConfig {
    let enabled: Bool
    let threshold: Int
    let rpmText: String
    let fallbackRPM: Int
}

struct RuleDecision {
    let rpm: Int
    let reason: String
}

func ruleRPM(rpmText: String, fallback: Int) -> Int {
    let trimmed = rpmText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let rpm = Int(trimmed) else {
        return max(minRPM, min(maxRPM, fallback))
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
            rpm: ruleRPM(rpmText: gpu.rpmText, fallback: gpu.fallbackRPM),
            reason: "GPU Temp > \(gpu.threshold)C"
        )
    }

    if cpu.enabled, let value = temperatures.cpuDie, value > Double(cpu.threshold) {
        return RuleDecision(
            rpm: ruleRPM(rpmText: cpu.rpmText, fallback: cpu.fallbackRPM),
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

let gpuRule = RuleConfig(enabled: true, threshold: 70, rpmText: "4100", fallbackRPM: 4100)
let cpuRule = RuleConfig(enabled: true, threshold: 90, rpmText: "7000", fallbackRPM: 7000)

let gpuDecision = ruleDecision(
    temperatures: Temperatures(cpuDie: 60, gpuProximity: 71),
    gpu: gpuRule,
    cpu: cpuRule
)
assertEqual(gpuDecision?.rpm, 4100, "GPU rule uses direct RPM")
assertEqual(gpuDecision?.reason, "GPU Temp > 70C", "GPU rule reason")

let cpuDecision = ruleDecision(
    temperatures: Temperatures(cpuDie: 91, gpuProximity: 60),
    gpu: gpuRule,
    cpu: cpuRule
)
assertEqual(cpuDecision?.rpm, 7000, "CPU rule uses direct RPM")
assertEqual(cpuDecision?.reason, "CPU Die > 90C", "CPU rule reason")

let rpmOverride = ruleDecision(
    temperatures: Temperatures(cpuDie: 60, gpuProximity: 75),
    gpu: RuleConfig(enabled: true, threshold: 70, rpmText: "4200", fallbackRPM: 4100),
    cpu: cpuRule
)
assertEqual(rpmOverride?.rpm, 4200, "manual RPM override wins")

assertEqual(ruleRPM(rpmText: "9999", fallback: 4100), maxRPM, "rule RPM clamps high")
assertEqual(ruleRPM(rpmText: "10", fallback: 4100), minRPM, "rule RPM clamps low")
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
