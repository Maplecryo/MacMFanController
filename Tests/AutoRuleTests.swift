import Foundation

let minRPM = 1200
let maxRPM = 7000

enum FanPreset {
    case p20
    case p40
    case p50
    case p80
    case max

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

func ruleDecision(temperatures: Temperatures, gpu: RuleConfig, cpu: RuleConfig) -> RuleDecision? {
    if gpu.enabled, let value = temperatures.gpuProximity, value > Double(gpu.threshold) {
        return RuleDecision(rpm: ruleRPM(preset: gpu.preset, rpmText: gpu.rpmText), reason: "GPU Temp > \(gpu.threshold)C")
    }

    if cpu.enabled, let value = temperatures.cpuDie, value > Double(cpu.threshold) {
        return RuleDecision(rpm: ruleRPM(preset: cpu.preset, rpmText: cpu.rpmText), reason: "CPU Die > \(cpu.threshold)C")
    }

    return nil
}

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let gpuRule = RuleConfig(enabled: true, threshold: 70, preset: .p50, rpmText: "")
let cpuRule = RuleConfig(enabled: true, threshold: 90, preset: .max, rpmText: "")

let gpuDecision = ruleDecision(temperatures: Temperatures(cpuDie: 60, gpuProximity: 72), gpu: gpuRule, cpu: cpuRule)
assert(gpuDecision?.rpm == FanPreset.p50.rpm, "GPU rule should use the selected preset RPM")
assert(gpuDecision?.reason == "GPU Temp > 70C", "GPU rule should report its configured threshold")

let cpuDecision = ruleDecision(temperatures: Temperatures(cpuDie: 95, gpuProximity: 60), gpu: gpuRule, cpu: cpuRule)
assert(cpuDecision?.rpm == FanPreset.max.rpm, "CPU rule should trigger when GPU does not")
assert(cpuDecision?.reason == "CPU Die > 90C", "CPU rule should report its configured threshold")

let rpmOverride = RuleConfig(enabled: true, threshold: 70, preset: .p50, rpmText: "3600")
let overrideDecision = ruleDecision(temperatures: Temperatures(cpuDie: 60, gpuProximity: 72), gpu: rpmOverride, cpu: cpuRule)
assert(overrideDecision?.rpm == 3600, "Manual RPM should override the preset")

let clamped = RuleConfig(enabled: true, threshold: 70, preset: .p50, rpmText: "99999")
let clampedDecision = ruleDecision(temperatures: Temperatures(cpuDie: 60, gpuProximity: 72), gpu: clamped, cpu: cpuRule)
assert(clampedDecision?.rpm == maxRPM, "Manual RPM override should be clamped")

let noDecision = ruleDecision(temperatures: Temperatures(cpuDie: 80, gpuProximity: 60), gpu: gpuRule, cpu: cpuRule)
assert(noDecision == nil, "Rules should not trigger below thresholds")

print("AutoRuleTests passed")
