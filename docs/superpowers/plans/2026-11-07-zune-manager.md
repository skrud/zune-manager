# Zune Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS SwiftUI app that browses, adds, removes and extracts music on the owner's Zune 30 through the owner's libmtp fork.

**Architecture:** A Swift package with a pure-logic library (`ZuneKit`: models, browsing index, tag reading, add/delete/export planning, app state) and a device layer that wraps libmtp behind a `ZuneDeviceClient` protocol. All libmtp calls run one at a time on a dedicated worker thread with time limits. The app state (`ZuneStore`) is tested against an in-memory fake device; the live device layer is tested against the real Zune through a small CLI (`zune-probe`) that uses the same code as the app.

**Tech Stack:** Swift 6.3 (Command Line Tools only, no Xcode), SwiftPM, SwiftUI (macOS 14+), Swift Testing, AVFoundation (tags), ImageIO (art), IOKit (USB attach/detach), libmtp fork (C) built with libgcrypt for MTPZ.

**Spec:** `docs/superpowers/specs/2026-11-06-zune-manager-design.md`

## Global Constraints

- Builds and tests with the Command Line Tools only: `swift build`, `swift test`, `scripts/bundle-app.sh`. Xcode must not be required.
- Swift tools version 6.0, Swift 6 language mode, platform `.macOS(.v14)`.
- Swift Testing needs these paths (put them in `Package.swift` for the test target): framework dir `/Library/Developer/CommandLineTools/Library/Developer/Frameworks` (`-F` for compiler and linker, plus `-rpath`), and `-rpath /Library/Developer/CommandLineTools/Library/Developer/usr/lib`.
- libmtp comes from the owner's fork at `~/workspace/libmtp`, installed to `~/.local/opt/libmtp-zune` (override with env `LIBMTP_PREFIX`). Never link Homebrew's libmtp (it has no MTPZ).
- The MTPZ key file `~/.mtpz-data` is already installed. Never print, copy or commit its contents.
- Open the device with `LIBMTP_Open_Raw_Device` (cached). This is only safe because the fork sets `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL` on the Zune; the build script refuses to build without it.
- Never call `LIBMTP_Track_Exists` (it reports "exists" for any id). Existence checks use the fork's `LIBMTP_Object_Exists_On_Device` (Task 1).
- All libmtp calls go through `DeviceWorker` (one at a time, never on the main thread, every call with a time limit).
- Never cancel a transfer mid-file: libmtp progress callbacks always return 0. Cancellation happens only between files. Never kill a process that is mid-transfer.
- Device-touching steps need the owner: Zune plugged in, Helium (and any Chromium-based browser) closed. If the Zune stops responding, stop and ask the owner to soft-reset it (hold Back + Up) and replug.
- Device test content uses artist `Claude Test` and is deleted at the end of each device test.
- App name `Zune Manager`, bundle id `com.skrud.ZuneManager`.
- Exact copy, used verbatim where named:
  - `ZuneStore.stuckMessage`: `Your Zune stopped responding. Quit Zune Manager, soft-reset the Zune (hold Back + Up until it restarts), then reopen the app. If a Chromium-based browser like Helium is open, close it first — it can interfere with the Zune.`
  - Delete confirmation (album): `Delete '<album>' by <album artist> (<n> songs, <size>) from your Zune? This can't be undone.` (`1 song` when n = 1; size from `ByteCountFormatter` with `.file` style).
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01UdmpMmttV6NPmT4d9sgeMm
  ```

## Review Focus

1. **Songs with missing tags** (no title, artist or album): title falls back to the file name, artist to `Unknown Artist`, album to `Unknown Album`; they still browse, group and upload. Pinned in Task 2 (`indexUsesUnknownForEmptyFields`) and Task 3 (`readsUntaggedFileWithFallbacks`).
2. **Non-ASCII and path-hostile names** (`Motörhead`, `AC/DC`, `Re: Stacks`): search is case- and diacritic-insensitive, exported paths are sanitized, uploads keep the Unicode. Pinned in Task 2 (`searchIgnoresCaseAndDiacritics`), Task 4 (`exportPathSanitizesSlashesAndColons`), Task 6 device test (title `Tëst Ünicode / Song`).
3. **The same song twice in one add batch** (a folder with nested copies): one copy is added, the other is reported as skipped. Pinned in Task 4 (`planSkipsDuplicatesWithinBatch`).
4. **Not enough space** (the Zune has ~1.2 GB free): refused up front, nothing partially copied. Pinned in Task 4 (`planThrowsWhenNotEnoughSpace`) and Task 8 (`addRefusesBeforeSendingWhenNoSpace`).
5. **Zune unplugged mid-operation:** the operation stops, the summary says which files were done and which were not, the app returns to "Connect your Zune". Pinned in Task 7 (`detachDuringDeleteStopsAndReports`).

---

## File Structure

```
Package.swift
scripts/build-libmtp.sh          fork build + install to ~/.local/opt/libmtp-zune
scripts/bundle-app.sh            swift build -c release + assemble "Zune Manager.app"
third_party/libmtp-zune.patch    the fork changes this app needs (for reference/re-applying)
Resources/Info.plist
Sources/CLibMTP/module.modulemap, shim.h
Sources/ZuneKit/Model/           MediaItem.swift, Selection.swift
Sources/ZuneKit/Library/         LibraryIndex.swift
Sources/ZuneKit/Local/           LocalSong.swift, TagReader.swift, FileScanner.swift, Artwork.swift
Sources/ZuneKit/Planning/        Duplicates.swift, AddPlanner.swift, DeletePlanner.swift, ExportNaming.swift
Sources/ZuneKit/Device/          ZuneError.swift, DeviceWorker.swift, MTPSession.swift,
                                 ZuneDeviceClient.swift, LiveZuneDevice.swift
Sources/ZuneKit/Store/           ZuneStore.swift, ZuneStore+Add.swift, OperationSummary.swift
Sources/ZuneTestSupport/         MP3Fixture.swift, ImageFixture.swift
Sources/zune-probe/main.swift    device CLI used for real-device tests
Sources/ZuneManager/             ZuneManagerApp.swift, USBWatcher.swift, Views/*.swift
Tests/ZuneKitTests/              one test file per ZuneKit file under test, FakeZuneDevice.swift
```

---

### Task 1: Fork prerequisites and libmtp install

**Files:**
- Modify (fork): `~/workspace/libmtp/src/libmtp.c`, `src/libmtp.h.in`, `src/libmtp.sym`
- Create: `scripts/build-libmtp.sh`, `third_party/libmtp-zune.patch`, `README.md`

**Interfaces:**
- Produces: C function `int LIBMTP_Object_Exists_On_Device(LIBMTP_mtpdevice_t *device, uint32_t id)` returning `1` (exists), `0` (device says invalid handle), `-1` (other error). Installed libmtp at `$LIBMTP_PREFIX` (default `~/.local/opt/libmtp-zune`) with `include/libmtp.h`, `lib/libmtp.dylib`, `bin/mtp-*`.

- [ ] **Step 1: Add the function to the fork.** In `src/libmtp.c`, after `LIBMTP_Track_Exists`, add (it bypasses libmtp's object cache on purpose):

```c
int LIBMTP_Object_Exists_On_Device(LIBMTP_mtpdevice_t *device, uint32_t const id)
{
  PTPParams *params = (PTPParams *) device->params;
  PTPObjectInfo oi;
  uint16_t ret;

  memset(&oi, 0, sizeof(oi));
  ret = ptp_getobjectinfo(params, id, &oi);
  ptp_free_objectinfo(&oi);
  if (ret == PTP_RC_OK)
    return 1;
  if (ret == PTP_RC_InvalidObjectHandle)
    return 0;
  add_ptp_error_to_errorstack(device, ret, "LIBMTP_Object_Exists_On_Device(): could not query object.");
  return -1;
}
```

Declare it in `src/libmtp.h.in` next to `LIBMTP_Track_Exists` and add `LIBMTP_Object_Exists_On_Device` to `src/libmtp.sym`. Do not commit in the fork (the owner decides); the Zune flag change in `src/music-players.h` is already present and uncommitted.

- [ ] **Step 2: Write `scripts/build-libmtp.sh`** (bash, `set -euo pipefail`):
  - `FORK=${LIBMTP_FORK:-$HOME/workspace/libmtp}`, `PREFIX=${LIBMTP_PREFIX:-$HOME/.local/opt/libmtp-zune}`.
  - Fail with a clear message unless `grep -A1 '"Zune", 0x0710' "$FORK/src/music-players.h"` contains `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL` and `$FORK/src/libmtp.h.in` contains `LIBMTP_Object_Exists_On_Device`.
  - Fail unless `brew --prefix libgcrypt` and `brew --prefix libusb` exist (print `brew install libgcrypt libusb autoconf automake libtool gettext pkg-config`).
  - `PATH="$(brew --prefix libtool)/libexec/gnubin:$(brew --prefix gettext)/bin:$PATH"`; run `./autogen.sh` if `configure` is missing; `./configure --prefix="$PREFIX" CPPFLAGS=-I/opt/homebrew/include LDFLAGS=-L/opt/homebrew/lib`; `make -j8`; `make install`.
  - Verify: `grep -q 'define USE_MTPZ' config.h`, `otool -L "$PREFIX/lib/libmtp.dylib" | grep -q gcrypt`, `nm -gU "$PREFIX/lib/libmtp.dylib" | grep -q _LIBMTP_Object_Exists_On_Device`; print `libmtp-zune installed at $PREFIX`.

- [ ] **Step 3: Run it**

Run: `scripts/build-libmtp.sh`
Expected: ends with `libmtp-zune installed at /Users/skrud/.local/opt/libmtp-zune`.

- [ ] **Step 4: Save the fork diff and write `README.md`**

Run: `git -C ~/workspace/libmtp diff > third_party/libmtp-zune.patch` (must contain both the flag change and the new function).
`README.md`: what the app is, prerequisites (`~/.mtpz-data`, the fork, Homebrew deps), `scripts/build-libmtp.sh`, `swift test`, `scripts/bundle-app.sh`, and "close Chromium-based browsers while the Zune is connected; if the Zune stops responding, hold Back + Up to soft-reset it".

- [ ] **Step 5: Smoke-test the installed tools against the device** (owner: Zune plugged in, Helium closed)

Run: `~/.local/opt/libmtp-zune/bin/mtp-detect 2>&1 | tail -1`
Expected: `OK.`

- [ ] **Step 6: Commit** `scripts/build-libmtp.sh third_party/libmtp-zune.patch README.md` — "Add libmtp fork build script and required fork patch".

---

### Task 2: Package skeleton, models and the browsing index

**Files:**
- Create: `Package.swift`, `Sources/CLibMTP/module.modulemap`, `Sources/CLibMTP/shim.h`, `Sources/ZuneKit/Model/MediaItem.swift`, `Sources/ZuneKit/Model/Selection.swift`, `Sources/ZuneKit/Library/LibraryIndex.swift`, placeholder `Sources/ZuneManager/ZuneManagerApp.swift`, placeholder `Sources/zune-probe/main.swift`, `Sources/ZuneTestSupport/MP3Fixture.swift` (empty enum for now)
- Test: `Tests/ZuneKitTests/LibraryIndexTests.swift`

**Interfaces:**
- Produces (all `public`, `Sendable`):

```swift
enum MediaKind: Hashable { case audio }                        // .video later
enum MediaFormat: String, Hashable { case mp3, m4a, wma, other }
struct MediaItem: Identifiable, Hashable {
  let id: UInt32; var kind: MediaKind; var title: String; var artist: String; var album: String
  var genre: String; var trackNumber: Int /*0 = unknown*/; var durationMs: Int
  var fileSize: UInt64; var fileName: String; var format: MediaFormat
}
struct AlbumObject: Identifiable, Hashable { let id: UInt32; var name: String; var artist: String; var itemIDs: [UInt32] }
struct StorageInfo: Hashable { var capacityBytes: UInt64; var freeBytes: UInt64 }
struct DeviceSnapshot { var deviceName: String; var items: [MediaItem]; var albums: [AlbumObject]; var storage: StorageInfo }
struct AlbumKey: Hashable { let name: String; let albumArtist: String }   // display values
struct AlbumEntry: Identifiable, Hashable { var id: AlbumKey; var albumObjectID: UInt32?; var itemIDs: [UInt32] }
enum Selection: Hashable { case items([UInt32]); case album(AlbumKey); case artist(String) }
struct LibraryIndex {
  static let unknownArtist = "Unknown Artist"; static let unknownAlbum = "Unknown Album"
  init(snapshot: DeviceSnapshot)
  func artists(matching query: String) -> [String]
  func albums(artist: String?, matching query: String) -> [AlbumEntry]
  func items(artist: String?, album: AlbumKey?, matching query: String) -> [MediaItem]
  func item(_ id: UInt32) -> MediaItem?
  func albumArtist(of id: UInt32) -> String
  func resolve(_ selection: Selection) -> [MediaItem]
}
```

Rules (the spec's "mirror the Zune's menus"): artists are track artists. An item's album artist is the `artist` of the album object whose `itemIDs` contains it, else the item's artist. Albums group by (album name, album artist) compared case-insensitively and ignoring surrounding whitespace, displayed with the first-seen spelling. `albums(artist:)` lists albums containing at least one item by that artist (`nil` = all). `items(artist:album:)` filters by both when given. Artists and albums sort with `localizedStandardCompare`; items sort by track number (0 last), then title. `query` matches title, artist, album or album artist with `localizedStandardContains` semantics (case- and diacritic-insensitive); empty query matches everything. `resolve(.artist)` = that artist's items; `resolve(.album)` = the album's items.

- [ ] **Step 1: Write `Package.swift`.** Products/targets: `CLibMTP` (`.systemLibrary`, path `Sources/CLibMTP`), `ZuneKit` (depends on `CLibMTP`; `swiftSettings: .unsafeFlags(["-Xcc", "-I\(prefix)/include"])`; `linkerSettings: .unsafeFlags(["-L\(prefix)/lib"])` and `.linkedLibrary("mtp")`), `ZuneTestSupport` (depends on `ZuneKit`), executable `ZuneManager` (depends on `ZuneKit`), executable `zune-probe` (depends on `ZuneKit`, `ZuneTestSupport`), test target `ZuneKitTests` (depends on `ZuneKit`, `ZuneTestSupport`, with the Swift Testing flags from Global Constraints). `prefix` = `ProcessInfo.processInfo.environment["LIBMTP_PREFIX"] ?? NSHomeDirectory() + "/.local/opt/libmtp-zune"`. Module map: `module CLibMTP [system] { header "shim.h" link "mtp" export * }`; `shim.h` is `#include <libmtp.h>`.

- [ ] **Step 2: Write the failing tests** in `LibraryIndexTests.swift` (build a small `DeviceSnapshot` helper in the file):

```swift
@Test func artistsAreTrackArtistsSorted() {
  // items by "Rush", "3 Inches of Blood", "rush " → ["3 Inches of Blood", "Rush"]
  #expect(index.artists(matching: "") == ["3 Inches of Blood", "Rush"])
}
@Test func compilationGroupsUnderAlbumArtist() {
  // two items, artists "A" and "B", both in album object (name "Hits", artist "Various Artists")
  #expect(index.albums(artist: nil, matching: "").map(\.id) == [AlbumKey(name: "Hits", albumArtist: "Various Artists")])
  #expect(index.albums(artist: "A", matching: "").count == 1)
  #expect(index.items(artist: "A", album: hits, matching: "").map(\.artist) == ["A"])
}
@Test func itemWithoutAlbumObjectUsesTrackArtist() {
  #expect(index.albumArtist(of: m4aID) == "Rush")
  #expect(index.albums(artist: "Rush", matching: "").first?.albumObjectID == nil)
}
@Test func albumNamesGroupIgnoringCaseAndSpaces() // "2112" and "2112 " by Rush → one AlbumEntry with 2 itemIDs
@Test func itemsSortByTrackNumberUnknownLast()    // track numbers [2, 0, 1] → titles in order 1, 2, then the 0
@Test func searchIgnoresCaseAndDiacritics() {
  #expect(index.artists(matching: "motorhead") == ["Motörhead"])
  #expect(index.items(artist: nil, album: nil, matching: "ACE OF").map(\.title) == ["Ace of Spades"])
}
@Test func indexUsesUnknownForEmptyFields() {
  // item with artist "" and album "" → listed under "Unknown Artist" / "Unknown Album"
}
@Test func resolveAlbumAndArtist()               // resolve(.album(key)).count == 2; resolve(.artist("Rush")) ids == [1, 2, 5]
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter LibraryIndexTests`
Expected: FAIL (compile errors: `LibraryIndex` not defined).

- [ ] **Step 4: Implement the models and `LibraryIndex`** in the files listed. Precompute dictionaries in `init` (artist → item ids, album key → entry, item id → album artist) so column queries don't rescan 3,000 items.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter LibraryIndexTests`
Expected: PASS. Also `swift build` succeeds (proves the CLibMTP module map and link flags resolve).

- [ ] **Step 6: Commit** — "Add package skeleton, models and browsing index".

---

### Task 3: Reading local files (scan, tags, artwork)

**Files:**
- Create: `Sources/ZuneKit/Local/LocalSong.swift`, `TagReader.swift`, `FileScanner.swift`, `Artwork.swift`; fill in `Sources/ZuneTestSupport/MP3Fixture.swift`, create `Sources/ZuneTestSupport/ImageFixture.swift`
- Test: `Tests/ZuneKitTests/TagReaderTests.swift`, `FileScannerTests.swift`, `ArtworkTests.swift`

**Interfaces:**
- Produces (`public`, `Sendable`):

```swift
struct LocalSong: Hashable {
  var url: URL; var title: String; var artist: String; var album: String; var albumArtist: String?
  var trackNumber: Int; var year: Int?; var genre: String; var durationMs: Int; var fileSize: UInt64
  var embeddedArtwork: Data?
  var effectiveAlbumArtist: String { get }   // albumArtist ?? artist
}
enum TagReader { static func read(_ url: URL) async throws -> LocalSong }
enum FileScanner {
  struct Result: Sendable { var mp3s: [URL]; var skipped: [URL] }
  static func scan(_ urls: [URL]) -> Result       // recursive; hidden files ignored; .mp3 case-insensitive; sorted by path
  static func coverImage(forSongAt url: URL) -> URL?   // cover.jpg / folder.jpg, case-insensitive, same folder
}
struct AlbumArt: Hashable { var jpeg: Data; var width: Int; var height: Int }
enum Artwork { static let maxPixels = 240; static func zuneAlbumArt(from imageData: Data) -> AlbumArt? }
// ZuneTestSupport:
enum MP3Fixture { static func write(to url: URL, title: String?, artist: String?, album: String?, albumArtist: String? = nil,
                                    track: String? = nil, year: String? = nil, genre: String? = nil,
                                    artworkJPEG: Data? = nil, seconds: Double = 2) throws }
enum ImageFixture { static func jpeg(width: Int, height: Int) -> Data; static func png(width: Int, height: Int) -> Data }
```

`MP3Fixture` writes an ID3v2.3 tag (text frames `TIT2 TPE1 TALB TPE2 TRCK TYER TCON` with UTF-8 encoding byte `0x03`, plus `APIC` with mime `image/jpeg`, type 3, when art is given; tag size as a syncsafe integer) followed by `Int(seconds * 44100 / 1152)` MPEG-1 Layer III frames, each the header `FF FB 90 64` plus 413 zero bytes. (Verified during planning: AVFoundation reads every one of these tags and a ~2 s duration from such a file, and resolves genre `(17)` to `Rock`.)

`TagReader` uses `AVURLAsset` (`load(.duration)`, `loadMetadata(for: .id3Metadata)`). Fallbacks: title → file name without extension, artist → `LibraryIndex.unknownArtist`, album → `LibraryIndex.unknownAlbum`, genre → `""`. Track `"3/12"` → 3. Year from `TYER` or the first 4 digits of `TDRC`. `fileSize` from the file's resource values.

`Artwork.zuneAlbumArt` decodes any ImageIO-readable image and produces a JPEG that fits within 240×240, keeping the aspect ratio and never upscaling (`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` 240 and `kCGImageSourceCreateThumbnailWithTransform`, then `CGImageDestination` with `UTType.jpeg`, quality 0.85). Returns `nil` for undecodable data.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func readsAllTags() async throws {
  try MP3Fixture.write(to: url, title: "Tears", artist: "Rush", album: "2112", albumArtist: "Rush",
                       track: "5/6", year: "1976", genre: "(17)", artworkJPEG: ImageFixture.jpeg(width: 300, height: 300))
  let s = try await TagReader.read(url)
  #expect(s.title == "Tears" && s.artist == "Rush" && s.album == "2112" && s.albumArtist == "Rush")
  #expect(s.trackNumber == 5 && s.year == 1976 && s.genre == "Rock")
  #expect(abs(s.durationMs - 2000) < 100)
  #expect(s.embeddedArtwork != nil)
}
@Test func readsUntaggedFileWithFallbacks() async throws {
  // file "07 Some Song.mp3" with no tags
  #expect(s.title == "07 Some Song" && s.artist == "Unknown Artist" && s.album == "Unknown Album" && s.trackNumber == 0)
}
@Test func keepsUnicodeTags() async throws          // title "Tëst Ünicode / Song" round-trips exactly
@Test func scanRecursesAndSkipsNonMP3() {
  // dir/a.mp3, dir/sub/B.MP3, dir/notes.txt, dir/.hidden.mp3, dir/c.m4a
  #expect(r.mp3s.map(\.lastPathComponent) == ["a.mp3", "B.MP3"])
  #expect(Set(r.skipped.map(\.lastPathComponent)) == ["notes.txt", "c.m4a"])
}
@Test func scanAcceptsSingleFile()                   // scan([a.mp3]).mp3s == [a.mp3]
@Test func findsCoverJpgCaseInsensitive()            // "Folder.JPG" found; none → nil
@Test func artworkFitsWithin240KeepingAspect() {
  let art = try #require(Artwork.zuneAlbumArt(from: ImageFixture.png(width: 600, height: 300)))
  #expect(art.width == 240 && art.height == 120)
  #expect(art.jpeg.starts(with: [0xFF, 0xD8]))
}
@Test func artworkDoesNotUpscale()                   // 100×100 → 100×100
@Test func artworkRejectsGarbage()                   // Data("nope".utf8) → nil
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'TagReaderTests|FileScannerTests|ArtworkTests'`
Expected: FAIL (types not defined).

- [ ] **Step 3: Implement `MP3Fixture`, `ImageFixture` (CoreGraphics bitmap filled with a solid colour, encoded with ImageIO), `LocalSong`, `TagReader`, `FileScanner`, `Artwork`.**

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'TagReaderTests|FileScannerTests|ArtworkTests'`
Expected: PASS.

- [ ] **Step 5: Commit** — "Read MP3 tags, scan folders and prepare album art".

---

### Task 4: Planning adds, deletes and exports

**Files:**
- Create: `Sources/ZuneKit/Planning/Duplicates.swift`, `AddPlanner.swift`, `DeletePlanner.swift`, `ExportNaming.swift`
- Test: `Tests/ZuneKitTests/DuplicatesTests.swift`, `AddPlannerTests.swift`, `DeletePlannerTests.swift`, `ExportNamingTests.swift`

**Interfaces:**
- Consumes: Task 2 models and `LibraryIndex`; Task 3 `LocalSong`.
- Produces (`public`, `Sendable`):

```swift
struct DuplicateKey: Hashable { init(artist: String, album: String, title: String) }  // trimmed, case-insensitive
struct Duplicate: Identifiable, Hashable { var id: URL { incoming.url }; var incoming: LocalSong; var existing: MediaItem }
enum DuplicateChoice: Hashable { case overwrite, skip }
enum Duplicates { static func find(incoming: [LocalSong], existing: [MediaItem]) -> [Duplicate] }

enum OverwriteMode: Hashable { case uploadThenDelete, deleteThenUpload }
struct AddStep: Hashable { var song: LocalSong; var replacing: MediaItem? }
struct AddPlan: Hashable { var steps: [AddStep]; var skippedDuplicates: [LocalSong]; var skippedInBatch: [LocalSong]
                           var overwriteMode: OverwriteMode; var incomingBytes: UInt64 }
enum AddPlanError: Error, Equatable { case notEnoughSpace(neededBytes: UInt64, availableBytes: UInt64) }
enum AlbumTarget: Hashable { case existing(AlbumObject); case create(name: String, artist: String) }
enum AddPlanner {
  static let spaceMarginBytes: UInt64 = 10 * 1024 * 1024
  static func plan(songs: [LocalSong], duplicates: [Duplicate], choices: [URL: DuplicateChoice], freeBytes: UInt64) throws -> AddPlan
  static func albumTarget(for song: LocalSong, albums: [AlbumObject]) -> AlbumTarget
}

struct DeletePlan: Hashable { var itemIDs: [UInt32]; var albumObjectsToDelete: [UInt32]; var totalBytes: UInt64; var confirmationText: String }
enum DeletePlanner { static func plan(_ selection: Selection, index: LibraryIndex, albums: [AlbumObject]) -> DeletePlan }

enum ExportNaming { static func relativePath(for item: MediaItem) -> String }
```

Rules:
- `Duplicates.find`: an incoming song is a duplicate of an existing item when `DuplicateKey(artist, album, title)` match. Format is ignored.
- `AddPlanner.plan`: songs are processed in order; a song whose key already appeared earlier in the batch goes to `skippedInBatch`; a duplicate with choice `.skip` (or no choice) goes to `skippedDuplicates`; `.overwrite` becomes a step with `replacing`. `incomingBytes` = sum of step file sizes. If `freeBytes >= incomingBytes + margin` → `.uploadThenDelete`; else if `freeBytes + (sum of replaced sizes) >= incomingBytes + margin` → `.deleteThenUpload`; else throw `.notEnoughSpace(neededBytes: incomingBytes + margin, availableBytes: freeBytes)`.
- `albumTarget`: an album object whose name equals `song.album` and artist equals `song.effectiveAlbumArtist` (trimmed, case-insensitive) → `.existing`; otherwise `.create(name: song.album, artist: song.effectiveAlbumArtist)`.
- `DeletePlanner`: item ids = `index.resolve(selection)` ids. An album object is deleted when none of its item ids that exist in the index survive the deletion. Confirmation copy:
  - album: `Delete '<name>' by <albumArtist> (<n> songs, <size>) from your Zune? This can't be undone.`
  - artist: `Delete all songs by <artist> (<n> songs, <size>) from your Zune? This can't be undone.`
  - one item: `Delete '<title>' by <artist> (1 song, <size>) from your Zune? This can't be undone.`
  - several items: `Delete <n> songs (<size>) from your Zune? This can't be undone.`
  - `1 song` / `<n> songs`; size from `ByteCountFormatter` with `.countStyle = .file`.
- `ExportNaming.relativePath`: `<Artist>/<Album>/<NN> <Title>.<ext>`; `NN` is two-digit track number, omitted (with its space) when 0. Each component: `/` and `:` → `_`, trimmed, leading dots removed, empty → `Unknown`. Extension: `fileName`'s extension lowercased, else `format.rawValue`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func duplicateIgnoresCaseFormatAndSpaces()   // incoming "tears"/"RUSH"/"2112 " vs existing m4a "Tears"/"Rush"/"2112" → 1 duplicate
@Test func planSkipsDuplicatesWithinBatch() throws {
  let p = try AddPlanner.plan(songs: [a, aCopyInSubfolder], duplicates: [], choices: [:], freeBytes: .max)
  #expect(p.steps.map(\.song.url) == [a.url] && p.skippedInBatch.map(\.url) == [aCopyInSubfolder.url])
}
@Test func planSkipsDuplicateWithoutChoice()        // no choice → skippedDuplicates
@Test func planUploadsFirstWhenSpaceAllows()       // free 100 MB, incoming 20 MB, overwrite → .uploadThenDelete
@Test func planDeletesFirstWhenTight()             // free 25 MB, incoming 20 MB, replacing 18 MB → .deleteThenUpload
@Test func planThrowsWhenNotEnoughSpace() {
  #expect(throws: AddPlanError.notEnoughSpace(neededBytes: 20_000_000 + AddPlanner.spaceMarginBytes, availableBytes: 5_000_000)) {
    try AddPlanner.plan(songs: [twentyMB], duplicates: [], choices: [:], freeBytes: 5_000_000)
  }
}
@Test func albumTargetMatchesAlbumArtistCaseInsensitive()  // existing ("Hits", "Various Artists"), song albumArtist "various artists" → .existing
@Test func albumTargetCreatesWhenMissing()                // → .create(name: "2112", artist: "Rush")
@Test func deleteAlbumConfirmationText() {
  // album 2112 by Rush, 6 items totalling 52_000_000 bytes, album object 100
  #expect(plan.confirmationText == "Delete '2112' by Rush (6 songs, 52 MB) from your Zune? This can't be undone.")
  #expect(plan.albumObjectsToDelete == [100])
}
@Test func deletePartOfAlbumKeepsAlbumObject()     // .items([1]) of a 2-item album → albumObjectsToDelete == []
@Test func deleteArtistOnCompilationKeepsOthers()  // artist "A" on "Hits" with "B" also on it → album object kept
@Test func deleteSingleSongTextUsesSingular()      // "Delete 'Tears' by Rush (1 song, 9.4 MB) …"
@Test func exportPathFormat()                      // track 2 "A Passage to Bangkok" mp3 → "Rush/2112/02 A Passage to Bangkok.mp3"
@Test func exportPathSanitizesSlashesAndColons()   // artist "AC/DC", title "Re: Stacks", track 0, m4a → "AC_DC/<album>/Re_ Stacks.m4a"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'DuplicatesTests|AddPlannerTests|DeletePlannerTests|ExportNamingTests'`
Expected: FAIL (types not defined).

- [ ] **Step 3: Implement the four files.**

- [ ] **Step 4: Run tests to verify they pass**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit** — "Plan adds, deletes and exports".

---

### Task 5: Device layer — worker, reading from the Zune, probe CLI

**Files:**
- Create: `Sources/ZuneKit/Device/ZuneError.swift`, `DeviceWorker.swift`, `MTPSession.swift`, `ZuneDeviceClient.swift`, `LiveZuneDevice.swift`; replace `Sources/zune-probe/main.swift`
- Test: `Tests/ZuneKitTests/DeviceWorkerTests.swift`

**Interfaces:**
- Consumes: Task 2 models; Task 1 `LIBMTP_Object_Exists_On_Device`.
- Produces (`public` unless noted):

```swift
enum ZuneError: Error, Equatable, Sendable {
  case noDevice
  case deviceNotResponding(operation: String)
  case libmtp(operation: String, message: String)
  case verificationFailed(operation: String)
}
final class DeviceWorker: @unchecked Sendable {
  init(label: String)
  var isStuck: Bool { get }
  func run<T: Sendable>(_ operation: String, timeout: Duration, _ body: @escaping @Sendable () throws -> T) async throws -> T
}
struct TransferProgress: Sendable, Hashable { var sent: UInt64; var total: UInt64 }
protocol ZuneDeviceClient: Sendable {
  func connect() async throws -> DeviceSnapshot
  func refreshStorage() async throws -> StorageInfo
  func objectExists(_ id: UInt32) async throws -> Bool
  func download(_ id: UInt32, to url: URL, progress: @escaping @Sendable (TransferProgress) -> Void) async throws
  func albumArt(albumID: UInt32) async throws -> Data?
  func sendSong(_ song: LocalSong, progress: @escaping @Sendable (TransferProgress) -> Void) async throws -> MediaItem
  func createAlbum(name: String, artist: String, itemIDs: [UInt32]) async throws -> AlbumObject
  func updateAlbum(_ album: AlbumObject) async throws
  func setAlbumArt(albumID: UInt32, art: AlbumArt) async throws
  func delete(_ id: UInt32) async throws
  func disconnect() async
}
final class LiveZuneDevice: ZuneDeviceClient { init() }   // write methods throw until Task 6
```

`DeviceWorker`: runs bodies one at a time on a single dedicated `Thread`/serial queue. `run` races the body against `timeout`; on timeout it sets `isStuck = true` and throws `.deviceNotResponding(operation:)` (the body is left to finish on its own; its result is dropped). Once stuck, every later `run` throws `.deviceNotResponding` immediately without running its body.

`MTPSession` (internal, not Sendable, only touched inside worker bodies) wraps `LIBMTP_Init` (once), `LIBMTP_Detect_Raw_Devices` (first device; none → `.noDevice`), `LIBMTP_Open_Raw_Device`, `LIBMTP_Get_Friendlyname`, `LIBMTP_Get_Storage` (sum capacity/free over storages), `LIBMTP_Get_Tracklisting_With_Callback`, `LIBMTP_Get_Album_List`, `LIBMTP_Object_Exists_On_Device`, `LIBMTP_Get_Track_To_File`, `LIBMTP_Get_Representative_Sample` (returns the sample's data when `size > 0`, else `nil`), `LIBMTP_Release_Device`. Every failing call turns libmtp's error stack (`LIBMTP_Get_Errorstack`, then `LIBMTP_Clear_Errorstack`) into `.libmtp(operation:message:)`. Filetype mapping: `LIBMTP_FILETYPE_MP3` → `.mp3`, `LIBMTP_FILETYPE_M4A`/`LIBMTP_FILETYPE_MP4` → `.m4a`, `LIBMTP_FILETYPE_WMA` → `.wma`, else `.other`. Free every libmtp list it receives. Progress callbacks reach Swift through an `Unmanaged` box passed as the `data` pointer and always return 0.

`LiveZuneDevice` owns one `DeviceWorker` and one `MTPSession?`. Timeouts: `connect` 300 s; downloads and uploads `90 s + 1 s per MB`; everything else 90 s.

`zune-probe` subcommands (print plain lines; exit non-zero on error): `info` (name, storage, counts), `list` (one line per item: `id<TAB>artist<TAB>album<TAB>title<TAB>format`), `albums` (`id<TAB>artist<TAB>name<TAB>count`), `exists <id>` (`yes`/`no`), `get <id> <file>`, `art-get <albumID> <file.jpg>` (prints `no art` when none).

- [ ] **Step 1: Write the failing worker tests**

```swift
@Test func returnsValue() async throws { #expect(try await worker.run("x", timeout: .seconds(1)) { 42 } == 42) }
@Test func propagatesError() async      // body throws ZuneError.libmtp(operation: "x", message: "m") → same error
@Test func timesOutAndBecomesStuck() async {
  await #expect(throws: ZuneError.deviceNotResponding(operation: "slow")) {
    try await worker.run("slow", timeout: .milliseconds(100)) { Thread.sleep(forTimeInterval: 1); return 0 }
  }
  #expect(worker.isStuck)
}
@Test func stuckWorkerRefusesWithoutRunning() async  // after a timeout, a second run throws and its body never sets a flag
@Test func runsOneAtATime() async throws            // 10 concurrent runs; a shared counter never exceeds 1 inside bodies
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DeviceWorkerTests`
Expected: FAIL (types not defined).

- [ ] **Step 3: Implement `ZuneError`, `DeviceWorker`, `TransferProgress`, `ZuneDeviceClient`, `MTPSession` (read operations), `LiveZuneDevice` (read operations; write operations `throw ZuneError.libmtp(operation:, message: "not implemented")`), and `zune-probe`.**

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DeviceWorkerTests`
Expected: PASS.

- [ ] **Step 5: Verify against the real Zune** (owner: Zune plugged in, Helium closed; run commands one after another, never in parallel)

Run: `swift run zune-probe info`
Expected: `Skrud's Zune`, about 29.8 GB capacity, about 3,097 items and 316 albums; completes in under 5 minutes.

Run: `swift run zune-probe list | head -3` then `swift run zune-probe exists <first id>` and `swift run zune-probe exists 4000000000`
Expected: `yes`, then `no`.

Run: `swift run zune-probe get <an mp3 id> /tmp/zp.mp3 && file /tmp/zp.mp3`
Expected: `Audio file with ID3 …`.

Run: `swift run zune-probe albums | head -5`, then `swift run zune-probe art-get <album id> /tmp/zp.jpg` for two albums.
Expected: either a JPEG (`file` says `JPEG image data`) or `no art`. Record which in the commit message: this is the spec's unverified "reading art back" question.

- [ ] **Step 6: Commit** — "Add device worker, libmtp session and probe CLI (read operations)".

---

### Task 6: Device layer — writing to the Zune

**Files:**
- Modify: `Sources/ZuneKit/Device/MTPSession.swift`, `LiveZuneDevice.swift`, `Sources/zune-probe/main.swift`

**Interfaces:**
- Consumes: Task 3 `LocalSong`, `AlbumArt`, `MP3Fixture`, `ImageFixture`; Task 5 worker/session/protocol.
- Produces: working `LiveZuneDevice.sendSong`, `createAlbum`, `updateAlbum`, `setAlbumArt`, `delete`; probe commands `make-test-album <dir>`, `put <file.mp3>`, `mkalbum <name> <artist> <id>...`, `art-put <albumID> <image>`, `rm <id>...`.

Details:
- `sendSong`: fill a `LIBMTP_track_t` (title, artist, album, genre, `date` as `"<year>0101T000000.0"` when known, tracknumber, duration in ms, filesize, `filetype = LIBMTP_FILETYPE_MP3`, `filename` = the local file name, `parent_id` = the device's `default_music_folder`, `storage_id` = 0) and call `LIBMTP_Send_Track_From_File`. Return the `MediaItem` built from the track after the call (libmtp fills `item_id`).
- `createAlbum`: `LIBMTP_Create_New_Album` with name, artist, tracks; return the album with its new id. `updateAlbum`: `LIBMTP_Update_Album`. `setAlbumArt`: `LIBMTP_new_filesampledata_t` with `filetype = LIBMTP_FILETYPE_JPEG`, width, height, size, data; `LIBMTP_Send_Representative_Sample`. `delete`: `LIBMTP_Delete_Object`.
- `make-test-album <dir>` writes three MP3s with `MP3Fixture`: artist and album artist `Claude Test`, album `Claude Test Album`, tracks `1/3`..`3/3`, titles `Probe One`, `Probe Two`, `Tëst Ünicode / Song`, embedded art `ImageFixture.jpeg(width: 300, height: 300)`.
- `put` reads tags with `TagReader`, sends, then prints `sent <id>` and `verified` (via `objectExists`) or fails.

- [ ] **Step 1: Implement the write operations and the probe commands.**

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Device test — add** (owner present; Zune plugged in; Helium closed)

Run: `swift run zune-probe make-test-album /tmp/claude-test`, then `swift run zune-probe put` for each of the three files.
Expected: three `sent <id>` + `verified` lines.

Run: `swift run zune-probe mkalbum "Claude Test Album" "Claude Test" <id1> <id2> <id3>`, then `swift run zune-probe art-put <albumID> <one of the mp3s' cover, or ImageFixture output>`.
Expected: `album <id>` then `art set`.

Run: `swift run zune-probe art-get <albumID> /tmp/zp-art.jpg && file /tmp/zp-art.jpg`
Expected: `JPEG image data … 240 x 240` (if it prints `no art`, record that reading art back does not work; the app will show placeholders).

- [ ] **Step 4: Owner checks the Zune.** Ask the owner to unplug and look under Music → Artists → `Claude Test`: one album, three songs in order, `Tëst Ünicode / Song` spelled correctly, cover art showing, each song plays. Record the answer.

- [ ] **Step 5: Device test — remove** (replug first)

Run: `swift run zune-probe rm <id1> <id2> <id3> <albumID>`, then `swift run zune-probe exists` for each.
Expected: four `no`.

- [ ] **Step 6: Commit** — "Add writing to the Zune (songs, albums, art, delete)", with the art-read and owner-check results in the message body.

---

### Task 7: App state — connect, browse, delete, export, art cache

**Files:**
- Create: `Sources/ZuneKit/Store/ZuneStore.swift`, `OperationSummary.swift`
- Test: `Tests/ZuneKitTests/FakeZuneDevice.swift`, `ZuneStoreTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 4, 5.
- Produces:

```swift
struct OperationSummary: Hashable, Sendable {
  var title: String; var succeeded: [String]; var skipped: [String]; var failed: [String: String]   // name → reason
  var notDone: [String]
}
struct Activity: Hashable, Sendable { var title: String; var fileIndex: Int; var fileCount: Int; var fraction: Double; var cancelRequested: Bool }
@MainActor @Observable final class ZuneStore {
  enum Phase: Equatable { case waitingForDevice, connecting, ready, stuck, failed(String) }
  static let stuckMessage: String          // exact copy from Global Constraints
  private(set) var phase: Phase
  private(set) var snapshot: DeviceSnapshot?
  private(set) var index: LibraryIndex?
  var selectedArtist: String?; var selectedAlbum: AlbumKey?; var selectedItemIDs: Set<UInt32>; var searchText: String
  private(set) var activity: Activity?
  private(set) var lastSummary: OperationSummary?
  init(makeClient: @escaping @Sendable () -> any ZuneDeviceClient)
  func deviceAttached() async
  func deviceDetached()
  func reconnect() async
  func deletePlan(for selection: Selection) -> DeletePlan?
  func delete(_ plan: DeletePlan) async
  func export(_ selection: Selection, to folder: URL) async
  func albumArt(albumObjectID: UInt32) async -> Data?
  func cancelAfterCurrentFile()
  func dismissSummary()
}
```

Behaviour:
- `deviceAttached` (when `waitingForDevice` or `failed`): `phase = .connecting`, create a client, `connect()`, then `.ready` with snapshot and index. `.deviceNotResponding` from any call, at any time → `phase = .stuck` (the UI shows `stuckMessage` and Quit). Any other connect error → `.failed(<message>)`. `reconnect` = disconnect + `deviceAttached`.
- `deviceDetached`: an operation in progress stops after its current call; the remaining files go to `summary.notDone`; `phase = .waitingForDevice`; snapshot and index cleared.
- One operation at a time: `delete`/`export`/`add` return immediately when `activity != nil`.
- `delete(plan)`: for each item id: `delete`, then `objectExists` must be `false` (else `failed[title] = "still on the Zune after deleting"`); on success remove it from the snapshot and from any album object's `itemIDs`. Then delete the plan's album objects, verified the same way. Rebuild the index, `refreshStorage`, set `lastSummary`.
- `export(selection, to:)`: for each item, destination = folder + `ExportNaming.relativePath`; existing file → `skipped`; otherwise download to a temp file in the destination folder, check its size equals `fileSize` (else `failed`), then move into place, creating directories.
- `cancelAfterCurrentFile` sets `activity.cancelRequested`; the loop checks it between files and lists the rest under `notDone`.
- `albumArt` caches per album object id for the session, including `nil` results.
- Progress callbacks update `activity` on the main actor.

`FakeZuneDevice` (actor conforming to `ZuneDeviceClient`): in-memory items/albums/storage; a `calls: [String]` log with exactly these entries per method: `connect`, `storage` (refreshStorage), `exists <id>`, `download <id>`, `art <albumID>` (albumArt), `send <title>`, `createAlbum <name>`, `updateAlbum <albumID>`, `setArt <albumID>`, `delete <id>`, `disconnect`; new item ids start at 11 and new album ids at 101; injectable failures: `connectError`, `stuckOn: Set<String>` (operation names that throw `.deviceNotResponding`), `failSendFor: Set<String>` (titles), `existsAfterDelete: Bool`, and `onDownload: (@Sendable (UInt32) async -> Void)?` hook.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func connectPopulatesIndex() async      // phase == .ready; index?.artists(matching: "") == ["Rush"]
@Test func connectTimeoutIsStuck() async      // stuckOn ["connect"] → phase == .stuck
@Test func connectErrorIsFailed() async       // connectError .libmtp → phase == .failed(...)
@Test func deleteAlbumDeletesTracksThenAlbum() async {
  await store.delete(plan)  // album with items 1, 2 and album object 100
  #expect(fake.calls == ["delete 1", "exists 1", "delete 2", "exists 2", "delete 100", "exists 100", "storage"])
  #expect(store.index?.item(1) == nil && store.lastSummary?.succeeded.count == 2)
}
@Test func deleteVerificationFailureIsReported() async   // existsAfterDelete = true → failed has the title; item still in snapshot
@Test func detachDuringDeleteStopsAndReports() async {
  // fake calls store.deviceDetached() from inside its first "delete" call
  #expect(store.phase == .waitingForDevice && store.lastSummary?.notDone.count == 1)
}
@Test func exportWritesNamedFilesAndSkipsExisting() async  // pre-existing "Rush/2112/02 A Passage to Bangkok.mp3" → skipped; other file written with fake's bytes
@Test func exportSizeMismatchFails() async                  // fake writes fewer bytes than fileSize → failed
@Test func cancelStopsBetweenFiles() async                  // onDownload of first item calls cancelAfterCurrentFile → 1 succeeded, rest notDone
@Test func secondOperationIgnoredWhileBusy() async          // start export, call delete concurrently → no delete calls
@Test func albumArtIsCached() async                         // two calls → fake.calls.filter { $0.hasPrefix("art") }.count == 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ZuneStoreTests`
Expected: FAIL (types not defined).

- [ ] **Step 3: Implement `OperationSummary`, `Activity`, `ZuneStore` (everything above) and `FakeZuneDevice`.**

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 5: Commit** — "Add app state: connect, browse, delete, export".

---

### Task 8: App state — adding songs

**Files:**
- Create: `Sources/ZuneKit/Store/ZuneStore+Add.swift`
- Test: `Tests/ZuneKitTests/ZuneStoreAddTests.swift`

**Interfaces:**
- Consumes: Tasks 3, 4, 7.
- Produces:

```swift
struct AddPreparation: Sendable, Hashable { var songs: [LocalSong]; var duplicates: [Duplicate]; var nonMP3: [URL]; var unreadable: [URL: String] }
extension ZuneStore {
  func prepareAdd(_ urls: [URL]) async -> AddPreparation        // FileScanner + TagReader + Duplicates against snapshot
  func planAdd(_ prep: AddPreparation, choices: [URL: DuplicateChoice]) throws -> AddPlan   // AddPlanner with current free space
  func add(_ plan: AddPlan, preparation: AddPreparation) async
}
```

`add` per step, checking `cancelRequested` between steps:
1. `deleteThenUpload` with `replacing`: delete the old item, verify gone, remove from snapshot and album objects.
2. `sendSong`; verify `objectExists(id)`; add the item to the snapshot. A failure goes to `failed[title]` and the loop moves to the next step.
3. `AddPlanner.albumTarget` against the snapshot's current albums: `.existing` → `updateAlbum` with the new id appended; `.create` → `createAlbum` and then album art: `song.embeddedArtwork`, else the data of `FileScanner.coverImage(forSongAt:)`, through `Artwork.zuneAlbumArt`, then `setAlbumArt`. Art failures are recorded in `failed["<album> (art)"]` without failing the song. The new or updated album goes into the snapshot so later songs of the batch reuse it.
4. `uploadThenDelete` with `replacing`: delete the old item, verify gone, remove from snapshot and album objects.

The summary lists added songs in `succeeded`; `skippedDuplicates`, `skippedInBatch`, `nonMP3` and `unreadable` in `skipped` (with the reason in the name, e.g. `notes.txt (not an MP3)`); rebuild the index; `refreshStorage`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func addCreatesAlbumWithArtThenReusesIt() async throws {
  // two songs, same album "2112"/"Rush", first has embedded art; no album on the fake
  #expect(fake.calls == ["send Tears", "exists 11", "createAlbum 2112", "setArt 101",
                         "send Lessons", "exists 12", "updateAlbum 101", "storage"])
}
@Test func addAppendsToExistingAlbumObject() async throws   // album object 100 exists → updateAlbum 100 with itemIDs [1, 2, 11]
@Test func addUsesCoverJpgWhenNoEmbeddedArt() async throws  // folder has cover.jpg → "setArt …" present
@Test func duplicateSkippedByDefault() async throws         // existing "Tears" → no "send Tears"; summary.skipped contains "Tears"
@Test func overwriteUploadsBeforeDeleting() async throws {
  // plenty of space, choice .overwrite for "Tears" (existing id 5)
  #expect(fake.calls.firstIndex(of: "send Tears")! < fake.calls.firstIndex(of: "delete 5")!)
}
@Test func overwriteDeletesFirstWhenTight() async throws    // plan.overwriteMode == .deleteThenUpload and "delete 5" precedes "send Tears"
@Test func addRefusesBeforeSendingWhenNoSpace() async {
  #expect(throws: AddPlanError.self) { try store.planAdd(prep, choices: [:]) }
  #expect(!fake.calls.contains { $0.hasPrefix("send") })
}
@Test func failedSendContinuesWithNext() async throws       // failSendFor ["Tears"] → failed["Tears"], "Lessons" still sent
@Test func nonMP3FilesReportedAsSkipped() async throws      // notes.txt → skipped contains "notes.txt (not an MP3)"
```

(Fixture files come from `MP3Fixture` in a temp directory; the fake assigns item ids from 11 and album ids from 101.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ZuneStoreAddTests`
Expected: FAIL (`prepareAdd` not defined).

- [ ] **Step 3: Implement `ZuneStore+Add.swift`.**

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 5: Commit** — "Add songs: duplicates, overwrite order, albums and art".

---

### Task 9: The app window — connection states, column browser, search, packaging

**Files:**
- Create: `Sources/ZuneManager/ZuneManagerApp.swift`, `USBWatcher.swift`, `Views/ContentView.swift`, `Views/StatusViews.swift`, `Views/ColumnBrowserView.swift`, `Views/AlbumArtThumbnail.swift`, `Views/FooterView.swift`, `Resources/Info.plist`, `scripts/bundle-app.sh`

**Interfaces:**
- Consumes: `ZuneStore` (Tasks 7–8), `LiveZuneDevice` (Task 5).
- Produces: `final class USBWatcher { init(vendorID: Int = 0x045E, productID: Int = 0x0710, onAttach: @escaping @MainActor () -> Void, onDetach: @escaping @MainActor () -> Void) }`; a runnable `build/Zune Manager.app`.

Details:
- `USBWatcher`: IOKit `IOServiceAddMatchingNotification` for `kIOFirstMatchNotification` and `kIOTerminatedNotification` on `IOServiceMatching("IOUSBHostDevice")` with `idVendor`/`idProduct`; drain both iterators at start (so an already-plugged Zune reports attach). On attach, wait 2 seconds before calling `store.deviceAttached()` (the Zune needs a moment after plugging in).
- `ContentView` switches on `store.phase`: `waitingForDevice` → "Connect your Zune" with a reminder to close Chromium-based browsers; `connecting` → spinner and "Reading your Zune… this takes about a minute"; `stuck` → `ZuneStore.stuckMessage` with a **Quit** button (`NSApp.terminate`); `failed(msg)` → the message, its details, and **Reconnect**; `ready` → browser.
- `ColumnBrowserView` (the layout the owner picked, option A): three side-by-side lists — Artists, Albums, Songs — backed by `index.artists/albums/items` with `store.searchText`. Selecting an artist sets `selectedArtist` and clears album selection; selecting an album sets `selectedAlbum`. Album rows show `AlbumArtThumbnail` (32 pt; loads via `store.albumArt` in `.task`, placeholder when `nil` or no album object). Song rows: `<track>. <title>` and duration `m:ss`. Songs allow multiple selection into `selectedItemIDs`.
- Toolbar: device name, **Add…** button (disabled for now, wired in Task 10), `.searchable(text: $store.searchText)`.
- `FooterView`: `<n> songs` (count of visible songs; `3,097 songs` style grouping), a capacity bar, and `<free> free of <capacity>` with `ByteCountFormatter` `.file` style.
- `scripts/bundle-app.sh`: `swift build -c release --product ZuneManager`; create `build/Zune Manager.app/Contents/MacOS/ZuneManager` and `Contents/Info.plist` (copied from `Resources/Info.plist`: `CFBundleIdentifier com.skrud.ZuneManager`, `CFBundleName Zune Manager`, `CFBundleExecutable ZuneManager`, `CFBundlePackageType APPL`, `LSMinimumSystemVersion 14.0`, `NSPrincipalClass NSApplication`, `NSHighResolutionCapable true`); `codesign --force -s - "build/Zune Manager.app"`; print the path.

- [ ] **Step 1: Implement the files above.**

- [ ] **Step 2: Build and package**

Run: `swift build && scripts/bundle-app.sh`
Expected: `build/Zune Manager.app` printed; `swift test` still passes.

- [ ] **Step 3: Check it with the owner** (Helium closed)
  - Open the app with the Zune unplugged → "Connect your Zune".
  - Plug it in → "Reading your Zune…", then the three columns appear within about 5 minutes, footer shows about `3,097 songs` and `… free of 29.8 GB`.
  - Click `Rush` → only Rush albums; click an album → its songs in track order.
  - Type `motor` (or another partial name from the library) in search → columns narrow live.
  - Album covers appear (or placeholders if Task 5 found art can't be read back).
  - Unplug → back to "Connect your Zune"; plug in → reconnects without restarting the app.

- [ ] **Step 4: Commit** — "Add app window: connection states, column browser, search and packaging".

---

### Task 10: The app window — add, delete, save to Mac; end-to-end check

**Files:**
- Create: `Sources/ZuneManager/Views/AddFlow.swift`, `Views/DuplicatesSheet.swift`, `Views/ActivityBar.swift`, `Views/SummarySheet.swift`
- Modify: `Views/ColumnBrowserView.swift`, `Views/ContentView.swift`

**Interfaces:**
- Consumes: `ZuneStore` add/delete/export API (Tasks 7–8), `DeletePlan.confirmationText`, `AddPlan.overwriteMode`.

Details:
- **Add:** the toolbar **Add…** opens an `NSOpenPanel` (files and folders, multiple, `.mp3` and folders); dropping files or folders onto the window does the same. Flow: `prepareAdd` → if duplicates, `DuplicatesSheet` (one row per duplicate: title, artist, album, existing format vs incoming format, a per-row Overwrite/Skip picker defaulting to Skip, plus **Overwrite All** and **Skip All**) → `planAdd` (a `notEnoughSpace` error is shown as "Not enough space on your Zune: needs <size>, <size> free.") → if `overwriteMode == .deleteThenUpload`, confirm with: `There isn't enough free space to copy the new versions first. Zune Manager will delete the existing copies of <n> songs before copying the new ones. If a copy fails, those songs will be missing from your Zune.` (buttons **Delete and Copy** / **Cancel**) → `add`.
- **Delete:** context menu item **Delete from Zune…** on artist, album and song rows, and the Delete key in each column, build a `Selection`, get `store.deletePlan`, and show a confirmation dialog with `confirmationText` and a destructive **Delete** button.
- **Save to Mac…:** context menu item on the same rows; an `NSOpenPanel` choosing a folder; `store.export`.
- **ActivityBar:** while `activity != nil`, a bar above the footer: title, `file <i> of <n>`, a progress bar, **Cancel** (→ `cancelAfterCurrentFile`, label changes to "Stopping after this file…"). Add/Delete/Save are disabled meanwhile.
- **SummarySheet:** shown when `lastSummary` is set: counts and expandable lists of succeeded, skipped, failed (with reasons) and not done; **OK** → `dismissSummary`.

- [ ] **Step 1: Implement the views and wire them in.**

- [ ] **Step 2: Build and package**

Run: `swift test && scripts/bundle-app.sh`
Expected: tests PASS; app bundle printed.

- [ ] **Step 3: End-to-end check with the owner** (Helium closed). Make test content with `swift run zune-probe make-test-album /tmp/claude-test` (quit the app before running the probe; only one program may use the Zune at a time).
  1. Add the `/tmp/claude-test` folder with **Add…** → progress, summary `3 added`; `Claude Test` → `Claude Test Album` shows three songs with a cover.
  2. Add the same folder again → the duplicates sheet lists three songs; **Skip All** → summary `3 skipped`.
  3. Add again → **Overwrite All** → summary `3 added`; still exactly three songs in the album.
  4. **Save to Mac…** on the album to `/tmp/claude-export` → `Claude Test/Claude Test Album/01 Probe One.mp3`, `02 Probe Two.mp3`, `03 Tëst Ünicode _ Song.mp3`; `file` reports MP3s with ID3; saving again → `3 skipped`.
  5. Quit the app, unplug, owner checks the Zune: `Claude Test` album, three songs, cover, plays.
  6. Replug, open the app, **Delete from Zune…** on the album → the confirmation reads `Delete 'Claude Test Album' by Claude Test (3 songs, <size>) from your Zune? This can't be undone.` → **Delete** → album and artist disappear; free space goes back up.
  7. Quit, unplug, owner checks: `Claude Test` is gone from the Zune's menus.

- [ ] **Step 4: Commit** — "Add, delete and save to Mac from the app window".
