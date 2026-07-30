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
            Toggle("usb_copy.schedule.run_on_connect", isOn: $trigger.runWhenPlugIn)
                .help("usb_copy.schedule.run_on_connect.description")
        }
        Toggle("usb_copy.schedule.eject.label", isOn: $trigger.ejectWhenTaskDone)
            .help("usb_copy.schedule.eject.description")
        if showsSchedule {
            Toggle("usb_copy.schedule.enable", isOn: $trigger.scheduleEnabled)
                .help("usb_copy.schedule.enable.label")
        }

        if showsSchedule && trigger.scheduleEnabled {
            GroupBox("usb_copy.schedule.run_days") {
                VStack(alignment: .leading) {
                    ForEach(USBCopyWeekday.allCases) { weekday in
                        Toggle(weekday.localizedName, isOn: weekdayBinding(weekday.rawValue))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LabeledContent("usb_copy.schedule.reference_date") {
                TextField("usb_copy.schedule.reference_date.placeholder", text: $trigger.scheduleContent.date)
                    .frame(minWidth: 140)
                    .help("usb_copy.schedule.date.hint")
            }

            Stepper(value: $trigger.scheduleContent.hour, in: 0...23) {
                Text(String(localized: "usb_copy.schedule.start_hour", defaultValue: "Start hour: \(trigger.scheduleContent.hour.formatted(.number.precision(.integerLength(2))))"))
            }
            Stepper(value: $trigger.scheduleContent.minute, in: 0...59) {
                Text(String(localized: "usb_copy.schedule.start_minute", defaultValue: "Start minute: \(trigger.scheduleContent.minute.formatted(.number.precision(.integerLength(2))))"))
            }
            Stepper(value: $trigger.scheduleContent.repeatDate, in: 0...365) {
                Text(String(localized: "usb_copy.schedule.repeat_days", defaultValue: "Repeat interval in days: \(trigger.scheduleContent.repeatDate)"))
            }
            Stepper(value: $trigger.scheduleContent.repeatHour, in: 0...23) {
                Text(String(localized: "usb_copy.schedule.repeat_hours", defaultValue: "Repeat interval in hours: \(trigger.scheduleContent.repeatHour)"))
            }
            Stepper(value: $trigger.scheduleContent.lastWorkHour, in: 0...23) {
                Text(String(localized: "usb_copy.schedule.last_run_hour", defaultValue: "Last run hour: \(trigger.scheduleContent.lastWorkHour)"))
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
        case .sunday: "usb_copy.schedule.sunday"
        case .monday: "usb_copy.schedule.monday"
        case .tuesday: "usb_copy.schedule.tuesday"
        case .wednesday: "usb_copy.schedule.wednesday"
        case .thursday: "usb_copy.schedule.thursday"
        case .friday: "usb_copy.schedule.friday"
        case .saturday: "usb_copy.schedule.saturday"
        }
    }
}
