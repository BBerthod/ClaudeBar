import SwiftUI
import Charts

struct Sparkline: View {
    let data: [Int]

    var body: some View {
        if data.isEmpty {
            Color.clear
                .frame(width: 80, height: 24)
        } else {
            Chart {
                ForEach(data.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Day", index),
                        y: .value("Count", data[index])
                    )
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Day", index),
                        y: .value("Count", data[index])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.secondary.opacity(0.2),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(width: 80, height: 24)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        Sparkline(data: [3, 7, 2, 9, 5, 12, 8])
        Sparkline(data: [1, 1, 2, 3, 5, 8, 13, 21])
        Sparkline(data: [])
    }
    .padding()
}
