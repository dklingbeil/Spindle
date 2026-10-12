# Spindle

An illustrated turntable that lives on your Mac desktop as the wallpaper, seen from
straight above so the desktop becomes the desk. It shows what is playing in Spotifast,
Spotify or Apple Music: the record spins, the tonearm tracks the song, the cover lies
beside the deck, and earlier covers pile up on the other side. The desk takes its
colour from the cover. The turntable is also the remote: click and drag it to control
playback.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), which creates the Xcode project from `project.yml`

```bash
brew install xcodegen
```

## Build and run

Generate the Xcode project (repeat this whenever you add files or edit `project.yml`):

```bash
xcodegen generate
```

Then either open `Spindle.xcodeproj` in Xcode and press Run, or build from the terminal:

```bash
xcodebuild -project Spindle.xcodeproj -scheme Spindle -configuration Release -derivedDataPath build build
```

```bash
open build/Build/Products/Release/Spindle.app
```

To keep it, copy `Spindle.app` into `/Applications` and turn on **Launch at Login**
from its menu bar icon.

## Using it

Spindle has no Dock icon. Everything is under the record icon in the menu bar.

| Menu item | What it does |
| --- | --- |
| Play / Pause, Next Track, Previous Track | Controls the active player |
| Show / Hide Turntable | Hides the scene without quitting |
| Display | **Desktop Wallpaper** (behind your icons and windows) or a movable **Window** |
| Scene | **Daylight** (a sunlit desk), **Midnight** (lamplight), or **Turntable Only** (no desk; sits on your own wallpaper) |
| Size, Float Above Windows | Window mode only |
| Launch at Login | Starts Spindle when you log in |

### Controlling playback from the turntable

| Do this | To |
| --- | --- |
| Click the record, the tonearm or the Start · Stop button | Play / pause |
| Drag the tonearm across the record | Seek: outer edge is the start of the track, the label is the end |
| Drag the tonearm off the record | Pause |
| Click the cover on the left | Next track |
| Click the pile of sleeves on the right | Previous track |
| Scroll over the turntable, or drag the fader up and down | Volume |

In wallpaper mode the scene sits behind your desktop icons, where macOS does not
deliver clicks. Spindle instead watches for clicks that land on empty desktop
(no window on top) and treats those as clicks on the scene. Finder still receives
them too, so dragging the tonearm also draws Finder's selection rectangle, and if
*System Settings → Desktop & Dock → Click wallpaper to reveal desktop* is set to
*Always*, clicking the turntable also moves your windows aside.

## Supported players

| Player | How Spindle follows it | How Spindle controls it |
| --- | --- | --- |
| Spotifast | Polls its command-line remote once a second | The same command-line remote |
| Spotify | System playback notifications | AppleScript |
| Apple Music | System playback notifications | AppleScript |

- No login is needed for any of them.
- Spotify and Apple Music only announce themselves when playback changes, so
  nothing shows until you next play, pause or skip. Spotifast shows up straight away.
- The first time you control Spotify or Apple Music, macOS asks whether Spindle may
  control that app. Following along needs no permission.
- Covers come from the player when it supplies one (Spotifast), otherwise from
  Spotify's public oEmbed endpoint or the iTunes Search API. That lookup sends the
  track ID, or the artist and album name, to Spotify or Apple.

## Making it your own

| File | What is in it |
| --- | --- |
| `project.yml` | App name, bundle identifier, version |
| `Sources/Plan.swift` | Where everything sits on the desk, in millimetres, and what counts as a click on each part |
| `Sources/Illustration.swift` | The artwork, drawn in code: deck, record, tonearm, sleeves, sunlight, default cover |
| `Sources/Palette.swift` | Picking the desk's colours from the cover |
| `Sources/Stage.swift` | The layers the artwork lives in and how they move: spin, arm, sleeves sliding to the pile |
| `Sources/SceneView.swift` | Pointer handling: what clicking and dragging each part does |
| `Sources/Player.swift` | Talking to Spotifast, Spotify and Apple Music |
| `Sources/SpindleApp.swift` | Menu bar, the wallpaper window, desktop click forwarding |
| `Scripts/make-icon.swift` | Draws the app icon |

Everything is drawn in millimetres measured from the centre of the deck, so the
artwork stays sharp at any size. The deck's colours are at the top of
`Illustration.swift`; how light or vivid the desk gets is in `Palette.swift`.

To change the app icon, edit `Scripts/make-icon.swift` and run it from the repository root:

```bash
swift Scripts/make-icon.swift
```

## Limitations

- Wallpaper mode uses the main display only.
- Apple Music does not report playback position, so the tonearm assumes each track
  starts from the beginning.
- The app is not sandboxed or notarised; it is set up for running on your own Mac.
