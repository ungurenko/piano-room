import SwiftUI

struct KeyboardView: View {
    @EnvironmentObject private var state: AppState

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let blackClasses: Set<Int> = [1, 3, 6, 8, 10]
    private static let allNotes: [Int] = Array(21...108)
    private static let whiteNotes: [Int] = allNotes.filter { !blackClasses.contains($0 % 12) }
    private static let blackNotes: [Int] = allNotes.filter { blackClasses.contains($0 % 12) }

    var body: some View {
        GeometryReader { geometry in
            let whiteWidth = geometry.size.width / CGFloat(Self.whiteNotes.count)
            let height = geometry.size.height

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Self.whiteNotes, id: \.self) { note in
                        whiteKey(note: note, width: whiteWidth, height: height)
                    }
                }

                ForEach(Self.blackNotes, id: \.self) { note in
                    blackKey(note: note, width: whiteWidth * 0.58, height: height * 0.60)
                        .offset(x: whiteWidth * CGFloat(Self.whitesBefore(note)) - whiteWidth * 0.29)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.panel.opacity(0.55))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .shadow(color: Theme.shadow, radius: 18, x: 0, y: 9)
    }

    // MARK: - Клавиши

    private func whiteKey(note: Int, width: CGFloat, height: CGFloat) -> some View {
        let isActive = state.runningNotes.contains(UInt8(note))
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: 7,
                bottomTrailingRadius: 7,
                topTrailingRadius: 2,
                style: .continuous
            )
            .fill(
                isActive
                    ? LinearGradient(
                        colors: [Color(hex: 0xFBE2BE), Color(hex: 0xEEC78D)],
                        startPoint: .top, endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [Color(hex: 0xFFFEFB), Color(hex: 0xF2E9DB)],
                        startPoint: .top, endPoint: .bottom
                    )
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(hex: 0xE6DCCD))
                    .frame(height: 1)
            }

            if note % 12 == 0 {
                Text("C\(note / 12 - 1)")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Theme.mutedSoft)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
        }
        .shadow(color: Theme.shadowSoft, radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                state.noteFromScreen(
                    UInt8(note),
                    velocity: Self.velocity(atY: value.location.y, height: height)
                )
            }
        )
        .animation(.easeOut(duration: 0.08), value: isActive)
    }

    private func blackKey(note: Int, width: CGFloat, height: CGFloat) -> some View {
        let isActive = state.runningNotes.contains(UInt8(note))
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                isActive
                    ? LinearGradient(
                        colors: [Color(hex: 0xC88A50), Color(hex: 0xA86A35)],
                        startPoint: .top, endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [Color(hex: 0x4C4239), Color(hex: 0x241E19)],
                        startPoint: .top, endPoint: .bottom
                    )
            )
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: width * 0.55, height: 2)
                    .padding(.bottom, 5)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 1.5, x: 0, y: 1.5)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    state.noteFromScreen(
                        UInt8(note),
                        velocity: Self.velocity(atY: value.location.y, height: height)
                    )
                }
            )
            .animation(.easeOut(duration: 0.08), value: isActive)
    }

    // MARK: - Геометрия

    /// Громкость зависит от места клика: ближе к низу клавиши — громче.
    private static func velocity(atY y: CGFloat, height: CGFloat) -> UInt8 {
        guard height > 0 else { return 96 }
        let ratio = max(0, min(1, y / height))
        return UInt8(48 + ratio * 72)
    }

    private static func whitesBefore(_ note: Int) -> Int {
        var count = 0
        for candidate in allNotes where candidate < note {
            if !blackClasses.contains(candidate % 12) { count += 1 }
        }
        return count
    }
}
