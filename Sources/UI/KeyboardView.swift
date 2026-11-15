import SwiftUI

struct KeyboardView: View {
    @Environment(AppState.self) private var state

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let blackClasses: Set<Int> = [1, 3, 6, 8, 10]
    private static let allNotes: [Int] = Array(21...108)
    private static let whiteNotes: [Int] = allNotes.filter { !blackClasses.contains($0 % 12) }
    private static let blackNotes: [Int] = allNotes.filter { blackClasses.contains($0 % 12) }

    var body: some View {
        VStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.accent)
                .frame(height: 3)
                .accessibilityHidden(true)

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
                        blackKey(note: note, width: whiteWidth * 0.58, height: height * 0.615)
                            .offset(x: whiteWidth * CGFloat(Self.whitesBefore(note)) - whiteWidth * 0.29)
                    }
                }
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.keyBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Клавиши

    private func whiteKey(note: Int, width: CGFloat, height: CGFloat) -> some View {
        let isActive = state.runningNotes.contains(UInt8(note))

        return ZStack(alignment: .bottom) {
            Rectangle()
                .fill(
                    isActive
                        ? AnyShapeStyle(Theme.keyPressed)
                        : AnyShapeStyle(LinearGradient(
                            colors: [Theme.keyWhiteTop, Theme.keyWhiteBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )

            if note % 12 == 0 {
                Text("C\(note / 12 - 1)")
                    .font(Theme.ui(8.5, weight: .medium))
                    .foregroundStyle(Theme.mutedSoft)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.keyBorder)
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isActive ? Theme.accent : Theme.keyBorder)
                .frame(height: isActive ? 3 : 1)
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                state.noteFromScreen(
                    UInt8(note),
                    velocity: Self.velocity(atY: value.location.y, height: height)
                )
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.noteNames[note % 12])\(note / 12 - 1)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { state.noteFromScreen(UInt8(note)) }
        .animation(.easeOut(duration: 0.07), value: isActive)
    }

    private func blackKey(note: Int, width: CGFloat, height: CGFloat) -> some View {
        let isActive = state.runningNotes.contains(UInt8(note))

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(
                isActive
                    ? AnyShapeStyle(Theme.accent)
                    : AnyShapeStyle(LinearGradient(
                        colors: [Theme.keyBlackTop, Theme.keyBlackBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    state.noteFromScreen(
                        UInt8(note),
                        velocity: Self.velocity(atY: value.location.y, height: height)
                    )
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Self.noteNames[note % 12])\(note / 12 - 1)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { state.noteFromScreen(UInt8(note)) }
            .animation(.easeOut(duration: 0.07), value: isActive)
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
