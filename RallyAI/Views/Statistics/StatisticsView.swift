import SwiftUI

// MARK: - Private Types

private struct PlayerStats {
    let player: Player
    var serveAttempts      = 0; var aces               = 0; var serveErrors      = 0
    var hitAttempts        = 0; var kills              = 0; var hitErrors        = 0
    var blockSolo          = 0; var blockAssist        = 0; var blockErrors      = 0
    var assists            = 0; var ballHandlingErrors = 0
    var digs               = 0; var digErrors          = 0
    var goodPasses         = 0; var badPasses          = 0; var passErrors       = 0

    var totalSR: Int { goodPasses + badPasses + passErrors }

    var killPct: Double? { hitAttempts > 0 ? Double(kills - hitErrors) / Double(hitAttempts) : nil }
    var passRating: Double? {
        totalSR > 0
            ? (Double(goodPasses) * 3 + Double(badPasses) * 2) / (Double(totalSR) * 3)
            : nil
    }
}

private struct StatColumn {
    let header: String
    let width: CGFloat
}

private struct StatRow: Identifiable {
    let id       = UUID()
    let jersey   : String
    let name     : String
    let cells    : [String]
    var isFooter : Bool = false
}

// MARK: - StatTable

private struct StatTable: View {
    let columns: [StatColumn]
    let rows: [StatRow]

    private let noWidth: CGFloat = 36
    private let hPad:   CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                VStack(spacing: 0) {
                    dataRow(row)
                    if idx < rows.count - 1 {
                        let next = rows[idx + 1]
                        if !row.isFooter && next.isFooter {
                            // Full-width rule before footer section
                            Color(.separator).frame(height: 0.5)
                        } else if !row.isFooter && !next.isFooter {
                            Divider()
                                .padding(.leading, noWidth + hPad + 8)
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("No.")
                .frame(width: noWidth, alignment: .center)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            ForEach(0..<columns.count, id: \.self) { i in
                Text(columns[i].header)
                    .frame(width: columns[i].width, alignment: .trailing)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(height: 32)
        .padding(.horizontal, hPad)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    private func dataRow(_ row: StatRow) -> some View {
        HStack(spacing: 0) {
            Text(row.jersey)
                .foregroundStyle(.secondary)
                .frame(width: noWidth, alignment: .center)
            Text(row.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            ForEach(0..<min(columns.count, row.cells.count), id: \.self) { i in
                Text(row.cells[i])
                    .monospacedDigit()
                    .frame(width: columns[i].width, alignment: .trailing)
            }
        }
        .font(row.isFooter ? .subheadline.weight(.semibold) : .subheadline)
        .foregroundStyle(row.isFooter ? .secondary : .primary)
        .frame(height: 42)
        .padding(.horizontal, hPad)
        .background(row.isFooter ? Color(.tertiarySystemGroupedBackground) : Color.clear)
    }
}

// MARK: - StatisticsView

struct StatisticsView: View {
    @EnvironmentObject var vm: TrackingViewModel
    /// When non-nil, displays this past match's stats in read-only mode.
    var session: MatchSession? = nil
    /// 0 = Full Match, N = Set N
    @State private var selectedSet: Int = 0

    // MARK: Data-source abstraction (active match vs. past match)

    private var activeGameState: GameState {
        session?.gameState ?? vm.gameState
    }
    private var activeRosterState: RosterState {
        session?.rosterState ?? vm.rosterState
    }

    // MARK: Column Definitions

    private let servCols = [
        StatColumn(header: "SA",    width: 44),
        StatColumn(header: "ACE",   width: 44),
        StatColumn(header: "SE",    width: 44)
    ]
    private let atkCols = [
        StatColumn(header: "K",   width: 36),
        StatColumn(header: "E",   width: 36),
        StatColumn(header: "TA",  width: 44),
        StatColumn(header: "PCT", width: 52)
    ]
    private let blkCols = [
        StatColumn(header: "BS",    width: 44),
        StatColumn(header: "BA",    width: 44),
        StatColumn(header: "BE",    width: 44)
    ]
    private let bhCols = [
        StatColumn(header: "Assists", width: 60),
        StatColumn(header: "BHE",     width: 44)
    ]
    private let digCols = [
        StatColumn(header: "Digs",  width: 52),
        StatColumn(header: "DE",    width: 44)
    ]
    private let passCols = [
        StatColumn(header: "SR",    width: 36),
        StatColumn(header: "GP",    width: 36),
        StatColumn(header: "BP",    width: 36),
        StatColumn(header: "RE",    width: 36),
        StatColumn(header: "PR",    width: 52)
    ]

    // MARK: Data

    private var scopeEvents: [RallyEvent] {
        selectedSet == 0
            ? activeGameState.events
            : activeGameState.events.filter { $0.setNumber == selectedSet }
    }

    private var activePlayers: [Player] {
        activeRosterState.players
            .filter(\.isActive)
            .sorted {
                $0.jerseyNumber != $1.jerseyNumber
                    ? $0.jerseyNumber < $1.jerseyNumber
                    : $0.displayName < $1.displayName
            }
    }

    private var allStats: [PlayerStats] {
        computeStats(events: scopeEvents, players: activePlayers)
    }

    // MARK: Body

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if session != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.caption.weight(.semibold))
                        Text("Past match — read only")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                scopeCardRow

                statSection("Serving",      cols: servCols, rows: servingRows)
                statSection("Attacking",    cols: atkCols,  rows: attackingRows)
                statSection("Blocking",     cols: blkCols,  rows: blockingRows)
                statSection("Ball Handling",cols: bhCols,   rows: ballHandlingRows)
                statSection("Digs",         cols: digCols,  rows: digsRows)
                statSection("Passing",      cols: passCols, rows: passingRows)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.map { matchTitle($0) } ?? "Game Statistics")
        .navigationBarTitleDisplayMode(.inline)

        if session != nil {
            content
        } else {
            NavigationStack { content }
        }
    }

    private func matchTitle(_ s: MatchSession) -> String {
        let name = s.match.matchName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let us   = s.match.ourTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let them = s.match.opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !us.isEmpty && !them.isEmpty { return "\(us) vs \(them)" }
        if !them.isEmpty { return "vs \(them)" }
        return s.match.startedAt.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Scope Card Row

    private var scopeCardRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Full Match card — shows sets won across completed sets
                let setsWon = activeGameState.setsWonBeforeCurrentSet()
                scopeCard(
                    setNum: 0,
                    title: "Full Match",
                    score: "\(setsWon.us) – \(setsWon.them)",
                    badge: nil,
                    isLive: false
                )

                // One card per set
                ForEach(1...max(1, activeGameState.currentSetNumber), id: \.self) { setNum in
                    let isLive = session == nil && setNum == activeGameState.currentSetNumber
                    let score  = isLive
                        ? activeGameState.derivedScore(forSet: activeGameState.currentSetNumber)
                        : activeGameState.derivedScore(forSet: setNum)
                    let badge: String? = isLive ? "LIVE"
                        : score.us > score.them ? "W"
                        : score.them > score.us ? "L"
                        : nil

                    scopeCard(
                        setNum: setNum,
                        title: "Set \(setNum)",
                        score: "\(score.us) – \(score.them)",
                        badge: badge,
                        isLive: isLive
                    )
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func scopeCard(
        setNum: Int,
        title: String,
        score: String,
        badge: String?,
        isLive: Bool
    ) -> some View {
        let isSelected = selectedSet == setNum

        return VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)

            Text(score)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(isSelected ? .white : .primary)

            Group {
                if let badge {
                    if isLive {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.blue : .white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                isSelected ? Color.white : Color.blue,
                                in: Capsule()
                            )
                    } else {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(
                                isSelected
                                    ? .white
                                    : (badge == "W" ? Color.green : Color.red)
                            )
                    }
                } else {
                    Color.clear.frame(height: 14)
                }
            }
        }
        .frame(width: 88, height: 82)
        .background(
            isSelected
                ? Color.blue
                : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedSet = setNum
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedSet)
    }

    // MARK: - Section Builder

    private func statSection(_ title: String, cols: [StatColumn], rows: [StatRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
            StatTable(columns: cols, rows: rows)
        }
    }

    // MARK: - Row Builders

    private var servingRows: [StatRow] {
        let s = allStats
        let playerRows = s.map { ps in
            StatRow(jersey: "\(ps.player.jerseyNumber)", name: ps.player.displayName,
                    cells: ["\(ps.serveAttempts)", "\(ps.aces)", "\(ps.serveErrors)"])
        }
        let t0 = s.reduce(0) { $0 + $1.serveAttempts }
        let t1 = s.reduce(0) { $0 + $1.aces }
        let t2 = s.reduce(0) { $0 + $1.serveErrors }
        return playerRows + [
            StatRow(jersey: "", name: "Team", cells: ["\(t0)", "\(t1)", "\(t2)"], isFooter: true)
        ]
    }

    private var attackingRows: [StatRow] {
        let s = allStats
        let playerRows = s.map { ps in
            StatRow(jersey: "\(ps.player.jerseyNumber)", name: ps.player.displayName,
                    cells: ["\(ps.kills)", "\(ps.hitErrors)", "\(ps.hitAttempts)", fpct(ps.killPct)])
        }
        let tK  = s.reduce(0) { $0 + $1.kills }
        let tE  = s.reduce(0) { $0 + $1.hitErrors }
        let tTA = s.reduce(0) { $0 + $1.hitAttempts }
        let tPct: Double? = tTA > 0 ? Double(tK - tE) / Double(tTA) : nil
        return playerRows + [
            StatRow(jersey: "", name: "Team", cells: ["\(tK)", "\(tE)", "\(tTA)", fpct(tPct)], isFooter: true)
        ]
    }

    private var blockingRows: [StatRow] {
        let s = allStats
        let playerRows = s.map { ps in
            StatRow(jersey: "\(ps.player.jerseyNumber)", name: ps.player.displayName,
                    cells: ["\(ps.blockSolo)", "\(ps.blockAssist)", "\(ps.blockErrors)"])
        }
        let t0 = s.reduce(0) { $0 + $1.blockSolo }
        let t1 = s.reduce(0) { $0 + $1.blockAssist }
        let t2 = s.reduce(0) { $0 + $1.blockErrors }
        return playerRows + [
            StatRow(jersey: "", name: "Team", cells: ["\(t0)", "\(t1)", "\(t2)"], isFooter: true)
        ]
    }

    private var ballHandlingRows: [StatRow] {
        let s = allStats
        let playerRows = s.map { ps in
            StatRow(jersey: "\(ps.player.jerseyNumber)", name: ps.player.displayName,
                    cells: ["\(ps.assists)", "\(ps.ballHandlingErrors)"])
        }
        let t0 = s.reduce(0) { $0 + $1.assists }
        let t1 = s.reduce(0) { $0 + $1.ballHandlingErrors }
        return playerRows + [
            StatRow(jersey: "", name: "Team", cells: ["\(t0)", "\(t1)"], isFooter: true)
        ]
    }

    private var digsRows: [StatRow] {
        let s = allStats
        let playerRows = s.map { ps in
            StatRow(jersey: "\(ps.player.jerseyNumber)", name: ps.player.displayName,
                    cells: ["\(ps.digs)", "\(ps.digErrors)"])
        }
        let t0 = s.reduce(0) { $0 + $1.digs }
        let t1 = s.reduce(0) { $0 + $1.digErrors }
        return playerRows + [
            StatRow(jersey: "", name: "Team", cells: ["\(t0)", "\(t1)"], isFooter: true)
        ]
    }

    private var passingRows: [StatRow] {
        let s = allStats
        let playerRows = s.map { ps in
            StatRow(jersey: "\(ps.player.jerseyNumber)", name: ps.player.displayName,
                    cells: ["\(ps.totalSR)", "\(ps.goodPasses)", "\(ps.badPasses)", "\(ps.passErrors)", fpct(ps.passRating)])
        }
        let tSR = s.reduce(0) { $0 + $1.totalSR }
        let tGP = s.reduce(0) { $0 + $1.goodPasses }
        let tBP = s.reduce(0) { $0 + $1.badPasses }
        let tRE = s.reduce(0) { $0 + $1.passErrors }
        let tPR: Double? = tSR > 0 ? (Double(tGP) * 3 + Double(tBP) * 2) / (Double(tSR) * 3) : nil
        return playerRows + [
            StatRow(jersey: "", name: "Team",
                    cells: ["\(tSR)", "\(tGP)", "\(tBP)", "\(tRE)", fpct(tPR)],
                    isFooter: true)
        ]
    }

    // MARK: - Formatting

    /// Formats a hitting-efficiency value as ".XXX" or "-.XXX" (NCAA style). Nil returns "—".
    private func fpct(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v >=  1.0 { return "1.000" }
        if v <= -1.0 { return "-1.000" }
        if v < 0 { return String(format: "-.%03d", Int((-v * 1000).rounded())) }
        return String(format: ".%03d", Int((v * 1000).rounded()))
    }

    // MARK: - Aggregation

    private func computeStats(events: [RallyEvent], players: [Player]) -> [PlayerStats] {
        var map = Dictionary(uniqueKeysWithValues: players.map { ($0.id, PlayerStats(player: $0)) })

        for event in events {
            guard let pid = resolvedPlayerID(for: event), map[pid] != nil else { continue }
            switch event.action {
            case .ace:              map[pid]!.aces               += 1; map[pid]!.serveAttempts += 1
            case .serve:            map[pid]!.serveAttempts      += 1
            case .serveError:       map[pid]!.serveErrors        += 1; map[pid]!.serveAttempts += 1
            case .kill:             map[pid]!.kills              += 1; map[pid]!.hitAttempts   += 1
            case .hitAttempt:       map[pid]!.hitAttempts        += 1
            case .hitError:         map[pid]!.hitErrors          += 1; map[pid]!.hitAttempts   += 1
            case .block:            map[pid]!.blockSolo          += 1
            case .blockAssist:      map[pid]!.blockAssist        += 1
            case .blockError:       map[pid]!.blockErrors        += 1
            case .assist:           map[pid]!.assists            += 1
            case .ballHandlingError:map[pid]!.ballHandlingErrors += 1
            case .dig:              map[pid]!.digs               += 1
            case .digError:         map[pid]!.digErrors          += 1
            case .goodPass:         map[pid]!.goodPasses         += 1
            case .badPass:          map[pid]!.badPasses          += 1
            case .passError:        map[pid]!.passErrors         += 1
            default: break
            }
        }

        return players.compactMap { map[$0.id] }
    }

    private func resolvedPlayerID(for event: RallyEvent) -> UUID? {
        if let pid = event.playerID { return pid }
        if let num = event.playerNumber { return activeRosterState.playerByJerseyNumber(num)?.id }
        return nil
    }
}

#Preview {
    StatisticsView()
        .environmentObject(TrackingViewModel(restoreOnInit: false))
}
