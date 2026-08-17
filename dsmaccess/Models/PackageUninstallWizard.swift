//
//  PackageUninstallWizard.swift
//  dsmaccess
//
//  The uninstall questions a package asks before it is removed. DSM serves them in the
//  `uninstall_pages` field as a JSON array encoded as a URL-escaped string, already
//  translated. Measured on DSM 7.4 across the seven packages of the test NAS that carry one.
//
//  Three shapes exist. `singleselect` and `multiselect` are declarative and rebuilt here as
//  native controls; a page carrying `custom_render_fn` is a JavaScript function DSM runs to
//  draw itself, which cannot be reproduced and is refused by name.
//

import Foundation

struct PackageUninstallWizard: Equatable, Sendable {
    struct Option: Identifiable, Equatable, Sendable {
        /// Key sent back in `extra_values`, e.g. `wizard_keep_data`.
        let key: String
        let label: String
        let isDefault: Bool

        var id: String { key }
    }

    struct Field: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// One option among several, as a picker.
            case singleChoice
            /// Independent checkboxes.
            case multipleChoice
        }

        let id: String
        let kind: Kind
        let prompt: String?
        let options: [Option]
    }

    struct Step: Identifiable, Equatable, Sendable {
        let id: Int
        let title: String?
        /// Items DSM sends without a `type`: explanatory paragraphs, no control.
        let explanations: [String]
        let fields: [Field]
    }

    let steps: [Step]

    var isEmpty: Bool {
        steps.allSatisfy { $0.fields.isEmpty && $0.explanations.isEmpty }
    }

    /// Answers to send when nothing is touched, straight from each option's `defaultValue`.
    var defaultAnswers: [String: Bool] {
        var answers = [String: Bool]()
        for field in steps.flatMap(\.fields) {
            for option in field.options {
                answers[option.key] = option.isDefault
            }
        }
        return answers
    }
}

extension PackageUninstallWizard {
    /// Decodes what DSM sends, or nil when the package asks nothing. Throws when a page can
    /// only be drawn by running DSM's own JavaScript.
    static func decode(from raw: String?) throws -> PackageUninstallWizard? {
        guard let raw, !raw.isEmpty,
              let unescaped = raw.removingPercentEncoding,
              let data = unescaped.data(using: .utf8) else { return nil }
        // DSM answers a bare `null` for a package that asks nothing.
        let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if decoded == nil || decoded is NSNull { return nil }
        guard let pages = decoded as? [[String: Any]] else {
            // An unknown shape must not be read as "no questions": that would uninstall
            // without asking what the package wanted to ask.
            throw DSMError.packageCenter(
                String(localized: "packages.uninstall.wizard.unreadable.error")
            )
        }
        guard !pages.isEmpty else { return nil }

        var steps = [Step]()
        for (index, page) in pages.enumerated() {
            guard page["custom_render_fn"] == nil else {
                throw DSMError.packageCenter(
                    String(localized: "packages.uninstall.wizard.custom_render.error")
                )
            }
            let items = page["items"] as? [[String: Any]] ?? []
            var explanations = [String]()
            var fields = [Field]()
            for (itemIndex, item) in items.enumerated() {
                let prompt = displayableText(item["desc"])
                let subitems = item["subitems"] as? [[String: Any]] ?? []
                let kind: Field.Kind? = switch item["type"] as? String {
                case "singleselect": .singleChoice
                case "multiselect": .multipleChoice
                default: nil
                }
                guard let kind, !subitems.isEmpty else {
                    if let prompt { explanations.append(prompt) }
                    continue
                }
                let options = subitems.compactMap { subitem -> Option? in
                    guard let key = (subitem["key"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !key.isEmpty else { return nil }
                    return Option(
                        key: key,
                        label: displayableText(subitem["desc"]) ?? key,
                        isDefault: subitem["defaultValue"] as? Bool ?? false
                    )
                }
                guard !options.isEmpty else { continue }
                fields.append(
                    Field(
                        id: "\(index).\(itemIndex)",
                        kind: kind,
                        prompt: prompt,
                        options: options
                    )
                )
            }
            steps.append(
                Step(
                    id: index,
                    title: displayableText(page["step_title"]),
                    explanations: explanations,
                    fields: fields
                )
            )
        }
        let wizard = PackageUninstallWizard(steps: steps)
        return wizard.isEmpty ? nil : wizard
    }

    /// DSM sends some labels as references into its own translation table
    /// ("pkgmgr:uninstall_wizard_page_description") and resolves them in the web client. The
    /// app has no such table, so a reference is dropped rather than read out as-is. The rest
    /// arrives as HTML, whose tags would otherwise be spoken.
    private static func displayableText(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let looksLikeTranslationKey = !text.contains(" ")
            && text.contains(":")
            && !text.contains("://")
        guard !looksLikeTranslationKey else { return nil }
        let stripped = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}
