//
//  USBCopyScheduleFields.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyScheduleFields: View {
    @Binding var trigger: USBCopyTrigger
    var showsRunWhenPlugIn = true
    var showsSchedule = true

    var body: some View {
        if showsRunWhenPlugIn {
            Toggle("Exécuter la tâche à la connexion du périphérique", isOn: $trigger.runWhenPlugIn)
                .help("Démarrer automatiquement cette tâche lorsque son périphérique USB est connecté")
        }
        Toggle("Éjecter le périphérique à la fin de la tâche", isOn: $trigger.ejectWhenTaskDone)
            .help("Éjecter le périphérique USB après la fin de la copie")
        if showsSchedule {
            Toggle("Activer la planification", isOn: $trigger.scheduleEnabled)
                .help("Exécuter aussi cette tâche selon un horaire")
        }

        if showsSchedule && trigger.scheduleEnabled {
            GroupBox("Jours d’exécution") {
                VStack(alignment: .leading) {
                    ForEach(USBCopyWeekday.allCases) { weekday in
                        Toggle(weekday.localizedName, isOn: weekdayBinding(weekday.rawValue))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LabeledContent("Date de référence") {
                TextField("AAAA/MM/JJ", text: $trigger.scheduleContent.date)
                    .frame(minWidth: 140)
                    .help("Date au format année, mois et jour, séparés par des barres obliques")
            }

            Stepper(value: $trigger.scheduleContent.hour, in: 0...23) {
                Text("Heure de début : \(trigger.scheduleContent.hour.formatted(.number.precision(.integerLength(2)))) h")
            }
            Stepper(value: $trigger.scheduleContent.minute, in: 0...59) {
                Text("Minute de début : \(trigger.scheduleContent.minute.formatted(.number.precision(.integerLength(2))))")
            }
            Stepper(value: $trigger.scheduleContent.repeatDate, in: 0...365) {
                Text("Répétition en jours : \(trigger.scheduleContent.repeatDate)")
            }
            Stepper(value: $trigger.scheduleContent.repeatHour, in: 0...23) {
                Text("Répétition en heures : \(trigger.scheduleContent.repeatHour)")
            }
            Stepper(value: $trigger.scheduleContent.lastWorkHour, in: 0...23) {
                Text("Dernière heure d’exécution : \(trigger.scheduleContent.lastWorkHour)")
            }
        }
    }

    private func weekdayBinding(_ value: Int) -> Binding<Bool> {
        Binding(
            get: { selectedWeekdays.contains(value) },
            set: { isSelected in
                var weekdays = selectedWeekdays
                if isSelected {
                    weekdays.insert(value)
                } else {
                    weekdays.remove(value)
                }
                trigger.scheduleContent.weekDay = weekdays.sorted().map(String.init).joined(separator: ",")
            }
        )
    }

    private var selectedWeekdays: Set<Int> {
        Set(trigger.scheduleContent.weekDay.split(separator: ",").compactMap { Int($0) })
    }
}

private enum USBCopyWeekday: Int, CaseIterable, Identifiable {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Self { self }

    var localizedName: LocalizedStringKey {
        switch self {
        case .sunday: "Dimanche"
        case .monday: "Lundi"
        case .tuesday: "Mardi"
        case .wednesday: "Mercredi"
        case .thursday: "Jeudi"
        case .friday: "Vendredi"
        case .saturday: "Samedi"
        }
    }
}
