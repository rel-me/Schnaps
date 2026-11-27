# User request

> It doesn't seem like we actually have all the xScope features... can you use that app and all the tools and figure out where we need to improve Schnaps to make it have the same functionality... also search the xscope website

## Audit findings

Compared Schnaps at `a9c940b` with xScope 4.7.2. The installed xScope process was running, but desktop automation timed out when attaching to it, including after launching it from Finder. The xScope findings come from its bundled Help and official documentation. Schnaps findings come from the implementation and its [design tools guide](../design-tools.md). Interaction feel, measurement accuracy, current browser compatibility, and device-to-device mirroring were unverified.

| Tool | What Schnaps already supports | What to add or verify |
| --- | --- | --- |
| Dimensions | Hover measurements and aspect ratio, distance and area pins, sensitivity, screenshot export. Measure Area already detects object bounds inside a dragged selection. | Turn the current hover result into an editable frame or four guides. Turn a snapped Measure Area selection into a frame. Compare results on flat fills, gradients and translucent materials, and bordered photos. xScope exposes separate sensitivity for these cases and a calibration preview. |
| Rulers | Two independently adjustable rulers, angle and length sync, edge snapping, calipers, square extensions and alignment marks. | Add the cursor position indicator and backing-pixel length nudges. Test edge and endpoint snapping on mixed-scale displays. |
| Overlay | Window following, a mockup, a grid and preset outer-window resizing. Separate WebKit preview has a controlled viewport and full-page PNG/PDF. | Attach to the browser's content viewport so measurements and breakpoint grids track CSS pixels. Add editable per-breakpoint grid profiles, automatic switching, and project persistence. Add full-page capture from the attached browser workflow. Verify whether xScope retains signed-in and scripted page state before making a claim about it. Add mockup scale, offset and reload-on-save controls. |
| Screens | Logical-size device presets, editable insets and keyboard height, TV title/action-safe areas, vision simulation and 1× Retina preview. | Add selectable, versioned OS/browser chrome and usable-area presets, including keyboard and orientation variants. Add TV center-cut areas and verify captures with the simulated content area. |
| Loupe | Backing-pixel selection, zoom and grid, live pin, sRGB conversion, primary/reference formats, vision simulation and saved swatches. | Add separate Freeze Image and Lock Position actions, on-image dimensions, selectable working color space, Display P3 output and gamut warnings. Test the color readout against known wide-gamut and sRGB patches. |
| Guides | Horizontal and vertical guides, precise coordinates, distance labels, drag duplication, keyboard selection and shared layout files. | Add click-to-place guides, exact batches of guides and gutters, individually selected link groups and undo. Verify backing-pixel movement at 1× and 2×. |
| Frames | Editable bounds and aspect ratio, grids, drag duplication, linked movement and screenshot export. | Add drag-to-draw and shrink-to-fit creation, independent edge resizing, selective link groups, and undo. Add a clean screenshot option that omits frame labels and controls and a direct copy action for frame dimensions. |
| Crosshair | Pointer following, pinning, custom origin, adjustable width and automatic contrast. | Add a bottom-left origin for AppKit coordinates and a coordinate-label visibility toggle. Verify signed offsets across displays and readability over mixed backgrounds. |
| Text | Unicode name, scalar and range search, explicit conversions, mojibake repair, first-line font metrics, palette, foreground/background controls and CLI conversion. | Add searchable Unicode block and HTML entity names, related-character browsing, per-glyph metrics and font fallback indication, file inspection, and mixed-format detection. Add explicit UTF-16/32 bytes and string formats. |
| Mirror | Local live preview of a selected Mac window, image file or clipboard. | Add a paired iPhone/iPad receiver for live preview with source lock, zoom and positioning. Add Apple Watch transfer and layouts, app-icon and wallpaper templates, and evaluate document-level Photoshop integration and Apple TV presentation against the installed product. |

SmartTools is an additional workflow across the suite. xScope can activate or hide specific tools based on the frontmost app. Schnaps has configurable shortcuts and a toolbar but lacks app-specific tool profiles. A shared screenshot shortcut for the active surface would also remove the need to remember different capture actions for measurement, marker, and browser preview workflows.

## Suggested implementation order

1. Connect Dimensions and Measure Area to editable frames and guides. Reuse existing detected geometry and marker storage. Verify that saving a capture or creating a marker uses the same bounds on 1× and 2× screens, including displays above or to the left of the main screen. Follow with direct guide/frame creation and undo.
2. Make the browser overlay viewport-aware. On a page with real media queries, the browser's reported viewport width, selected grid, and breakpoint transition should agree. Verify full-height capture from the attached workflow using both a local page and an authenticated test fixture.
3. Extend Loupe sampling through color management and freezing. A frozen image should stay fixed while underlying content changes, and a locked position should keep sampling live at the same coordinate. Validate pixel selection, measurement in the magnified image, and wide-gamut output.
4. Fill the remaining Mac workflows, including backing-pixel ruler/guide/frame editing, Screens presets, Crosshair preferences, Text inspection, and app-specific profiles. Test keyboard focus and clicks through to the underlying app while multiple tools are visible.
5. Treat Mirror as a companion-app project. Validate pairing, reconnecting to a locked source, iPhone/iPad display behavior and Watch transfer on real hardware. The prior [Mac design tools plan](../prompts.md) deferred this work.

## References

- [xScope user guide](https://xscopeapp.com/guide)
- [xScope feature list](https://xscopeapp.com/features)
- [xScope Retina behavior](https://xscopeapp.com/retina)
- [xScope version history](https://xscopeapp.com/history)
- [xScope Mirror App Store listing](https://apps.apple.com/us/app/xscope-mirror/id488819289)
- Bundled Help under `/Applications/xScope.app/Contents/Resources`, including the tool tutorials, keyboard reference, and SmartTools.

## Follow-up user request

> try again

Finder responded and opened the installed app, but attaching to xScope by bundle ID or path still timed out. Hands-on results remain pending. The official workflow pages give three additional cases to verify:

- Resize the Loupe view independently of zoom, lock it, then draw a measurement directly over magnified pixels. Schnaps currently draws a fixed 180-point view. [Inspecting guide](https://xscopeapp.com/inspecting)
- Drag a saved color directly into both a text editor and a native color well. The text target should receive the active output format. [Measuring guide](https://xscopeapp.com/measuring)
- Toggle independent Screens chrome regions, such as the status bar, lock-screen controls, navigation bar, tab bar, and keyboard, while checking the design in place. [Inspecting guide](https://xscopeapp.com/inspecting)
