//
//  SudoAuditSection.swift
//  facekey
//
//  The history of sudo requests Facekey handled, with a clear button and the
//  switch that keeps command arguments out of it.
//

import SwiftUI

struct SudoAuditSection: View {
    let model: SudoAuditListModel
    let settings: SudoApprovalSettings

    /// The newest entries only; the log itself keeps more.
    private static let visibleCount = 30
    /// What shows before "Show more", so the page does not grow with the history.
    private static let collapsedCount = 5
    /// The expanded list scrolls inside this height instead of lengthening the page.
    private static let expandedMaxHeight: CGFloat = 260

    @State private var entries: [SudoAuditEntry] = []
    @State private var storesExecutableOnly = false
    @State private var errorMessage: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsSectionTitle(text: "History")
                .padding(.bottom, -4)

            SettingsGroup {
                SettingsRowContent(
                    title: "Keep only the program name",
                    subtitle: "Leaves the arguments of each command out of the history."
                ) {
                    FacekeyToggle(isOn: Binding(
                        get: { storesExecutableOnly },
                        set: { newValue in
                            storesExecutableOnly = newValue
                            settings.storesExecutableOnly = newValue
                        }
                    ))
                }

                SettingsGroupDivider()

                SettingsRowContent(title: "Clear history") {
                    HoldToConfirmButton(title: "Clear", action: clear)
                }
            }

            if entries.isEmpty {
                SettingsCaption(text: "Nothing here yet.")
            } else {
                SettingsGroup {
                    if isExpanded {
                        ScrollView {
                            rows(Array(entries.prefix(Self.visibleCount)))
                        }
                        .frame(maxHeight: Self.expandedMaxHeight)
                    } else {
                        rows(Array(entries.prefix(Self.collapsedCount)))
                    }

                    if entries.count > Self.collapsedCount {
                        SettingsGroupDivider()
                        Button {
                            withAnimation(SettingsMetrics.stateTransitionAnimation) { isExpanded.toggle() }
                        } label: {
                            Text(isExpanded ? "Show less" : "Show more")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(FacekeyTheme.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: SettingsMetrics.rowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let errorMessage {
                SettingsCaption(text: LocalizedStringKey.verbatim(errorMessage))
            }
        }
        .onAppear(perform: reload)
    }

    private func rows(_ shown: [SudoAuditEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(shown) { entry in
                if entry.id != shown.first?.id {
                    SettingsGroupDivider()
                }
                row(for: entry)
            }
        }
    }

    private func row(for entry: SudoAuditEntry) -> some View {
        let when = entry.time.formatted(date: .abbreviated, time: .shortened)
        let detail = [when, entry.displaySetup, entry.command].filter { !$0.isEmpty }.joined(separator: " · ")
        return SettingsRowContent(
            title: LocalizedStringKey.verbatim(entry.appName),
            subtitle: LocalizedStringKey.verbatim(detail)
        ) {
            Text(entry.outcome.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entry.outcome == .approved ? SettingsMetrics.textPrimary : SettingsMetrics.textSecondary)
        }
    }

    private func clear() {
        do {
            try model.clear()
            errorMessage = nil
        } catch {
            errorMessage = sudoErrorMessage(error)
        }
        reload()
    }

    private func reload() {
        storesExecutableOnly = settings.storesExecutableOnly
        do {
            entries = try model.entries()
        } catch {
            entries = []
            errorMessage = sudoErrorMessage(error)
        }
    }
}

private extension SudoAuditOutcome {
    var title: String {
        switch self {
        case .approved: return String(localized: "Approved")
        case .cancelled: return String(localized: "Cancelled")
        case .timedOut: return String(localized: "Timed out")
        case .notMatched: return String(localized: "Face not matched")
        case .declinedPolicy: return String(localized: "App blocked")
        case .declinedLocked: return String(localized: "Session locked")
        case .declinedUnknown: return String(localized: "Unknown app")
        }
    }
}
