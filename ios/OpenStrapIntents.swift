// OpenStrap App Intents — Siri / Shortcuts / Spotlight / Ultra Action Button.
//
// Add to the Runner (iOS app) target. These read the phone's App Group snapshot
// (the same keys WidgetService writes) and answer spoken/dialog queries. Because
// they're AppShortcuts, they work with zero user setup: "Hey Siri, OpenStrap
// recovery". The Apple Watch Ultra's Action Button can be bound to any of these
// via Settings ▸ Action Button ▸ Shortcut.

import AppIntents
import Foundation

// MARK: - Shared reader

enum OpenStrapShared {
  static var appGroup: String {
    Bundle.main.object(forInfoDictionaryKey: "OpenStrapAppGroupIdentifier") as? String
      // Same fallback as AppGroup.swift and WidgetService.fallbackAppGroupId:
      // the build-configured default (ios/Config/Signing.defaults.xcconfig).
      // Three different fallbacks for one group meant that if Info.plist ever
      // went missing, Siri and the widget would read different suites.
      ?? "group.com.example.openstrap"
  }

  static func defaults() -> UserDefaults? { UserDefaults(suiteName: appGroup) }

  /// `has_data` is the phone saying the snapshot is non-empty and describes a
  /// recent day — but it is a bool frozen when the phone last pushed, so on a
  /// phone that stopped syncing it stays true forever. Siri answers in the
  /// present tense, so it ages `updated_at` here, at answer time.
  ///
  /// Same 26 h and same reasoning as `kStaleAfter` in
  /// ios/OpenStrapWidget/OpenStrapWidget.swift and WatchMetrics.swift —
  /// separate build targets, so it cannot be one declaration.
  static let staleAfter: TimeInterval = 26 * 3600

  static var hasData: Bool {
    guard defaults()?.bool(forKey: "has_data") ?? false else { return false }
    let at = defaults()?.object(forKey: "updated_at") as? Int ?? 0
    // An unknown timestamp is not a claim of staleness.
    return at <= 0 || Date().timeIntervalSince1970 - Double(at) <= staleAfter
  }
  static var readiness: Int { defaults()?.object(forKey: "readiness") as? Int ?? -1 }
  /// The phone's own band label, published as `readiness_band` (thresholds:
  /// `readinessBand` in lib/ui2/screens/home_screen.dart). Siri used to carry a
  /// fourth private copy of the cut-offs, so it called 65 "moderate" while the
  /// phone said "Steady" and the widget drew orange.
  static var readinessBand: String { defaults()?.string(forKey: "readiness_band") ?? "" }
  static var strain: Double { defaults()?.object(forKey: "strain") as? Double ?? -1 }
  static var hrv: Int { defaults()?.object(forKey: "hrv") as? Int ?? -1 }
  static var rhr: Int { defaults()?.object(forKey: "rhr") as? Int ?? -1 }
  static var sleepMin: Int { defaults()?.object(forKey: "sleep_min") as? Int ?? -1 }

  /// Spoken, so it is words rather than the phone's "7h 05m" — but a 45-minute
  /// nap is not "0 hours 45 minutes".
  static var sleepText: String {
    guard sleepMin >= 0 else { return "no sleep data yet" }
    let h = sleepMin / 60, m = sleepMin % 60
    if h == 0 { return "\(m) minutes" }
    if m == 0 { return h == 1 ? "1 hour" : "\(h) hours" }
    return "\(h) \(h == 1 ? "hour" : "hours") \(m) minutes"
  }
  static var noData: String { "I don't have today's numbers yet. Open OpenStrap and sync your band." }

  /// What to say when the phone has today's snapshot but is holding one number
  /// back, or nil when the number is simply missing and [noData] is right.
  ///
  /// The bare ints are -1 for a baseline still calibrating, a provisional score
  /// still finishing and a night still being worked out, and none of those is
  /// cleared by a sync — telling someone on night 2 of 4 to sync their band
  /// sends them round in a circle for days. WidgetService already resolves the
  /// reason into `overnight_why` and the `ring_<key>_*` strings the widget
  /// draws, so Siri says the same thing rather than inventing a fourth answer.
  /// A provisional number is still not spoken: Siri only reads final scores.
  static func pendingLine(ring key: String, noun: String, heldOver: Bool,
                          in d: UserDefaults? = defaults()) -> String? {
    guard let d else { return nil }
    if heldOver, let why = d.string(forKey: "overnight_why"), !why.isEmpty {
      return why
    }
    guard let state = d.object(forKey: "ring_\(key)_state") as? Int else { return nil }
    let value = d.string(forKey: "ring_\(key)_value") ?? ""
    let sub = d.string(forKey: "ring_\(key)_sub") ?? ""
    let why = d.string(forKey: "ring_\(key)_why") ?? ""
    switch state {
    case 1:
      // State 1 carries either a provisional number or the word for a
      // baseline still filling, with "2 of 4 nights" under it.
      if Int(value) != nil { return "\(noun) is still finishing up. Ask again a little later." }
      return sub.isEmpty
        ? "\(noun) is still calibrating."
        : "\(noun) is still calibrating, \(sub) so far."
    case 2:
      return why.isEmpty ? nil : "\(noun) isn't scored yet. \(why)"
    default:
      return nil
    }
  }

  /// [pendingLine] when there is one, otherwise [noData].
  static func notReady(ring key: String, noun: String, heldOver: Bool) -> String {
    guard hasData else { return noData }
    return pendingLine(ring: key, noun: noun, heldOver: heldOver) ?? noData
  }

  /// The snapshot as JSON for [GetNumbersIntent]. Every number is null unless
  /// [hasData]; a -1 sentinel is null too. `date` is the local day of `updated_at`.
  static func numbersJSON() -> String {
    let d = defaults()
    let at = d?.object(forKey: "updated_at") as? Int ?? 0
    let fresh = hasData
    func int(_ key: String) -> Any {
      guard fresh, let v = d?.object(forKey: key) as? Int, v >= 0 else { return NSNull() }
      return v
    }
    var out: [String: Any] = [
      "source": "OpenStrap",
      "has_data": fresh,
      "readiness": int("readiness"),
      "hrv_ms": int("hrv"),
      "hrv_baseline_ms": int("hrv_baseline"),
      "resting_hr": int("rhr"),
      "sleep_min": int("sleep_min"),
      "sleep_need_min": int("sleep_need_min"),
      "sleep_efficiency": int("sleep_efficiency"),
    ]
    let band = d?.string(forKey: "readiness_band") ?? ""
    out["readiness_band"] = fresh && !band.isEmpty ? band : NSNull()
    if fresh, let s = d?.object(forKey: "strain") as? Double, s >= 0 {
      // Decimal so JSON says 8.4, not 8.4000000000000004.
      out["strain"] = NSDecimalNumber(string: String(format: "%.1f", s))
    } else {
      out["strain"] = NSNull()
    }
    if at > 0 {
      let written = Date(timeIntervalSince1970: TimeInterval(at))
      let iso = ISO8601DateFormatter()
      iso.timeZone = .current
      out["updated_at"] = iso.string(from: written)
      let day = DateFormatter()
      day.locale = Locale(identifier: "en_US_POSIX")
      day.dateFormat = "yyyy-MM-dd"
      out["date"] = day.string(from: written)
    } else {
      out["updated_at"] = NSNull()
      out["date"] = NSNull()
    }
    let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data("{}".utf8)
    return String(data: data, encoding: .utf8) ?? "{}"
  }
}

// MARK: - Intents

@available(iOS 16.0, *)
struct RecoveryIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Readiness"
  static var description = IntentDescription("Ask OpenStrap for today's readiness.")
  static var openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard OpenStrapShared.hasData, OpenStrapShared.readiness >= 0 else {
      return .result(dialog: IntentDialog(stringLiteral: OpenStrapShared.notReady(
        ring: "recovery", noun: "Readiness", heldOver: true)))
    }
    // "Readiness, out of 100" — the app's own name and unit. It is not a
    // percentage and it is not called Recovery anywhere else in the product.
    let band = OpenStrapShared.readinessBand
    let line = "Your readiness is \(OpenStrapShared.readiness) out of 100."
    return .result(dialog: IntentDialog(
      stringLiteral: band.isEmpty ? line : "\(line) \(band)."))
  }
}

@available(iOS 16.0, *)
struct StrainIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Strain"
  static var description = IntentDescription("Ask OpenStrap for today's strain.")
  static var openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard OpenStrapShared.hasData, OpenStrapShared.strain >= 0 else {
      return .result(dialog: IntentDialog(stringLiteral: OpenStrapShared.notReady(
        ring: "strain", noun: "Strain", heldOver: false)))
    }
    let s = String(format: "%.1f", OpenStrapShared.strain)
    return .result(dialog: "Today's strain so far is \(s) out of twenty-one.")
  }
}

@available(iOS 16.0, *)
struct SleepIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Sleep"
  static var description = IntentDescription("Ask OpenStrap how you slept.")
  static var openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard OpenStrapShared.hasData, OpenStrapShared.sleepMin >= 0 else {
      return .result(dialog: IntentDialog(stringLiteral: OpenStrapShared.notReady(
        ring: "sleep", noun: "Sleep", heldOver: true)))
    }
    return .result(dialog: "You slept \(OpenStrapShared.sleepText) last night.")
  }
}

/// "Get Today's Numbers": the widget snapshot as one JSON text value, so a
/// shortcut can pass it to another app ("Get Dictionary from Input" picks keys).
@available(iOS 16.0, *)
struct GetNumbersIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Today's Numbers"
  static var description = IntentDescription(
    "Readiness, HRV, resting heart rate, sleep and strain from OpenStrap's latest sync, as JSON for your own Shortcuts. A number that isn't there is null.")
  static var openAppWhenRun = false

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    .result(value: OpenStrapShared.numbersJSON())
  }
}

// MARK: - Action intents (these actually DO something, not just answer)

@available(iOS 16.0, *)
struct SyncDataIntent: AppIntent {
  static var title: LocalizedStringResource = "Sync Data"
  static var description = IntentDescription(
    "Sync your paired band into Edge without opening the app. Large backlogs may need more than one run.")
  static var openAppWhenRun = false
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @Parameter(title: "Ignore Connectivity Errors", description:
    "Skip quietly when Bluetooth is unavailable or the band cannot be reached. Pairing, permission, and other errors are still reported.", default: false)
  var ignoreConnectivityErrors: Bool

  static var parameterSummary: some ParameterSummary {
    Summary("Sync band data") { \.$ignoreConnectivityErrors }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    .result(value: try await syncMessage(using: .shared))
  }

  @MainActor
  func syncMessage(using bridge: ShortcutSyncBridge) async throws -> String {
    do {
      return try await bridge.sync().message
    } catch let error as ShortcutSyncFailure where ignoreConnectivityErrors && error.canIgnore {
      return "Skipped: \(error.localizedDescription)"
    }
  }
}

@available(iOS 16.0, *)
struct OpenEdgeAndSyncIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Edge and Sync"
  static var description = IntentDescription(
    "Open Edge and sync your paired band. Use this interactive action for catch-up that needs the app in front.")
  static var openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let reply = try await ShortcutSyncBridge.shared.sync()
    return .result(value: reply.message)
  }
}

/// Buzzes the band once, e.g. at the end of a rest timer in another app.
/// Runs in the app process without opening it and only uses a connection the
/// app already has; it never throws, so a missed buzz doesn't stop the
/// calling shortcut.
@available(iOS 16.0, *)
struct BuzzBandIntent: AppIntent {
  static var title: LocalizedStringResource = "Buzz Band"
  static var description = IntentDescription(
    "Buzz your band once over Edge's existing connection. Nothing happens if Edge isn't connected to the band at that moment.")
  static var openAppWhenRun = false
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    .result(value: await ShortcutSyncBridge.shared.buzz().message)
  }
}

/// Band Timer: "Remind me in 20 minutes with Edge", spoken or typed to Siri /
/// Apple Intelligence, which fills in the minutes from the request (older
/// Siri asks "How many minutes?"). When time is up the BAND buzzes, not the
/// phone. It is armed as the band's own alarm, so it goes off with the phone
/// locked and Edge closed. Separate from the Fajr alarm (own storage, own buzz
/// count, lib/state/band_timer.dart); it only borrows the band's single alarm
/// slot while it is the first thing due, and the next alarm goes back on after.
@available(iOS 16.0, *)
struct BandTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Band Timer"
  static var description = IntentDescription(
    "Set a timer that buzzes your band (not the phone) when time is up. Works with the phone locked; the band keeps the time itself.",
    categoryName: "Timer",
    searchKeywords: ["timer", "remind me", "buzz", "countdown", "band"])
  static var openAppWhenRun = false
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @Parameter(title: "Minutes",
             description: "How many minutes from now the band buzzes, e.g. 20, or 90 for an hour and a half.",
             inclusiveRange: (1, 1440),
             requestValueDialog: IntentDialog("How many minutes?"))
  var minutes: Int

  @Parameter(title: "Buzzes",
             description: "How many times the band buzzes when time is up.",
             default: 3,
             inclusiveRange: (1, 20))
  var buzzes: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Buzz the band in \(\.$minutes) minutes") { \.$buzzes }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let text = await BandTimerRunner.set(minutes: min(max(minutes, 1), 1440),
                                         buzzes: min(max(buzzes, 1), 20))
    return .result(value: text, dialog: IntentDialog(stringLiteral: text))
  }
}

/// Stops the band timer; the next alarm (Fajr, weekly) goes back on the band.
@available(iOS 16.0, *)
struct CancelBandTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Cancel Band Timer"
  static var description = IntentDescription("Stop the band timer.",
    categoryName: "Timer", searchKeywords: ["timer", "cancel", "stop"])
  static var openAppWhenRun = false
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let text = await BandTimerRunner.set(minutes: 0, buzzes: 0)
    return .result(value: text, dialog: IntentDialog(stringLiteral: text))
  }
}

@available(iOS 16.0, *)
@MainActor
enum BandTimerRunner {
  /// minutes > 0 starts the timer, 0 stops it. Returns what Siri says.
  static func set(minutes: Int, buzzes: Int) async -> String {
    let bridge = ShortcutSyncBridge.shared
    guard let reply = await bridge.call("buzzTimer", ["minutes": minutes, "buzzes": buzzes],
                                        timeout: 15) as? [String: Any],
          let status = reply["status"] as? String else {
      return "Edge did not answer. Open Edge and try again."
    }
    let at = Date(timeIntervalSince1970: TimeInterval(reply["at"] as? Int ?? 0))
    if status == "needsSync" {
      // Not connected right now: one sync connects, and connecting arms the
      // band from the same plan.
      _ = try? await bridge.sync(timeout: 25)
    }
    let state = await bridge.call("buzzTimerStatus", nil, timeout: 5) as? String
    if minutes == 0 {
      return state == "timer" || status == "failed"
        ? "Timer stopped in Edge, but the band could not be reached yet. Open Edge to update it."
        : "Band timer stopped."
    }
    let time = at.formatted(date: .omitted, time: .shortened)
    switch state {
    case "timer":
      return "Done. Your band will buzz at \(time), in \(minutes) minutes."
    case "other" where status != "failed":
      return "Timer set for \(time). An earlier alarm is on the band first, so the timer goes on right after it."
    default:
      return "Timer set for \(time), but the band could not be reached. Keep Edge connected or open it so the band gets it."
    }
  }
}

/// Flutter consumes the breathing route on launch and resume because opening
/// the app does not guarantee a fresh process.
@available(iOS 16.0, *)
struct StartBreathingIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Breathing Session"
  static var description = IntentDescription(
    "Start a guided resonance-breathing session in OpenStrap.")
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult & ProvidesDialog {
    OpenStrapShared.defaults()?.set("/breathing", forKey: "pending_route")
    return .result(dialog: "Starting your breathing session.")
  }
}

/// "Enable tomorrow's alarm" — the other action intent. It does not carry a
/// time: it turns on whatever hour/minute tomorrow's weekday already has in
/// the app's weekly schedule (same toggle as the Alarm screen), so there is
/// nothing to ask Siri to parse and nothing that can silently pick the wrong
/// time. Setting the actual band alarm needs a live BLE connection the
/// widget process doesn't have, so — same as [StartBreathingIntent] — this
/// just latches a flag and opens the app; AppState.checkPendingSiriRoute
/// consumes it and does the real write (setScheduleDay → engine.setAlarm) on
/// launch/resume.
@available(iOS 16.0, *)
struct EnableTomorrowAlarmIntent: AppIntent {
  static var title: LocalizedStringResource = "Enable Tomorrow's Alarm"
  static var description = IntentDescription(
    "Turn on tomorrow's alarm at whatever time you already set for that weekday in OpenStrap.")
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult & ProvidesDialog {
    // Latch WHEN the request was made, not a weekday. Which slot "tomorrow"
    // means depends on the schedule: asked at 00:40 on a Tuesday with a
    // 07:00 Tuesday alarm, it is that morning's; asked at 09:00 after that
    // alarm has passed, it is Wednesday's. Only the Dart side has the
    // schedule, so it resolves the weekday (siriTomorrowAlarmWeekday in
    // lib/state/alarm_schedule.dart) against this instant — not against
    // whenever the app happens to launch/resume, which may be after midnight.
    let requestedAt = Int(Date().timeIntervalSince1970)
    OpenStrapShared.defaults()?.set(requestedAt, forKey: "enable_tomorrow_alarm_requested_at")
    // Same App Group route latch StartBreathingIntent uses, so the user lands
    // on the Alarm screen and can see the toggle actually flipped rather than
    // wondering whether Siri did anything.
    OpenStrapShared.defaults()?.set("/alarm", forKey: "pending_route")
    return .result(dialog: "Turning on tomorrow's alarm.")
  }
}

// MARK: - Shortcuts provider (zero-setup Siri phrases)

@available(iOS 16.0, *)
struct OpenStrapShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SyncDataIntent(),
      phrases: ["Sync data in \(.applicationName)", "Sync my band with \(.applicationName)"],
      shortTitle: "Sync Data",
      systemImageName: "arrow.triangle.2.circlepath")

    AppShortcut(
      intent: RecoveryIntent(),
      phrases: [
        "\(.applicationName) readiness",
        "What's my readiness in \(.applicationName)",
        "\(.applicationName) recovery",
        "How recovered am I in \(.applicationName)",
      ],
      shortTitle: "Readiness",
      systemImageName: "bolt.heart")

    AppShortcut(
      intent: StrainIntent(),
      phrases: [
        "\(.applicationName) strain",
        "What's my strain in \(.applicationName)",
      ],
      shortTitle: "Strain",
      systemImageName: "flame")

    AppShortcut(
      intent: SleepIntent(),
      phrases: [
        "\(.applicationName) sleep",
        "How did I sleep in \(.applicationName)",
      ],
      shortTitle: "Sleep",
      systemImageName: "moon.zzz")

    AppShortcut(
      intent: StartBreathingIntent(),
      phrases: [
        "Start breathing in \(.applicationName)",
        "\(.applicationName) breathe",
        "Start a breathing session in \(.applicationName)",
        "Breathe with \(.applicationName)",
      ],
      shortTitle: "Breathe",
      systemImageName: "wind")

    AppShortcut(
      intent: EnableTomorrowAlarmIntent(),
      phrases: [
        "Enable tomorrow's alarm in \(.applicationName)",
        "Turn on tomorrow's alarm in \(.applicationName)",
        "\(.applicationName) enable tomorrow's alarm",
      ],
      shortTitle: "Tomorrow's Alarm",
      systemImageName: "alarm")

    AppShortcut(
      intent: BandTimerIntent(),
      phrases: [
        "Set a band timer in \(.applicationName)",
        "Remind me with \(.applicationName)",
        "Start a timer with \(.applicationName)",
        "\(.applicationName) timer",
        "Buzz my band later with \(.applicationName)",
      ],
      shortTitle: "Band Timer",
      systemImageName: "timer")

    AppShortcut(
      intent: CancelBandTimerIntent(),
      phrases: [
        "Stop the band timer in \(.applicationName)",
        "Cancel the timer in \(.applicationName)",
        "\(.applicationName) stop timer",
      ],
      shortTitle: "Stop Band Timer",
      systemImageName: "timer.slash")

    AppShortcut(
      intent: BuzzBandIntent(),
      phrases: [
        "Buzz my band with \(.applicationName)",
        "\(.applicationName) buzz",
      ],
      shortTitle: "Buzz Band",
      systemImageName: "waveform")
  }
}
