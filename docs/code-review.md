# Code review

Reviewed the first-party Swift app, clipboard/history library, conversion core,
CLI, JavaScript bridge, package manifest, and build/release configuration.
Vendored JavaScript libraries were not audited internally.

## Fixes implemented

- Area selection: cursor tracking and explicit mouse-event routing keep the
  crosshair active; guides show both axes. Clamp drags to the starting display,
  use the final mouse-up position, and focus the overlay under the pointer.
  Coordinate conversion is extracted and tested for offset displays and all
  four drag directions.
- Screenshots: unique filenames avoid same-second overwrites, slash characters
  in prefixes cannot create path components, writes are atomic, and save errors
  are reported.
- History: Clear queues an empty snapshot immediately, after earlier saves.
- Shortcut recording: repeated clicks cancel recording; closing a window,
  leaving the app, or removing the field releases its event monitor and resumes
  shortcuts. Other record buttons are disabled during recording. Labels can
  contain a literal pipe without breaking preference decoding.
- Secrets: unavailable authentication no longer reveals content; locked entries
  cannot be exported through their actions menu.
- Storage/cache: nonpositive capacities behave as empty stores without crashes.
- CLI: piped RTF remains bytes; binary conversion results go to stdout when
  stdin supplied the input; invalid UTF-8 produces an error.
- Web runtime: failure to install remote-request blocking fails the conversion;
  a terminated WebKit process invalidates readiness.
- Deployment review: added a complete app icon and bundle metadata, fresh
  universal builds, recoverable bundle replacement, version/signature/resource
  verification, test-gated CI releases, and ZIP/checksum packaging.
- HTML/RTF conversion removes style/script content before converting.
- Login setup creates missing directories, reports failures, and does not
  terminate the running app when disabled.
- Image previews are downsampled; deduplication preserves different source
  formats. Exporting OCR does not dismiss the image's unsaved-edit protection.
- Capture stops on denied permissions and the macOS 13 fallback crops actual
  framebuffer pixels for Retina/scaled displays.

## Remaining findings and limits

- Interactive capture still needs visual verification on physical displays,
  including Retina scaling, multiple Spaces, Escape, and the macOS 13 fallback.
  Geometry tests do not verify AppKit cursor ownership or framebuffer contents.
  The overlay-removal delay is still a timing heuristic.
- History has an entry-count limit but no byte budget. Full-resolution source
  screenshots and open editors can still retain substantial memory.
- Secret detection checks preview and source text but remains heuristic. It can
  miss credentials in RTF-only payloads or images. History is plaintext on
  disk for entries not classified as secrets.
- ConversionGraph exposes mutation while declaring unchecked Sendable; callers
  must honor its documented construction-before-use requirement.
- Background history-save failures are still silently ignored. Permission or
  disk-full failures can prevent history changes from surviving a restart.
- A built-in editor now supports text source editing and rectangular image blur
  and highlight, with full-resolution flattened export and annotation undo/redo.
  Rich-text editing and rendered Markdown/HTML previews are not implemented.

## Manual capture checks

Automated validation: `swift test` passed 94 tests across all three targets.
CLI smoke checks confirmed piped RTF reaches conversion and piped Mermaid PNG
is emitted as a valid PNG on stdout. A regression test now prevents CSS leakage.

1. Start the rebuilt app, press Shift-Command-1, and confirm crosshair and guides
   follow the pointer on each display.
2. Drag each direction, release outside the starting screen, and verify the
   saved image matches the bounded selection with no overlay or guides.
3. Cancel with Escape, then capture again and verify ordinary cursor behavior
   returns after both cancellation and completion.
4. Capture twice quickly and verify both files remain available.
