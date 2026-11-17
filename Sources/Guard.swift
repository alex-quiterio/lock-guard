// While the screen is locked, records keyboard/mouse input and wrong passwords, and reports them on unlock.
import Foundation
import IOKit

let graceAfterLock: TimeInterval = 5      // ignore your own input right after locking
let burstGap: TimeInterval = 10           // input closer than this is one burst
let ownerWindow: TimeInterval = 30        // a burst ending this close to the unlock is probably you
let logFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/lock-guard.log")

final class LockGuard {
    private var lockedAt: Date?
    private var lastIdle: TimeInterval = 0
    private var inputs: [Date] = []
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private let isEnabled: () -> Bool
    private let onReport: (Summary) -> Void

    init(isEnabled: @escaping () -> Bool, onReport: @escaping (Summary) -> Void) {
        self.isEnabled = isEnabled
        self.onReport = onReport
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in self.locked() }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in self.unlocked() }
    }

    private func locked() {
        guard isEnabled() else { return }

        lockedAt = Date()
        inputs = []
        lastIdle = HID.idleSeconds() ?? 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.poll() }
        // Keep App Nap from stretching the 1-second poll while nobody is at the Mac.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Watching the locked screen")
        Report.write("🔒 Locked")
    }

    // Any input since the last poll (about 1 s ago) leaves the idle counter below the poll interval,
    // so steady typing counts too, not only the first key after a pause.
    private func poll() {
        guard let lockedAt, let idle = HID.idleSeconds() else { return }

        if idle < 1.1 || idle + 0.5 < lastIdle {
            let at = Date().addingTimeInterval(-idle)
            if at.timeIntervalSince(lockedAt) > graceAfterLock { inputs.append(at) }
        }

        lastIdle = idle
    }

    private func unlocked() {
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }

        activity = nil
        guard let lockedAt else { return }

        self.lockedAt = nil
        let unlockedAt = Date()
        let failures = Passwords.failures(from: lockedAt, to: unlockedAt)
        let summary = Summary(lockedAt: lockedAt, unlockedAt: unlockedAt, inputs: inputs, failures: failures)
        Report.write(summary.logEntry)
        onReport(summary)
    }
}

struct Summary {
    let lockedAt: Date
    let unlockedAt: Date
    let bursts: [(start: Date, end: Date)]
    let failures: [Date]

    init(lockedAt: Date, unlockedAt: Date, inputs: [Date], failures: [Date]) {
        self.lockedAt = lockedAt
        self.unlockedAt = unlockedAt
        self.failures = failures
        var bursts: [(start: Date, end: Date)] = []
        for at in inputs.sorted() {
            if let last = bursts.last, at.timeIntervalSince(last.end) <= burstGap {
                bursts[bursts.count - 1].end = at
            } else {
                bursts.append((at, at))
            }
        }

        self.bursts = bursts
    }

    private func isOwner(_ date: Date) -> Bool {
        unlockedAt.timeIntervalSince(date) <= ownerWindow
    }

    private var otherBursts: [(start: Date, end: Date)] { bursts.filter { !isOwner($0.end) } }
    private var otherFailures: [Date] { failures.filter { !isOwner($0) } }

    var isSuspicious: Bool { !otherBursts.isEmpty || !otherFailures.isEmpty }

    var headline: String {
        guard isSuspicious else { return "Locked \(Clock.span(lockedAt, unlockedAt)): nobody touched it" }

        var parts: [String] = []
        if !otherBursts.isEmpty {
            parts.append("input at " + otherBursts.map { Clock.span($0.start, $0.end) }.joined(separator: ", "))
        }

        if !otherFailures.isEmpty {
            let n = otherFailures.count
            parts.append("\(n) wrong password\(n == 1 ? "" : "s") (\(otherFailures.map(Clock.time).joined(separator: ", ")))")
        }

        return "While locked \(Clock.span(lockedAt, unlockedAt)): " + parts.joined(separator: "; ")
    }

    // The unlock line, then one aligned row per input burst and wrong password, in time order.
    var logEntry: String {
        let verdict = isSuspicious ? "⚠️  SOMEONE TOUCHED IT" : "✅ nobody else touched it"
        var lines = ["🔓 Unlocked after \(Clock.duration(unlockedAt.timeIntervalSince(lockedAt)))  ·  \(verdict)"]
        let rows: [(at: Date, line: String)] =
            bursts.map { ($0.start, row("⌨️", "input", Clock.span($0.start, $0.end), isOwner($0.end) ? "you, unlocking" : "⚠️")) }
            + failures.map { ($0, row("❌", "wrong password", Clock.time($0), isOwner($0) ? "your typo?" : "⚠️")) }
        lines += rows.sorted { $0.at < $1.at }.map(\.line)
        return lines.joined(separator: "\n")
    }

    private func row(_ icon: String, _ what: String, _ when: String, _ note: String) -> String {
        let pad = { (s: String, n: Int) in s.padding(toLength: max(n, s.count), withPad: " ", startingAt: 0) }
        return Report.indent + "\(icon) " + pad(what, 16) + pad(when, 19) + note
    }
}

enum HID {
    // HIDIdleTime resets on any keyboard or mouse event, including at the lock screen.
    static func idleSeconds() -> TimeInterval? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }

        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)
        guard let number = value?.takeRetainedValue() as? NSNumber else { return nil }

        return number.doubleValue / 1_000_000_000
    }
}

enum Passwords {
    // The lock screen logs this line once per wrong password. opendirectoryd's own failures are noisy:
    // macOS checks the password by itself on every lock, so we don't use them.
    static func failures(from start: Date, to end: Date) -> [Date] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show", "--style", "compact",
            "--start", fmt.string(from: start), "--end", fmt.string(from: end.addingTimeInterval(1)),
            "--predicate", "process == \"loginwindow\" AND eventMessage CONTAINS \"authFailWithMessage\" AND eventMessage CONTAINS \"INCORRECT password\"",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count > 1 else { return nil }

            return fmt.date(from: "\(fields[0]) \(fields[1].prefix(8))")
        }
    }
}

enum Clock {
    static func time(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    static func span(_ a: Date, _ b: Date) -> String {
        b.timeIntervalSince(a) < 1 ? time(a) : "\(time(a))–\(time(b))"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
}

enum Report {
    static let indent = String(repeating: " ", count: 10)
    private static let lastDayKey = "lastLogDay"

    // Each entry starts with its time; a new day gets a header line first.
    static func write(_ text: String) {
        let now = Date()
        let day = DateFormatter()
        day.dateFormat = "EEEE d MMMM yyyy"
        let today = day.string(from: now)
        var out = ""
        if UserDefaults.standard.string(forKey: lastDayKey) != today || !FileManager.default.fileExists(atPath: logFile.path) {
            let title = "━━━ \(today) "
            out += "\n" + title + String(repeating: "━", count: max(3, 56 - title.count)) + "\n\n"
            UserDefaults.standard.set(today, forKey: lastDayKey)
        }

        out += "\(Clock.time(now))  \(text)\n"
        append(out)
    }

    private static func append(_ text: String) {
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: logFile)
        }
    }

    static func notify(_ text: String) {
        guard let script = Bundle.main.url(forResource: "notify", withExtension: "applescript") else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [script.path, "Lock Guard", text]
        try? process.run()
    }
}
