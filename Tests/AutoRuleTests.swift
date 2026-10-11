import Foundation

let minRPM = 1200
let maxRPM = 7000

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

func ruleDecision(temperatures: Temperatures, gpu: RuleConfig, cpu: RuleConfig) -> RuleDecision? {
    if gpu.enabled, let value = temperatures.gpuProximity, value > Double(gpu.threshold) {
        return RuleDecision(rpm: ruleRPM(rpmText: gpu.rpmText, fallback: gpu.fallbackRPM), reason: "GPU Temp > \(gpu.threshold)C")
    }

    if cpu.enabled, let value = temperatures.cpuDie, value > Double(cpu.threshold) {
        return RuleDecision(rpm: ruleRPM(rpmText: cpu.rpmText, fallback: cpu.fallbackRPM), reason: "CPU Die > \(cpu.threshold)C")
    }

    return nil
}

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let gpuRule = RuleConfig(enabled: true, threshold: 70, rpmText: "4100", fallbackRPM: 4100)
let cpuRule = RuleConfig(enabled: true, threshold: 90, rpmText: "7000", fallbackRPM: 7000)

let gpuDecision = ruleDecision(temperatures: Temperatures(cpuDie: 60, gpuProximity: 72), gpu: gpuRule, cpu: cpuRule)
assert(gpuDecision?.rpm == 4100, "GPU rule should use its direct RPM")
assert(gpuDecision?.reason == "GPU Temp > 70C", "GPU rule should report its configured threshold")

let cpuDecision = ruleDecision(temperatures: Temperatures(cpuDie: 95, gpuProximity: 60), gpu: gpuRule, cpu: cpuRule)
assert(cpuDecision?.rpm == 7000, "CPU rule should trigger when GPU does not")
assert(cpuDecision?.reason == "CPU Die > 90C", "CPU rule should report its configured threshold")

let rpmOverride = RuleConfig(enabled: true, threshold: 70, rpmText: "3600", fallbackRPM: 4100)
let overrideDecision = ruleDecision(temperatures: Temperatures(cpuDie: 60, gpuProximity: 72), gpu: rpmOverride, cpu: cpuRule)
assert(overrideDecision?.rpm == 3600, "Rule should use the direct RPM")

let clamped = RuleConfig(enabled: true, threshold: 70, rpmText: "99999", fallbackRPM: 4100)
let clampedDecision = ruleDecision(temperatures: Temperatures(cpuDie: 60, gpuProximity: 72), gpu: clamped, cpu: cpuRule)
assert(clampedDecision?.rpm == maxRPM, "Manual RPM override should be clamped")

let noDecision = ruleDecision(temperatures: Temperatures(cpuDie: 80, gpuProximity: 60), gpu: gpuRule, cpu: cpuRule)
assert(noDecision == nil, "Rules should not trigger below thresholds")

print("AutoRuleTests passed")
