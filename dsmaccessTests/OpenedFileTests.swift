import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct OpenedFileTests {
    /// Forme relevée sur le DS920+ en DSM 7.4 le 30/07/2026. Les chemins réels du NAS n'y
    /// figurent pas : seule la forme de la réponse est reprise.
    @Test func readsOpenedFilesAsTheNASSendsThem() throws {
        let payload = Data(#"""
        {"OpenedFiles":[
          {"filename":"journal.log","hidden":0,"host":"-","path":"AppData/service/journal.log",
           "pid":"23037","service":"Service local","user":"-"},
          {"filename":"rapport.docx","hidden":0,"host":"10.0.0.2","path":"Documents/rapport.docx",
           "pid":"14002","service":"SMB","user":"testeur"}],
         "total":2}
        """#.utf8)

        let page = try JSONDecoder().decode(OpenedFilePage.self, from: payload)

        #expect(page.total == 2)
        #expect(page.files.count == 2)
        let network = try #require(page.files.last)
        #expect(network.displayName == "rapport.docx")
        #expect(network.folder == "Documents")
        #expect(network.service == "SMB")
        #expect(network.account == "testeur")
        #expect(network.host == "10.0.0.2")
        #expect(network.processID == "14002")
    }

    /// DSM écrit « - » et non une chaîne vide quand la valeur ne s'applique pas : un service
    /// du NAS lui-même n'a ni compte ni machine d'origine. Affiché tel quel, ce tiret passerait
    /// pour une donnée renvoyée par le NAS.
    @Test func readsADashAsAnAbsentAccountAndHost() throws {
        let payload = Data(#"""
        {"OpenedFiles":[{"filename":"base.db","host":"-","path":"AppData/base.db",
          "pid":"19896","service":"Service local","user":"-"}],"total":1}
        """#.utf8)

        let file = try #require(
            try JSONDecoder().decode(OpenedFilePage.self, from: payload).files.first
        )

        #expect(file.account == nil)
        #expect(file.host == nil)
        // Le reste de la ligne survit : le fichier reste listé avec son service.
        #expect(file.service == "Service local")
        #expect(file.displayName == "base.db")
    }

    /// `path` est relatif au partage et se termine par le nom du fichier. Le dossier en est
    /// déduit pour ne pas répéter le nom dans deux colonnes voisines ; un chemin sans dossier
    /// ne doit pas produire une chaîne vide, qui se lirait comme une valeur.
    @Test func derivesTheFolderWithoutRepeatingTheFileName() throws {
        let payload = Data(#"""
        {"OpenedFiles":[
          {"filename":"a.txt","path":"a.txt","pid":"1","service":"SMB","user":"testeur","host":"10.0.0.2"},
          {"filename":"b.txt","path":"Partage/Sous dossier/b.txt","pid":"2","service":"SMB","user":"testeur","host":"10.0.0.2"}],
         "total":2}
        """#.utf8)

        let files = try JSONDecoder().decode(OpenedFilePage.self, from: payload).files

        #expect(files[0].folder == nil)
        #expect(files[1].folder == "Partage/Sous dossier")
    }

    /// Un même processus tient souvent plusieurs fichiers, et un même chemin peut être ouvert
    /// par plusieurs processus. Sans les deux dans la clé, des lignes distinctes se
    /// confondraient dans le tableau.
    @Test func distinguishesFilesHeldByTheSameProcess() throws {
        let payload = Data(#"""
        {"OpenedFiles":[
          {"filename":"un.log","path":"App/un.log","pid":"19896","service":"S","user":"-","host":"-"},
          {"filename":"deux.log","path":"App/deux.log","pid":"19896","service":"S","user":"-","host":"-"}],
         "total":2}
        """#.utf8)

        let files = try JSONDecoder().decode(OpenedFilePage.self, from: payload).files

        #expect(files[0].id != files[1].id)
    }

    /// Un NAS au repos ne renvoie aucun fichier. L'absence de la clé ne doit pas faire échouer
    /// le décodage : l'écran a un état vide à présenter.
    @Test func survivesAResponseWithoutAnyOpenedFile() throws {
        let page = try JSONDecoder().decode(
            OpenedFilePage.self, from: Data(#"{"total":0}"#.utf8)
        )

        #expect(page.files.isEmpty)
        #expect(page.total == 0)
    }
}
