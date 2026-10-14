//
//  OnboardingNotchView.swift
//  facekey
//
//  Routes `controller.step` to its screen and applies the scroll-with-blur transition
//  between them: Next travels upward, Back is the mirror, travelling downward.
//

import SwiftUI

struct OnboardingNotchView: View {
    let controller: OnboardingController

    var body: some View {
        ZStack {
            switch controller.step {
            case .intro:
                IntroStepView(controller: controller)
            case .permissions:
                PermissionsStepView(controller: controller)
            case .securityNotice:
                SecurityNoticeStepView(controller: controller)
            case .preSetup:
                PreSetupStepView(controller: controller)
            case .selectCamera:
                SelectCameraStepView(controller: controller)
            case .enroll:
                EnrollStepView(controller: controller)
            case .name:
                NameStepView(controller: controller)
            case .password:
                PasswordStepView(controller: controller)
            case .complete:
                CompleteStepView(detail: controller.completionDetail)
            }
        }
        .id(controller.step)
        .frame(width: controller.panelSize.width, height: controller.panelSize.height)
        .transition(stepTransition)
        .overlay(alignment: .topTrailing) {
            if controller.showsQuitControl {
                QuitControl(action: controller.quit)
            }
        }
    }

    private var stepTransition: AnyTransition {
        let travel = controller.panelSize.height
        let insertionOffset: CGFloat = controller.navDirection == .forward ? travel : -travel
        let removalOffset: CGFloat = controller.navDirection == .forward ? -travel : travel
        return .asymmetric(
            insertion: .modifier(
                active: OffsetBlurOpacity(offset: insertionOffset, blur: 12, opacity: 0),
                identity: OffsetBlurOpacity(offset: 0, blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: OffsetBlurOpacity(offset: removalOffset, blur: 12, opacity: 0),
                identity: OffsetBlurOpacity(offset: 0, blur: 0, opacity: 1)
            )
        )
    }
}

/// Backing modifier for the scroll+blur transition — offsets, blurs, and fades at once
/// so content reads as scrolling past with a dissolve rather than a hard cut.
private struct OffsetBlurOpacity: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// Small close control that quits first-run setup; the app has no Dock icon or menu bar item until onboarding finishes.
private struct QuitControl: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.5))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(isHovering ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .padding(6)
        .help("Quit Facekey")
        .accessibilityLabel("Quit Facekey")
    }
}
