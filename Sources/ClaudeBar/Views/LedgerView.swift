import SwiftUI

struct LedgerView: View {
    var ledgerService: LedgerService
    var statsService: StatsService

    @State private var searchText: String = ""
    @State private var daysFilter: Int = 7
    @State private var modelFilter: String = "All"

    // MARK: - Filtered data

    private var allModels: [String] {
        let raw = Set(ledgerService.entries.map { StatsService.displayName(for: $0.model) })
        return ["All"] + raw.sorted()
    }

    private var filteredEntries: [LedgerEntry] {
        ledgerService.entries.filter { entry in
            let matchesSearch = searchText.isEmpty
                || entry.projectName.localizedCaseInsensitiveContains(searchText)
            let matchesModel = modelFilter == "All"
                || StatsService.displayName(for: entry.model) == modelFilter
            return matchesSearch && matchesModel
        }
    }

    private var totalCost: Double {
        filteredEntries.reduce(0) { $0 + $1.estimatedCost }
    }

    private var totalTokens: Int {
        filteredEntries.reduce(0) { $0 + $1.totalTokens }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                filterBar
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                summaryCards
                    .padding(.horizontal, 12)

                if ledgerService.isLoading {
                    loadingState
                } else if filteredEntries.isEmpty {
                    emptyState
                } else {
                    entryList
                }

                Spacer(minLength: 12)
            }
        }
        .onAppear { ledgerService.load(days: daysFilter) }
        .onChange(of: daysFilter) {
            modelFilter = "All"
            ledgerService.load(days: daysFilter)
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            TextField("Search projects...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Picker("Period", selection: $daysFilter) {
                    Text("7d").tag(7)
                    Text("30d").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 120)

                Picker("Model", selection: $modelFilter) {
                    ForEach(allModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Summary

    private var summaryCards: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            StatCard(
                title: "Messages",
                value: "\(filteredEntries.count)",
                icon: "message"
            )
            StatCard(
                title: "Cost",
                value: CostCalculator.formatCost(totalCost),
                icon: "dollarsign.circle"
            )
            StatCard(
                title: "Tokens",
                value: totalTokens.abbreviatedTokenCount,
                icon: "number"
            )
        }
    }

    // MARK: - Entry list

    private var entryList: some View {
        LazyVStack(spacing: 6) {
            ForEach(filteredEntries) { entry in
                LedgerRowView(entry: entry)
                    .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Parsing session files...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No entries found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Ledger entries appear after using Claude Code.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 12)
    }
}

// MARK: - Row view

struct LedgerRowView: View {
    let entry: LedgerEntry

    var body: some View {
        GroupBox {
            HStack(spacing: 8) {
                // Model color dot
                Circle()
                    .fill(Color.color(for: entry.model))
                    .frame(width: 8, height: 8)

                // Project name
                Text(entry.projectName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                // Cost
                Text(CostCalculator.formatCost(entry.estimatedCost))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(costColor(for: entry.estimatedCost))
            }

            HStack(spacing: 10) {
                // Model name
                Text(entry.displayModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Tokens
                Label(entry.totalTokens.abbreviatedTokenCount, systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Cache indicator
                if entry.cacheReadTokens > 0 || entry.cacheWriteTokens > 0 {
                    Label("cached", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                // Tool calls
                if entry.toolCallCount > 0 {
                    Label("\(entry.toolCallCount)", systemImage: "wrench")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Timestamp
                Text(entry.timestamp.timeAgoString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func costColor(for cost: Double) -> Color {
        switch cost {
        case ..<0.01:  return .secondary
        case ..<0.10:  return .primary
        case ..<0.50:  return .orange
        default:       return .red
        }
    }
}

#Preview {
    LedgerView(
        ledgerService: LedgerService(),
        statsService: StatsService()
    )
    .frame(width: 420, height: 520)
}
