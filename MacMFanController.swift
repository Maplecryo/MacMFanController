import AppKit
import SwiftUI

private let minRPM = 1200
private let maxRPM = 7000

enum FanMode: String, CaseIterable, Identifiable {
    case synced = "Sync both fans"
    case independent = "Independent"
    var id: String { rawValue }
}

enum FanPreset: String, CaseIterable, Identifiable {
    case p20 = "20%"
    case p40 = "40%"
    case p50 = "50%"
    case p80 = "80%"
    case max = "MAX"

    var id: String { rawValue }

    var percent: Int {
        switch self {
        case .p20: return 20
        case .p40: return 40
        case .p50: return 50
        case .p80: return 80
        case .max: return 100
        }
    }

    var rpm: Int {
        minRPM + Int(Double(maxRPM - minRPM) * Double(percent) / 100.0)
    }
}

struct Temperatures {
    var cpuDie: Double?
    var gpuProximity: Double?

    var menuTitle: String {
        cpuDie.map { "Fan \(Int($0.rounded()))C" } ?? "Fan"
    }
}

struct CommandResult {
    let code: Int32
    let output: String
}

struct RuleDecision {
    let rpm: Int
    let reason: String
}

struct RuleConfig {
    let enabled: Bool
    let threshold: Int
    let rpmText: String
    let fallbackRPM: Int
}

@MainActor
final class FanController: ObservableObject {
    @Published var backendText = "Checking backend..."
    @Published var statusText = "Ready."
    @Published var isRunning = false
    @Published var fanMode: FanMode = .synced
    @Published var fan0Preset: FanPreset = .p40
    @Published var fan1Preset: FanPreset = .p40
    @Published var manualRPMText = "2500"
    @Published var manualFan0RPMText = "2500"
    @Published var manualFan1RPMText = "2500"
    @Published var availableFanCount = 0
    @Published var temperatures = Temperatures()
    @Published var rulesEnabled = false
    @Published var gpuRuleEnabled = true
    @Published var cpuRuleEnabled = false
    @Published var gpuRuleThreshold = 70
    @Published var cpuRuleThreshold = 90
    @Published var gpuRuleThresholdText = "70"
    @Published var cpuRuleThresholdText = "90"
    @Published var gpuRuleRPM = "4100"
    @Published var cpuRuleRPM = "7000"
    @Published var lastRuleText = "No rule triggered yet."
    @Published var menuTitle = "Fan"

    private let smctlPath: String?
    private let worker = DispatchQueue(label: "com.maplecryo.MacMFanController.smctl", qos: .userInitiated)
    private let outputLimit = 64 * 1024
    private var pollTimer: Timer?
    private var lastRuleRPM: Int?

    init() {
        let candidates = [
            "/opt/homebrew/bin/smctl",
            "/usr/local/bin/smctl",
            "/usr/bin/smctl"
        ]
        smctlPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        backendText = smctlPath.map { "Backend: \($0)" } ?? "Backend missing: install smctl and its daemon"
        startPolling()
    }

    func startPolling() {
        pollTimer?.invalidate()
        refreshTemperatures()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTemperatures()
            }
        }
    }

    func applySyncedPreset(_ preset: FanPreset) {
        fanMode = .synced
        fan0Preset = preset
        fan1Preset = preset
        runFanCommand(preset: preset, fan: "all", reason: "Manual synced preset")
    }

    func applyFan0Preset(_ preset: FanPreset) {
        fanMode = .independent
        fan0Preset = preset
        runFanCommand(preset: preset, fan: "0", reason: "Manual fan 0 preset")
    }

    func applyFan1Preset(_ preset: FanPreset) {
        fanMode = .independent
        fan1Preset = preset
        runFanCommand(preset: preset, fan: "1", reason: "Manual fan 1 preset")
    }

    func applyManualSyncedRPM() {
        fanMode = .synced
        let rpm = Self.clampedRPM(manualRPMText, fallback: 2500)
        manualRPMText = "\(rpm)"
        runRPMCommand(rpm: rpm, fan: "all", reason: "Manual synced RPM")
    }

    func applyManualFan0RPM() {
        fanMode = .independent
        let rpm = Self.clampedRPM(manualFan0RPMText, fallback: 2500)
        manualFan0RPMText = "\(rpm)"
        runRPMCommand(rpm: rpm, fan: "0", reason: "Manual fan 0 RPM")
    }

    func applyManualFan1RPM() {
        fanMode = .independent
        let rpm = Self.clampedRPM(manualFan1RPMText, fallback: 2500)
        manualFan1RPMText = "\(rpm)"
        runRPMCommand(rpm: rpm, fan: "1", reason: "Manual fan 1 RPM")
    }

    func restoreAuto() {
        runAsync(["fan", "profile", "auto"], label: "Restore Auto")
        lastRuleRPM = nil
        lastRuleText = "Automatic fan control restored."
    }

    func refreshStatus() {
        runAsync(["sensors"], label: "Fan Status")
    }

    func refreshTemperatures() {
        guard smctlPath != nil else {
            statusText = """
            smctl was not found.

            Install backend:
              brew install leaperone/smctl/smctl
              sudo smctl daemon install
            """
            return
        }

        worker.async { [weak self] in
            guard let self else { return }
            let outputs = [
                Self.run(path: self.smctlPath, args: ["sensors"], outputLimit: self.outputLimit).output
            ].filter { !$0.isEmpty }
            let joined = outputs.joined(separator: "\n")
            let temps = Self.parseTemperatures(joined)

            DispatchQueue.main.async {
                self.temperatures = temps
                if !joined.isEmpty {
                    self.availableFanCount = Self.parseFanCount(joined)
                }
                self.menuTitle = temps.menuTitle
                if !joined.isEmpty {
                    self.statusText = Self.formatTemps(temps) + "\n\n" + Self.truncate(joined, limit: 4000)
                }
                self.evaluateRules()
            }
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func runFanCommand(preset: FanPreset, fan: String, reason: String) {
        runRPMCommand(rpm: preset.rpm, fan: fan, reason: "\(reason): \(preset.rawValue)")
    }

    private func runRPMCommand(rpm: Int, fan: String, reason: String) {
        var args = ["fan", "set", "\(rpm)"]
        if fan != "all" {
            args.append(contentsOf: ["--fan", fan])
        }
        runAsync(args, label: "\(reason) (\(rpm) RPM)")
    }

    nonisolated static func clampedRPM(_ text: String, fallback: Int) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rpm = Int(trimmed) else {
            return max(minRPM, min(maxRPM, fallback))
        }
        return max(minRPM, min(maxRPM, rpm))
    }

    private func evaluateRules() {
        guard rulesEnabled else { return }
        syncRuleThresholdsFromText()

        let decision = Self.ruleDecision(
            temperatures: temperatures,
            gpu: RuleConfig(
                enabled: gpuRuleEnabled,
                threshold: gpuRuleThreshold,
                rpmText: gpuRuleRPM,
                fallbackRPM: 4100
            ),
            cpu: RuleConfig(
                enabled: cpuRuleEnabled,
                threshold: cpuRuleThreshold,
                rpmText: cpuRuleRPM,
                fallbackRPM: 7000
            )
        )

        if let decision {
            triggerRule(decision)
        }
    }

    private func triggerRule(_ decision: RuleDecision) {
        guard lastRuleRPM != decision.rpm else { return }
        lastRuleRPM = decision.rpm
        fanMode = .synced
        lastRuleText = "\(decision.reason) -> fans \(decision.rpm) RPM"
        runRPMCommand(rpm: decision.rpm, fan: "all", reason: "Auto rule")
    }

    private func syncRuleThresholdsFromText() {
        gpuRuleThreshold = Self.clampedTemperature(gpuRuleThresholdText, fallback: gpuRuleThreshold)
        cpuRuleThreshold = Self.clampedTemperature(cpuRuleThresholdText, fallback: cpuRuleThreshold)
        gpuRuleThresholdText = "\(gpuRuleThreshold)"
        cpuRuleThresholdText = "\(cpuRuleThreshold)"
    }

    nonisolated static func ruleDecision(
        temperatures: Temperatures,
        gpu: RuleConfig,
        cpu: RuleConfig
    ) -> RuleDecision? {
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

    nonisolated static func ruleRPM(rpmText: String, fallback: Int) -> Int {
        let trimmed = rpmText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rpm = Int(trimmed) else {
            return max(minRPM, min(maxRPM, fallback))
        }
        return max(minRPM, min(maxRPM, rpm))
    }

    nonisolated static func clampedTemperature(_ text: String, fallback: Int) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else {
            return fallback
        }
        return max(20, min(120, value))
    }

    private func runAsync(_ args: [String], fallback: [String]? = nil, label: String) {
        guard smctlPath != nil else {
            statusText = "smctl was not found. Install smctl and its daemon."
            return
        }

        isRunning = true
        statusText = "\(label)\nRunning: smctl \(args.joined(separator: " "))"
        worker.async { [weak self] in
            guard let self else { return }
            let result = Self.run(path: self.smctlPath, args: args, outputLimit: self.outputLimit)
            let finalResult = (result.code != 0 && fallback != nil)
                ? Self.run(path: self.smctlPath, args: fallback!, outputLimit: self.outputLimit)
                : result

            DispatchQueue.main.async {
                self.statusText = finalResult.output.isEmpty
                    ? "\(label)\nCommand completed."
                    : "\(label)\n\(Self.truncate(finalResult.output, limit: 4000))"
                self.isRunning = false
            }
        }
    }

    nonisolated private static func run(path: String?, args: [String], outputLimit: Int) -> CommandResult {
        guard let path else {
            return CommandResult(code: 127, output: "smctl was not found.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(8)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                return CommandResult(code: 124, output: "smctl timed out after 8 seconds.")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data.prefix(outputLimit), encoding: .utf8) ?? ""
            return CommandResult(code: process.terminationStatus, output: text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return CommandResult(code: 1, output: error.localizedDescription)
        }
    }

    nonisolated private static func parseTemperatures(_ text: String) -> Temperatures {
        if let jsonTemps = parseJSONTemperatures(text) {
            return jsonTemps
        }

        var temps = Temperatures()

        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            guard let keyed = keyedTemperature(in: line) else { continue }
            let key = keyed.key.lowercased()
            let value = keyed.value

            if key == "tp0d" || key == "tc0d" || lower.contains("cpu die") || (lower.contains("cpu") && lower.contains("die")) {
                temps.cpuDie = temps.cpuDie ?? value
            }
            if key == "tg0p" || lower.contains("gpu proximity") || (lower.contains("gpu") && lower.contains("prox")) {
                temps.gpuProximity = temps.gpuProximity ?? value
            }
        }

        return temps
    }

    nonisolated private static func parseFanCount(_ text: String) -> Int {
        if let jsonText = jsonSubstring(from: text),
           let data = jsonText.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let fans = root["fans"] as? [[String: Any]] {
            return max(1, fans.count)
        }

        var highestIndex = -1
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Fan "), let colon = trimmed.firstIndex(of: ":") else { continue }
            let indexText = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<colon]
            if let index = Int(indexText) {
                highestIndex = max(highestIndex, index)
            }
        }
        return max(1, highestIndex + 1)
    }

    nonisolated private static func parseJSONTemperatures(_ text: String) -> Temperatures? {
        guard let jsonText = jsonSubstring(from: text),
              let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var temps = Temperatures()

        if let entries = root["temperatures"] as? [[String: Any]] {
            for entry in entries {
                let key = (entry["key"] as? String ?? "").lowercased()
                let name = (entry["name"] as? String ?? "").lowercased()
                guard let value = entry["celsius"] as? Double ?? entry["value"] as? Double else { continue }

                if key == "tg0p" || name.contains("gpu proximity") || (name.contains("gpu") && name.contains("prox")) {
                    temps.gpuProximity = temps.gpuProximity ?? value
                }
                if key == "tp0d" || key == "tc0d" || name.contains("cpu die") || (name.contains("cpu") && name.contains("die")) {
                    temps.cpuDie = temps.cpuDie ?? value
                }
            }
        }

        return temps
    }

    nonisolated private static func jsonSubstring(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    nonisolated private static func keyedTemperature(in text: String) -> (key: String, value: Double)? {
        let pattern = #"([A-Za-z]{1,3}\d[A-Za-z0-9])\s+(-?\d+(?:\.\d+)?)\s*(?:°?\s*C|celsius)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let keyRange = Range(match.range(at: 1), in: text),
              let valueRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]),
              value > -20,
              value < 130 else {
            return nil
        }
        return (String(text[keyRange]), value)
    }

    nonisolated private static func formatTemps(_ temps: Temperatures) -> String {
        func fmt(_ value: Double?) -> String {
            value.map { String(format: "%.1f C", $0) } ?? "unavailable"
        }
        return """
        CPU Die: \(fmt(temps.cpuDie))
        GPU Proximity: \(fmt(temps.gpuProximity))
        """
    }

    nonisolated private static func truncate(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "\n... output truncated ..."
    }
}

struct MenuContentView: View {
    @EnvironmentObject private var controller: FanController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                presets
                Divider()
                temperatures
                Divider()
                rules
                Divider()
                status
                Divider()
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 390, height: 640)
        .scrollIndicators(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mac M Fan Controller")
                .font(.headline)
            Text(controller.backendText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                modeButton("Sync both fans", selected: controller.fanMode == .synced) {
                    controller.fanMode = .synced
                }
                modeButton(
                    "Independent",
                    selected: controller.fanMode == .independent,
                    disabled: controller.availableFanCount > 0 && controller.availableFanCount < 2
                ) {
                    controller.fanMode = .independent
                }
            }

            Text(fanAvailabilityText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    presetRow(title: "Both fans") { preset in
                        controller.applySyncedPreset(preset)
                    }
                    manualRPMRow(title: "Manual RPM", rpmText: $controller.manualRPMText) {
                        controller.applyManualSyncedRPM()
                    }
                }
                .opacity(controller.fanMode == .synced ? 1 : 0)
                .allowsHitTesting(controller.fanMode == .synced)
                .accessibilityHidden(controller.fanMode != .synced)

                VStack(alignment: .leading, spacing: 10) {
                    presetRow(title: "Fan 0") { preset in
                        controller.applyFan0Preset(preset)
                    }
                    manualRPMRow(title: "Fan 0 RPM", rpmText: $controller.manualFan0RPMText) {
                        controller.applyManualFan0RPM()
                    }
                    if controller.availableFanCount > 1 {
                        presetRow(title: "Fan 1") { preset in
                            controller.applyFan1Preset(preset)
                        }
                        manualRPMRow(title: "Fan 1 RPM", rpmText: $controller.manualFan1RPMText) {
                            controller.applyManualFan1RPM()
                        }
                    } else {
                        Text("Fan 1 was not detected by smctl on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(controller.fanMode == .independent ? 1 : 0)
                .allowsHitTesting(controller.fanMode == .independent)
                .accessibilityHidden(controller.fanMode != .independent)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(
                height: controller.fanMode == .synced
                    ? 78
                    : (controller.availableFanCount > 1 ? 160 : 130),
                alignment: .topLeading
            )

            Button("Reset to Auto") {
                controller.restoreAuto()
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isRunning)

        }
    }

    private func presetRow(title: String, action: @escaping (FanPreset) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 6)], spacing: 6) {
                ForEach(FanPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        action(preset)
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(controller.isRunning)
                }
            }
        }
    }

    @ViewBuilder
    private func modeButton(
        _ title: String,
        selected: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if selected {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
                .frame(maxWidth: .infinity)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .disabled(disabled)
                .frame(maxWidth: .infinity)
        }
    }

    private var fanAvailabilityText: String {
        switch controller.availableFanCount {
        case 0:
            return "Checking available fans..."
        case 1:
            return "1 fan detected. Fan 1 controls are unavailable on this Mac."
        default:
            return "\(controller.availableFanCount) fans detected."
        }
    }

    private func manualRPMRow(title: String, rpmText: Binding<String>, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            TextField("RPM", text: rpmText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 86)
            Button("Apply") {
                action()
            }
            .disabled(controller.isRunning)
        }
    }

    private var temperatures: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            tempRow("CPU Die", controller.temperatures.cpuDie)
            tempRow("GPU Proximity", controller.temperatures.gpuProximity)
        }
    }

    private func tempRow(_ label: String, _ value: Double?) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.1f C", $0) } ?? "Unavailable")
                .font(.system(.body, design: .monospaced))
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Auto-trigger rules", isOn: $controller.rulesEnabled)
            ruleRow(
                label: "GPU",
                enabled: $controller.gpuRuleEnabled,
                threshold: $controller.gpuRuleThreshold,
                thresholdText: $controller.gpuRuleThresholdText,
                rpmText: $controller.gpuRuleRPM
            )
            ruleRow(
                label: "CPU Die",
                enabled: $controller.cpuRuleEnabled,
                threshold: $controller.cpuRuleThreshold,
                thresholdText: $controller.cpuRuleThresholdText,
                rpmText: $controller.cpuRuleRPM
            )
            Text(controller.lastRuleText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ruleRow(
        label: String,
        enabled: Binding<Bool>,
        threshold: Binding<Int>,
        thresholdText: Binding<String>,
        rpmText: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(label, isOn: enabled)
                    .frame(width: 92, alignment: .leading)
                Text("Trigger >")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Temp", text: thresholdText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .onSubmit {
                        threshold.wrappedValue = FanController.clampedTemperature(
                            thresholdText.wrappedValue,
                            fallback: threshold.wrappedValue
                        )
                        thresholdText.wrappedValue = "\(threshold.wrappedValue)"
                    }
                Text("C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("Output RPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                TextField("RPM", text: rpmText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit {
                        rpmText.wrappedValue = "\(FanController.clampedRPM(rpmText.wrappedValue, fallback: 2500))"
                    }
                Text("1200-7000")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
            }
        }
        .disabled(!controller.rulesEnabled)
    }

    private var status: some View {
        ScrollView {
            Text(controller.statusText)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(height: 110)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                controller.refreshTemperatures()
            }
            .disabled(controller.isRunning)

            Button("Fan Status") {
                controller.refreshStatus()
            }
            .disabled(controller.isRunning)

            Spacer()

            Button("Quit") {
                controller.quit()
            }
        }
    }
}

@main
struct MacMFanControllerApp: App {
    @StateObject private var controller = FanController()

    var body: some Scene {
        MenuBarExtra(controller.menuTitle, systemImage: "fanblades") {
            MenuContentView()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)
    }
}
