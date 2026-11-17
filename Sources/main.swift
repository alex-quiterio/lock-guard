// The menu bar app: a shield icon with an on/off toggle, the last report, the log and "Open at login".
import AppKit

let enabledKey = "enabled"
let statusItemName = "lock-guard"
let loginAgentLabel = "com.alex-quiterio.lock-guard.login"
let loginAgentPlist = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(loginAgentLabel).plist")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var lockGuard: LockGuard!
    private var lastReport: Summary?
    private var hasAlert = false

    private var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        placeNextToBattery()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = statusItemName
        statusItem.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        lockGuard = LockGuard(isEnabled: { [unowned self] in isEnabled }, onReport: { [unowned self] in report($0) })
        lockGuard.start()
        Report.write("app started, guard \(isEnabled ? "on" : "off")")
        refreshIcon()
    }

    // A new icon lands furthest left, which a full menu bar hides behind the notch. Start next to the battery
    // (positions count points from the right edge); a Cmd-drag afterwards overwrites this and is kept.
    private func placeNextToBattery() {
        let key = "NSStatusItem Preferred Position \(statusItemName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }

        let battery = UserDefaults(suiteName: "com.apple.controlcenter")?
            .object(forKey: "NSStatusItem Preferred Position Battery") as? Double ?? 400
        UserDefaults.standard.set(battery + 16, forKey: key)
    }

    private func report(_ summary: Summary) {
        lastReport = summary
        guard summary.isSuspicious else { return }

        hasAlert = true
        refreshIcon()
        Report.notify(summary.headline)
    }

    private func refreshIcon() {
        let name = hasAlert ? "exclamationmark.shield.fill" : isEnabled ? "lock.shield.fill" : "shield.slash"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Lock Guard")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !isEnabled && !hasAlert
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(title: "Guard while locked", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = isEnabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())
        let last = NSMenuItem(title: lastReport?.headline ?? "No report since the app started", action: nil, keyEquivalent: "")
        last.isEnabled = false
        menu.addItem(last)
        menu.addItem(NSMenuItem(title: "Show log…", action: #selector(showLog), keyEquivalent: "l"))
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = FileManager.default.fileExists(atPath: loginAgentPlist.path) ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit Lock Guard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != nil && $0.target == nil && $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard hasAlert else { return }

        hasAlert = false
        refreshIcon()
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        Report.write("guard \(isEnabled ? "on" : "off")")
        refreshIcon()
    }

    @objc private func showLog() {
        if !FileManager.default.fileExists(atPath: logFile.path) { Report.write("log created") }

        NSWorkspace.shared.open(logFile)
    }

    // A plain launchd plist that runs `open` on this app at login; removing it turns that off.
    @objc private func toggleLogin() {
        if FileManager.default.fileExists(atPath: loginAgentPlist.path) {
            try? FileManager.default.removeItem(at: loginAgentPlist)
            return
        }

        let plist: [String: Any] = [
            "Label": loginAgentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
        ]
        try? FileManager.default.createDirectory(at: loginAgentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (plist as NSDictionary).write(to: loginAgentPlist, atomically: true)
    }
}

// `Lock Guard check [minutes] [--notify]` reads the idle counter and the recent wrong passwords, then exits.
let args = CommandLine.arguments
if args.count > 1 && args[1] == "check" {
    let minutes = Double(args.count > 2 ? args[2] : "10") ?? 10
    print("idle for \(String(format: "%.1f", HID.idleSeconds() ?? -1))s")
    let failures = Passwords.failures(from: Date().addingTimeInterval(-minutes * 60), to: Date())
    print("wrong passwords in the last \(Int(minutes)) min: \(failures.count)", failures.map(Clock.time))
    if args.contains("--notify") { Report.notify("Test: this is how a report looks.") }

    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
