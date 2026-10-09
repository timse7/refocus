# Refocus

A native Apple silicon re-implementation of [Hocus Focus](https://hocusfoc.us/) (UglyApps, last release 1.3 from 2015, Intel only).

## What Hocus Focus does (and what Refocus reproduces)

- Menu bar app with no Dock icon. It **hides applications that sat in the background** longer than a timeout.
- Each app can follow the profile default, use its own **timeout** (slider; 0 = never hide → "Disabled" group), or be **hidden as soon as it loses focus**.
- **Profiles** (for example "Default" or "Focus Mode"), each with a default timeout and default "hide when focus is lost", plus per-app overrides. A **global hotkey cycles profiles** and shows "Switched to X profile".
- Global on/off switch, launch at login, and a running "apps hidden in total" counter.

Refocus also imports the original's settings: the Core Data store in
`~/Library/Application Support/com.uglyapps.HocusFocus/HocusFocus.db` and the `com.uglyapps.HocusFocus` defaults. This happens automatically on first launch, and later from Settings → General.

## How it works

- `NSWorkspace` activation notifications track when each app was last in front. A 1 s timer hides apps whose time is up with `NSRunningApplication.hide()`. This **needs no Accessibility permission**.
- Only apps with a visible window on the current Space count down (`CGWindowListCopyWindowInfo`; owner PIDs need no Screen Recording permission).
- The hotkey uses Carbon `RegisterEventHotKey`, so it needs no Input Monitoring permission.
- Settings are stored as JSON in `~/Library/Application Support/Refocus/config.json`.

## Build

```bash
./build-app.sh
open build/Refocus.app
```

The app icon is drawn in code (`Icon/make-icon.swift`). After editing it, run `Icon/build-icns.sh` to regenerate `Resources/AppIcon.icns`.

Requires Xcode 16+ and macOS 14+. Quit Hocus Focus first so the two don't compete.

## License

MIT, see [LICENSE](LICENSE). Refocus is an independent project and is not affiliated with UglyApps or Hocus Focus.
