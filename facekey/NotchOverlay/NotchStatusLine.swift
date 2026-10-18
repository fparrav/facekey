import SwiftUI

struct NotchStatusLine: View {
    let message: NotchStatusMessage

    private var toneColor: Color {
        switch message.tone {
        case .accent:
            FacekeyTheme.accent
        case .failure:
            Color(red: 1.0, green: 0.35, blue: 0.37)
        case .warning:
            Color(red: 245 / 255, green: 183 / 255, blue: 59 / 255)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .stroke(toneColor, lineWidth: 2)
                .frame(width: 14, height: 14)
                .fixedSize()

            Text(LocalizedStringKey(message.key))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(message.key)))
    }
}

#Preview {
    VStack(spacing: 12) {
        NotchStatusLine(message: .for(state: .scanning, hoverRetryEnabled: false))
        NotchStatusLine(message: .for(state: .success, hoverRetryEnabled: false))
        NotchStatusLine(message: .for(state: .failure, hoverRetryEnabled: true))
        NotchStatusLine(message: .for(state: .cameraUnavailable, hoverRetryEnabled: false))
        NotchStatusLine(message: .for(state: .sudoApproval, hoverRetryEnabled: false))
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
