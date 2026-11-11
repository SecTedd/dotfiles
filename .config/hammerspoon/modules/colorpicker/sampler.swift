// macOS's color sampler (the loupe with the pixel grid) as a command:
//   sampler [colorSpace]      default sRGB; also displayP3, adobeRGB, genericRGB
// Prints the picked pixel as #rrggbb in that color space and exits 0.
// Esc (nothing picked) exits 1, an unknown color space exits 2.
// Compiled by setup.sh with the Xcode command-line tools; run by
// modules/colorpicker.lua, which puts the hex on the clipboard.
import AppKit

let spaces: [String: NSColorSpace] = [
    "sRGB": .sRGB,
    "displayP3": .displayP3,
    "adobeRGB": .adobeRGB1998,
    "genericRGB": .genericRGB,
]

let requested = CommandLine.arguments.dropFirst().first ?? "sRGB"
guard let space = spaces[requested] else {
    let known = spaces.keys.sorted().joined(separator: ", ")
    FileHandle.standardError.write(Data("unknown color space \(requested) (one of: \(known))\n".utf8))
    exit(2)
}

func hex(_ color: NSColor) -> String? {
    guard let c = color.usingColorSpace(space) else { return nil }
    func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "#%02x%02x%02x", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar
NSColorSampler().show { picked in
    guard let picked, let out = hex(picked) else { exit(1) }
    print(out)
    exit(0)
}
app.run()
