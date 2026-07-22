//
//  USBCopyFilter.swift
//  dsmaccess
//
//  Filtres de fichiers de USB Copy et conversion vers une sélection modifiable.
//

import Foundation

struct USBCopyFileRules: nonisolated Codable, Equatable, Sendable {
    var extensions: [String]
    var names: [String]
}

struct USBCopyFilter: nonisolated Codable, Equatable, Sendable {
    var whiteList: USBCopyFileRules
    var blackList: USBCopyFileRules
    var customizedList: USBCopyFileRules

    enum CodingKeys: String, CodingKey {
        case whiteList = "white_list"
        case blackList = "black_list"
        case customizedList = "customized_list"
    }

    static func defaultValue(for type: USBCopyTaskType) -> Self {
        let selected: Set<String>
        let includesOtherFiles: Bool
        switch type {
        case .importPhoto:
            selected = USBCopyFileCategory.image.extensions
                .union(USBCopyFileCategory.video.extensions)
            includesOtherFiles = false
        case .importGeneral, .exportGeneral:
            selected = USBCopyFileCategory.allBuiltInExtensions
            includesOtherFiles = true
        }
        return USBCopyFilterSelection(
            selectedExtensions: selected,
            includesOtherFiles: includesOtherFiles,
            customExtensions: [],
            customNames: []
        ).filter
    }
}

struct USBCopyFilterResult: nonisolated Decodable, Sendable {
    let taskFilter: USBCopyFilter

    private enum CodingKeys: String, CodingKey {
        case taskFilter = "task_filter"
    }
}

enum USBCopyFileCategory: String, CaseIterable, Identifiable, Sendable {
    case audio
    case video
    case image
    case document

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .audio: String(localized: "Audio")
        case .video: String(localized: "Vidéo")
        case .image: String(localized: "Image")
        case .document: String(localized: "Document")
        }
    }

    var extensions: Set<String> {
        switch self {
        case .audio:
            ["aac", "aif", "aifc", "aiff", "ape", "au", "cdda", "dff", "dsf", "eaac", "flac", "kar", "l16", "m3u", "m4a", "m4b", "m4p", "mid", "midi", "mp1", "mp2", "mp3", "mpc", "mpga", "ogg", "pcm", "pls", "ra", "ram", "snd", "tta", "vqf", "wav", "wma"]
        case .video:
            ["3g2", "3gp", "aaf", "amr", "ani", "asf", "asx", "avi", "dat", "dif", "divx", "dv", "dvr-ms", "f4v", "flv", "ifo", "m1v", "m2t", "m2ts", "m2v", "m4u", "m4v", "mkv", "mov", "movie", "mp4", "mpe", "mpeg", "mpeg1", "mpeg2", "mpeg4", "mpg", "mts", "mxf", "mxu", "ogm", "ogv", "qt", "qtx", "rec", "rm", "rmvb", "swf", "tp", "trp", "ts", "vob", "webm", "wmv", "wmv9", "wmx", "xvid"]
        case .image:
            ["3fr", "ari", "arw", "bay", "bmp", "cap", "cgm", "cr2", "crw", "dcr", "dcs", "djv", "djvu", "dng", "drf", "eip", "erf", "fff", "gif", "ico", "ief", "iff", "iiq", "ilbm", "jp2", "jpe", "jpeg", "jpg", "k25", "kdc", "lbm", "mac", "mef", "mng", "mos", "mrw", "nef", "nrw", "obm", "orf", "pbm", "pct", "pcx", "pef", "pgm", "pic", "pict", "png", "pnm", "pnt", "pntg", "ppm", "psd", "ptx", "pxn", "qti", "qtif", "r3d", "raf", "ras", "raw", "rgb", "rw2", "rwl", "rwz", "sr2", "srf", "srw", "svg", "tga", "tif", "tiff", "ufo", "wbmp", "x3f", "xbm", "xpm", "xwd"]
        case .document:
            ["doc", "docx", "epub", "htm", "html", "key", "mobi", "numbers", "odp", "ods", "odt", "pages", "pdf", "pps", "ppsx", "ppt", "pptx", "prc", "txt", "xls", "xlsx"]
        }
    }

    static var allBuiltInExtensions: Set<String> {
        allCases.reduce(into: Set<String>()) { $0.formUnion($1.extensions) }
    }
}

struct USBCopyFilterSelection: Equatable, Sendable {
    var selectedExtensions: Set<String>
    var includesOtherFiles: Bool
    var customExtensions: [String]
    var customNames: [String]
    private var unmanagedWhiteExtensions: Set<String>
    private var unmanagedWhiteNames: Set<String>
    private var unmanagedBlackExtensions: Set<String>
    private var unmanagedBlackNames: Set<String>

    init(
        selectedExtensions: Set<String>,
        includesOtherFiles: Bool,
        customExtensions: [String],
        customNames: [String]
    ) {
        self.selectedExtensions = selectedExtensions
        self.includesOtherFiles = includesOtherFiles
        self.customExtensions = customExtensions
        self.customNames = customNames
        unmanagedWhiteExtensions = []
        unmanagedWhiteNames = []
        unmanagedBlackExtensions = []
        unmanagedBlackNames = []
    }

    init(filter: USBCopyFilter) {
        let builtInExtensions = USBCopyFileCategory.allBuiltInExtensions
        includesOtherFiles = filter.whiteList.extensions.contains("*")
        if includesOtherFiles {
            selectedExtensions = builtInExtensions
                .subtracting(filter.blackList.extensions)
        } else {
            selectedExtensions = Set(filter.whiteList.extensions)
                .intersection(builtInExtensions)
        }
        customExtensions = filter.customizedList.extensions
        customNames = filter.customizedList.names
        unmanagedWhiteExtensions = Set(filter.whiteList.extensions)
            .subtracting(builtInExtensions)
            .subtracting(["*"])
            .subtracting(customExtensions)
        unmanagedWhiteNames = Set(filter.whiteList.names)
            .subtracting(["*"])
            .subtracting(customNames)
        unmanagedBlackExtensions = Set(filter.blackList.extensions)
            .subtracting(builtInExtensions)
        unmanagedBlackNames = Set(filter.blackList.names)
            .subtracting([".SynologyUSBCopy.config"])
    }

    var filter: USBCopyFilter {
        var whiteExtensions = unmanagedWhiteExtensions
        var whiteNames = unmanagedWhiteNames
        var blackExtensions = unmanagedBlackExtensions
        var blackNames = unmanagedBlackNames
        if includesOtherFiles {
            whiteExtensions.insert("*")
            whiteNames.insert("*")
            blackExtensions.formUnion(
                USBCopyFileCategory.allBuiltInExtensions.subtracting(selectedExtensions)
            )
        } else {
            whiteExtensions.formUnion(selectedExtensions)
        }
        whiteExtensions.formUnion(customExtensions)
        whiteNames.formUnion(customNames)
        blackNames.insert(".SynologyUSBCopy.config")
        return USBCopyFilter(
            whiteList: USBCopyFileRules(
                extensions: whiteExtensions.sorted(),
                names: whiteNames.sorted()
            ),
            blackList: USBCopyFileRules(
                extensions: blackExtensions.sorted(),
                names: blackNames.sorted()
            ),
            customizedList: USBCopyFileRules(
                extensions: customExtensions,
                names: customNames
            )
        )
    }
}
