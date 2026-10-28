import Foundation

/// The screenshot in a MesenCE save state (`.mss`), drawn as MesenCE's default video filter draws each console's
/// picture with its default settings (ADR 0027). The state's header is "MSS", MesenCE's version, the format's
/// version, the console, then the frame as the console's PPU left it, 16 bits a pixel and zlib-compressed, then the
/// ROM's file name.
public enum MesenScreenshot {
    /// The screenshot in `file`; nil when it can't be read, or its console isn't one Ludeum plays with MesenCE.
    public static func of(_ file: URL) -> SaveStateScreenshot? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return decode(data)
    }

    /// The screenshot in a state's bytes.
    static func decode(_ data: Data) -> SaveStateScreenshot? {
        var reader = Reader(data: data)
        guard reader.bytes(3) == Data("MSS".utf8), reader.u32() != nil, let format = reader.u32(), (3...4).contains(format)
        else { return nil }
        // Format 3 had a SHA-1, as 40 hex digits, after its version.
        if format == 3 { _ = reader.bytes(40) }
        guard let console = reader.u32(), let size = reader.u32(), let width = reader.u32(), let height = reader.u32(),
            reader.u32() != nil, let packedSize = reader.u32(), packedSize > 2, packedSize <= 2 << 20,
            let packed = reader.bytes(packedSize), let nameSize = reader.u32(), nameSize <= 4096,
            let name = reader.bytes(nameSize).flatMap({ String(data: $0, encoding: .utf8) })
        else { return nil }
        // zlib's: its 2-byte header, then deflate.
        guard let frame = try? (packed.dropFirst(2) as NSData).decompressed(using: .zlib) as Data, frame.count >= size
        else { return nil }
        let bytes = [UInt8](frame)
        let pixels = (0..<bytes.count / 2).map { UInt16(bytes[$0 * 2]) | UInt16(bytes[$0 * 2 + 1]) << 8 }
        switch console {
        case 0: return snes(pixels, width: width, height: height)
        case 1: return gameBoy(pixels, width: width, height: height)
        case 2: return nes(pixels, width: width, height: height)
        case 3: return pcEngine(pixels)
        case 4: return masterSystem(pixels, width: width, height: height, gameGear: (name as NSString).pathExtension.lowercased() == "gg")
        case 5: return gameBoyAdvance(pixels, width: width, height: height)
        default: return nil
        }
    }

    /// The pixels from `x`, `y`, `width` × `height` of a frame `stride` wide, coloured by `color`.
    private static func picture(
        _ pixels: [UInt16], stride: Int, x: Int = 0, y: Int = 0, width: Int, height: Int, color: (UInt16) -> UInt32
    ) -> SaveStateScreenshot? {
        guard width > 0, height > 0, (y + height - 1) * stride + x + width <= pixels.count else { return nil }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let rgb = color(pixels[(y + row) * stride + x + column])
                let at = (row * width + column) * 4
                rgba[at] = UInt8(rgb >> 16 & 0xFF)
                rgba[at + 1] = UInt8(rgb >> 8 & 0xFF)
                rgba[at + 2] = UInt8(rgb & 0xFF)
            }
        }
        return SaveStateScreenshot(width: width, height: height, rgba: Data(rgba))
    }

    /// 0xRRGGBB from 5-bit channels, as MesenCE widens them.
    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        func widen(_ c: Int) -> UInt32 { UInt32(c << 3 | c >> 2) }
        return widen(r) << 16 | widen(g) << 8 | widen(b)
    }

    /// 0xRRGGBB from 15-bit colour, red in the low 5 bits.
    private static func color15(_ pixel: UInt16) -> UInt32 {
        rgb(Int(pixel & 0x1F), Int(pixel >> 5 & 0x1F), Int(pixel >> 10 & 0x1F))
    }

    /// The NES's: a palette index with the emphasis bits above it, 256 × 240 with nothing cropped by default
    /// (`NesDefaultVideoFilter`).
    static func nes(_ pixels: [UInt16], width: Int, height: Int) -> SaveStateScreenshot? {
        guard width == 256, height == 240 else { return nil }
        return picture(pixels, stride: width, width: width, height: height) { nesColor($0 & 0x1FF) }
    }

    /// A 2C02's colour: the palette's, darkened by 0.84 in each channel not emphasised, but in columns $xE and $xF.
    static func nesColor(_ index: UInt16) -> UInt32 {
        let base = nesPalette[Int(index & 0x3F)]
        let emphasis = index >> 6
        guard emphasis != 0, index & 0x0F <= 0x0D else { return base }
        var (r, g, b) = (Double(base >> 16 & 0xFF), Double(base >> 8 & 0xFF), Double(base & 0xFF))
        if emphasis & 1 != 0 { (g, b) = (g * 0.84, b * 0.84) }
        if emphasis & 2 != 0 { (r, b) = (r * 0.84, b * 0.84) }
        if emphasis & 4 != 0 { (r, g) = (r * 0.84, g * 0.84) }
        return UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
    }

    /// The SNES's (and a Super Game Boy's, border and all): 15-bit, 256 × 239, or 512 × 478 in its high resolution,
    /// 7 rows cropped from the top and 8 from the bottom, twice that in high resolution (`SnesDefaultVideoFilter`).
    static func snes(_ pixels: [UInt16], width: Int, height: Int) -> SaveStateScreenshot? {
        guard (width, height) == (256, 239) || (width, height) == (512, 478) else { return nil }
        let scale = width / 256
        return picture(pixels, stride: width, y: 7 * scale, width: width, height: height - 15 * scale) { color15($0) }
    }

    /// The Game Boy's and Game Boy Color's: 15-bit, 160 × 144, its colours adjusted toward a Game Boy Color's screen, as
    /// MesenCE does by default when it plays a Game as a Game Boy Color (`GbDefaultVideoFilter`), which it always does
    /// with Ludeum's default model but for a Super Game Boy Game, on the SNES. A Game set to play as a Game Boy is
    /// adjusted too, its white a light gray. MesenCE's blending with the frame before isn't done.
    static func gameBoy(_ pixels: [UInt16], width: Int, height: Int) -> SaveStateScreenshot? {
        guard width == 160, height == 144 else { return nil }
        return picture(pixels, stride: width, width: width, height: height) { pixel in
            let (r, g, b) = (Int(pixel & 0x1F), Int(pixel >> 5 & 0x1F), Int(pixel >> 10 & 0x1F))
            let r2 = min(240, (r * 26 + g * 4 + b * 2) >> 2)
            let g2 = min(240, (g * 24 + b * 8) >> 2)
            let b2 = min(240, (r * 6 + g * 4 + b * 22) >> 2)
            return UInt32(r2) << 16 | UInt32(g2) << 8 | UInt32(b2)
        }
    }

    /// The Game Boy Advance's: 15-bit, 240 × 160, its colours adjusted toward its screen's, as MesenCE does by default
    /// (`GbaDefaultVideoFilter`). MesenCE's blending with the frame before isn't done.
    static func gameBoyAdvance(_ pixels: [UInt16], width: Int, height: Int) -> SaveStateScreenshot? {
        guard width == 240, height == 160 else { return nil }
        return picture(pixels, stride: width, width: width, height: height) { gameBoyAdvanceColors[Int($0 & 0x7FFF)] }
    }

    private static let gameBoyAdvanceColors: [UInt32] = (0..<0x8000).map { pixel in
        let lr = pow(Double(pixel & 0x1F) / 31, 4)
        let lg = pow(Double(pixel >> 5 & 0x1F) / 31, 4)
        let lb = pow(Double(pixel >> 10 & 0x1F) / 31, 4)
        func channel(_ linear: Double) -> UInt32 { UInt32(min(pow(linear / 255, 1 / 2.2) * 0xFFFF / 280, 255)) }
        return channel(50 * lg + 240 * lr) << 16 | channel(30 * lb + 230 * lg + 10 * lr) << 8 | channel(220 * lb + 10 * lg + 50 * lr)
    }

    /// The Master System's and Game Gear's: 15-bit in a 256 × 240 frame whose first 192 rows are the picture, taken
    /// to be in its usual 192-line mode, as MesenCE's state of the VDP isn't read. The Game Gear's is the 160 × 144
    /// in the middle of that; it's taken to be one when the ROM is a `.gg` (`SmsDefaultVideoFilter`). MesenCE's
    /// blending of a Game Gear's with the frame before isn't done.
    static func masterSystem(_ pixels: [UInt16], width: Int, height: Int, gameGear: Bool) -> SaveStateScreenshot? {
        guard width == 256, height == 240 else { return nil }
        if gameGear {
            return picture(pixels, stride: width, x: 48, y: 24, width: 160, height: 144) { color15($0) }
        }
        return picture(pixels, stride: width, width: width, height: 192) { color15($0) }
    }

    /// The PC Engine's: rows 682 wide, 242 of them and one more giving each row's clock divider, its colours GRB333
    /// through MesenCE's palette, gray when bit 9 is set. With MesenCE's default 18 columns cropped either side and 3
    /// rows at the top, a frame all at one divider is 256, 341 or 512 wide and 239 tall (`PceDefaultVideoFilter`).
    /// One mixing dividers MesenCE draws four times over; here it's 256 wide, each row stretched across it.
    static func pcEngine(_ pixels: [UInt16]) -> SaveStateScreenshot? {
        let (stride, rows, top) = (682, 242, 3)
        guard pixels.count >= stride * (rows + 1) else { return nil }
        let dividers = (top..<rows).map { Int(pixels[stride * rows + $0] & 0xFF) }
        func color(_ pixel: UInt16) -> UInt32 {
            let rgb = pcEnginePalette[Int(pixel & 0x1FF)]
            guard pixel & 0x200 != 0 else { return rgb }
            let (r, g, b) = (Double(rgb >> 16), Double(rgb >> 8 & 0xFF), Double(rgb & 0xFF))
            let y = UInt32(min(0.299 * r + 0.587 * g + 0.114 * b, 255))
            return y << 16 | y << 8 | y
        }
        // Where a row's picture starts, past MesenCE's crop, and how wide it is before the crop.
        func left(_ divider: Int) -> Int {
            switch divider {
            case 2: 240 / 2 - 36 + 18 * 4 / 2
            case 3: 216 / 3 - 24 + 18 * 4 / 3
            default: 192 / 4 - 18 + 18
            }
        }
        func rowWidth(_ divider: Int) -> Int {
            switch divider {
            case 2: 64 * 8 + 72
            case 3: 43 * 8 - 3 + 48
            default: 32 * 8 + 36
            }
        }
        if let divider = dividers.first, [2, 3, 4].contains(divider), dividers.allSatisfy({ $0 == divider }) {
            let width = rowWidth(divider) - 36 * 4 / divider
            return picture(pixels, stride: stride, x: left(divider), y: top, width: width, height: rows - top, color: color)
        }
        var rgba = [UInt8](repeating: 255, count: 256 * (rows - top) * 4)
        for (row, divider) in dividers.enumerated() {
            // MesenCE's 4× picture is 1,168 wide before its crop: every fourth of its columns.
            let ratio = Double(rowWidth(divider)) / 1168
            for column in 0..<256 {
                let rgb = color(pixels[(row + top) * stride + left(divider) + Int(Double(column * 4) * ratio)])
                let at = (row * 256 + column) * 4
                (rgba[at], rgba[at + 1], rgba[at + 2]) = (UInt8(rgb >> 16 & 0xFF), UInt8(rgb >> 8 & 0xFF), UInt8(rgb & 0xFF))
            }
        }
        return SaveStateScreenshot(width: 256, height: rows - top, rgba: Data(rgba))
    }

    /// MesenCE's default NES palette, for a 2C02 (`NesConfig.UserPalette`).
    static let nesPalette = colors(
        """
        666666 002A88 1412A7 3B00A4 5C007E 6E0040 6C0600 561D00 333500 0B4800 005200 004F08 00404D 000000 000000 000000
        ADADAD 155FD9 4240FF 7527FE A01ACC B71E7B B53120 994E00 6B6D00 388700 0C9300 008F32 007C8D 000000 000000 000000
        FFFEFF 64B0FF 9290FF C676FF F36AFF FE6ECC FE8170 EA9E22 BCBE00 88D800 5CE430 45E082 48CDDE 4F4F4F 000000 000000
        FFFEFF C0DFFF D3D2FF E8C8FF FBC2FF FEC4EA FECCC5 F7D8A5 E4E594 CFEF96 BDF4AB B3F3CC B5EBF2 B8B8B8 000000 000000
        """)

    /// MesenCE's default PC Engine palette, by GRB333 (`PcEngineConfig.DefaultPalette`).
    static let pcEnginePalette = colors(
        """
        000000 000016 040235 01004B 07046A 050180 0B069F 0903B5 1A0003 200521 1E0237 240756 22046C 28098B 2506A1 2B0BC0
        3D080D 3B0524 400A42 3E0759 440C77 42098D 480EAC 450BC2 570910 550526 5B0A45 59075B 5E0C7A 5C0990 620EAF 600BC5
        720913 770E31 750B48 7B1066 790C7C 7F119B 7C0EB1 8213D0 94111E 920E34 981352 951069 9B1587 99129E 9F17BC 9D13D2
        AE1120 AC0E36 B21355 B0106B B6158A B312A0 B917BF B714D5 C91123 CF1641 CC1358 D21876 D0158C D61AAB D417C1 DA1CE0
        092408 07211E 0D263D 0A2353 102872 0E2588 142AA7 1127BD 23240B 212121 27263F 252356 2A2874 28258B 2E2AA9 2C27BF
        3E240D 43292C 412642 472B61 452877 4B2D95 482AAC 4E2FCA 602C18 5E292E 642E4D 612B63 673082 652D98 6B32B7 692FCD
        7A2D1B 782931 7E2E50 7C2B66 823084 7F2D9B 8532B9 832FD0 952D1D 9B323C 982F52 9E3471 9C3087 A236A6 A032BC A637DA
        B73528 B5323E BB375D B93473 BF3992 BC36A8 C23BC7 C038DD D2352B CF3241 D53760 D33476 D93994 D736AB DC3BC9 DA38E0
        0A4008 0F4526 0D423D 13475B 114471 174990 1445A6 1A4AC5 2C4813 2A4529 304A47 2D475E 334C7C 314993 2F46A9 354BC7
        464815 44452B 4A4A4A 484760 4E4C7F 4B4995 514EB4 4F4BCA 614818 674D36 644A4D 6A4F6B 684C81 6E51A0 6C4EB6 7253D5
        835123 814D39 875257 854F6E 8B548C 8851A3 864EB9 8C53D7 9E5125 9B4D3C A1535A 9F4F70 A5548F A351A5 A856C4 A653DA
        B85128 BE5646 BC535D C1587B BF5592 C55AB0 C356C6 C95CE5 DA5933 D85649 DE5B68 DC587E D95594 DF5AB3 DD57C9 E35CE8
        126410 106126 166645 14625B 1A6779 176490 1D69AE 1B66C5 2D6412 336931 306647 366B66 34687C 3A6D9B 3869B1 3E6FCF
        476415 4D6933 4B664A 516B68 4E687F 546D9D 526AB3 586FD2 6A6C20 676936 6D6E55 6B6B6B 717089 6F6DA0 7472BE 726FD5
        846C22 8A7141 886E57 8D7376 8B708C 9175AB 8F72C1 9577DF 9E6C25 A47144 A26E5A A87378 A6708F AB75AD A972C4 AF77E2
        C17530 BE7246 C47765 C2737B C8799A C675B0 CC7ACE C977E5 DB7532 E17A51 DF7767 E57C86 E2799C E87EBB E67BD1 EC80F0
        137F0F 19842E 178144 1D8663 1A8379 208898 1E85AE 248ACD 36881A 338531 398A4F 378665 3D8C84 3B889A 418DB9 3E8ACF
        50881D 568D3B 548A52 598F70 578C87 5D91A5 5B8EBB 6193DA 6A8820 708D3E 6E8A54 748F73 728C89 7791A8 758EBE 7B93DD
        8D902A 8B8D41 90925F 8E8F76 949494 9291AA 9896C9 9593DF A7902D AD954C AB9262 B19780 AE9497 B499B5 B296CC B89BEA
        C19030 C7964E C59264 CB9783 C99499 CF99B8 CC96CE D29BED E4993A E29651 E89B6F E59886 EB9DA4 E999BA EF9ED9 ED9BEF
        1CA317 22A836 20A54C 26AA6B 23A781 29ACA0 27A9B6 25A6CC 36A31A 3CA939 3AA54F 40AA6D 3EA784 43ACA2 41A9B9 47AED7
        59AC25 57A93B 5CAE5A 5AAB70 60B08F 5EACA5 64B2C3 61AEDA 73AC28 79B146 77AE5C 7DB37B 7AB091 78ADA8 7EB2C6 7CAEDC
        8DAC2A 93B149 91AE5F 97B37E 95B094 9BB5B2 98B2C9 9EB7E7 B0B435 AEB14B B4B66A B1B380 B7B89F B5B5B5 BBBAD4 B9B7EA
        CAB438 D0B956 CEB66C D4BB8B D2B8A1 CFB5B8 D5BAD6 D3B7EC E5B53A EBBA59 E8B66F EEBB8E ECB8A4 F2BDC2 F0BAD9 F5BFF7
        25C71F 23C436 28C954 26C66B 2CCB89 2AC89F 30CDBE 2DCAD4 3FC722 3DC438 43C957 40C66D 46CB8C 44C8A2 4ACDC1 48CAD7
        59C825 5FCD43 5DC959 63CF78 61CB8E 67D0AD 64CDC3 6AD2E2 7CD02F 7ACD46 80D264 7DCF7B 83D499 81D1AF 87D6CE 85D2E4
        96D032 94CD48 9AD267 98CF7D 9ED49C 9BD1B2 A1D6D1 9FD3E7 B1D035 B7D553 B4D26A BAD788 B8D49E BED9BD BCD6D3 C1DBF2
        D3D840 D1D556 D7DA74 D5D78B DADCA9 D8D9C0 DEDEDE DCDBF4 EED842 EBD558 F1DA77 EFD78D F5DCAC F2D9C2 F8DEE1 F6DBF7
        25E31F 2BE83E 29E554 2FEA73 2DE789 33ECA7 30E9BE 36EEDC 48EB2A 46E840 4CED5F 49EA75 4FEF94 4DECAA 53F1C9 51EEDF
        62EC2D 60E843 66ED61 64EA78 6AEF96 67ECAD 6DF1CB 6BEEE1 7DEC2F 83F14E 80EE64 86F383 84EF99 8AF4B7 88F1CE 8DF6EC
        9FF43A 9DF150 A3F66F A1F385 A6F8A4 A4F5BA AAFAD9 A8F6EF BAF43D B7F153 BDF672 BBF388 C1F8A6 BFF5BD C4FADB C2F7F2
        D4F43F DAF95E D7F674 DDFB93 DBF8A9 E1FDC8 DFFADE E5FFFC F6FC4A F4F960 FAFE7F F8FB95 FEFFB4 FBFDCA FFFFE9 FFFFFF
        """)

    private static func colors(_ hex: String) -> [UInt32] {
        hex.split(whereSeparator: \.isWhitespace).map { UInt32($0, radix: 16)! }
    }

    /// Little-endian values from the front of a state.
    private struct Reader {
        let data: Data
        var offset = 0

        mutating func bytes(_ count: Int) -> Data? {
            guard count >= 0, offset + count <= data.count else { return nil }
            defer { offset += count }
            let start = data.startIndex + offset
            return data[start..<start + count]
        }

        mutating func u32() -> Int? {
            bytes(4).map { Int($0.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) }
        }
    }
}
