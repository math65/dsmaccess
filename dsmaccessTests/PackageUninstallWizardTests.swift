import Foundation
import Testing
@testable import dsmaccess

/// Payloads copied from what DSM 7.4 actually served for the packages of the test NAS.
/// A wrong answer on this screen erases package data irreversibly, so the decoding of every
/// shape DSM was seen to send is pinned here.
@MainActor
struct PackageUninstallWizardTests {
    @Test func decodesTheSingleChoiceFFmpegAsks() throws {
        let raw = escaped(
            """
            [{"step_title":"Uninstall package","items":[{"desc":"Keep or delete package \
            settings.","type":"singleselect","subitems":[{"defaultValue":true,"desc":\
            "<b>Uninstall only.</b> Keep existing files.","key":"wizard_keep_data"},\
            {"defaultValue":false,"desc":"Erase all of the package data files.",\
            "key":"wizard_delete_data"}]}]}]
            """
        )

        let wizard = try #require(try PackageUninstallWizard.decode(from: raw))
        let step = try #require(wizard.steps.first)
        #expect(step.title == "Uninstall package")
        let field = try #require(step.fields.first)
        #expect(field.kind == .singleChoice)
        #expect(field.prompt == "Keep or delete package settings.")
        // The label arrives as HTML; its tags must not be read out.
        #expect(field.options.map(\.label) == [
            "Uninstall only. Keep existing files.",
            "Erase all of the package data files.",
        ])
        // DSM expects every key of the group, not only the chosen one.
        #expect(wizard.defaultAnswers == ["wizard_keep_data": true, "wizard_delete_data": false])
    }

    /// Hyper Backup mixes checkboxes with paragraphs that carry no type, and one of its
    /// labels is a reference into DSM's translation table rather than text.
    @Test func keepsExplanationsAndDropsUnresolvedTranslationKeys() throws {
        let raw = escaped(
            """
            [{"step_title":"Uninstall package","items":[\
            {"desc":"pkgmgr:uninstall_wizard_page_description"},\
            {"desc":"All Hyper Backup task settings will be removed."},\
            {"type":"multiselect","subitems":[{"defaultValue":false,"desc":"Remove settings",\
            "key":"pkgwizard_remove_config"}]}]}]
            """
        )

        let wizard = try #require(try PackageUninstallWizard.decode(from: raw))
        let step = try #require(wizard.steps.first)
        #expect(step.explanations == ["All Hyper Backup task settings will be removed."])
        #expect(step.fields.count == 1)
        #expect(step.fields[0].kind == .multipleChoice)
        #expect(wizard.defaultAnswers == ["pkgwizard_remove_config": false])
    }

    /// Plex draws its pages by running a JavaScript function DSM ships. Rendering something
    /// else in its place would be inventing questions the package never asked.
    @Test func refusesPagesDSMDrawsWithItsOwnCode() throws {
        let raw = escaped(
            """
            [{"custom_render_name":"remove_setting","custom_render_fn":"function(){}"}]
            """
        )

        #expect(throws: (any Error).self) {
            try PackageUninstallWizard.decode(from: raw)
        }
    }

    @Test func treatsAPackageWithoutQuestionsAsHavingNone() throws {
        #expect(try PackageUninstallWizard.decode(from: escaped("null")) == nil)
        #expect(try PackageUninstallWizard.decode(from: escaped("[]")) == nil)
        #expect(try PackageUninstallWizard.decode(from: nil) == nil)
    }

    /// DSM serves the whole structure percent-escaped inside the JSON payload.
    private func escaped(_ json: String) -> String {
        json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? json
    }
}
