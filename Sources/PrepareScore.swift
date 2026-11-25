import Foundation

// Converts a locally supplied piano arrangement into the single melodic line used
// by the film. All notes and their timings come from the input Standard MIDI File.
private struct ScoreError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private struct Reader {
    let bytes: ArraySlice<UInt8>
    var position: Int

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        position = bytes.startIndex
    }

    var atEnd: Bool { position == bytes.endIndex }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count <= bytes.endIndex - position else { throw ScoreError("MIDI 文件意外截断。") }
        defer { position += count }
        return bytes[position..<(position + count)]
    }

    mutating func integer(_ width: Int) throws -> Int {
        try take(width).reduce(0) { ($0 << 8) | Int($1) }
    }

    mutating func variable() throws -> Int {
        var result = 0
        for _ in 0..<4 {
            let byte = try integer(1)
            result = (result << 7) | (byte & 127)
            if byte < 128 { return result }
        }
        throw ScoreError("无效的 MIDI 可变长度整数。")
    }

    mutating func chunk() throws -> (String, Reader) {
        let name = String(decoding: try take(4), as: UTF8.self)
        let length = try integer(4)
        return (name, Reader(try take(length)))
    }
}

private struct Note {
    var start: Int
    var end: Int
    var pitch: Int
    let velocity: Int
}

private struct Event {
    let tick: Int, key: Int, velocity: Int, order: Int
}

private struct Score {
    let division: Int
    var events: [Event] = []
    var tempos: [(tick: Int, value: Int)] = []
    var channels: Set<Int> = []
    var signature: [UInt8] = [4, 2, 24, 8]

    mutating func readTrack(_ data: Reader) throws {
        var track = data, tick = 0, previous: Int?
        while !track.atEnd {
            tick += try track.variable()
            let first = try track.integer(1)
            if first == 0xff {
                previous = nil
                let type = try track.integer(1), length = try track.variable()
                let payload = try track.take(length)
                if type == 0x51 {
                    guard length == 3 else { throw ScoreError("无效的 tempo 事件。") }
                    tempos.append((tick, payload.reduce(0) { ($0 << 8) | Int($1) }))
                } else if type == 0x58 {
                    let value = Array(payload)
                    guard value.count == 4, value[0] == 4, value[1] == 2 else { throw ScoreError("本 MV 需要 4/4 拍的编曲。") }
                    if tick == 0 { signature = value }
                } else if type == 0x2f { break }
            } else if first == 0xf0 || first == 0xf7 {
                previous = nil
                let length = try track.variable()
                _ = try track.take(length)
            } else {
                let status: Int, a: Int
                if first < 128 {
                    guard let previous else { throw ScoreError("MIDI 缺少通道事件状态。") }
                    status = previous; a = first
                } else {
                    guard first < 0xf0 else { throw ScoreError("不支持此 MIDI 系统事件。") }
                    status = first; previous = first; a = try track.integer(1)
                }
                let kind = status >> 4, channel = status & 15
                let b = (kind == 12 || kind == 13) ? 0 : try track.integer(1)
                guard a < 128, b < 128 else { throw ScoreError("MIDI 音符数据损坏。") }
                if kind == 8 || kind == 9 {
                    let velocity = kind == 9 ? b : 0
                    if velocity > 0 { channels.insert(channel) }
                    events.append(Event(tick: tick, key: channel * 128 + a, velocity: velocity, order: events.count))
                }
            }
        }
    }

    func pairedNotes() throws -> [Note] {
        guard channels.count == 1, !channels.contains(9) else { throw ScoreError("请选择同一编配的单通道钢琴 MIDI 或触控板独奏 MIDI。") }
        var active: [Int: [Event]] = [:], notes: [Note] = []
        for e in events.sorted(by: { ($0.tick, $0.order) < ($1.tick, $1.order) }) {
            if e.velocity > 0 { active[e.key, default: []].append(e) }
            else if var queue = active[e.key], !queue.isEmpty {
                let on = queue.removeFirst()
                active[e.key] = queue.isEmpty ? nil : queue
                if on.tick < e.tick { notes.append(Note(start: on.tick, end: e.tick, pitch: e.key % 128, velocity: on.velocity)) }
            }
        }
        guard active.isEmpty, !notes.isEmpty else { throw ScoreError("MIDI 含未结束的音符，或没有可演奏音符。") }
        return notes.sorted { ($0.start, $0.pitch, $0.end, $0.velocity) < ($1.start, $1.pitch, $1.end, $1.velocity) }
    }
}

private func loadScore(_ data: Data) throws -> Score {
    var file = Reader(Array(data)[...])
    var (name, header) = try file.chunk()
    guard name == "MThd" else { throw ScoreError("请选择标准 MIDI 文件（.mid 或 .midi）。") }
    let format = try header.integer(2), trackCount = try header.integer(2), division = try header.integer(2)
    guard (format == 0 || format == 1), trackCount > 0, division > 0, division < 32768 else { throw ScoreError("需要按四分音符计时的格式 0 或格式 1 MIDI。") }
    var score = Score(division: division), count = 0
    while count < trackCount {
        let (kind, track) = try file.chunk()
        if kind == "MTrk" { try score.readTrack(track); count += 1 }
    }
    return score
}

private func arrange(_ notes: [Note], division: Int) -> [Note] {
    var result: [Note] = []
    let groups = Dictionary(grouping: notes, by: \.start)
    for tick in groups.keys.sorted() {
        // Notes in each group were sorted by pitch, duration, then velocity.
        let chord = groups[tick]!
        var note = chord.last!
        let bar = tick / (4 * division) + 1, beat = tick % (4 * division)
        if (112...120).contains(bar) {
            if chord.count == 2 || chord.count == 3 { continue }
        } else if bar == 160 && 2 * beat >= 7 * division {
            // The bass answers the upper phrase here.
        } else if bar == 161 && beat == 3 * division {
            note.start = max(tick, result.last?.end ?? tick)
            note.pitch = min(127, note.pitch + 12)
        } else if note.pitch < (bar >= 137 ? 69 : 67) { continue }
        guard note.end > note.start else { continue }
        if let last = result.last, last.end > note.start { result[result.count - 1].end = note.start }
        result.append(note)
    }
    return result
}

private func variable(_ n: Int) -> [UInt8] {
    var value = n, bytes = [UInt8(value & 127)]
    value >>= 7
    while value > 0 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }
    return Array(bytes.reversed())
}

private func encode(_ notes: [Note], score: Score, tempo: Int) -> Data {
    let title = Array("Senbonzakura - Trackpad Solo".utf8)
    var track: [UInt8] = [0, 255, 3, UInt8(title.count)] + title
    track += [0, 255, 88, 4] + score.signature
    track += [0, 255, 81, 3, UInt8(tempo >> 16), UInt8((tempo >> 8) & 255), UInt8(tempo & 255)]
    var last = 0
    for note in notes {
        track += variable(note.start - last) + [0x90, UInt8(note.pitch), UInt8(note.velocity)]
        track += variable(note.end - note.start) + [0x80, UInt8(note.pitch), 0]
        last = note.end
    }
    track += [0, 255, 47, 0]
    var out = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, UInt8(score.division >> 8), UInt8(score.division & 255)]
    out += Array("MTrk".utf8)
    for shift in [24, 16, 8, 0] { out.append(UInt8((track.count >> shift) & 255)) }
    return Data(out + track)
}

private func prepare(input: URL, output: URL) throws {
    let data = try Data(contentsOf: input)
    let score = try loadScore(data)
    guard let tempo = score.tempos.first(where: { $0.tick == 0 })?.value,
          score.tempos.allSatisfy({ abs($0.value - 387097) <= 1 }) else { throw ScoreError("请使用与 MV 匹配的固定 155 BPM 钢琴编配。") }
    let notes = try score.pairedNotes()
    func matchesFilm(_ sequence: [Note]) -> Bool {
        let seconds = Double(sequence.map(\.end).max() ?? 0) * Double(tempo) / 1_000_000 / Double(score.division)
        return sequence.first?.start == 0 && abs(seconds - 250.684) < 0.15
    }
    guard matchesFilm(notes) else { throw ScoreError("音符起止时间与这支 4 分 10.684 秒的 MV 不符。") }
    let mono = zip(notes, notes.dropFirst()).allSatisfy { $0.end <= $1.start }
    let prepared = mono ? notes : arrange(notes, division: score.division)
    guard matchesFilm(prepared) else { throw ScoreError("提取的声部与本曲编配不符。请导入对应版本的钢琴谱或单声部谱。") }
    try encode(prepared, score: score, tempo: tempo).write(to: output, options: .atomic)
}

do {
    let args = CommandLine.arguments
    guard args.count == 3 else { throw ScoreError("用法：PrepareScore INPUT.mid OUTPUT.mid") }
    try prepare(input: URL(fileURLWithPath: args[1]), output: URL(fileURLWithPath: args[2]))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
