# Zune Manager

A native macOS app for managing the music on a Microsoft Zune 30: browse what's on it
(Artists → Albums → Songs, with search), add MP3s from the Mac, delete songs or albums,
and save songs back to the Mac.

It talks to the Zune through a fork of [libmtp](https://github.com/libmtp/libmtp) built
with MTPZ support (the Zune refuses file transfers without the MTPZ handshake).

## Prerequisites

- macOS 14 or later, with the Xcode Command Line Tools (full Xcode is not needed).
- Homebrew packages: `brew install libgcrypt libusb autoconf automake libtool gettext pkg-config`
- The libmtp fork at `~/workspace/libmtp` (`git@github.com:skrud/libmtp.git`, branch
  `zune-mtpz`). The changes this app needs are also in `third_party/libmtp-zune.patch`:
  - the Zune (045e:0710) is flagged `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL`, because
    asking it for every object's metadata at once stalls it after the MTPZ handshake;
  - `LIBMTP_Object_Exists_On_Device()`, which asks the device directly whether an object
    exists (libmtp's `LIBMTP_Track_Exists()` answers from its cache, so it can't confirm
    that a copy or delete really happened).
- The MTPZ key file at `~/.mtpz-data`.

## Build

```sh
scripts/build-libmtp.sh   # builds the fork, installs to ~/.local/opt/libmtp-zune
scripts/test.sh           # unit tests (no Zune needed)
scripts/bundle-app.sh     # builds "build/Zune Manager.app"
```

Set `LIBMTP_FORK` / `LIBMTP_PREFIX` to use a different fork checkout or install location.

`swift run zune-probe info` (and its other subcommands) talks to the real Zune from the
terminal, using the same code as the app. Only one program can use the Zune at a time,
so quit the app first.

## Using it

- Close Chromium-based browsers (Chrome, Helium, …) while the Zune is connected. They
  open USB devices and can break the connection.
- The first load after plugging in takes about a minute.
- If the Zune stops responding, quit the app, soft-reset the Zune (hold Back + Up until
  it restarts), plug it back in and reopen the app.
