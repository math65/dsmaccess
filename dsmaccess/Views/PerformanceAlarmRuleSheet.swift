//
//  PerformanceAlarmRuleSheet.swift
//  dsmaccess
//
//  Composing an alarm rule. The form shrinks or expands depending on the chosen type: a
//  system rule has no target, a service rule requires one.
//
//  The threshold is bounded by the type / resource pair, as DSM does it: out of bounds, the
//  NAS refuses the rule. The bounds are therefore stated on screen rather than discovered
//  through a failure.
//

import SwiftUI

struct PerformanceAlarmRuleSheet: View {
    @Bindable var vm: PerformanceAlarmViewModel
    @State private var draft: PerformanceAlarmRuleDraft
    /// Receives the draft to save, or `nil` if the user backs out.
    let completion: (PerformanceAlarmRuleDraft?) -> Void

    @State private var thresholdText: String
    @State private var validationMessage: String?
    @AccessibilityFocusState private var focusFirstField: Bool
    @AccessibilityFocusState private var focusValidation: Bool

    init(
        vm: PerformanceAlarmViewModel,
        draft: PerformanceAlarmRuleDraft,
        completion: @escaping (PerformanceAlarmRuleDraft?) -> Void
    ) {
        self.vm = vm
        self.completion = completion
        _draft = State(initialValue: draft)
        _thresholdText = State(initialValue: String(draft.threshold))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.isCreation ? "alarm.rule.new.title" : "alarm.rule.edit.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Form {
                Section {
                    Picker("alarm.rule.target.label", selection: $draft.kind) {
                        ForEach(PerformanceAlarmRule.Kind.editable) { kind in
                            Text(vm.kindText(kind)).tag(kind)
                        }
                    }
                    .accessibilityFocused($focusFirstField)
                    .onChange(of: draft.kind) { _, _ in adoptDefaults() }

                    switch draft.kind {
                    case .service:
                        targetPicker(title: "common.column.service", targets: vm.services)
                    case .volume:
                        targetPicker(title: "common.column.volume", targets: vm.volumes)
                    default:
                        EmptyView()
                    }
                }

                Section {
                    Picker("common.column.resource", selection: $draft.resource) {
                        ForEach(measures) { measure in
                            Text(vm.resourceText(measure.resource, for: draft.kind))
                                .tag(measure.resource)
                        }
                    }
                    .onChange(of: draft.resource) { _, _ in adoptThresholdDefault() }

                    LabeledContent("alarm.rule.threshold.label") {
                        HStack(spacing: 6) {
                            TextField("alarm.rule.threshold.label", text: $thresholdText)
                                .labelsHidden()
                                .frame(width: 90)
                            if !unit.isEmpty {
                                Text(unit)
                            }
                        }
                    }
                    .accessibilityHint(Text(boundsHint))

                    Text(boundsHint)
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)

                    Picker("common.column.severity", selection: $draft.severity) {
                        Text("common.level.warning").tag(PerformanceAlarmRule.Severity.warning)
                        Text("common.level.critical").tag(PerformanceAlarmRule.Severity.critical)
                    }

                    Toggle("alarm.rule.active.label", isOn: $draft.isEnabled)
                        .accessibilityHint("alarm.rule.active.hint")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($focusValidation)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("monitor.alarm.rule.fields.label")
            .labeledContentStyle(.readable)

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { completion(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(draft.isCreation ? "common.button.create" : "common.button.save") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.isLoadingTargets)
            }
            .padding(20)
        }
        .frame(minWidth: 460, minHeight: 420)
        .task {
            await vm.loadTargets()
            adoptTargetIfNeeded()
            focusFirstField = true
        }
    }

    @ViewBuilder
    private func targetPicker(title: LocalizedStringKey, targets: [PerformanceAlarmViewModel.Target]) -> some View {
        if vm.isLoadingTargets {
            LabeledContent(title) {
                Text("common.status.loading")
                    .foregroundStyle(.readableSecondary)
            }
        } else if targets.isEmpty {
            // The NAS has nothing to offer: say so, rather than showing an empty list where
            // you could not tell whether it failed or is genuinely empty.
            LabeledContent(title) {
                Text("alarm.rule.target.empty")
                    .foregroundStyle(.readableOrange)
            }
        } else {
            Picker(title, selection: $draft.target) {
                ForEach(targets) { target in
                    Text(target.label).tag(target.value)
                }
            }
        }
    }

    private var measures: [PerformanceAlarmRule.Measure] {
        PerformanceAlarmRule.measures(for: draft.kind)
    }

    private var currentMeasure: PerformanceAlarmRule.Measure? {
        measures.first { $0.resource == draft.resource }
    }

    private var unit: String {
        vm.unitText(currentMeasure?.unit ?? .none)
    }

    private var boundsHint: String {
        guard let measure = currentMeasure else { return "" }
        if unit.isEmpty {
            return String(localized: "alarm.rule.threshold.range.hint", defaultValue: "Between \(measure.range.lowerBound) and \(measure.range.upperBound)")
        }
        return String(localized: "alarm.rule.threshold.range_with_unit.hint", defaultValue: "Between \(measure.range.lowerBound) and \(measure.range.upperBound) \(unit)")
    }

    /// The resource catalog changes with the type: a resource that does not exist for the
    /// new type would leave a form the NAS would refuse.
    private func adoptDefaults() {
        if !measures.contains(where: { $0.resource == draft.resource }),
           let first = measures.first {
            draft.resource = first.resource
        }
        adoptThresholdDefault()
        adoptTargetIfNeeded()
    }

    private func adoptThresholdDefault() {
        guard let measure = currentMeasure else { return }
        draft.threshold = measure.defaultThreshold
        thresholdText = String(measure.defaultThreshold)
    }

    private func adoptTargetIfNeeded() {
        let available = draft.kind == .service ? vm.services : vm.volumes
        guard draft.kind == .service || draft.kind == .volume else { return }
        if !available.contains(where: { $0.value == draft.target }) {
            draft.target = available.first?.value ?? ""
        }
    }

    private func submit() {
        guard let measure = currentMeasure else {
            fail(String(localized: "alarm.rule.resource.error.unavailable"))
            return
        }
        guard let threshold = Int(thresholdText.trimmingCharacters(in: .whitespaces)) else {
            fail(String(localized: "alarm.rule.threshold.error.not_integer"))
            return
        }
        guard measure.range.contains(threshold) else {
            fail(String(localized: "alarm.rule.threshold.error.out_of_range", defaultValue: "The threshold must be between \(measure.range.lowerBound) and \(measure.range.upperBound)."))
            return
        }
        if draft.kind.fixedTarget == nil, draft.target.isEmpty {
            fail(String(localized: "alarm.rule.target.hint"))
            return
        }

        validationMessage = nil
        draft.threshold = threshold
        completion(draft)
    }

    private func fail(_ message: String) {
        validationMessage = message
        VoiceOver.announce(message, category: .error, priority: .high)
        focusValidation = true
    }
}
