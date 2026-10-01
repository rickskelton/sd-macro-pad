# SDINNOVATION "SIDE-KEYBOARD" macro pads: technical reference

Everything I worked out about these pads, written down so they can be driven from any program:
USB identity, the configuration protocol, the bootloader, firmware, and recovery. It comes from
poking at my own two pads over 30 September – 1 October 2026.

Each fact is marked with how it is known:

- **[tested]** I saw it happen on the real hardware.
- **[vendor code]** read out of the vendor's configuration app; I haven't exercised it.
- **[other projects]** reported by the open-source Knurl / MacroPad projects; I haven't reproduced it.

## 1. The two pads

| | 6-key | 16-key |
|---|---|---|
| Controls | 6 keys (3 × 2), 1 dial with push | 16 keys (4 × 4), 3 dials with push |
| USB ID | `6D80:DC81` | `6D7D:DCFC` |
| USB strings | manufacturer `SDINNOVATION`, product `SIDE-KEYBOARD`, serial `2022-12-01` | same |
| LEDs | one RGB LED per key | one RGB LED per key |
| MCU family (vendor name) | `951` | `951` |
| Flash | 32 KB: bootloader `0x0000–0x0FFF`, application `0x1000–0x7FFF` | same |
| Firmware now | v105 (was factory) | v105 (was factory) |

I bought both on Temu. The same vendor (also trading as SDCX / Huali / "SD-TECH") sells
3-, 4-, 8-, 9-, 10-, 12- and 15-key siblings that use the same protocol; section 9 lists their IDs.

### Control numbering (key table index)

Keys are numbered row by row from the top-left. Each dial owns three consecutive slots.

```
6-key                      16-key
 0  1  2     dial 1         0  1  2  3     dial 1: 16 press, 17 cw, 18 ccw
 3  4  5     16 press       4  5  6  7     dial 2: 19 press, 20 cw, 21 ccw
             17 clockwise   8  9 10 11     dial 3: 22 press, 23 cw, 24 ccw
             18 anticlock. 12 13 14 15
```

- 6-key key order and dial slots: **[tested]** on v105 (keys typed a–f in order; press, clockwise,
  anticlockwise typed g, h, i).
- 16-key order: **[vendor code]** (the vendor's layout file). Not yet pressed-through on v105.
  Which physical dial is "dial 1" is also from the vendor layout only.
- Per-key colour index equals key index: **[tested]** on the 6-key.

## 2. Firmware generations

The pads shipped with a **factory firmware** that neither the vendor's tools nor the open-source
tools can configure. Flashing the vendor's **v105** image fixes that.

| | Factory firmware | v105 |
|---|---|---|
| USB interfaces | 2 | 3 |
| Configuration channel | 31-byte reports, report ID 2, inside interface 0 (section 10) | 64-byte reports on its own interface (section 4) |
| Seen by vendor app / sdcx-tech.com / Knurl | no | yes |
| Remapping | works, raw 3-byte entries | works, full feature set |
| Lighting | brightness only; colours locked | effects, colour, per-key colours |
| Macros | none found | work |
| Profiles | none found | 6 |

How to tell which a pad runs: v105 exposes a HID interface with usage page `0xFF00`, usage `2`
and 64-byte reports. The factory firmware does not. `sdpad list` reports either state.

## 3. USB interfaces on v105 **[tested]**

| Interface | Purpose | Reports |
|---|---|---|
| 0 | Composite input | ID 1: N-key keyboard (modifier byte + key bitmap, 15 bytes with ID). ID 2: mouse. ID 3: consumer. ID 4: system control. ID 5: radio-control bits. |
| 1 | Boot keyboard | No report ID, 8 bytes: `[modifiers, 0, key1 … key6]` |
| 2 | **Configuration** | No report ID, 64 bytes in and out. Usage page `0xFF00`, usage `2`. |

What the pad sends when used, as captured:

| Action | Interface / report | Example |
|---|---|---|
| Keystroke | interface 1 | `02 00 68 00 00 00 00 00` (Shift + F13), then all zeros on release |
| Mouse wheel | interface 0, ID 2 | `02 00 00 00 00 00 01 00` = `[id, buttons, x lo, x hi, y lo, y hi, wheel, pan]` |
| Media key | interface 0, ID 3 | `03 E2 00` (mute), then `03 00 00`. Usage is 16-bit little-endian. |

On the factory firmware the consumer report had ID 4, and the mouse ID 3.

## 4. Configuration protocol (v105)

### Framing **[tested]**

- Host sends a 64-byte output report (report ID 0) on interface 2. Byte 0 is `06`, byte 1 the
  command, then arguments, zero-padded.
- The pad answers every frame with a 64-byte input report: `AA <command> …`.
  The key-table read `08` is answered as `AA 07`.
- **Read the answer before sending the next frame.** Other projects report that a pad which is
  written to without being read stops accepting frames until it is replugged **[other projects]**.
  All code here waits for each answer.
- With hidapi, prepend a `00` report-ID byte to each write (65 bytes on the wire to the library).
- Offsets and lengths are little-endian unless stated.
- **Never send frames starting `5A` or `55 FF` on this channel** unless you mean to enter the
  firmware updater (section 6).
- The pad can also push unsolicited frames starting `AA FA` (lighting status) **[vendor code]**.
  Match answers on the command byte and ignore the rest.

### Command summary

| Frame (after `06`) | Meaning | Status |
|---|---|---|
| `05` | Read device info | tested |
| `08 3A <off lo> <off hi> 00 <layer>` | Read 56 bytes of the key table | tested |
| `10 07 <off lo> <off hi> 00 <layer> 00 <type> <c1> <c2> <c3>` | Write one key entry, offset = 4 × index | tested |
| `09 <len+3> <off lo> <off hi> 00 <layer> 00 <data ≤ 56>` | Write a block of key entries | vendor code |
| `0A` | Read lighting | tested |
| `0B 0B 00 00 <11 bytes>` | Write lighting | tested |
| `13 3A <off lo> <off hi>` | Read 56 bytes of per-key colours | tested |
| `14 03 <off lo> <off hi> 00 00 00 <R> <G> <B>` | Write one key colour, offset = 3 × index | tested |
| `12 <len+3> <off lo> <off hi> 00 00 00 <data ≤ 56>` | Write a block of key colours | vendor code |
| `0C <len ≤ 56> <off lo> <off hi>` | Read macro table bytes | tested |
| `0D <len ≤ 59> <off lo> <off hi> <data>` | Write macro table bytes | tested |
| `FB <n>` | Select profile `n` (0-based) | tested |
| `16 00 00 00 01 00 <mode>` | Read the lighting block as it would be for `mode` | vendor code |
| `FC 02 00 00 <lo> <hi>` | Auto-sleep seconds (wireless models) | vendor code |
| `0F 04` | Erase all macros | vendor code |
| `0F FF` | **Factory reset** | vendor code, never sent here |

### Device info: `06 05` **[tested]**

Answer `AA 05 <len> 00 00 <data>`; data starts at byte 5:

| Data byte | Field | 6-key value |
|---|---|---|
| 0–1 | protocol version | 1 |
| 2–3 | product ID | `DC81` |
| 4–5 | firmware version | 105 (`69 00`) |
| 6, 7, 8, 9 | work mode, link status, battery, charging (wireless models) | 0, 1, 100, 0 |
| 10 | profile count | 6 |
| 11 | active profile, 0-based | 0 |
| 12 | layer count | 1 |
| 13 | layer | 1 |

### Key table

4 bytes per entry, `[type, code1, code2, code3]`, at offset `4 × index`. Buttons use indices
0–15 and dials start at 16 (section 1), on every model. Each profile has its own table
**[tested]**: profile 1 holds the test mappings, profile 2 still held its default.

| Type | Meaning | code1 | code2 | code3 | Status |
|---|---|---|---|---|---|
| `20` | Keystroke | HID modifier mask | HID keyboard usage (0 = modifiers only) | 0 | tested |
| `30` | Consumer (media) key | usage low byte | usage high byte | 0 | tested |
| `10` | Mouse | button mask: 1 left, 2 right, 4 middle, 8 back, 16 forward | 0 | wheel steps, signed (`01` up, `FF` down) | wheel tested; buttons vendor code |
| `60` | Run macro | macro index 0–15 | repeat count | mode: 0 play `count` times, 1 loop while held, 2 loop until any key, 3 loop until pressed again | mode 0 tested; other modes vendor code |
| `13` | Disabled | 0 | 0 | 0 | tested (factory default for unused slots) |
| `40` | System control | 1 power, 2 sleep, 4 wake | 0 | 0 | vendor code |
| `1F` | Pad function (lighting keys, profile switch…) | function number | 0 | 0 | see below |
| `11` | Mouse move | | | | vendor code |
| `70` | Wheel (alternative encoding) | `01` up, `FF` down | | | vendor code |
| `80` | Open a website | | | | other projects |
| `FF` | Custom key combination | | | | vendor code |

Modifier mask: `01` Ctrl, `02` Shift, `04` Alt/Option, `08` GUI/Command, `10`–`80` the
right-hand versions.

Pad functions (`1F`) listed by the vendor: 0 lights on/off, 1 brightness +, 2 brightness −,
3 next effect, 4 next colour, 5 speed +, 6 speed −, 19 switch profile, 20 light direction,
25 lock keyboard. **Functions 2 and 3 were assigned to keys on the 6-key and pressed: nothing
visibly happened** (the pad was in per-key colour mode at the time) **[tested]**. Treat `1F`
as unreliable on these two models until shown otherwise. The app does not offer it.

Default tables after flashing v105:

- 6-key: every key `20 01 04 00` (Ctrl+A) in profile 1, `20 01 06 00` (Ctrl+C) in profile 2;
  dial press mute `30 E2`, clockwise volume up `30 E9`, anticlockwise volume down `30 EA`.
- 16-key: number-pad keys (`5F 60 61 56 / 5C 5D 5E 57 / 59 5A 5B 54 / 55 62 63 58`); dial 1
  = Num Lock, Backspace, Space; dials 2 and 3 = mute, volume up, volume down.

### Lighting: `06 0A` / `06 0B`

Read answer: `AA 0A 0B 00 00 <type> 00 <mode> <brightness> <speed> <direction> <colour flag> <colour index> <H> <S> <V>`.

Write: `06 0B 0B 00 00 <type> 00 <mode> <brightness> <speed> <direction> <colour flag> 00 <H> <S> <V>`.

| Field | Values |
|---|---|
| type | 1 on both pads |
| mode | 0 off, 1 solid, 2 breathing, 3 light on key press, 4 tide (default), 5 per-key colours |
| brightness | 0–4 |
| speed | 0–4. Other projects report erratic behaviour at 5. |
| colour flag | 0 = cycle the built-in palette, 1 = use H/S/V. Send 0 when mode is 0. Tide (mode 4) ignores it and always runs the palette **[tested]**. |
| H, S, V | 0–255 each (hue 0 = red, 85 = green, 170 = blue) |

Status: solid red on the 16-key **[tested]**; per-key mode on the 6-key **[tested]**; tide is
the running default **[tested]**. Whether the brightness and speed bytes visibly change
anything on v105 has **not** been checked by eye; other projects found the brightness byte had
no visible effect on the 3-key sibling and dimmed through V instead.

### Per-key colours: `06 13` / `06 14` **[tested]**

Three bytes per key, `R G B`, at offset `3 × index`. They are displayed only in mode 5.
Default is green (`00 FF 00`) for every key. Verified on the 6-key with six different colours.

### Macros: `06 0C` / `06 0D` **[tested]**

One 4096-byte table, shared by all profiles.

- Bytes 0–63: one little-endian 16-bit start offset per macro; `FF FF` means empty. The vendor
  app uses 16 macros.
- From byte 64: actions, 4 bytes each: `[delay lo, delay hi, flags, code]`. Delay is
  milliseconds before the action.
- Flags: bits 0–2 kind (2 key, 3 mouse button, 4 vertical wheel, 5 horizontal wheel);
  bit 6 (`40`) press, clear for release; bit 7 (`80`) last action of this macro.
- Code: HID keyboard usage (modifiers are their own key usages `E0`–`E7`), mouse button mask,
  or wheel delta (`01` / `FF`).

Tested: a macro of `0A 00 42 0B`, `0A 00 02 0B`, `0A 00 42 0C`, `0A 00 82 0C` at offset 64,
assigned with key entry `60 00 01 00`, typed "hi". The vendor app rewrites the whole table on
every save; writing only the used part also works.

### Profiles: `06 FB <n>` **[tested]**

Six profiles. Selecting one changes the active key table at once and is reported by `06 05`.
Lighting and key colours read the same in profiles 1 and 2; whether they are stored per profile
was not determined.

On a profile change the pad blinks key 1 white, once per profile number (firmware behaviour).
Key 1's LED was then seen to stay dark in per-key mode. The app re-sends the lighting block
after the blinking ends; whether that is what restores the LED was not confirmed.

### Persistence and wear

Settings are stored in the pad's flash and need no host software afterwards. On the factory
firmware, settings survived a replug **[tested]**. On v105 this is expected but was not
separately confirmed by replugging after a change.

Every write is a flash write. Do not animate LEDs by streaming colour writes; flash endurance
on this class of MCU is limited (typically tens of thousands of cycles), and nothing here
found a way to set LEDs without writing flash.

## 5. Bootloader **[tested]**

- Enter: hold the **top-left and top-right keys while plugging in**. The pad enumerates as
  USB `5566:0009`, manufacturer `ZXWMicroChip`, product `Bootloader`, one HID interface
  (usage page 1, usage 0) with 64-byte reports, no report ID.
- Leave: unplug and plug back in without holding keys. After a flash the pad stays in the
  bootloader until replugged.
- The vendor app enters it from the configuration channel with `55 FF 00 00` **[vendor code]**.
- The bootloader region is never written by the vendor's updater or by this project, so a bad
  application image is always recoverable through the key combination. I ended up there four
  times and it recovered every time.

| Frame | Meaning | Answer |
|---|---|---|
| `55 FF 01 00` | Connect | `AA FF 01 0A 02 6F 80 00 00 80 10 00 7F FF` |
| `55 FF 02 04 <addr hi> <addr lo> <len hi> <len lo>` | Begin write | `AA FF 02 01 01 …` |
| raw 64-byte frames | Data, in order, no answer per frame | none |
| `55 FF 04 00` | Checksum | `AA FF 04 02 <sum hi> <sum lo>`: 16-bit sum of all bytes written |
| `55 FF 05 01 01` | End update | `AA FF 05 01 01` |
| `55 FF 03 04 <addr hi> <addr lo> <len hi> <len lo>` | **Read flash** | header `AA FF 03 04 …`, then raw 64-byte frames |

Addresses and lengths here are **big-endian**. The read command is not used by the vendor app;
I found it by trying the missing command number. It reads the whole 32 KB including the
bootloader itself, which is what made a backup of the factory firmware possible.

The vendor's updater writes `0x7000` bytes at address `0x1000` (the application area), taken
from offset `0x1000` of the 32 KB image file.

## 6. Firmware files

The firmware images belong to the vendor, so they are **not in this repository**. They ship
inside the vendor's Electron app "SDTech Option" 1.0.3 (`Contents/Resources/app.asar`, folder
`src/`, mapped to USB IDs by `src/update.json`) and are served by the vendor's web
configurators at www.sdcx-tech.com and www.huali-tech.com. The ones I used:

| File | SHA-256 | Notes |
|---|---|---|
| `6key_v105.bin` | `2dfbd25aee719b13136d3bb3986778d089d8857f32627f5aa7813d1140bca991` | For `6D80:DC81`. Running on my 6-key. |
| `16key_v105.bin` | `2552c187c0a4ec55787bf8ff8699dbed1834609119487318f97031f3ccb2e6ef` | For `6D7D:DCFC`. Running on my 16-key. |
| `16key_v101.bin` | `d812f0aa0b84c52b8c6ab3427304c99fea856d59d262b6988ca9d1d5bec18131` | Older image for the 16-key. Never run here. |

Each image is exactly 32,768 bytes. The v105 files leave the bootloader area blank (`FF`),
which is fine because only the application area is ever written.

**Back up your pad before flashing it** (section 7). I have a full dump of my 6-key's factory
flash, taken before anything was written to it. I do not have one for the 16-key: I overwrote
its factory firmware before I had found the bootloader's read command, and it is gone.

A trick that got the 16-key back on its feet while its proper image would not run: the 6-key's
factory dump with the USB ID patched to `6D7D:DCFC` (the four bytes `80 6D 81 DC` at `0x1388`).
It boots on the 16-key board but only drives 6 keys, 6 LEDs and one dial. Useful as proof a
board is alive, nothing more.

### Pitfall: extracting from `app.asar`

File data in an asar archive starts at `8 + <second 32-bit header field>`, not
`8 + <third field>`. Getting this wrong shifts every extracted file by 4 bytes. I got it wrong
the first time, flashed three misaligned images to the 16-key, and none of them ran. A
correctly extracted image has `xx DF 08 F0 FF FF FF FF` at file offset `0x1000`, and the v105
images have `FF` throughout `0x0004–0x0FFF`. `sdpad firmware id <file>` finds the USB ID inside
an image and fails on a misaligned one.

## 7. Updating or restoring firmware

```bash
./sdpad firmware id 6key_v105.bin        # which model an image is for
./sdpad firmware dump backup.bin         # pad must be in bootloader mode
./sdpad firmware flash 6key_v105.bin     # pad must be in bootloader mode
```

1. Unplug other SD pads, or at least make sure only one is in bootloader mode.
2. Hold top-left + top-right, plug in, release. `sdpad list` should say a pad is in bootloader mode.
3. `sdpad firmware dump <file>` to keep a copy of what is on it.
4. `sdpad firmware flash <image>`. It saves a second backup to the temp folder, refuses an image
   whose USB ID differs from the pad's current firmware (override with `--force`), writes,
   and compares the bootloader's checksum with the image.
5. Replug without holding keys.

If a pad does not come up after a flash (no lights, not on USB): repeat from step 2 with a
known-good image. The key combination is handled by the bootloader and does not depend on
the application.

To go back to the firmware a pad came with, flash the dump you took in step 3.

## 8. Using the pads from another program

Three levels, simplest first.

**A. Let the pad be a keyboard.** Program keys to shortcuts nothing else uses (F13–F24, or
combinations with Ctrl+Option+Shift+Cmd) and register those as global hotkeys in your program.
No USB code, works on every OS, survives without any helper running.

**B. Read the pad's HID reports directly**, when the program must tell the pad apart from the
main keyboard or see dial turns as events. Open the HID interfaces of `6D80:DC81` /
`6D7D:DCFC` and parse the reports in section 3. On macOS this needs the Input Monitoring
permission, and the keystrokes still reach the focused app unless the keys are programmed to
something harmless (F13–F24) or the device is seized (`kIOHIDOptionsTypeSeizeDevice`).
`PadListener` in `SDPadKit` does the reading; `sdpad listen` shows the raw reports.

**C. Drive the configuration channel** to remap keys or use the LEDs as status lights.
Remember each change is a flash write (section 4, "Persistence and wear").

### Swift, with the library in this repository

```swift
import SDPadKit

let pad = PadMonitor().settle().pads.first!          // keeps working after the monitor is gone
try pad.writeKey(.key(0), .key(0x68, [.command]))     // key 1 = Cmd+F13
try pad.writeKey(.knob(0, .clockwise), .consumer(0xE9))
try pad.writeKeyColour(0, RGB(hex: "#FF0000")!)
var light = try pad.readLight()
light.mode = LightEffect.perKey.rawValue
try pad.writeLight(light)
```

Add the package as a dependency
(`.package(url: "https://github.com/rickskelton/sd-macro-pad", branch: "main")`, product `SDPadKit`).
`Pad` methods block until the pad answers, so call them off the main thread in a UI. For hot-plug,
keep a `PadMonitor` and set `onChange`.

### Any language, with hidapi

```python
import hid
dev = hid.device()
path = next(d["path"] for d in hid.enumerate(0x6D80, 0xDC81)
            if d["usage_page"] == 0xFF00 and d["usage"] == 2)
dev.open_path(path)

def request(*payload):
    frame = [0x00, 0x06, *payload]                 # 00 = report ID for hidapi
    dev.write(frame + [0] * (65 - len(frame)))
    while True:
        reply = dev.read(64, 1500)
        if not reply:
            raise TimeoutError
        if reply[0] == 0xAA and reply[1] == (0x07 if payload[0] == 0x08 else payload[0]):
            return reply

info = request(0x05)                                # firmware = info[9] | info[10] << 8
request(0x10, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x08, 0x68, 0x00)   # key 1 = Cmd+F13
request(0x14, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00)         # key 1 LED red
```

The Python example follows the frames I verified with the Swift tools; I have not run it as written.
On Windows the configuration interface is the HID collection with usage page `FF00`; on Linux
a udev rule is needed for non-root access.

## 9. Sibling models

From the vendor's `update.json`. Same protocol family; I have only tested the two pads above.

| USB ID | Model | Vendor image |
|---|---|---|
| `6D7B:DCFA` | 3 keys | `3key_v105.bin` |
| `6D7C:DCFB` | 4 keys | `4key_v105.bin` |
| `6D80:DC81` | 6 keys | `6key_v105.bin` |
| `6D81:DC82` | 8 keys | `8key_v105.bin` |
| `6D7F:DCFE` | 9 keys | `9key_v105.bin` |
| `6D82:DC83` | 10 keys | `10key_v105.bin` |
| `6D83:DC84` | 12 keys | `12key_v105.bin` |
| `6D7E:DCFD` | 15 keys | `15key_v105.bin` |
| `6D7D:DCFC` | 16 keys | `16key_v105.bin` |
| `0816:246D–2475` | The same boards sold under the "SD" ID | `…sd_v105.bin` (identical except for the USB ID) |

The `…sd` images differ from the plain ones in 6 bytes: the USB vendor/product ID.

## 10. Factory-firmware protocol (legacy)

Only relevant to a pad that has not been updated. I worked this out by probing before I had the
v105 image; it is superseded by v105.

- Channel: interface 0, report ID 2, 31 data bytes each way (usage page `FF00`, usage 1).
  Byte 0 is the command. The vendor's `06 …` commands are all answered `01 08` (rejected).
- Reads: `01` version; `03` lighting (10 bytes); `07` returns `02 58` (600, probably a sleep
  timer); `02 00 04 00 00 <len hi> <len lo>` streams the key map; `04 00 04 00 00 <len hi> <len lo>`
  streams the per-key colour table. The streamed reads are raw windows into flash (key map at
  `0x7780`, colours at `0x7600`) and run on into firmware code if the length is too large.
- Writes use the read command plus `0x80`: `82 00 04 00 00 <len hi> <len lo>` followed by raw
  31-byte data frames, each acknowledged `82 00 01 01`. **The pad then treats every frame as
  data until the announced length has arrived**; a wrong length leaves it stuck until replugged.
  `83 00 0A <10 bytes>` writes lighting; `84 …` writes colours.
- Key entries are 3 bytes `[type, a, b]`: `02` keystroke `[mods, usage]`, `03` consumer
  `[usage lo, usage hi]`, `04` mouse buttons, `05` system control, `01` a bare key usage.
  Slot order matches section 1 (keys 0–14, then dial slots from 15: press, …).
- Lighting: byte 1 is brightness and takes effect live. The effect, speed and direction bytes
  are stored but changed nothing visible. Bytes 4–9 (`00 FF 00 FF 00 FF`) reject changes.
  The stored colour table was not displayed in any mode found.
- Commands `0x09–0x3F` and most of `0x40–0xFF` answer `FF FF` (unknown). `0x55` and `0x5A`
  were never sent.

## 11. What is in this repository

| Path | Contents |
|---|---|
| `Sources/SDPadKit` | The library: `Pad`, `PadMonitor`, `Bootloader`, `PadListener`, models, macro codec |
| `Sources/sdpad` | The command-line tool (run `sdpad` for help) |
| `Sources/SDPadApp` | The Mac app: remapping, lighting, profiles, macros, plus a Tools window (diagnostics dump, key test, raw console, firmware backup and flashing) and built-in Help |
| `scripts/build-app.sh` | Builds `SD Macro Pad.app` and `sdpad` (needs Xcode's Swift toolchain). Signs with a Developer ID certificate if one is in the keychain; `--notarize` also notarises and staples. |
| `scripts/make-icon.swift` | Draws the app icon into `Resources/AppIcon.icns` |

A signed, notarised build of the app is on the Releases page.

## 12. Open questions

- 16-key on v105: confirm key order and which dial is 1, 2, 3 by pressing through them.
- Whether brightness and speed visibly work on v105, and whether lighting is per profile.
- Whether settings written on v105 survive a replug (expected, not confirmed).
- Pad functions (`1F`): no effect seen; untested outside per-key mode.
- Key 1's LED staying dark after a profile switch, and whether re-sending lighting cures it.
- Mouse buttons, system keys, macro loop modes, website and "custom combination" entries.
- Entering the bootloader by command (`55 FF 00 00`) instead of the key combination.
- Whether LEDs can be set without a flash write.

## 13. Sources

- Vendor app "SDTech Option" 1.0.3 (Electron) and its bundled firmware.
- Vendor web configurators: https://www.sdcx-tech.com and https://www.huali-tech.com
- Knurl (macOS, MIT): https://github.com/dozzenn/knurl
- MacroPad fork with WebHub support (Windows, GPL-3.0): https://github.com/ysalitrynskyi/MacroPad
