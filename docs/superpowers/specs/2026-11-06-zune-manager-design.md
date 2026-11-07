# Zune Manager — Design

Date: 2026-11-06
Status: reviewed, awaiting owner approval

## Intent

A native macOS app for managing the music on a Microsoft Zune 30 while it is plugged
into this Mac. The owner has no Windows machine; the Zune software is Windows-only.
The app replaces the Zune software for the things that matter: seeing what's on the
device, adding music from the Mac, removing music, and copying music back off.

It is a personal tool for one person on one Mac. It is not distributed.

## Success, and what would make it a failure

The owner's words: it would be a failure "if it crashed, or didn't actually work."

- **Reliability comes first**, ahead of features and polish.
- "Actually works" means: what the app says happened on the Zune really happened, and
  the result shows up correctly in the Zune's own menus (songs grouped under the right
  artist and album, album art showing).

## Goals (v1)

1. **Browse** everything on the Zune: Artists → Albums → Songs.
2. **Search** across artists, albums and song titles.
3. **Add** MP3s from the Mac: a single file or a folder (including subfolders).
4. **Remove** music, usually a whole album, after a confirmation.
5. **Extract** songs from the Zune to the Mac.
6. **Album art**: shown in the app; sent to the Zune when adding.

## Non-goals (v1)

- **Videos.** Music only for now, but videos are planned next (see "Designing for video
  later").
- Playlists, podcasts, pictures, firmware updates, Zune Marketplace, DRM-protected content.
- Syncing with Apple Music / a library database. Files are picked from the filesystem.
- Editing tags of songs already on the Zune.
- Running on other Macs, code signing, notarization, App Store.

## Anti-goals

- The app must never crash. A libmtp failure or a stuck device must surface as a clear
  message with a way forward (reconnect), never a crash, beachball or silent hang.
- The app must never report success for something that did not happen on the device.

## The device and what is already known

Verified on the owner's device during setup (2026-11-06):

- Zune 30 (USB 045e:0710), firmware 03.30, "Skrud's Zune", 29.8 GB, ~1.2 GB free.
- Contents: ~3,097 tracks (2,714 MP3, 381 M4A, 2 WMA) in ~316 album objects.
- The device needs the **MTPZ** handshake before it transfers files. libmtp performs it
  automatically when built with libgcrypt and given the key file `~/.mtpz-data` (already
  installed on this Mac). Handshake verified working.
- **libmtp fork**: `~/workspace/libmtp` (remote `git@github.com:skrud/libmtp.git`). One
  required change, currently uncommitted on `master`: the Zune 0x0710 entry in
  `src/music-players.h` has `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL`. Without it,
  libmtp's "fetch metadata for all objects" request stalls the Zune after the handshake
  and the device needs a soft reset (hold Back + Up). With it, the stock tools work.
- Verified operations with the fork: list all tracks (~80 s for the full device),
  download a track (~6 s for 9 MB), upload a track with metadata via the track API plus
  album creation (the song appeared and played on the Zune), delete a track and an album
  object.
- Timings above are per connection. Opening a connection = MTPZ handshake + metadata
  enumeration, so **reconnecting per action is not acceptable**.
- **Known libmtp bug**: `LIBMTP_Track_Exists` returns "exists" for any non-zero id (it
  calls `ptp_object_want` with no fields requested, which inserts into the cache without
  asking the device). Do not use it to verify anything.
- **Things that interfere with the USB device**: Chromium-based browsers (the owner's
  browser, Helium) open the Zune's USB device and caused session failures. macOS's
  `ptpcamerad` runs too but did not cause problems in testing. The app cannot control
  these; see "Connection and errors".
- Killing a libmtp process mid-transfer leaves the Zune wedged until a soft reset.
- Album art on the Zune: album objects (format 0xBA03, "Abstract Audio Album") take a
  representative sample in **JPEG, at most 240×240**. Writing art via libmtp is expected
  to work but has **not been verified**; reading it back has **not been verified** either.

## Decided by the owner

- **Platform**: native macOS app in **SwiftUI**, calling the libmtp fork **directly**
  (in-process), not shelling out to the `mtp-*` tools. If libmtp crashes turn out to be a
  real problem, the fallback is moving the USB work into a separate helper process; that
  is not part of v1.
- **Layout**: a **column browser**, like old iTunes: three side-by-side columns,
  Artists → Albums → Songs. Selecting an artist filters albums; selecting an album
  filters songs. A toolbar holds the device name, an **Add…** button and a **search**
  field. A footer shows the song count and a free-space bar ("1.2 GB free of 29.8 GB").
- **Adding**: pick one MP3 or a folder of MP3s from the filesystem.
- **Removing**: usually a whole album. Ask for confirmation, then delete all its tracks.
- **Duplicates on add**: if songs already exist on the Zune, ask: **Overwrite** (delete
  the existing ones first, since MTP cannot overwrite in place) or **Skip**.
- **Extract**: copy songs from the Zune to the Mac.
- **Album art** matters, both in the app and on the device.
- **Videos later**: music only for v1, but keep video in mind.
- **A new git repo** for the app (this one).

## Calls made by the designer (owner can override)

- **The fork is installed to a fixed prefix** on this Mac (e.g. `~/.local/opt/libmtp-zune`),
  and the app links against it there. The app is not self-contained. The scratchpad build
  used during setup is temporary and must not be relied on.
- **No Xcode required.** This Mac has only the Command Line Tools (Swift 6.3, macOS 26.6).
  The app builds with Swift Package Manager, and a script assembles the `.app` bundle.
  The owner may install Xcode later; the build must keep working without it.
- **One connection for the app's lifetime.** Connect once, enumerate once, keep the
  session open, apply adds and deletes to the in-memory model incrementally.
- **Remove scope**: delete works on a song, an album, or an artist (all their albums),
  each with a confirmation naming what goes, for example
  *"Delete '2112' by Rush (6 songs, 52 MB) from your Zune? This can't be undone."*
  When an album's tracks are deleted, the Zune's album object is deleted too, so no empty
  album is left in the Zune's menus. Deleting some songs from an album leaves the album
  object with its remaining tracks.
- **Add details**: Add… accepts files and folders (recursing into subfolders); dropping
  files or folders onto the window does the same. Tags are read from each MP3 (title,
  artist, album, album artist, track number, year, genre, duration, embedded art), using
  macOS's own frameworks (AVFoundation). Non-MP3 files are skipped and listed at the end.
  Songs are grouped into albums on the Zune by creating or updating the album object
  for (album, album artist or artist).
- **Artist grouping mirrors the Zune's own menus.** The Artists column lists track
  artists; a song appears under its own artist. Albums are grouped by album artist (from
  the Zune's album objects, falling back to the track artist for tracks with no album
  object, e.g. some M4A/WMA). Selecting an artist shows the albums containing their songs.
  "Delete artist" removes only that artist's songs (and any album object left empty).
  A compilation added from the Mac becomes one album object under its album artist
  (e.g. "Various Artists"), not one album per track artist. Note: libmtp's track record
  has no album-artist field; album artist lives on the album object.
- **Duplicate rule**: a song is "already there" when artist, album and title match,
  ignoring case, regardless of format. Before copying anything, the whole batch is
  checked; if there are duplicates the app asks once, listing them with the format of
  each copy (e.g. existing M4A vs incoming MP3), with Overwrite / Skip and an
  "apply to all" choice so there is no prompt per song.
- **Overwrite order**: when free space allows, upload the new file first and delete the
  old copy only after the upload is verified, so a failed upload never loses the song.
  When there isn't room, warn that the old copy will be deleted first, then proceed only
  on confirmation.
- **Album art on add**: embedded art from the MP3 tags; otherwise `cover.jpg` or
  `folder.jpg` in the same folder. Scaled to fit 240×240 and sent as JPEG.
- **Album art in the app**: small covers in the Albums column, fetched lazily as they
  scroll into view (so they don't slow down startup), cached for the session. If reading
  art from the Zune turns out not to work, show a placeholder.
- **Extract**: select a song, album or artist → "Save to Mac…" (and drag to Finder if
  practical). Files are written as `Artist/Album/NN Title.ext` under the chosen folder;
  files that already exist there are skipped.
- **Browsing shows everything on the device**, including the M4A and WMA tracks, even
  though v1 only adds MP3s.
- **One operation at a time.** While an add, delete or extract runs, others are disabled.
  Progress is shown (per file and overall), and a running batch can be cancelled
  between files, never mid-file (killing a transfer mid-file wedges the device).
- **Verification**: after each add or delete, the app confirms the change on the device
  by asking the device directly for that object (not via `LIBMTP_Track_Exists`), and
  only then updates the model. A failed verification is reported as an error for that
  file.

## Connection and errors

- Launching with no Zune attached shows a "Connect your Zune" state. Plugging it in is
  detected and the app connects without a restart. Unplugging is detected too.
- Connecting shows progress; the first load takes about a minute (handshake + ~3,100
  tracks). The window stays responsive throughout.
- All libmtp calls run off the main thread, one at a time (libmtp is not safe to call
  concurrently on one device).
- Every device operation has a time limit. If libmtp returns an error, the app says so
  plainly and offers **Reconnect**. If a libmtp call does not return within the time
  limit, the in-process call cannot be safely abandoned, so the app instead says the
  Zune stopped responding and offers **Quit**, with the instructions: soft-reset the Zune
  (hold Back + Up), then reopen the app. **The owner accepted quit-and-reopen as the
  recovery path for v1**; no helper process in v1. The message also mentions that
  Chromium-based browsers can interfere, since that was the cause of failures during
  setup.
- Errors from libmtp's error stack are shown in plain words, with the details available.
- Unplugging during a transfer is reported as such; nothing is reported as done unless
  verified.

## Designing for video later

Video is the next feature after v1. The structure should leave room for it without
building it now: the data model should not assume every item is a song, and adding
should be organized so a "convert before sending" step can be slotted in. The Zune 30
accepts video at up to 320×240 (WMV and MP4 per the device report), so most videos will
need conversion; that is a later problem.

## Testing

- Behaviour that doesn't need the device (tag reading, duplicate matching, file naming,
  model updates) gets automated tests.
- Device behaviour is tested against the owner's real Zune at each step, with the owner
  checking the Zune's own menus where it matters (new songs appear under the right
  artist/album, art shows, deleted albums are gone).
- Use clearly named test content (e.g. artist "Claude Test") and clean it up afterwards.

## Left to the builder

- Project layout, module boundaries, and how the C library is exposed to Swift.
- How the app bundle is assembled and where the libmtp prefix is configured.
- Exact timeouts, progress UI details, keyboard shortcuts, and sorting within columns.
- Whether album art reads need their own fallback strategy beyond a placeholder.
- Whether the fork change should also be committed upstream-friendly (the owner allowed
  changes to the fork; committing it is the owner's call).
