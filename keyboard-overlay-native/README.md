# Keyboard Overlay (native)

A transparent, click-through, always-on-top overlay that shows a keyboard, arrow
keys and left/right mouse buttons, and highlights them live as you press
them — useful for streaming or recording tutorials.

Native Swift/AppKit app (a `WKWebView` hosting the visual layer, driven by
Apple's own `NSEvent.addGlobalMonitorForEvents` for global key/mouse
capture). Unlike the earlier Electron version, this doesn't bundle any
third-party global-hook library, so it isn't flagged by XProtect.

## Build & install

```
./build.sh && ./install.sh
```

`build.sh` produces `build/Keyboard Overlay.app`, ad-hoc signed (no paid
Apple Developer ID needed for local use). `install.sh` quits any running
copy, replaces `/Applications/Keyboard Overlay.app`, and clears the
quarantine flag — always use it rather than moving the built app over by
hand. Skipping it (e.g. just dragging the `.app` into `/Applications` in
Finder, or launching straight from wherever it was unzipped) can leave the
app under App Translocation: macOS runs it from a randomized read-only path
on every launch, which silently breaks permission grants (Accessibility/
Input Monitoring never stick — same symptom as not having granted them at
all) and can leave clicks in the app behaving inconsistently.

Since the app is ad-hoc signed rather than notarized/Developer-ID signed,
**every rebuild changes its identity from TCC's point of view** — a prior
Accessibility/Input Monitoring grant does not carry over to a new build. In
System Settings → Privacy & Security, remove the old "Keyboard Overlay"
entries after each rebuild so you get a clean, single, working grant rather
than a stale one sitting next to it.

## Run

Launch `/Applications/Keyboard Overlay.app` (after `./install.sh`) by
double-click. It needs:
- **Accessibility** (System Settings → Privacy & Security → Accessibility)
  — this is what `NSEvent`'s global key monitor actually checks.
- **Input Monitoring** (same pane) — belt-and-suspenders; some macOS
  versions also gate on this.

Until both are granted for *this exact build*, the overlay still appears
but nothing lights up.

## Usage

- Click-through by default — never blocks the app/game underneath.
- Small drag-handle + red quit-circle docked in the overlay's top-left
  corner: drag the bar to move the whole overlay, click the circle to quit.
- Menu bar item (⌨) as a backup: **Move / Resize Overlay**, **Reset
  Position**, **Quit**.

## Extending

Keys are matched by the macOS virtual keycode table in `Sources/main.swift`
(`keyCodeToName`) against `data-key` attributes in `Resources/index.html`.
To add a key: find its keycode (see Apple's `Carbon HIToolbox/Events.h`
`kVK_*` constants), add it to the map, and add a matching
`.key[data-key="..."]` element in the HTML.
