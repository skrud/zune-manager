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
let device = LiveZuneDevice()

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
    default:
        await device.disconnect()
        fail(usage)
    }
    await device.disconnect()
} catch {
    await device.disconnect()
    fail("error: \(error)")
}
