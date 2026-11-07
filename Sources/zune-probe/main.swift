// zune-probe: drives the real Zune from the terminal through the same code the app uses.
// Only one program can use the Zune at a time: quit Zune Manager before running this.
import Foundation
import ZuneKit
import ZuneTestSupport

let usage = """
    usage: zune-probe <command>
      info                      device name, storage, item and album counts
      list                      id, artist, album, title, format of every item
      albums                    id, artist, name, track count of every album object
      exists <id>               yes / no
      get <id> <file>           copy an item to the Mac
      art-get <albumID> <file>  save an album object's cover (prints "no art" if none)
      make-test-album <dir>     write three tagged test MP3s (artist "Claude Test"); no Zune needed
      put <file.mp3>            copy an MP3 to the Zune and verify it arrived
      mkalbum <name> <artist> <id>...   create an album object
      art-put <albumID> <image> set an album object's cover
      rm <id>...                delete objects and verify they're gone
      add-test-album <dir>      put every MP3 in <dir>, make one album with the first file's art,
                                verify everything, read the art back (one connection)
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func id(_ s: String) -> UInt32 {
    guard let v = UInt32(s) else { fail("not an id: \(s)") }
    return v
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail(usage) }

if command == "make-test-album", args.count == 2 {
    let dir = URL(fileURLWithPath: args[1])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let art = ImageFixture.jpeg(width: 300, height: 300)
    for (n, title) in ["Probe One", "Probe Two", "Tëst Ünicode / Song"].enumerated() {
        let file = dir.appendingPathComponent(String(format: "%02d.mp3", n + 1))
        try MP3Fixture.write(to: file, title: title, artist: "Claude Test", album: "Claude Test Album",
                             albumArtist: "Claude Test", track: "\(n + 1)/3", year: "2026", genre: "Test",
                             artworkJPEG: art, seconds: 10)
        print("wrote \(file.path)")
    }
    exit(0)
}

if command == "make-unicode-check", args.count == 2 {
    // Two songs telling apart "the Zune reads titles from the file's tags" from "the Zune shows
    // the title sent over MTP": one has a UTF-16 ID3 title, the other has no title tag at all
    // (its title comes from the file name, sent over MTP only).
    let dir = URL(fileURLWithPath: args[1])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let art = ImageFixture.jpeg(width: 300, height: 300)
    try MP3Fixture.write(to: dir.appendingPathComponent("01.mp3"), title: "Tëst ID3 Ünicode",
                         artist: "Claude Test", album: "Claude Test Album 2", albumArtist: "Claude Test",
                         track: "1", artworkJPEG: art, seconds: 10)
    try MP3Fixture.write(to: dir.appendingPathComponent("Tëst MTP-only Ünicode.mp3"), title: nil,
                         artist: "Claude Test", album: "Claude Test Album 2", albumArtist: "Claude Test",
                         track: "2", artworkJPEG: art, seconds: 10)
    print("wrote \(dir.path)")
    exit(0)
}

let device = LiveZuneDevice()

func put(_ file: URL) async throws -> (LocalSong, MediaItem) {
    let song = try await TagReader.read(file)
    let item = try await device.sendSong(song) { _ in }
    print("sent \(item.id) \(song.title)")
    guard try await device.objectExists(item.id) else { fail("not verified: \(item.id)") }
    print("verified")
    return (song, item)
}

do {
    let snapshot = try await device.connect()
    switch (command, args.count) {
    case ("info", 1):
        let gb = { (b: UInt64) in String(format: "%.1f GB", Double(b) / 1e9) }
        print(snapshot.deviceName)
        print("storage: \(gb(snapshot.storage.freeBytes)) free of \(gb(snapshot.storage.capacityBytes))")
        print("items: \(snapshot.items.count)")
        print("albums: \(snapshot.albums.count)")
    case ("list", 1):
        for i in snapshot.items {
            print([String(i.id), i.artist, i.album, i.title, i.format.rawValue].joined(separator: "\t"))
        }
    case ("albums", 1):
        for a in snapshot.albums {
            print([String(a.id), a.artist, a.name, String(a.itemIDs.count)].joined(separator: "\t"))
        }
    case ("exists", 2):
        print(try await device.objectExists(id(args[1])) ? "yes" : "no")
    case ("get", 3):
        try await device.download(id(args[1]), to: URL(fileURLWithPath: args[2])) { _ in }
        print("saved \(args[2])")
    case ("art-get", 3):
        if let data = try await device.albumArt(albumID: id(args[1])) {
            try data.write(to: URL(fileURLWithPath: args[2]))
            print("saved \(args[2]) (\(data.count) bytes)")
        } else {
            print("no art")
        }
    case ("read-check", 2):
        // exists (real + bogus id), copy the first MP3 to <dir>, read art for the first albums.
        let dir = URL(fileURLWithPath: args[1])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let mp3 = snapshot.items.first(where: { $0.format == .mp3 }) else { fail("no MP3s") }
        print("exists \(mp3.id): \(try await device.objectExists(mp3.id) ? "yes" : "no")")
        print("exists 4000000000: \(try await device.objectExists(4_000_000_000) ? "yes" : "no")")
        let file = dir.appendingPathComponent("item.mp3")
        try await device.download(mp3.id, to: file) { _ in }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        print("get \(mp3.id) '\(mp3.title)': \(size?.uint64Value ?? 0) bytes (expected \(mp3.fileSize))")
        for album in snapshot.albums.prefix(3) {
            if let data = try await device.albumArt(albumID: album.id) {
                try data.write(to: dir.appendingPathComponent("art-\(album.id).jpg"))
                print("art \(album.id) '\(album.name)': \(data.count) bytes")
            } else {
                print("art \(album.id) '\(album.name)': no art")
            }
        }
    case ("put", 2):
        _ = try await put(URL(fileURLWithPath: args[1]))
    case ("mkalbum", _) where args.count >= 4:
        let album = try await device.createAlbum(name: args[1], artist: args[2], itemIDs: args[3...].map(id))
        print("album \(album.id)")
    case ("art-put", 3):
        let image = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        guard let art = Artwork.zuneAlbumArt(from: image) else { fail("not an image: \(args[2])") }
        try await device.setAlbumArt(albumID: id(args[1]), art: art)
        print("art set (\(art.width)x\(art.height))")
    case ("rm", _) where args.count >= 2:
        for target in args[1...].map(id) {
            try await device.delete(target)
            let gone = try await !device.objectExists(target)
            print("deleted \(target): \(gone ? "gone" : "STILL THERE")")
            if !gone { fail("delete not verified: \(target)") }
        }
    case ("add-test-album", 2):
        let files = FileScanner.scan([URL(fileURLWithPath: args[1])]).mp3s
        guard let first = files.first else { fail("no MP3s in \(args[1])") }
        var sent: [(LocalSong, MediaItem)] = []
        for file in files { sent.append(try await put(file)) }
        let song = sent[0].0
        let album = try await device.createAlbum(name: song.album, artist: song.effectiveAlbumArtist,
                                                 itemIDs: sent.map(\.1.id))
        print("album \(album.id)")
        guard let embedded = try await TagReader.read(first).embeddedArtwork,
              let art = Artwork.zuneAlbumArt(from: embedded) else { fail("first file has no art") }
        try await device.setAlbumArt(albumID: album.id, art: art)
        print("art set (\(art.width)x\(art.height))")
        if let back = try await device.albumArt(albumID: album.id) {
            print("art read back: \(back.count) bytes, JPEG: \(back.starts(with: [0xFF, 0xD8]))")
        } else {
            print("art read back: no art")
        }
        print("ids to remove: \((sent.map(\.1.id) + [album.id]).map(String.init).joined(separator: " "))")
    default:
        await device.disconnect()
        fail(usage)
    }
    await device.disconnect()
} catch {
    await device.disconnect()
    fail("error: \(error)")
}
