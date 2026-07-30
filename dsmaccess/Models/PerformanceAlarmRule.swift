//
//  PerformanceAlarmRule.swift
//  dsmaccess
//
//  Règles de l'alarme des performances (SYNO.ResourceMonitor.EventRule). Une règle dit à quel
//  seuil le NAS doit consigner une alerte dans son historique : sans règle, ce journal reste
//  vide quoi qu'il arrive.
//
//  Contrat éprouvé sur DSM 7.4 le 30/07/2026, en créant puis supprimant de vraies règles.
//  Quatre particularités, dont trois que le client web de DSM laissait mal deviner :
//  — L'identifiant est une **chaîne composite** que le NAS fabrique :
//    « type_service_ressource_gravité ». Modifier l'un de ces champs change donc l'identité de
//    la règle, et deux règles qui partagent ce quadruplet entrent en collision (erreur 6106).
//  — La cible part dans un **paramètre unique, `service`**, quel que soit le type.
//  — `type` et `resource` sont des **entiers**, et le sens d'un code de ressource dépend du
//    type : `4` est la mémoire en pourcentage pour le système, en mégaoctets pour un service.
//  — `severity` ne connaît que deux valeurs, là où le journal en affiche trois.
//

import Foundation

struct PerformanceAlarmRule: nonisolated Decodable, Sendable, Identifiable {
    /// Chaîne composée par le NAS : « type_service_ressource_gravité ».
    let id: String
    let isEnabled: Bool
    let severity: Severity
    let kind: Kind
    let resource: Resource
    let threshold: Int
    /// Cible telle que le NAS l'a reçue : nom d'unité d'un service, chemin de volume, ou la
    /// constante « general » d'une règle système.
    let target: String
    /// Libellé que le NAS attache à la cible. Souvent lisible, parfois une clé de son propre
    /// catalogue — voir `displayTarget`.
    let targetLabel: String?

    /// Ce que la règle surveille. Le NAS envoie un entier ; une valeur inattendue serait une
    /// évolution de DSM et reste lisible plutôt que rejetée.
    enum Kind: Int, nonisolated Sendable, CaseIterable, Identifiable {
        case system = 0
        case service = 1
        case iSCSI = 2
        case volume = 3
        case internalUse = 4

        var id: Int { rawValue }

        /// Types que l'app sait composer. iSCSI et l'usage interne restent lisibles et
        /// supprimables, mais ne sont pas proposés à la création : le premier n'a pas pu être
        /// éprouvé faute de LUN, le second est réservé à Synology.
        static let editable: [Kind] = [.system, .service, .volume]

        var isEditable: Bool { Self.editable.contains(self) }

        /// Valeur que le NAS attend en cible pour les types qui n'en font pas choisir une.
        /// Vérifié : une règle système enregistrée porte bien « general ».
        var fixedTarget: String? {
            switch self {
            case .system: "general"
            case .internalUse: "internal_use"
            case .service, .iSCSI, .volume: nil
            }
        }
    }

    enum Severity: Int, nonisolated Sendable, CaseIterable, Identifiable {
        case warning = 0
        case critical = 1

        var id: Int { rawValue }
    }

    /// Grandeur surveillée. Le même code ne désigne pas la même chose d'un type à l'autre :
    /// il ne prend son sens qu'associé au type de la règle.
    enum Resource: Int, nonisolated Sendable {
        case processorUsage = 0
        case loadAverageOneMinute = 1
        case loadAverageFiveMinutes = 2
        case loadAverageFifteenMinutes = 3
        case memory = 4
        case diskActivity = 5
        case networkLatency = 6
        case ioLatency = 7
        case rootPartition = 8
        case temporaryDirectory = 9
        case coredumpCount = 10
        case graphicsUsage = 11
    }

    /// Unité affichée à côté du seuil. DSM la tire du couple type / ressource et ne la laisse
    /// jamais saisir.
    enum Unit: nonisolated Sendable {
        case percent
        case megabytes
        case megabytesPerSecond
        case milliseconds
        /// Une charge moyenne ou un décompte n'ont pas d'unité.
        case none
    }

    /// Une grandeur surveillable, avec ce que DSM accepte comme seuil. Les bornes viennent du
    /// client web : un seuil hors bornes est refusé par le NAS.
    struct Measure: nonisolated Sendable, Identifiable {
        let resource: Resource
        let unit: Unit
        let defaultThreshold: Int
        let range: ClosedRange<Int>

        var id: Int { resource.rawValue }
    }

    /// Grandeurs proposées pour un type, dans l'ordre où DSM les présente. Le GPU n'est
    /// proposé que sur un NAS qui en a un ; il n'apparaît donc pas ici, faute d'avoir pu
    /// vérifier le drapeau `support_nvidia_gpu` sur un modèle concerné.
    static func measures(for kind: Kind) -> [Measure] {
        switch kind {
        case .system:
            [
                Measure(resource: .processorUsage, unit: .percent, defaultThreshold: 80, range: 60...99),
                Measure(resource: .loadAverageOneMinute, unit: .none, defaultThreshold: 10, range: 1...1000),
                Measure(resource: .loadAverageFiveMinutes, unit: .none, defaultThreshold: 10, range: 1...1000),
                Measure(resource: .loadAverageFifteenMinutes, unit: .none, defaultThreshold: 10, range: 1...1000),
                Measure(resource: .memory, unit: .percent, defaultThreshold: 80, range: 1...99),
            ]
        case .service:
            [
                Measure(resource: .processorUsage, unit: .percent, defaultThreshold: 80, range: 60...99),
                Measure(resource: .memory, unit: .megabytes, defaultThreshold: 10, range: 1...524_288),
                Measure(resource: .diskActivity, unit: .megabytesPerSecond, defaultThreshold: 10, range: 1...65_536),
            ]
        case .volume:
            [Measure(resource: .diskActivity, unit: .percent, defaultThreshold: 80, range: 1...99)]
        case .iSCSI:
            [
                Measure(resource: .networkLatency, unit: .milliseconds, defaultThreshold: 100, range: 10...60_000),
                Measure(resource: .ioLatency, unit: .milliseconds, defaultThreshold: 100, range: 10...60_000),
            ]
        case .internalUse:
            [
                Measure(resource: .rootPartition, unit: .percent, defaultThreshold: 80, range: 1...99),
                Measure(resource: .temporaryDirectory, unit: .percent, defaultThreshold: 80, range: 1...99),
                Measure(resource: .coredumpCount, unit: .none, defaultThreshold: 0, range: 0...99),
            ]
        }
    }

    /// La grandeur telle que DSM la décrit pour ce couple, ou `nil` si le NAS a envoyé une
    /// combinaison que le client web ne propose pas.
    var measure: Measure? {
        Self.measures(for: kind).first { $0.resource == resource }
    }

    /// Cible telle qu'elle mérite d'être lue. Le NAS renvoie tantôt un libellé (« SNMP »),
    /// tantôt une clé de son propre catalogue (« firewall:firewall_service_opt_ssh ») que son
    /// client web résout et que nous ne pouvons pas résoudre ; le nom d'unité, lui, reste
    /// toujours parlant. Une règle système n'a pas de cible : « general » est une constante de
    /// DSM, pas quelque chose que l'utilisateur reconnaîtrait.
    var displayTarget: String? {
        guard kind != .system, kind != .internalUse else { return nil }
        if let targetLabel, !targetLabel.isEmpty, !targetLabel.contains(":") {
            return targetLabel
        }
        // Le nom d'unité systemd porte un suffixe qui n'apprend rien à la lecture :
        // « sshd.slice » se lit « sshd ».
        let unit = target.hasSuffix(Self.sliceSuffix)
            ? String(target.dropLast(Self.sliceSuffix.count))
            : target
        return ProcessGroup.readable(unit)
    }

    private static let sliceSuffix = ".slice"

    /// Clés de tri non optionnelles : une valeur absente se range en tête plutôt que
    /// d'empêcher le tri de sa colonne.
    var sortableTarget: String { displayTarget ?? "" }
    var sortableKind: Int { kind.rawValue }
    var sortableSeverity: Int { severity.rawValue }
    /// Trié comme un nombre : `Bool` n'est pas `Comparable`.
    var sortableEnabled: Int { isEnabled ? 1 : 0 }

    enum CodingKeys: String, CodingKey {
        case id, enable, severity, name, service, resource, threshold, type
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Sans identifiant, la règle ne peut être ni basculée ni supprimée : mieux vaut que le
        // décodage échoue que d'afficher une ligne sur laquelle aucune action ne marchera.
        id = try c.requiredFlexString(.id)
        isEnabled = c.flexBool(.enable) ?? false
        severity = Severity(rawValue: c.flexInt(.severity) ?? 0) ?? .warning
        kind = Kind(rawValue: c.flexInt(.type) ?? 0) ?? .system
        resource = Resource(rawValue: c.flexInt(.resource) ?? 0) ?? .processorUsage
        threshold = c.flexInt(.threshold) ?? 0
        target = c.flexString(.service) ?? ""
        targetLabel = c.flexString(.name)
    }
}

struct PerformanceAlarmRulePage: nonisolated Decodable, Sendable {
    let rules: [PerformanceAlarmRule]
    let total: Int?
    /// Le NAS autorise les règles d'usage interne, réservées à Synology.
    let supportsInternalUse: Bool

    enum CodingKeys: String, CodingKey {
        case rules, total
        case supportsInternalUse = "support_internal"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([PerformanceAlarmRule].self, forKey: .rules) ?? []
        total = c.flexInt(.total)
        supportsInternalUse = c.flexBool(.supportsInternalUse) ?? false
    }
}

/// Ce que `set` envoie pour créer ou modifier une règle. Sans `id`, DSM crée ; avec, il
/// remplace. `enable` part dans les deux cas : vérifié, le NAS le réclame aussi en
/// modification, contrairement à ce que laisse croire son propre formulaire.
struct PerformanceAlarmRuleDraft: nonisolated Sendable, Equatable {
    /// Identifiant de la règle modifiée, `nil` pour une création.
    var ruleID: String?
    var kind: PerformanceAlarmRule.Kind
    var resource: PerformanceAlarmRule.Resource
    var threshold: Int
    var severity: PerformanceAlarmRule.Severity
    var isEnabled: Bool
    /// Service ou volume choisi. Vide pour un type dont DSM fixe lui-même la valeur.
    var target: String

    var isCreation: Bool { ruleID == nil }

    /// La cible telle que `set` l'attend : la constante du type quand il en impose une.
    var resolvedTarget: String { kind.fixedTarget ?? target }

    init(
        ruleID: String? = nil,
        kind: PerformanceAlarmRule.Kind = .system,
        resource: PerformanceAlarmRule.Resource = .processorUsage,
        threshold: Int = 80,
        severity: PerformanceAlarmRule.Severity = .warning,
        isEnabled: Bool = true,
        target: String = ""
    ) {
        self.ruleID = ruleID
        self.kind = kind
        self.resource = resource
        self.threshold = threshold
        self.severity = severity
        self.isEnabled = isEnabled
        self.target = target
    }

    /// Reprend une règle existante pour la modifier.
    init(editing rule: PerformanceAlarmRule) {
        self.init(
            ruleID: rule.id,
            kind: rule.kind,
            resource: rule.resource,
            threshold: rule.threshold,
            severity: rule.severity,
            isEnabled: rule.isEnabled,
            target: rule.target
        )
    }
}
