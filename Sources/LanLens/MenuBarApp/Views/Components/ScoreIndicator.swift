import SwiftUI

struct ScoreIndicator: View {
    let score: Int

    private var filledDots: Int {
        switch score {
        case 0: return 0
        case 1..<20: return 1
        case 20..<40: return 2
        case 40..<60: return 3
        case 60..<80: return 4
        default: return 5
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index < filledDots ? Color.lanLensAccent : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Smart score \(score) out of 100")
        .accessibilityValue("\(filledDots) out of 5 dots")
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack {
            Text("Score 0:")
            Spacer()
            ScoreIndicator(score: 0)
        }
        HStack {
            Text("Score 15:")
            Spacer()
            ScoreIndicator(score: 15)
        }
        HStack {
            Text("Score 35:")
            Spacer()
            ScoreIndicator(score: 35)
        }
        HStack {
            Text("Score 55:")
            Spacer()
            ScoreIndicator(score: 55)
        }
        HStack {
            Text("Score 75:")
            Spacer()
            ScoreIndicator(score: 75)
        }
        HStack {
            Text("Score 95:")
            Spacer()
            ScoreIndicator(score: 95)
        }
    }
    .padding()
    .background(Color.lanLensBackground)
}
