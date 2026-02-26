# WhisperBar 🎙️

A lightweight macOS menu bar app that transcribes your voice **entirely offline** using Apple's [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML-optimised Whisper). Press a hotkey, speak, press again — your words are pasted instantly into whatever app you were using.

---

## Features

| | |
|---|---|
| 🔴 **On-demand recording** | Press a global hotkey to start recording; press again to stop |
| 🌊 **Live waveform widget** | A floating glassmorphic card appears on screen with animated bars that react to your voice in real time |
| ✂️ **Auto-paste** | Transcribed text is pasted directly into the previously active app via Cmd+V simulation |
| ⌨️ **Configurable hotkeys** | Set any key combo for Toggle mode and Push-to-Talk mode via an in-app key recorder |
| 🔁 **Two recording modes** | **Toggle** (press once/twice) or **Push-to-Talk** (hold key while speaking) |
| 📴 **100% offline** | Model downloads once from HuggingFace, then runs locally on your Mac forever |
| ⚡️ **Apple Silicon optimised** | Uses CoreML + Neural Engine via WhisperKit for fast transcription |
| 🗂️ **Model selection** | Choose from Tiny (39 MB) → Medium (769 MB) depending on your speed/accuracy needs |

---

## Screenshots

> Menu bar icon · Popover · Floating waveform widget

```
┌─────────────────────────────────────────────────────────┐
│  Menu Bar:  [🎤]  ← pulsing red dot while recording     │
└─────────────────────────────────────────────────────────┘

┌──────────────────────────────────────┐
│  WhisperBar                    ⚙     │
│ ──────────────────────────────────── │
│  [ 🔴  Stop Recording         ]      │
│  Global hotkey: ⌘ ⇧ Space           │
│ ──────────────────────────────────── │
│  Last transcription                  │
│  "Hello, this is a test of the…"    │
│                               [Copy] │
│ ──────────────────────────────────── │
│  ✅ Auto-paste                  Quit │
└──────────────────────────────────────┘

     Floating Waveform Widget (on desktop):
┌─────────────────────────────────────────┐
│  🔴 Recording…                        × │
│  ▁▃▅▇▅▃▁▂▄▆▇▆▄▂▁▃▅▇▅▃▁▂▄▆▇▄▂▁▃▅▇      │
│  Press hotkey again or × to stop        │
└─────────────────────────────────────────┘
```

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 13 Ventura or later |
| Swift | 5.9 or later |
| Xcode / Command Line Tools | 15 or later |
| Architecture | Apple Silicon (M1+) recommended; Intel supported |

---

## Installation

### Option 1 — Build from source (recommended)

```bash
# 1. Clone the repo
git clone https://github.com/sabranhameed/WhisperBar.git
cd WhisperBar

# 2. Build and package as a .app bundle
chmod +x build.sh
./build.sh

# 3. Run immediately
open WhisperBar.app

# Optional: install to Applications
cp -r WhisperBar.app /Applications/
```

> **First launch:** WhisperBar downloads the selected Whisper model (~74 MB for `base`) from HuggingFace. After that it works with no internet connection.

### Option 2 — Open in Xcode

```bash
git clone https://github.com/sabranhameed/WhisperBar.git
cd WhisperBar
open Package.swift   # Xcode opens the Swift package
```

Run the `WhisperBar` scheme. Xcode handles dependency resolution automatically.

---

## First-run setup

On the first launch, macOS will ask for two permissions:

1. **Microphone** — required to record your voice
2. **Accessibility** — required for the auto-paste feature (simulates Cmd+V in the target app)

Both can be granted or re-checked at any time via **Settings → Permissions** in the app.

> **Gatekeeper warning?** Because the binary is ad-hoc signed (not notarised), macOS may show an "unidentified developer" warning. Right-click → **Open** to bypass it, or run:
> ```bash
> xattr -d com.apple.quarantine WhisperBar.app
> ```

---

## Usage

### Toggle Mode (default)

| Action | Result |
|---|---|
| Press **⌘ ⇧ Space** | Recording starts, floating widget appears |
| Speak | Waveform animates with your voice |
| Press **⌘ ⇧ Space** again | Recording stops, transcription begins |
| Done | Text is pasted into your previous app |

### Push-to-Talk Mode

| Action | Result |
|---|---|
| Hold **⌘ ⌥ Space** | Recording starts |
| Release | Recording stops and transcription begins |

Switch modes and change both hotkeys in **Settings → Recording Mode / Keyboard Shortcuts**.

### Cancel a recording

- Click the **×** button on the floating widget
- Or press **Escape** at any time

---

## Settings

Open the popover by clicking the menu bar icon, then click ⚙.

| Setting | Description |
|---|---|
| **Whisper Model** | Tiny / Base / Small / Medium — downloaded once, cached locally |
| **Recording Mode** | Toggle or Push-to-Talk |
| **Toggle hotkey** | Configurable — click the button and press your desired key combo |
| **Push-to-talk hotkey** | Configurable — same key recorder |
| **Auto-paste** | Paste transcription into the previously active app automatically |
| **Show floating widget** | Toggle the waveform overlay on/off |
| **Launch at login** | Start WhisperBar automatically when you log in |

---

## Model comparison

| Model | Size | Speed | Accuracy |
|---|---|---|---|
| `tiny` | ~39 MB | ⚡⚡⚡⚡ | ★★☆☆ |
| `base` *(default)* | ~74 MB | ⚡⚡⚡ | ★★★☆ |
| `small` | ~244 MB | ⚡⚡ | ★★★★ |
| `medium` | ~769 MB | ⚡ | ★★★★★ |

Models are cached in `~/Library/Caches` by WhisperKit and reused across launches.

---

## Project structure

```
WhisperBar/
├── Package.swift                    # Swift Package — WhisperKit dependency
├── build.sh                         # Builds release binary + packages .app
└── Sources/WhisperBar/
    ├── main.swift                   # App entry point (NSApplication)
    ├── AppDelegate.swift            # Hides Dock icon, prompts permissions
    ├── AppState.swift               # Observable state + persisted settings
    ├── MenuBarController.swift      # Central coordinator for all services
    ├── AudioRecorder.swift          # 16 kHz WAV recording + real-time levels
    ├── AudioLevelData.swift         # Rolling buffer for waveform visualisation
    ├── FloatingRecordingWindow.swift # Borderless NSPanel + waveform SwiftUI view
    ├── WhisperTranscriber.swift     # WhisperKit wrapper (local inference)
    ├── TextInserter.swift           # Clipboard + CGEvent Cmd+V paste
    ├── HotkeyManager.swift          # Carbon toggle hotkey + NSEvent push-to-talk
    ├── KeyCombo.swift               # Hotkey data model (Codable, display string)
    ├── PopoverView.swift            # Menu bar popover UI
    └── SettingsView.swift           # Settings panel + key recorder component
```

---

## How it works

```
[Hotkey pressed]
      │
      ▼
[AudioRecorder]  ──── 16 kHz WAV ───▶  [WhisperTranscriber]
      │                                        │
      │ onLevel callback (20 Hz)               │ WhisperKit (CoreML)
      ▼                                        │ runs on Neural Engine / GPU
[AudioLevelData]                               │
      │                                        ▼
      ▼                                  Transcribed text
[FloatingRecordingWindow]                      │
  Animated waveform bars                       ▼
                                        [TextInserter]
                                        Sets clipboard + sends ⌘V
                                        to previously focused app
```

---

## Dependencies

| Package | Purpose |
|---|---|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Local Whisper inference via Apple CoreML |

All other functionality uses native Apple frameworks: `AppKit`, `SwiftUI`, `AVFoundation`, `Carbon`, `ServiceManagement`.

---

## License

MIT — do whatever you like with it.

