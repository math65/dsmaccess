//
//  PerformanceAlarmRuleSheet.swift
//  dsmaccess
//
//  Composition d'une règle d'alarme. Le formulaire se réduit ou s'étend selon le type choisi :
//  une règle système n'a pas de cible, une règle de service en exige une.
//
//  Le seuil est borné par le couple type / ressource, comme le fait DSM : hors bornes, le NAS
//  refuse la règle. Les bornes sont donc dites à l'écran plutôt que découvertes par un échec.
//

import SwiftUI

struct PerformanceAlarmRuleSheet: View {
    @Bindable var vm: PerformanceAlarmViewModel
    @State private var draft: PerformanceAlarmRuleDraft
    /// Reçoit le brouillon à enregistrer, ou `nil` si l'utilisateur renonce.
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
            // Le NAS n'a rien à proposer : le dire, plutôt que présenter une liste vide dont
            // on ne saurait pas si elle a échoué ou si elle est vide.
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

    /// Le catalogue des ressources change avec le type : une ressource qui n'existe pas pour
    /// le nouveau type laisserait un formulaire que le NAS refuserait.
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
