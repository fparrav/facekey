//
//  SettingsWindowView.swift
//  facekey
//
//  Root layout: one `.sidebar` material behind the whole window, a floating
//  sidebar on the leading side and the selected page scrolling beneath a
//  transparent header (traffic lights and, on the Camera and displays page,
//  the refresh action).
//

import AppKit
import SwiftUI

/// A closure `onPreferenceChange` can actually consume — that API requires
/// `Value: Equatable`, which a bare closure can never be. Equality is by
/// identity (a fresh `id` per instance), so this is deliberately never
/// equal to a previous instance.
struct HeaderAction: Equatable {
    private let id = UUID()
    let perform: () -> Void

    static func == (lhs: HeaderAction, rhs: HeaderAction) -> Bool { lhs.id == rhs.id }
}

/// Lets one page (today, only Camera and displays' "Refresh camera list")
/// publish a trailing action into the shared header without the header
/// needing to know that page's state. Switching away resolves back to
/// `defaultValue`.
struct HeaderTrailingActionKey: PreferenceKey {
    static var defaultValue: HeaderAction? { nil }
    static func reduce(value: inout HeaderAction?, nextValue: () -> HeaderAction?) {
        value = nextValue() ?? value
    }
}

struct SettingsWindowView: View {
    let environment: AppEnvironment
    @State private var selection: SettingsPage = SettingsPage.defaultPage
    @State private var headerTrailingAction: HeaderAction?
    @Environment(\.dismissWindow) private var dismissWindow

    /// Defense-in-depth, not the primary gate: Settings is `.suppressed` at
    /// launch and `AppDelegate.revealSettingsWindow()` refuses to open it
    /// while onboarding is incomplete. A real user should never hit this
    /// branch, only a blank frame before `dismissWindow` closes it.
    var body: some View {
        if FacekeySettings.shared.hasCompletedOnboarding {
            settingsContent
        } else {
            Color.clear
                .onAppear { dismissWindow(id: "settings") }
        }
    }

    private var settingsContent: some View {
        ZStack {
            VisualEffectView()
            SettingsMetrics.windowTintColor
            HStack(spacing: 0) {
                SettingsSidebar(
                    selection: $selection,
                    pages: SettingsPage.visiblePages(includingLab: environment.isDebugSectionRevealed),
                    pocController: environment.pocController
                )
                .padding(.leading, SettingsMetrics.sidebarInset)
                .padding(.top, SettingsMetrics.headerHeight)
                .padding(.bottom, SettingsMetrics.sidebarInset)

                contentPage
            }
        }
        // No `.clipShape`, manual stroke, or `.shadow` on the outer window —
        // deliberately: the window keeps its native background (see
        // WindowConfiguringView), so AppKit masks it to the real macOS
        // corner and draws its own edge highlight and shadow for free.
        //
        // Fills whatever size the window is (set once by
        // WindowConfiguringView) — a fixed size here combined with
        // content-size resizability made SwiftUI keep re-adding a titlebar
        // band to the window height.
        //
        // The width floor lives here, not only on `NSWindow.minSize`: SwiftUI rewrites the window's minimum from the root
        // view's own constraints, so a frame without `minWidth` let the window shrink until Spanish text wrapped mid-word.
        .frame(minWidth: SettingsMetrics.windowSize.width, maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(WindowConfigurator())
        // Cascades to every native control so nothing falls back to the
        // system accent. Only takes effect because the window can become
        // key; see WindowConfiguringView.configure.
        .tint(FacekeyTheme.accent)
        // `Window` is a singleton scene — closing it only orders the
        // NSWindow out, keeping `@State` alive, so without this `selection`
        // would remember the last page instead of resetting to Summary.
        .onDisappear { selection = SettingsPage.defaultPage }
        // The Face Lab entry is hidden again on relaunch only, so if the
        // selected page ever stops being visible, fall back to Summary.
        .onChange(of: environment.isDebugSectionRevealed) { _, isRevealed in
            if !isRevealed, selection == .faceLab {
                selection = SettingsPage.defaultPage
            }
        }
    }

    /// The header floats over the scroll content as an overlay so scrolled
    /// rows pass underneath it rather than being pushed aside.
    private var contentPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            pageBody
                .padding(.horizontal, SettingsMetrics.contentHorizontalPadding)
                .padding(.top, SettingsMetrics.headerHeight + 4)
                .padding(.bottom, SettingsMetrics.pageBottomInset)
                // Without an explicit top alignment the scroll view
                // centers short pages vertically, leaving a large gap
                // between the header and the first row.
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        // A new scroll view per page, so each page opens at its top instead of
        // inheriting the offset the previous page was scrolled to.
        .id(selection)
        .overlay(alignment: .top) {
            // Blur first, header content on top — so it fades whatever
            // scrolls beneath both without ever softening the buttons
            // themselves.
            ZStack(alignment: .top) {
                ProgressiveHeaderBlur(height: SettingsMetrics.headerBlurHeight)
                header
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(HeaderTrailingActionKey.self) { headerTrailingAction = $0 }
    }

    /// Leading side stays empty — the window's real traffic lights are drawn
    /// there by AppKit (see WindowConfiguringView). No background of its
    /// own; `ProgressiveHeaderBlur` sits behind it in `contentPage`.
    private var header: some View {
        HStack(spacing: 8) {
            Spacer()

            if let headerTrailingAction {
                Button(action: headerTrailingAction.perform) {
                    Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                        .frame(width: SettingsMetrics.headerButtonHeight, height: SettingsMetrics.headerButtonHeight)
                        .background(Circle().fill(SettingsMetrics.rowColor))
                        .overlay(
                            Circle()
                                .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh camera list")
            }
        }
        .padding(.horizontal, SettingsMetrics.contentHorizontalPadding)
        .frame(height: SettingsMetrics.headerHeight)
    }

    @ViewBuilder
    private var pageBody: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            switch selection {
            case .summary:
                SummarySettingsPage(environment: environment) { page in
                    withAnimation(SettingsMetrics.tabSelectionAnimation) {
                        selection = page
                    }
                }
            case .access:
                AccessSettingsPage(environment: environment)
            case .security:
                SecuritySettingsPage(environment: environment)
            case .devices:
                DevicesSettingsPage(environment: environment)
            case .app:
                AppSettingsPage(environment: environment)
            case .faceLab:
                LazyFaceLabPage()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Face Lab is deliberately hidden behind a debug gesture, so keeping its
/// Core ML pipeline alive for the app's entire background lifetime wastes a
/// substantial amount of memory. Create it only when that page is selected and
/// release it again as soon as the user leaves.
private struct LazyFaceLabPage: View {
    @State private var controller: FaceLabController?

    var body: some View {
        Group {
            if let controller {
                FaceLabView(controller: controller)
            } else {
                ProgressView("Loading Face Lab…")
                    .frame(maxWidth: .infinity, minHeight: SettingsMetrics.emptyStateMinHeight)
                    .task {
                        // Yield once so the loading state can draw before Core ML
                        // initializes its model and Neural Engine resources.
                        await Task.yield()
                        guard !Task.isCancelled, controller == nil else { return }
                        controller = FaceLabController()
                    }
            }
        }
        .onDisappear {
            controller?.stop()
            controller = nil
        }
    }
}
