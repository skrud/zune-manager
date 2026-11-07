# Zune Manager

A native macOS app for managing the music on a Microsoft Zune 30, no Windows needed.
You can browse what's on it, add MP3s from your Mac, delete songs, albums or artists, and
copy songs back to your Mac.

> [!WARNING]
> **Vibe-coded and experimental.** Almost all of this code was written by an AI coding
> agent (Claude Code), with a human steering, deciding and testing on a real device. It
> has a good unit-test suite and has been checked end to end on **one** Zune 30
> (firmware 3.30) on an Apple Silicon Mac running macOS 26, and nowhere else. It writes
> to and deletes from your Zune. **Back up anything you care about first**, and expect
> rough edges.
>
> It's also built on a **forked libmtp** (see below). The stock libmtp from Homebrew
> won't work.

## What it does

- **Browse**: a column browser (Artists → Albums → Songs), album covers read from the
  Zune, live search, and a free-space bar.
- **Add**: pick MP3 files or folders, or drag them in. The app reads tags and cover art
  (embedded, or a `cover.jpg` / `folder.jpg` next to the song) and files each song under
  the right album on the Zune. If songs are already there, you choose Skip or Overwrite.
  If there isn't room, nothing is copied.
- **Delete**: songs, albums or artists, after a confirmation. Album entries left empty
  are removed too.
- **Save to Mac**: copies songs off the Zune as `Artist/Album/NN Title.mp3`.
- **Careful with the device**: every copy and delete is checked with the Zune before it's
  reported as done. Only one thing talks to the Zune at a time, and never on the UI
  thread. Cancelling happens between files, and quitting waits for the current file to
  finish.

Music only for now. The Zune also plays video, but the app doesn't handle it yet.

## The forked libmtp

The Zune won't transfer files until a computer completes Microsoft's **MTPZ** handshake.
[libmtp](https://github.com/libmtp/libmtp) can do the handshake, but on macOS with a Zune
30 a few more things were needed. They live on the
[`zune-mtpz` branch of skrud/libmtp](https://github.com/skrud/libmtp/tree/zune-mtpz)
(also saved here as `third_party/libmtp-zune.patch`):

- **Bulk metadata request:** the Zune (045e:0710) is flagged
  `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL`. After the MTPZ handshake, asking it for
  every object's metadata at once stalls it until it's soft-reset.
- **`LIBMTP_Object_Exists_On_Device()`:** asks the device itself whether an object exists.
  `LIBMTP_Track_Exists()` answers from libmtp's cache, so it can't confirm that a copy or
  delete really happened.
- **Response codes:** `libusb1-glue.c` keeps the device's response code when the device
  answers without a data phase, so "no such object" isn't mistaken for a USB error.
- **`LIBMTP_Open_Raw_Device_With_Progress()`:** reports progress while the Zune's ~4,000
  objects are read, for the loading bar.

`scripts/build-libmtp.sh` also forces **iconv** on. macOS's iconv fails a gnulib
self-test, and without iconv, accented titles arrive on the Zune garbled.

**MTPZ keys are not included**, in this repo or in libmtp. libmtp reads them from
`~/.mtpz-data`, which you have to provide yourself.

## Requirements

- macOS 14 or later, with the Xcode Command Line Tools (full Xcode isn't needed).
- Homebrew packages: `brew install libgcrypt libusb autoconf automake libtool gettext pkg-config`
- The libmtp fork checked out at `~/workspace/libmtp`, on the `zune-mtpz` branch (or set
  `LIBMTP_FORK`).
- An MTPZ key file at `~/.mtpz-data`.

## Build

```sh
scripts/build-libmtp.sh   # builds the fork and installs it to ~/.local/opt/libmtp-zune
scripts/test.sh           # unit tests (no Zune needed)
scripts/bundle-app.sh     # builds "build/Zune Manager.app"
```

`LIBMTP_PREFIX` changes where the fork is installed. Use `scripts/test.sh` rather than
plain `swift test`: with only the Command Line Tools, SwiftPM silently runs zero tests
unless the script's framework paths are passed.

`swift run zune-probe info` (and its other subcommands) talks to the real Zune from the
terminal, using the same code as the app. Only one program can use the Zune at a time,
so quit the app first. `ZUNE_PROBE_PROGRESS=1` prints loading progress and timings.

## Using it

- **Close Chromium-based browsers** (Chrome, Helium, …) while the Zune is connected. They
  open USB devices and can break the connection.
- **Loading takes about a minute** after you plug the Zune in. The app reads every object
  on it, and a progress bar shows how far it's got.
- **If the Zune stops responding**, the app tells you. Quit it, soft-reset the Zune (hold
  Back + Up until it restarts), plug it back in and reopen the app.
- **The disc number isn't stored on the Zune**, so multi-disc albums can't be ordered by
  disc.

## Known gaps

- With very little free space, a batch that overwrites songs can run out of space partway.
- A failed read of the album list looks like "no albums", so later adds could create
  duplicate album entries.
- If the Zune holds both an M4A and an MP3 of the same song, Overwrite replaces only one.
- Some errors show libmtp's raw text instead of plain words.
- No video support yet.

## How it's put together

- `Sources/ZuneKit` holds the logic and the app state: the browsing index, tag reading,
  planning for adds, deletes and saves, the device layer, and the store. It's tested
  against an in-memory fake Zune.
- `Sources/ZuneManager` is the SwiftUI app.
- `Sources/zune-probe` is the device CLI.
- `docs/superpowers/` holds the design and implementation plan the agent worked from.
