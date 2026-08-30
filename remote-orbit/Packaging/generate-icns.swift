import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate-icns.swift INPUT.iconset OUTPUT.icns\n".utf8))
    exit(64)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png"),
]

func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

var payload = Data()
for (type, filename) in entries {
    let url = iconsetURL.appendingPathComponent(filename)
    guard let png = try? Data(contentsOf: url), !png.isEmpty else {
        FileHandle.standardError.write(Data("missing iconset member: \(filename)\n".utf8))
        exit(1)
    }
    payload.append(contentsOf: type.utf8)
    payload.append(bigEndian(UInt32(8 + png.count)))
    payload.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndian(UInt32(8 + payload.count)))
icns.append(payload)
try icns.write(to: outputURL, options: .atomic)
