# ISOLYNV2.0 RELEASE CHECKLIST

**Purpose:** core-hardening roadmap Phase 3c. The project currently ships as an
SPM executable target; actual distribution needs an Xcode app shell with
capabilities, privacy declarations, and signing. This document is the complete,
pre-researched checklist for that work so it becomes an afternoon of execution
instead of archaeology. NOTHING here exists yet -- every box starts unchecked.

Source of truth for requirements: audit F-05, `LiveWeatherService`'s capability
notes, and Apple's current App Store / notarization rules (re-verify versions at
execution time).

---

## 1. App shell

- [ ] Create a macOS **App** target in Xcode that wraps the existing SPM package
      (keep `IsolynApp` SPM target as the fast dev loop; the app shell is the
      distributable). Reference the package as a local package dependency.
- [ ] Deployment target: macOS 14.0 (matches Package.swift).
- [ ] Window configuration parity: min 900×620, default 1080×720, hidden title
      bar (see `IsolynApp.swift`) -- replicate in the shell or move sizing into
      shared code.

## 2. Privacy manifest (`PrivacyInfo.xcprivacy`)

- [ ] Add the privacy manifest to the app bundle.
- [ ] Declare **CoreLocation** access. IsolynV2.0 reads location ONLY to fetch live
      weather (`LiveWeatherService` → `CLLocationManager().location`, one-shot
      read, no continuous tracking, no background location).
      - Required-access-reason key for location: use the "app functionality"
        category (verify current Apple reason-code numbering at build time).
- [ ] Declare any required-API reasons Apple mandates for SDKs in use
      (UserDefaults is used by `AppearanceManager` -- declare the CA92.1-style
      "app functionality" access reason if/where required by then-current rules).

## 3. Usage-description strings (Info.plist)

- [ ] `NSLocationWhenInUseUsageDescription` -- suggested copy:
      > "IsolynV2.0 uses your approximate location to show real weather on the game
      > table. You can play everything without allowing this."
- [ ] No other usage strings are needed today (no camera/mic/photos/contacts).

## 4. Capabilities & entitlements

- [ ] **WeatherKit capability** enabled on the App ID + provisioning profile.
      Without it, `.live` weather mode silently falls back per
      `EnvironmentManager.makeWeatherSource` (documented degradation, but ship
      the capability so users actually get live weather).
- [ ] App Sandbox: enable, with **no** network exceptions beyond what WeatherKit
      requires (outgoing connections only). No file access beyond defaults.
- [ ] Hardened Runtime: enable (required for notarization).

## 5. Icon & assets

- [ ] App icon set (macOS .iconset / Asset Catalog). Candidate direction, NOT a
      decision: the ivory six-pip watermark from EntryView as the mark on an
      ebony rounded square.
- [ ] Verify no missing asset warnings at archive time.

## 6. Build, sign, notarize

- [ ] Release configuration build passes with zero warnings.
- [ ] Archive → export with Developer ID (for direct distribution) and/or App
      Store distribution.
- [ ] `codesign --verify --deep --strict` clean.
- [ ] Notarize + staple (xcrun notarytool / stapler) if distributing outside the
      Mac App Store.
- [ ] Gatekeeper double-click launch test on a clean user account.

## 7. Pre-flight functional checks on the packaged app

- [ ] Cold launch < ~2s to interactive entry screen (section 30 launch rule).
- [ ] Location permission prompt appears only when user switches weather to
      **Live**; denial degrades gracefully to last-known condition (never a
      blank sky).
- [ ] Full hot-seat match across all three modes end-to-end in the packaged
      binary.
- [ ] Appearance settings survive relaunch (UserDefaults through sandbox
      container).

## Explicitly out of scope until after UI revival

Fog-as-discrete-layer, difficulty selector UI, Training/Sandbox screens --
feature work stays governed by `isolyn roadmap.md`.
