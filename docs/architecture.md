# Architecture

## Native application

`Sources/Schnaps/App.swift` starts AppKit as a menu-bar utility, registers Carbon global hotkeys, and owns native settings and measurement windows. The settings view uses SwiftUI `NavigationSplitView`, a sidebar list, grouped forms, and system controls. About is the final settings pane, with version information and native update controls. Sparkle preferences are observed directly so changes in update dialogs stay in sync. Sparkle's `SPUStandardUpdaterController` owns update checking, UI, and installation.

`OverlayController` gives each activation one session that owns its windows and initial, live, and export captures. Closing the session cancels its tasks and detaches the canvases. Each capture verifies its session before applying a result. Windows accept pointer input immediately and hold off drawing marks until the initial scan completes. Both the global shortcuts and S switch tools within the current session and reuse its capture. Switching clears transient readings and restores the destination tool’s pins. Pins are held in memory for each tool and display. Activating the same tool toggles it off, and display topology changes close the session.

## Capture and coordinates

`ScreenSnapshot` uses `SCShareableContent` and `SCScreenshotManager` to capture each display, including any visible Schnaps windows. Captured CGImages are converted into tightly packed top-left-origin RGBA buffers in a cancellable detached task. Only immutable CGImage and geometry values cross actors; AppKit and ScreenCaptureKit objects remain on the main actor. Cancellation is checked before and after conversion so dismissed captures cannot publish converted pixels. AppKit global coordinates are converted into local flipped canvas coordinates; each display's captured width/height ratios convert between logical points and physical pixels. The two axes are scaled independently.

Snapshot images are held in memory unless the user explicitly exports a selection. Screenshot export crops the captured image, adds bounded logical-point padding, optionally resamples Retina images to 1x, and encodes PNG or JPEG. Freeze screen can be disabled to use a nonactivating panel over the live desktop with periodic fresh edge-detection snapshots. A refreshed capture replaces the prior scene. Without capture permission or after a capture error, manual selection remains usable.

## Measurement core

`MeasurementCore` is independent of AppKit's window/input system:

- `MeasurementGeometry` normalizes reverse drags, constrains selections, keeps squares inside bounds, translates rectangles, and formats units.
- `PixelBuffer.dimensions` scans horizontal and vertical continuous color runs through the pointer. RGB differences are bounded by a configurable tolerance, including one-pixel runs.
- `PixelBuffer.objectBounds` samples a loose selection's perimeter, requires a majority background color, then scans the interior for foreground bounds. This includes disconnected text or icon details. If no clear background is available, the app retains the manual selection.
- `TolerancePreset` defines stable identities for Zero, Low, Medium, and High (default thresholds 0, 8, 18, 36). User-configurable thresholds are resolved separately by `MeasurementPreferences`, including migration from saved slider values, bounded scroll steps, and wrapping keyboard cycles. Native menu checkmarks refresh when their submenu opens. Settings and every active display share the persisted value; held readings and snapped bounds recalculate on changes.
- `MeasurementPresentation` formats fractional/rounded points, Retina pixels, ordered clipboard formats, and aspect ratios. `MeasurementSnapping` constrains color-run rulers to guides and intersecting pinned objects. `ScreenshotGeometry` handles bounded padding and crop coordinates.
- `DimensionSpan` and `Dimensions` represent independent rulers and convert them to logical display coordinates.

Detection is contrast-based, not semantic object recognition. Complex imagery and gradients can produce unexpected boundaries. Shadow inclusion depends on tolerance. Use manual selection when exact visual bounds cannot be inferred.

## Validation

Swift Testing covers reverse drags, clipping, constrained squares, Retina units, movement bounds, image orientation, channel conversion, tolerance, invalid buffers, gap measurements, one-pixel features, object bounds, disconnected details, and shadow exclusion. Lifecycle stress tests cover repeated tool switches and copies, stale capture completions, and window cleanup. To run the native check against the WindowServer with Screen Recording permission, run `SCHNAPS_TEST_WINDOW_SERVER=1 swift test --filter windowServerCopyStress`. It draws a ruler over a test window and checks the captured pixels and displayed windows after copy in both freeze modes.

## Design tools

`DesignTools` owns bounded, Codable marker geometry and native inspector state. `DesignToolsController` manages click-through/nonactivating panels per display, capture lifecycle, and external-window following. `DesignCanvas` draws marks and handles explicit edit mode; hiding tools cancels capture and discards snapshots. Standard marker windows do not need screen pixels. Capture is conditional on Loupe, vision previews, automatic-contrast crosshair, or Control snapping during an edit. Each canvas caches filtered screen/Loupe crops and Retina resampling by source image identity, crop, vision mode, and output size. The cache retains only the current source frame, with an LRU limit of 32 rendered entries and 64 MiB of accounted image storage; oversized renders are drawn without caching. New frames and tool dismissal release cached images. Still-image capture is bounded to four updates per second.

`DesignGeometry`, `InspectorColor`, `ColorPalette`, `ScreenTemplate`, and `TextCodec` are Swift-only core helpers. `TextInspectorView` searches macOS Unicode scalar names in a cancellable background task, uses Core Text for glyph metrics, and never interprets input as executable content. The WHATWG named-entity data is app-owned static data in `HTMLEntities.swift`.

`BrowserPreview` uses WebKit's nonpersistent store and public full-page PDF API; PNG stitches bounded viewport snapshots rather than rasterizing PDF, preserving screen compositing effects; full-page dimensions bound allocations. Temporary document positioning changes and scroll position are restored after capture. `ImagePreview` uses a window-scoped ScreenCaptureKit filter, retains the selected source, and stops live capture on close. A generation token rejects stale capture images and errors after changing source/window or stopping live preview. Live clipboard preview decodes images only when the pasteboard change count advances and clears the previous image when the clipboard no longer contains one. External window resizing uses public Accessibility APIs and matches the selected window's geometry unambiguously before writing its size. No remote mirroring service or additional third-party runtime is installed.

`ToolOverlayController` owns an optional borderless NSPanel containing a compact NSStackView of native symbol buttons on system HUD material. A separate NSPopover contains the grouped tool inspector. Its explicit visibility preference defaults to false, survives termination, and is cleared by closing the panel. Measurement and design tool activation never enables it implicitly. Its content-sized frame has no title bar, traffic lights, or resize chrome; a drag grip moves the palette and a hide button clears the visibility preference. During measurement the inspector closes and the palette level moves above the measurement canvas; opening the inspector ends measurement and restores the normal floating level. Text inspection uses its own native window.

`MenuBarStatus` combines the new values from marker visibility, workspace visibility, Loupe, and Crosshair publishers and gives active measurement mode priority. `OverlayController` reports start, stop, and in-canvas mode changes. Only distinct state changes reach the status button. `MenuBarIcon` caches four original 22-point vector template images for system tinting; no per-frame icon drawing or polling is required.
