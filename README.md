# Spindle

A 3D turntable that lives on your Mac desktop as the wallpaper. It shows what is
playing in Spotifast, Spotify or Apple Music: the record spins, the tonearm tracks
the song, the cover sits on a stand, and earlier covers pile up beside the deck.
The turntable is also the remote: click and drag it to control playback.

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
| Scene | **Daylight**, **Midnight**, or **Turntable Only** (no room; sits on your own wallpaper) |
| Size, Float Above Windows | Window mode only |
| Launch at Login | Starts Spindle when you log in |

### Controlling playback from the turntable

| Do this | To |
| --- | --- |
| Click the record or the tonearm | Play / pause |
| Drag the tonearm across the record | Seek: outer edge is the start of the track, the label is the end |
| Drag the tonearm off the record | Pause |
| Click the cover on the stand | Next track |
| Click the pile of sleeves | Previous track |
| Scroll over the turntable, or drag the knob up and down | Volume |

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
| `Sources/TurntableScene.swift` | The 3D model: every part of the deck, the room, lights and camera |
| `Sources/Lathe.swift` | Helper that turns a 2D profile into a round part (platter, knob, lamp) |
| `Sources/Textures.swift` | Textures drawn in code: record grooves, window blinds, default cover |
| `Sources/Resources/` | Photo-scanned wood and plaster textures and the lighting image |
| `Sources/SceneView.swift` | Pointer handling: what clicking and dragging each part does |
| `Sources/Player.swift` | Talking to Spotifast, Spotify and Apple Music |
| `Sources/SpindleApp.swift` | Menu bar, the wallpaper window, desktop click forwarding |
| `Scripts/make-icon.swift` | Draws the app icon |

The model is in centimetres with the desk surface at height 0. To swap a material,
drop another texture set into `Sources/Resources/` (files named `<name>_diff.jpg`,
`<name>_nor.jpg`, `<name>_rough.jpg`) and change the name passed to `scanned(...)`.

To change the app icon, edit `Scripts/make-icon.swift` and run it from the repository root:

```bash
swift Scripts/make-icon.swift
```

## Limitations

- Wallpaper mode uses the main display only.
- Apple Music does not report playback position, so the tonearm assumes each track
  starts from the beginning.
- The app is not sandboxed or notarised; it is set up for running on your own Mac.

## Credits

Textures and the lighting image are from [Poly Haven](https://polyhaven.com), released
under CC0 (public domain): `wood_table_001`, `oak_veneer_01`, `beige_wall_001`
and the HDRI `brown_photostudio_02`.
