//
//  FeedbackView.swift
//  dsmaccess
//
//  "Contact the developer" form: problem report (with a diagnostic snapshot),
//  suggestion or question. Accessible in every state: focus placed on opening,
//  sending announced, error visible, announced and focused, automatic dismissal
//  after success.
//

import SwiftUI

struct FeedbackView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var model = FeedbackViewModel()
    @FocusState private var typeFocused: Bool
    @AccessibilityFocusState private var typeA11yFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        Group {
            if AppBackendClient.isConfigured {
                form
            } else {
                unavailable
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("common.action.contact_developer")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Picker("feedback.field.message_type", selection: $model.contactType) {
                ForEach(AppBackendClient.ContactType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .focused($typeFocused)
            .accessibilityFocused($typeA11yFocused)

            LabeledField(label: "feedback.field.email") {
                TextField("feedback.field.email", text: $model.email)
                    .textContentType(.emailAddress)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("feedback.field.message")
                    .font(.subheadline)
                    .foregroundStyle(.readableSecondary)
                    .accessibilityHidden(true)
                TextEditor(text: $model.message)
                    .font(.body)
                    .frame(minHeight: 120)
                    .border(.separator)
                    .accessibilityLabel("feedback.field.message")
            }

            if model.contactType == .bug {
                Text("feedback.diagnostic_snapshot.description")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
            }

            if let incident = model.incident {
                Text(String(localized: "feedback.unreadable_reply.description", defaultValue: "The unreadable reply will be attached: the \(incident.api) \(incident.method) call and the names of the fields received, without their contents."))
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.readableRed)
                    .accessibilityFocused($errorFocused)
            }

            HStack {
                if model.isSending {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("common.status.sending_message")
                }
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("common.button.upload") {
                    Task {
                        await model.send(session: session, settings: settings)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSend)
            }
        }
        .disabled(model.isSending)
        .onAppear {
            model.adoptPendingIncident()
            model.adoptPendingOperationFailure()
            typeFocused = true
            typeA11yFocused = true
        }
        .onChange(of: model.errorMessage) { _, newValue in
            if newValue != nil {
                errorFocused = true
            }
        }
        .onChange(of: model.didSucceed) { _, didSucceed in
            if didSucceed {
                dismiss()
            }
        }
    }

    private var unavailable: some View {
        Text("common.error.messaging_unavailable")
            .frame(minHeight: 80)
    }
}
