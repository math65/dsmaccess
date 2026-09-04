import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMErrorMessageTests {
    /// A four-digit code interpolated as an integer came out of the locale's number
    /// formatter as “4 562”: unsearchable, and read aloud as a quantity.
    @Test func writesACodeAsAnIdentifierRatherThanANumber() {
        #expect(4562.errorCodeText == "4562")
    }

    /// DSM repeats its code in the error detail. Naming the item is what the detail is for;
    /// the code itself belongs in the message once.
    @Test func namesTheItemAndStatesTheCodeOnlyOnce() throws {
        let error = DSMError.itemOperationFailed(
            code: 2002,
            item: "/documents/report.pdf",
            itemCode: 2002
        )
        let message = try #require(error.errorDescription)

        #expect(message.contains("/documents/report.pdf"))
        #expect(message.components(separatedBy: "2002").count == 2)
    }

    /// Two genuinely different codes both carry information and are both kept.
    @Test func keepsBothCodesWhenTheyDiffer() throws {
        let error = DSMError.itemOperationFailed(
            code: 1100,
            item: "/documents/:",
            itemCode: 418
        )
        let message = try #require(error.errorDescription)

        #expect(message.contains("1100"))
        #expect(message.contains("418"))
    }
}
