# Libra

Libra is a macOS app that imports assembly step files (exported from Autdesk Fusion, for example), which the user can ten assign arbitrary mass properties to. It has a graphcial UI -  a 3d viewer with pan, tilt, and zoom, but needs not geometry editing ability. The use case for the app is to be able to easily manipulate/calculate mass properties geometry for robotics projects. This project will also contain any export scripts (e.g. for Fusion) that might be necessary.

This project is for personal use only and will only be used for hobby purposes. It will never be on the app store.


## OS Target
- macOS 27

## General Dev Rules

- **Keep it simple.** Solo hobby project: prefer the simplest thing that works; no process or tooling for its own sake. Backwards compatibility never required unless specifically requested by the user.

- **Naming:** no abbreviations (`publisher`, not `pub`), in every language.
- **Languages and Frameworks:** Modern macOS/Swift. For sub-projects, use a sensible choice of language. For general scripting, or if there is no obvious choice, use Ruby.
- **Git:** the user handles commits and pushes unless they explicitly ask Claude to. When asked to commit, keep the message short and put the model name in parentheses at the end, e.g. `Add balance card (Opus 5.5)`. No "Co-Authored-By" or "Generated with Claude Code" lines. Commit on `main`; don't push unless asked.


## Tech Stack

- Swift 6 (strict concurrency), SwiftUI document app (`DocumentGroup` + `FileDocument`), Observation, Metal (`MTKView`)
- Swift Testing (`import Testing`) for all tests
- XcodeGen: `project.yml` generates `Libra.xcodeproj` (gitignored; never edit the project directly)
- OpenCASCADE 7.9 from Homebrew (`brew install opencascade`, pinned with `brew pin opencascade`), used only to import STEP. A `brew upgrade` that changes its version breaks the built app until it's rebuilt. No other dependencies; ask before adding any.

## Structure

- `LibraKit/`: local Swift package with all non-UI logic; no SwiftUI imports
  - `Sources/StepBridge/`: C++ over OpenCASCADE behind a plain C API (`StepBridge.h`). Reads the XCAF assembly tree, flattens each part instance to file coordinates, meshes it, computes exact unit-density volume properties, and records snap features (face/edge kinds, centers, axes). All output is SI. Catches every OCCT exception.
  - `Sources/StepImport/`: Swift `StepImporter` actor (OCCT settings are global, so imports run one at a time)
  - `Sources/LibraKit/Model/`: `LibraDocument` (the .libra file: parts, groups, Libra frame), `DocumentEditing` (every change to a document, plus `FrameTarget`), `Part`, `PartGeometry`, `MassAssignment`, `Frame`, `InertiaTensor`, `DisplayUnits`
  - `Mass/`: combining parts (parallel axis theorem) and re-expressing in frames
  - `View/`: `OrthographicCamera` (navigation math, pixel → ray), `ViewerScene` (what the viewer draws), `MarkerMesh` (screen-sized overlay triangles)
  - `Picking/`: ray picking and `Snapper` (feature under the cursor → origin point or direction)
  - `Export/`: `MassReport` and the JSON, CSV, MJCF and URDF writers
- `Libra/`: app target
  - `Models/DocumentModel.swift`: per-window UI state (selection, frame tool, hover snap) and the scene builder. Document data lives in the `FileDocument` and is passed in with `inout`.
  - `Views/`: sidebar outline and groups, inspector (parts, groups, frames), totals bar, export sheet, settings
  - `Viewer/`: self-contained Metal viewer. The app only talks to `ViewerView` and `ViewerScene`. Shaders are compiled at runtime from `Shaders.swift`, so the Metal Toolchain isn't needed.
  - `Constants.swift`: sizes, colors, preference keys. Use constants for magic numbers.
- `LibraTests/`: `DocumentModel` tests (selection, keys, scene)
- `Tools/generate_fixtures.cpp`: writes the STEP fixtures in `LibraKit/Tests/StepImportTests/Fixtures/` (known boxes and a cylinder; duplicate sibling names). The compile command is at the top of the file.

## Conventions

- Everything is stored in SI (m, kg, kg·m²); display units are only for showing and entering values.
- Inertia tensors hold tensor entries (`xy = -∫xy dm`), about the center of mass, which is what MJCF and URDF expect.
- A `.libra` file is self-contained JSON (meshes as base64). It keeps no link to the STEP file; a changed CAD model means a new import.
- The Libra frame is the reference for totals and export; groups have their own frames. Standard views and orbiting use the Libra frame's Z as up.
- Keep logic in LibraKit and test it there. Views stay thin.
- Change a document only through the `LibraDocument` methods in `DocumentEditing.swift` (groups, frames, mass). They enforce the rules, e.g. a part belongs to at most one group. Views may set plain fields such as a group's name directly.
- The importer makes sibling names unique ("Bracket", "Bracket (2)"), so a part's assembly path plus name identifies it.

## Commands

Xcode isn't the active developer directory, so prefix builds with `DEVELOPER_DIR`:

```zsh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate                                   # after adding/removing files or editing project.yml
(cd LibraKit && swift test)                         # package tests, including STEP import
xcodebuild -project Libra.xcodeproj -scheme Libra -derivedDataPath build test   # app tests
xcodebuild -project Libra.xcodeproj -scheme Libra -derivedDataPath build build  # → build/Build/Products/Debug/Libra.app
```
