import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Theme Palette (Ocean, Forest, Mono)

/// Theme-specific color palette. For system/light/dark returns system colors;
/// for midnight/ocean/forest etc. returns distinct themed palettes.
struct ThemePalette {
    let theme: AppTheme
    let accent: AccentColorOption

    // Backgrounds
    var bgDark: Color {
        switch theme {
        case .ocean: return Color(red: 0.898, green: 0.949, blue: 0.965)   // #e8f4f8
        case .forest: return Color(red: 0.898, green: 0.953, blue: 0.918)  // #e8f5e9
        case .rose: return Color(red: 0.973, green: 0.910, blue: 0.929)    // #f8e8ed
        case .cream: return Color(red: 0.980, green: 0.965, blue: 0.941)   // #faf6f0
        case .sepia: return Color(red: 0.165, green: 0.145, blue: 0.125)   // #2a2520
        case .slate: return Color(red: 0.102, green: 0.114, blue: 0.129)   // #1a1d21
        case .aurora: return Color(red: 0.102, green: 0.086, blue: 0.145)  // #1a1625
        case .midnight: return Color(white: 0.0)   // blackest black
        case .lavender: return Color(red: 0.961, green: 0.957, blue: 0.976) // #f5f4f9
        case .mint: return Color(red: 0.941, green: 0.973, blue: 0.957)    // #f0f8f4
        case .berry: return Color(red: 0.102, green: 0.039, blue: 0.102)  // #1a0a1a
        case .dusk: return Color(red: 0.059, green: 0.090, blue: 0.165)    // #0f172a
        case .coffee: return Color(red: 0.110, green: 0.098, blue: 0.090) // #1c1917
        case .dracula: return Color(red: 0.157, green: 0.165, blue: 0.212) // #282a36
        case .sunset: return Color(red: 0.988, green: 0.941, blue: 0.902)    // #fcf0e6 warm cream
        case .sand: return Color(red: 0.961, green: 0.937, blue: 0.910)     // #f5efe8 sandy beige
        case .peach: return Color(red: 0.992, green: 0.957, blue: 0.941)    // #fdf4f0 soft peach
        case .ember: return Color(red: 0.122, green: 0.122, blue: 0.125)   // #1f1f20 dark grey
        case .snow: return Color(red: 1.0, green: 1.0, blue: 1.0)          // #ffffff pure white
        case .linen: return Color(red: 0.980, green: 0.969, blue: 0.949) // #faf7f2 warm off-white
        case .graphite: return Color(red: 0.106, green: 0.110, blue: 0.122)   // #1b1c1f graphite dark
        case .amethyst: return Color(red: 0.357, green: 0.129, blue: 0.714)    // #5b21b6 royal purple
        case .ink: return Color(red: 0.051, green: 0.051, blue: 0.051)  // #0d0d0d near-black
        default: return systemBgDark
        }
    }

    var bgCard: Color {
        switch theme {
        case .ocean: return Color(red: 0.976, green: 0.984, blue: 0.988)
        case .forest: return Color(red: 0.976, green: 0.988, blue: 0.976)
        case .rose: return Color(red: 0.992, green: 0.949, blue: 0.961)    // #fdf2f5
        case .cream: return Color(red: 0.992, green: 0.980, blue: 0.961)   // #fdfaf5
        case .sepia: return Color(red: 0.208, green: 0.184, blue: 0.157)   // #352f28
        case .slate: return Color(red: 0.141, green: 0.157, blue: 0.180)   // #24282e
        case .aurora: return Color(red: 0.145, green: 0.125, blue: 0.200)  // #252033
        case .midnight: return Color(red: 0.02, green: 0.02, blue: 0.02)
        case .lavender: return Color(red: 0.984, green: 0.980, blue: 0.992) // #fbf9fd
        case .mint: return Color(red: 0.965, green: 0.988, blue: 0.976)    // #f6fcf9
        case .berry: return Color(red: 0.176, green: 0.078, blue: 0.176)  // #2d142d
        case .dusk: return Color(red: 0.118, green: 0.161, blue: 0.231)   // #1e293b
        case .coffee: return Color(red: 0.161, green: 0.145, blue: 0.141) // #292524
        case .dracula: return Color(red: 0.267, green: 0.278, blue: 0.353) // #44475a
        case .sunset: return Color(red: 0.996, green: 0.976, blue: 0.961)   // #fef9f5
        case .sand: return Color(red: 0.976, green: 0.957, blue: 0.933)     // #f9f4ee
        case .peach: return Color(red: 0.996, green: 0.969, blue: 0.961)    // #fef7f5
        case .ember: return Color(red: 0.180, green: 0.180, blue: 0.184)      // #2e2e2f grey card
        case .snow: return Color(red: 1.0, green: 1.0, blue: 1.0)            // #ffffff pure white
        case .linen: return Color(red: 0.961, green: 0.941, blue: 0.910) // #f5f0e8 slightly warmer white
        case .graphite: return Color(red: 0.157, green: 0.165, blue: 0.180)   // #282a2e elevated card
        case .amethyst: return Color(red: 0.400, green: 0.165, blue: 0.757)    // #6629c1 slightly lighter purple
        case .ink: return Color(red: 0.102, green: 0.102, blue: 0.110)  // #1a1a1c dark card
        default: return systemBgCard
        }
    }

    var bgSidebar: Color {
        switch theme {
        case .ocean: return Color(red: 0.929, green: 0.965, blue: 0.976)
        case .forest: return Color(red: 0.929, green: 0.976, blue: 0.941)
        case .rose: return Color(red: 0.988, green: 0.937, blue: 0.949)    // #fceef2
        case .cream: return Color(red: 0.973, green: 0.957, blue: 0.929)   // #f8f4ed
        case .sepia: return Color(red: 0.176, green: 0.157, blue: 0.133)   // #2d2822
        case .slate: return Color(red: 0.118, green: 0.133, blue: 0.149)   // #1e2226
        case .aurora: return Color(red: 0.122, green: 0.106, blue: 0.180)  // #1f1b2e
        case .midnight: return Color(white: 0.0)
        case .lavender: return Color(red: 0.957, green: 0.949, blue: 0.969) // #f4f2f7
        case .mint: return Color(red: 0.925, green: 0.965, blue: 0.949)  // #ecf6f2
        case .berry: return Color(red: 0.122, green: 0.047, blue: 0.122)  // #1f0c1f
        case .dusk: return Color(red: 0.071, green: 0.106, blue: 0.165)   // #121b2a
        case .coffee: return Color(red: 0.098, green: 0.086, blue: 0.078) // #191614
        case .dracula: return Color(red: 0.114, green: 0.118, blue: 0.145) // #1d1e24
        case .sunset: return Color(red: 0.980, green: 0.949, blue: 0.918)   // #faf2ea
        case .sand: return Color(red: 0.969, green: 0.945, blue: 0.922)      // #f7f1eb
        case .peach: return Color(red: 0.988, green: 0.957, blue: 0.941)     // #fcf4f0
        case .ember: return Color(red: 0.141, green: 0.141, blue: 0.145)    // #242425 grey sidebar
        case .snow: return Color(red: 0.976, green: 0.976, blue: 0.976)   // #f9f9f9 very light gray
        case .linen: return Color(red: 0.941, green: 0.922, blue: 0.890) // #f0ebe3 light warm gray
        case .graphite: return Color(red: 0.122, green: 0.125, blue: 0.141)   // #1f2024 sidebar
        case .amethyst: return Color(red: 0.298, green: 0.098, blue: 0.620)    // #4c19a0 darker purple sidebar
        case .ink: return Color(red: 0.039, green: 0.039, blue: 0.039)  // #0a0a0a near-black sidebar
        default: return systemBgSidebar
        }
    }

    var bgInput: Color {
        switch theme {
        case .ocean: return Color(red: 0.949, green: 0.976, blue: 0.984)
        case .forest: return Color(red: 0.949, green: 0.984, blue: 0.957)
        case .rose: return Color(red: 0.992, green: 0.957, blue: 0.969)    // #fdf4f7
        case .cream: return Color(red: 0.988, green: 0.973, blue: 0.949)   // #fcf8f2
        case .sepia: return Color(red: 0.239, green: 0.208, blue: 0.173)   // #3d352c
        case .slate: return Color(red: 0.165, green: 0.184, blue: 0.212)   // #2a2f36
        case .aurora: return Color(red: 0.176, green: 0.153, blue: 0.251)  // #2d2740
        case .midnight: return Color(red: 0.04, green: 0.04, blue: 0.04)
        case .lavender: return Color(red: 0.969, green: 0.965, blue: 0.980) // #f7f6fa
        case .mint: return Color(red: 0.953, green: 0.980, blue: 0.965)  // #f3faf6
        case .berry: return Color(red: 0.227, green: 0.102, blue: 0.227)  // #3a1a3a
        case .dusk: return Color(red: 0.141, green: 0.188, blue: 0.259)   // #243042
        case .coffee: return Color(red: 0.204, green: 0.184, blue: 0.176) // #342f2d
        case .dracula: return Color(red: 0.314, green: 0.325, blue: 0.396) // #50536a
        case .sunset: return Color(red: 0.988, green: 0.957, blue: 0.925)   // #fcf4ec
        case .sand: return Color(red: 0.957, green: 0.933, blue: 0.906)     // #f4eee7
        case .peach: return Color(red: 0.984, green: 0.953, blue: 0.937)    // #fbf3ef
        case .ember: return Color(red: 0.220, green: 0.220, blue: 0.224)      // #383839 grey input
        case .snow: return Color(red: 0.965, green: 0.965, blue: 0.965)   // #f7f7f7 very light input
        case .linen: return Color(red: 0.969, green: 0.953, blue: 0.925) // #f7f3ec warm input
        case .graphite: return Color(red: 0.188, green: 0.192, blue: 0.212)   // #303136 input field
        case .amethyst: return Color(red: 0.420, green: 0.192, blue: 0.780)    // #6b31c7 medium purple input
        case .ink: return Color(red: 0.133, green: 0.133, blue: 0.145)  // #222225 dark input
        default: return systemBgInput
        }
    }

    var bgElevated: Color {
        switch theme {
        case .ocean: return Color(red: 0.976, green: 0.988, blue: 0.992)
        case .forest: return Color(red: 0.976, green: 0.992, blue: 0.980)
        case .rose: return Color(red: 0.996, green: 0.973, blue: 0.980)    // #fef8fa
        case .cream: return Color(red: 0.996, green: 0.992, blue: 0.976)   // #fefdf9
        case .sepia: return Color(red: 0.259, green: 0.227, blue: 0.196)   // #423a32
        case .slate: return Color(red: 0.180, green: 0.204, blue: 0.235)   // #2e343c
        case .aurora: return Color(red: 0.196, green: 0.169, blue: 0.282)  // #322b48
        case .midnight: return Color(red: 0.06, green: 0.06, blue: 0.06)
        case .lavender: return Color(red: 0.992, green: 0.988, blue: 0.996) // #fcfbfd
        case .mint: return Color(red: 0.976, green: 0.992, blue: 0.984)   // #f9fdfb
        case .berry: return Color(red: 0.259, green: 0.122, blue: 0.259)  // #421f42
        case .dusk: return Color(red: 0.165, green: 0.212, blue: 0.282)   // #2a3648
        case .coffee: return Color(red: 0.235, green: 0.212, blue: 0.204) // #3c3634
        case .dracula: return Color(red: 0.341, green: 0.353, blue: 0.427) // #575a6d
        case .sunset: return Color(red: 1.0, green: 0.988, blue: 0.976)     // #fffcf9
        case .sand: return Color(red: 0.988, green: 0.969, blue: 0.949)      // #fcf7f2
        case .peach: return Color(red: 1.0, green: 0.980, blue: 0.973)      // #fffaf8
        case .ember: return Color(red: 0.259, green: 0.259, blue: 0.263)    // #424244 elevated grey
        case .snow: return Color(red: 0.988, green: 0.988, blue: 0.988)   // #fcfcfc almost white elevated
        case .linen: return Color(red: 0.976, green: 0.961, blue: 0.933) // #f9f5ee warm elevated
        case .graphite: return Color(red: 0.220, green: 0.227, blue: 0.247)   // #383a3f elevated
        case .amethyst: return Color(red: 0.443, green: 0.220, blue: 0.808)    // #7138ce brighter purple elevated
        case .ink: return Color(red: 0.165, green: 0.165, blue: 0.180)  // #2a2a2e dark elevated
        default: return systemBgCard
        }
    }

    var bgCrisp: Color { bgCard }

    var borderCrisp: Color {
        switch theme {
        case .ocean: return Color(red: 0.690, green: 0.831, blue: 0.875).opacity(0.6)
        case .forest: return Color(red: 0.596, green: 0.820, blue: 0.659).opacity(0.6)
        case .rose: return Color(red: 0.910, green: 0.722, blue: 0.784).opacity(0.6)  // #e8b8c8
        case .cream: return Color(red: 0.788, green: 0.722, blue: 0.659).opacity(0.6) // #c9b8a8
        case .sepia: return Color(red: 0.420, green: 0.357, blue: 0.310).opacity(0.7) // #6b5b4f
        case .slate: return Color(red: 0.290, green: 0.333, blue: 0.408).opacity(0.7) // #4a5568
        case .aurora: return Color(red: 0.357, green: 0.302, blue: 0.478).opacity(0.7) // #5b4d7a
        case .midnight: return Color(red: 0.91, green: 0.89, blue: 0.85).opacity(0.25)  // bone
        case .lavender: return Color(red: 0.753, green: 0.714, blue: 0.827).opacity(0.5) // #c0b6d3
        case .mint: return Color(red: 0.569, green: 0.800, blue: 0.667).opacity(0.5)   // #91ccaa
        case .berry: return Color(red: 0.631, green: 0.314, blue: 0.631).opacity(0.6)  // #a150a1
        case .dusk: return Color(red: 0.333, green: 0.427, blue: 0.522).opacity(0.6)  // #556d85
        case .coffee: return Color(red: 0.467, green: 0.416, blue: 0.384).opacity(0.6) // #776a62
        case .dracula: return Color(red: 0.404, green: 0.431, blue: 0.510).opacity(0.6) // #676e82
        case .sunset: return Color(red: 0.937, green: 0.620, blue: 0.482).opacity(0.5)  // #ef9e7b
        case .sand: return Color(red: 0.800, green: 0.690, blue: 0.580).opacity(0.5)    // #ccb094
        case .peach: return Color(red: 0.925, green: 0.624, blue: 0.620).opacity(0.5)     // #ec9f9e
        case .ember: return Color(red: 0.855, green: 0.200, blue: 0.200).opacity(0.5)   // #da3333 red accent
        case .snow: return Color(red: 0.0, green: 0.0, blue: 0.0).opacity(0.15)         // black border on white
        case .linen: return Color(red: 0.831, green: 0.549, blue: 0.306).opacity(0.4)  // #d48c4e terracotta
        case .graphite: return Color(red: 1.0, green: 1.0, blue: 1.0).opacity(0.12)   // subtle white border
        case .amethyst: return Color(red: 1.0, green: 1.0, blue: 1.0).opacity(0.25)    // white border on purple
        case .ink: return Color(red: 0.176, green: 0.831, blue: 0.749).opacity(0.30) // #2DD4BF teal border
        default: return systemBorderCrisp
        }
    }

    var borderSubtle: Color {
        switch theme {
        case .ocean: return Color(red: 0.690, green: 0.831, blue: 0.875).opacity(0.4)
        case .forest: return Color(red: 0.596, green: 0.820, blue: 0.659).opacity(0.4)
        case .rose: return Color(red: 0.910, green: 0.722, blue: 0.784).opacity(0.4)
        case .cream: return Color(red: 0.788, green: 0.722, blue: 0.659).opacity(0.35)
        case .sepia: return Color(red: 0.361, green: 0.302, blue: 0.263).opacity(0.6) // #5a4d43
        case .slate: return Color(red: 0.239, green: 0.275, blue: 0.329).opacity(0.6)  // #3d4654
        case .aurora: return Color(red: 0.290, green: 0.247, blue: 0.384).opacity(0.6) // #4a3f62
        case .midnight: return Color(red: 0.91, green: 0.89, blue: 0.85).opacity(0.15)  // bone
        case .lavender: return Color(red: 0.753, green: 0.714, blue: 0.827).opacity(0.3) // #c0b6d3
        case .mint: return Color(red: 0.569, green: 0.800, blue: 0.667).opacity(0.3)   // #91ccaa
        case .berry: return Color(red: 0.631, green: 0.314, blue: 0.631).opacity(0.4)  // #a150a1
        case .dusk: return Color(red: 0.333, green: 0.427, blue: 0.522).opacity(0.4)   // #556d85
        case .coffee: return Color(red: 0.467, green: 0.416, blue: 0.384).opacity(0.4) // #776a62
        case .dracula: return Color(red: 0.404, green: 0.431, blue: 0.510).opacity(0.4) // #676e82
        case .sunset: return Color(red: 0.937, green: 0.620, blue: 0.482).opacity(0.3)  // #ef9e7b
        case .sand: return Color(red: 0.800, green: 0.690, blue: 0.580).opacity(0.3)    // #ccb094
        case .peach: return Color(red: 0.925, green: 0.624, blue: 0.620).opacity(0.3)   // #ec9f9e
        case .ember: return Color(red: 0.855, green: 0.200, blue: 0.200).opacity(0.3)   // #da3333
        case .snow: return Color(red: 0.0, green: 0.0, blue: 0.0).opacity(0.08)         // subtle black
        case .linen: return Color(red: 0.831, green: 0.549, blue: 0.306).opacity(0.2)  // terracotta subtle
        case .graphite: return Color(red: 1.0, green: 1.0, blue: 1.0).opacity(0.08)   // subtle border
        case .amethyst: return Color(red: 1.0, green: 1.0, blue: 1.0).opacity(0.15)    // white subtle
        case .ink: return Color(red: 0.176, green: 0.831, blue: 0.749).opacity(0.15) // teal subtle
        default: return systemBorderSubtle
        }
    }

    /// Effective accent for themed modes
    var effectiveAccent: Color {
        switch theme {
        case .ocean: return Color(red: 0.220, green: 0.710, blue: 0.710)   // teal
        case .forest: return Color(red: 0.220, green: 0.780, blue: 0.490)  // green
        case .rose: return Color(red: 0.831, green: 0.298, blue: 0.510)    // rose
        case .cream: return Color(red: 0.545, green: 0.451, blue: 0.333)   // warm brown
        case .sepia: return Color(red: 0.902, green: 0.635, blue: 0.235)   // amber
        case .slate: return Color(red: 0.388, green: 0.702, blue: 0.929)   // cool blue
        case .aurora: return Color(red: 0.655, green: 0.545, blue: 0.980)  // purple/indigo
        case .midnight: return Color(red: 0.91, green: 0.89, blue: 0.85)   // bone #E8E4D9
        case .lavender: return Color(red: 0.651, green: 0.510, blue: 0.827) // lavender #a782d3
        case .mint: return Color(red: 0.220, green: 0.690, blue: 0.510)   // mint green
        case .berry: return Color(red: 0.976, green: 0.467, blue: 0.788)  // hot pink #f977c9
        case .dusk: return Color(red: 0.557, green: 0.733, blue: 0.973)   // twilight blue
        case .coffee: return Color(red: 0.867, green: 0.631, blue: 0.369) // warm amber
        case .dracula: return Color(red: 1.000, green: 0.475, blue: 0.776) // Dracula pink #ff79c6
        case .sunset: return Color(red: 0.957, green: 0.490, blue: 0.216)   // #f47d37 orange
        case .sand: return Color(red: 0.757, green: 0.553, blue: 0.373)    // #c18d5f tan
        case .peach: return Color(red: 0.937, green: 0.459, blue: 0.459)    // #ef7575 coral
        case .ember: return Color(red: 0.937, green: 0.220, blue: 0.220)     // #ef3838 red
        case .snow: return Color(red: 0.0, green: 0.0, blue: 0.0)            // #000000 pure black accent
        case .linen: return Color(red: 0.831, green: 0.459, blue: 0.306)  // #d4754e warm terracotta
        case .graphite:
            // Dark theme with a vivid four-color accent palette
            let vividBlue = Color(red: 0.259, green: 0.522, blue: 0.957)    // #4285F4
            let vividRed = Color(red: 0.929, green: 0.322, blue: 0.267)     // #EA4335
            let vividYellow = Color(red: 0.984, green: 0.737, blue: 0.016)  // #FBBC04
            let vividGreen = Color(red: 0.188, green: 0.616, blue: 0.290)   // #34A853
            switch accent {
            case .blue: return vividBlue
            case .pink, .purple: return vividRed
            case .orange, .amber: return vividYellow
            case .green, .teal: return vividGreen
            }
        case .amethyst: return Color(red: 1.0, green: 1.0, blue: 1.0)            // #ffffff pure white accent
        case .ink: return Color(red: 0.176, green: 0.831, blue: 0.749)  // #2DD4BF light teal
        default: return accent.color
        }
    }

    var effectiveAccentDarkVariant: Color {
        switch theme {
        case .ocean: return Color(red: 0.118, green: 0.565, blue: 0.565)
        case .forest: return Color(red: 0.157, green: 0.620, blue: 0.380)
        case .rose: return Color(red: 0.718, green: 0.192, blue: 0.396)
        case .cream: return Color(red: 0.420, green: 0.341, blue: 0.243)
        case .sepia: return Color(red: 0.780, green: 0.518, blue: 0.169)
        case .slate: return Color(red: 0.267, green: 0.584, blue: 0.827)
        case .aurora: return Color(red: 0.514, green: 0.408, blue: 0.878)
        case .midnight: return Color(red: 0.78, green: 0.76, blue: 0.72)   // darker bone
        case .lavender: return Color(red: 0.529, green: 0.400, blue: 0.698) // darker lavender
        case .mint: return Color(red: 0.157, green: 0.518, blue: 0.369) // darker mint
        case .berry: return Color(red: 0.808, green: 0.337, blue: 0.631) // darker pink
        case .dusk: return Color(red: 0.420, green: 0.580, blue: 0.808)  // darker blue
        case .coffee: return Color(red: 0.702, green: 0.482, blue: 0.247) // darker amber
        case .dracula: return Color(red: 0.827, green: 0.376, blue: 0.620) // darker dracula pink
        case .sunset: return Color(red: 0.820, green: 0.380, blue: 0.157)   // darker orange
        case .sand: return Color(red: 0.600, green: 0.420, blue: 0.255)    // darker tan
        case .peach: return Color(red: 0.820, green: 0.320, blue: 0.320)    // darker coral
        case .ember: return Color(red: 0.820, green: 0.180, blue: 0.180)   // darker red
        case .snow: return Color(red: 0.2, green: 0.2, blue: 0.2)        // dark gray
        case .linen: return Color(red: 0.686, green: 0.369, blue: 0.220)  // darker terracotta
        case .graphite: return Color(red: 0.259, green: 0.522, blue: 0.957)   // #4285f4
        case .amethyst: return Color(red: 0.85, green: 0.85, blue: 0.85)       // light gray on purple
        case .ink: return Color(red: 0.078, green: 0.722, blue: 0.651)  // #14B8A6 darker teal
        default: return accent.darkVariant
        }
    }

    var effectiveAccentLightVariant: Color {
        switch theme {
        case .ocean: return Color(red: 0.40, green: 0.85, blue: 0.85)
        case .forest: return Color(red: 0.40, green: 0.90, blue: 0.60)
        case .rose: return Color(red: 0.929, green: 0.537, blue: 0.663)
        case .cream: return Color(red: 0.698, green: 0.612, blue: 0.486)
        case .sepia: return Color(red: 0.929, green: 0.749, blue: 0.459)
        case .slate: return Color(red: 0.557, green: 0.796, blue: 0.969)
        case .aurora: return Color(red: 0.780, green: 0.698, blue: 1.0)
        case .midnight: return Color(red: 0.96, green: 0.94, blue: 0.91)   // lighter bone
        case .lavender: return Color(red: 0.827, green: 0.741, blue: 0.906) // lighter lavender
        case .mint: return Color(red: 0.40, green: 0.90, blue: 0.65)    // lighter mint
        case .berry: return Color(red: 1.0, green: 0.62, blue: 0.86)    // lighter pink
        case .dusk: return Color(red: 0.70, green: 0.85, blue: 1.0)     // lighter blue
        case .coffee: return Color(red: 0.98, green: 0.80, blue: 0.58)  // lighter amber
        case .dracula: return Color(red: 1.0, green: 0.67, blue: 0.87)  // lighter dracula pink
        case .sunset: return Color(red: 1.0, green: 0.65, blue: 0.45)     // lighter orange
        case .sand: return Color(red: 0.90, green: 0.70, blue: 0.50)      // lighter tan
        case .peach: return Color(red: 1.0, green: 0.65, blue: 0.65)      // lighter coral
        case .ember: return Color(red: 1.0, green: 0.45, blue: 0.45)      // lighter red
        case .snow: return Color(red: 0.4, green: 0.4, blue: 0.4)       // medium gray
        case .linen: return Color(red: 0.92, green: 0.62, blue: 0.42)  // lighter terracotta
        case .graphite: return Color(red: 0.65, green: 0.80, blue: 1.0)     // lighter blue
        case .amethyst: return Color(red: 1.0, green: 1.0, blue: 1.0)          // pure white
        case .ink: return Color(red: 0.369, green: 0.918, blue: 0.831)  // #5EEAD4 lighter teal
        default: return accent.lightVariant
        }
    }

    var textPrimary: Color {
        switch theme {
        case .ocean, .forest, .rose, .cream, .lavender, .mint, .sunset, .sand, .peach, .linen: return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .ink: return Color(red: 0.941, green: 0.941, blue: 0.949)  // #f0f0f2 near-white
        case .snow: return Color(red: 0.0, green: 0.0, blue: 0.0)   // pure black text
        case .sepia, .slate, .aurora, .berry, .dusk, .coffee, .dracula, .ember, .graphite: return Color(red: 0.95, green: 0.95, blue: 0.97)
        case .amethyst: return Color.white
        case .midnight: return Color(red: 0.91, green: 0.89, blue: 0.85)   // bone
        default: return Color.primary
        }
    }

    var textSecondary: Color {
        switch theme {
        case .ocean, .forest, .rose, .cream, .lavender, .mint, .sunset, .sand, .peach, .linen: return Color(red: 0.35, green: 0.35, blue: 0.38)
        case .ink: return Color(red: 0.627, green: 0.627, blue: 0.659)  // #a0a0a8 medium gray
        case .snow: return Color(red: 0.35, green: 0.35, blue: 0.35)   // dark gray secondary
        case .sepia, .slate, .aurora, .berry, .dusk, .coffee, .dracula, .ember, .graphite: return Color(red: 0.72, green: 0.72, blue: 0.76)
        case .amethyst: return Color(red: 0.85, green: 0.85, blue: 0.90)
        case .midnight: return Color(red: 0.72, green: 0.70, blue: 0.66)   // dimmer bone
        default: return Color.secondary
        }
    }

    var textMuted: Color {
        switch theme {
        case .ocean, .forest, .rose, .cream, .lavender, .mint, .sunset, .sand, .peach, .linen: return Color(red: 0.45, green: 0.45, blue: 0.48)
        case .ink: return Color(red: 0.420, green: 0.420, blue: 0.459)  // #6b6b75 muted gray
        case .snow: return Color(red: 0.55, green: 0.55, blue: 0.55)   // medium gray muted
        case .sepia, .slate, .aurora, .berry, .dusk, .coffee, .dracula, .ember, .graphite: return Color(red: 0.60, green: 0.60, blue: 0.65)
        case .amethyst: return Color(red: 0.72, green: 0.72, blue: 0.78)
        case .midnight: return Color(red: 0.55, green: 0.53, blue: 0.50)   // muted bone
        default: return Color.secondary.opacity(0.7)
        }
    }

    private var systemBgDark: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    private var systemBgCard: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var systemBgSidebar: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    private var systemBgInput: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #endif
    }

    private var systemBorderCrisp: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor).opacity(0.9)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    private var systemBorderSubtle: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark
    case midnight
    case ocean
    case forest
    case rose
    case cream
    case sepia
    case slate
    case aurora
    case lavender
    case mint
    case berry
    case dusk
    case coffee
    case dracula
    case sunset
    case sand
    case peach
    case ember
    // Fun themes (competitor-inspired)
    case snow
    case linen
    case graphite
    case amethyst
    case ink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .midnight: return "Midnight"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .rose: return "Rose"
        case .cream: return "Cream"
        case .sepia: return "Sepia"
        case .slate: return "Slate"
        case .aurora: return "Aurora"
        case .lavender: return "Lavender"
        case .mint: return "Mint"
        case .berry: return "Berry"
        case .dusk: return "Dusk"
        case .coffee: return "Coffee"
        case .dracula: return "Dracula"
        case .sunset: return "Sunset"
        case .sand: return "Sand"
        case .peach: return "Peach"
        case .ember: return "Ember"
        case .snow: return "Snow"
        case .linen: return "Linen"
        case .graphite: return "Graphite"
        case .amethyst: return "Amethyst"
        case .ink: return "Ink"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .midnight: return "moon.stars.fill"
        case .ocean: return "drop.fill"
        case .forest: return "leaf.fill"
        case .rose: return "heart.fill"
        case .cream: return "sun.horizon.fill"
        case .sepia: return "photo.fill"
        case .slate: return "square.fill"
        case .aurora: return "sparkles"
        case .lavender: return "wand.and.stars"
        case .mint: return "leaf.arrow.triangle.circlepath"
        case .berry: return "checkmark.seal.fill"
        case .dusk: return "moon.haze.fill"
        case .coffee: return "mug.fill"
        case .dracula: return "lightspectrum.horizontal"
        case .sunset: return "sun.horizon.fill"
        case .sand: return "hourglass"
        case .peach: return "heart.fill"
        case .ember: return "flame.fill"
        case .snow: return "bubble.left.fill"
        case .linen: return "sparkle"
        case .graphite: return "star.fill"
        case .amethyst: return "bolt.fill"
        case .ink: return "globe"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .ocean, .forest, .rose, .cream, .lavender, .mint, .sunset, .sand, .peach, .snow, .linen: return .light
        case .ink: return .dark
        case .dark, .midnight, .sepia, .slate, .aurora, .berry, .dusk, .coffee, .dracula, .ember: return .dark
        case .graphite, .amethyst: return .dark
        }
    }

    static var lightThemes: [AppTheme] { [.lavender, .mint, .ocean, .forest, .rose, .cream, .sunset, .sand, .peach, .light] }
    static var darkThemes: [AppTheme] { [.berry, .dusk, .coffee, .dracula, .midnight, .sepia, .slate, .aurora, .ember, .dark] }
    static var funThemes: [AppTheme] { [.snow, .linen, .graphite, .amethyst, .ink] }
}

// MARK: - Accent Color

enum AccentColorOption: String, CaseIterable, Identifiable {
    case purple
    case blue
    case green
    case orange
    case pink
    case teal
    case amber

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .purple: return Color(red: 0.561, green: 0.337, blue: 1.000)
        case .blue: return Color(red: 0.243, green: 0.533, blue: 0.976)
        case .green: return Color(red: 0.220, green: 0.780, blue: 0.490)
        case .orange: return Color(red: 1.000, green: 0.584, blue: 0.200)
        case .pink: return Color(red: 0.937, green: 0.325, blue: 0.537)
        case .teal: return Color(red: 0.220, green: 0.710, blue: 0.710)
        case .amber: return Color(red: 1.000, green: 0.749, blue: 0.000)
        }
    }

    var darkVariant: Color {
        switch self {
        case .purple: return Color(red: 0.404, green: 0.196, blue: 0.847)
        case .blue: return Color(red: 0.176, green: 0.388, blue: 0.847)
        case .green: return Color(red: 0.157, green: 0.620, blue: 0.380)
        case .orange: return Color(red: 0.847, green: 0.443, blue: 0.118)
        case .pink: return Color(red: 0.784, green: 0.216, blue: 0.420)
        case .teal: return Color(red: 0.118, green: 0.565, blue: 0.565)
        case .amber: return Color(red: 0.808, green: 0.584, blue: 0.000)
        }
    }

    /// Lighter variant for use on dark backgrounds (e.g. labels, icons).
    var lightVariant: Color {
        switch self {
        case .purple: return Color(red: 0.741, green: 0.612, blue: 1.000)
        case .blue: return Color(red: 0.45, green: 0.65, blue: 1.0)
        case .green: return Color(red: 0.40, green: 0.90, blue: 0.60)
        case .orange: return Color(red: 1.0, green: 0.75, blue: 0.45)
        case .pink: return Color(red: 1.0, green: 0.55, blue: 0.75)
        case .teal: return Color(red: 0.40, green: 0.85, blue: 0.85)
        case .amber: return Color(red: 1.0, green: 0.90, blue: 0.45)
        }
    }
}

// MARK: - App Density (Display)

enum AppDensity: String, CaseIterable, Identifiable {
    case comfortable
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .comfortable: return 1.0
        case .compact: return 0.92
        }
    }
}

// MARK: - Streaming Animation Style

enum StreamingAnimationStyle: String, CaseIterable, Identifiable {
    case smooth
    case typewriter
    case instant

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smooth: return "Smooth"
        case .typewriter: return "Typewriter"
        case .instant: return "Instant"
        }
    }
}

// MARK: - App Content Size (Text / Font scale)

enum AppContentSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .small: return 0.92
        case .medium: return 1.0
        case .large: return 1.12
        }
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "AppTheme") }
    }
    @Published var accentColor: AccentColorOption {
        didSet { UserDefaults.standard.set(accentColor.rawValue, forKey: "AccentColor") }
    }
    @Published var density: AppDensity {
        didSet { UserDefaults.standard.set(density.rawValue, forKey: "AppDensity") }
    }
    @Published var contentSize: AppContentSize {
        didSet { UserDefaults.standard.set(contentSize.rawValue, forKey: "AppContentSize") }
    }

    var colorScheme: ColorScheme? { theme.colorScheme }

    /// Theme-aware color palette. Use this for backgrounds and accents when theme is ocean/forest/mono.
    var palette: ThemePalette { ThemePalette(theme: theme, accent: accentColor) }

    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "AppTheme") ?? AppTheme.slate.rawValue
        // Migrate legacy theme rawValues: "mono"->slate, and the renamed
        // ex-competitor-branded themes -> their neutral names.
        let themeMigrations: [String: String] = [
            "mono": "slate",
            "chatGPT": "snow",
            "anthropicTheme": "linen",
            "geminiTheme": "graphite",
            "kiro": "amethyst",
            "perplexity": "ink"
        ]
        let migrated = themeMigrations[savedTheme] ?? savedTheme
        self.theme = AppTheme(rawValue: migrated) ?? .slate

        let savedAccent = UserDefaults.standard.string(forKey: "AccentColor") ?? AccentColorOption.purple.rawValue
        self.accentColor = AccentColorOption(rawValue: savedAccent) ?? .purple

        let savedDensity = UserDefaults.standard.string(forKey: "AppDensity") ?? AppDensity.comfortable.rawValue
        self.density = AppDensity(rawValue: savedDensity) ?? .comfortable

        let savedContentSize = UserDefaults.standard.string(forKey: "AppContentSize") ?? AppContentSize.medium.rawValue
        self.contentSize = AppContentSize(rawValue: savedContentSize) ?? .medium
    }
}
