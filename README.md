# SD Macro Pad

A Mac app for the cheap RGB macro pads sold on Temu and AliExpress that show up on USB as
**SDINNOVATION SIDE-KEYBOARD**.

I bought two: a 6-key with a dial and a 16-key with three dials. As delivered, every key typed
Ctrl+A, the lights ran a rainbow I couldn't change, and the download links in the leaflet were
dead. So I worked out how they talk and wrote my own software.

![SD Macro Pad](docs/screenshot.png)

## What it does

- Remaps every key and dial: shortcuts, media keys, mouse clicks and scrolling, sleep/power.
  Each dial has three actions (press, clockwise, anticlockwise).
- Lighting: off, solid, breathing, light-on-press, tide, or a colour per key.
- Six profiles, each with its own key map.
- Sixteen macros, stored on the pad.
- Tools: diagnostics, key tester, raw command console, firmware backup and flashing.

Settings live on the pad. Set it up once and it works on any machine, with or without the app.

## Download

Latest build is on the [Releases](../../releases) page. Signed and notarised. macOS 13 or later.

## Supported pads

| Pad | USB ID | Status |
|---|---|---|
| 6 keys + 1 dial | `6D80:DC81` | Works. I own one. |
| 16 keys + 3 dials | `6D7D:DCFC` | Works. I own one. |
| 3, 4, 8, 9, 10, 12 and 15-key versions | `6D7B`–`6D83` | Same protocol. Untested. They get a generic layout. |

## Firmware

Both of mine arrived on a factory firmware that nothing can configure, including the vendor's
own tools. The app detects this. The fix is the vendor's v105 firmware, which the app can flash
(Tools ▸ Firmware):

1. Hold the top-left and top-right keys while plugging the pad in. That is bootloader mode.
2. Back up what is on it.
3. Flash the v105 image for your exact model.
4. Replug.

The firmware images are the vendor's, so they are not in this repo. The
[technical reference](docs/TECHNICAL_REFERENCE.md) says where to find them and lists checksums.
The bootloader is never overwritten, so a bad flash can be redone.

## Command line

`sdpad` is built alongside the app:

```bash
sdpad list
sdpad keys
sdpad set 1 cmd+shift+4
sdpad set d1cw media:volup
sdpad light solid --colour "#ff3300"
sdpad colour 3 "#00ffaa"
sdpad macro 1 text "hello"
```

Run `sdpad` with no arguments for the full list.

## Using the pads in your own software

The app and the CLI share a Swift library, `SDPadKit`:

```swift
import SDPadKit

let pad = PadMonitor().settle().pads.first!
try pad.writeKey(.key(0), .key(0x68, [.command]))        // key 1 = Cmd+F13
try pad.writeKey(.knob(0, .clockwise), .consumer(0xE9))   // dial = volume up
try pad.writeKeyColour(0, RGB(hex: "#FF0000")!)
```

For other languages, [docs/TECHNICAL_REFERENCE.md](docs/TECHNICAL_REFERENCE.md) has the protocol:
command bytes, bootloader, macro format, and a hidapi example. Each item is marked as tested on
hardware or read from the vendor's code.

## Building

Needs Xcode's Swift toolchain.

```bash
scripts/build-app.sh
```

Builds `SD Macro Pad.app` and `sdpad` into the project folder. Signs with a Developer ID
certificate if there is one in the keychain. `--notarize` notarises too.

## Credits

[Knurl](https://github.com/dozzenn/knurl) and
[MacroPad](https://github.com/ysalitrynskyi/MacroPad) document the protocol for related pads.
Their notes saved me a lot of guessing.

## Disclaimer

Not affiliated with SDINNOVATION, SDCX or Huali. No warranty. Flashing firmware is at your own
risk. Back the pad up first.

MIT licence. See [LICENSE](LICENSE).
