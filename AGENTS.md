# Repository Guidelines

## Project Structure & Module Organization
- `Dochi/`: main macOS app code (`App`, `Models`, `State`, `ViewModels`, `Views`, `Services`, `Utilities`, `Resources`).
- `DochiMobile/`: iOS target code.
- `DochiCLI/`: CLI target code.
- `DochiTests/`: unit tests plus shared mocks in `DochiTests/Mocks`.
- `DochiUITests/`: UI test target.
- `spec/`: source-of-truth product and technical specs; link relevant sections in PRs.
- `scripts/`: development helpers like `smoke_test.sh`.
- `project.yml`: XcodeGen config. Regenerate `Dochi.xcodeproj` after changing it.

## Build, Test, and Development Commands
- `xcodegen generate`: regenerate the Xcode project from `project.yml`.
- `xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug build`: build the macOS app.
- `xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug -destination 'platform=macOS' test`: run the full test suite.
- `xcodebuild test -project Dochi.xcodeproj -scheme Dochi -destination 'platform=macOS' -only-testing:DochiTests/ToolRegistryTests`: run one test class.
- `./scripts/smoke_test.sh`: build, launch, and validate startup state via smoke log checks.

## Coding Style & Naming Conventions
- Language/toolchain: Swift 6 with strict concurrency (`SWIFT_STRICT_CONCURRENCY: targeted`).
- Concurrency: prefer `async/await`; use `Task.detached` only for clearly isolated heavy work.
- Architecture: protocol-based DI (`Dochi/Services/Protocols`) and mock injection in tests.
- Actor isolation: keep ViewModels and services `@MainActor` unless there is a strong reason not to.
- Logging: use `Log.*` (`os.Logger`); avoid `print()`.
- Naming: `UpperCamelCase` for types/files, `lowerCamelCase` for properties/functions, test classes end with `Tests`.

## Design Direction
- Optimize for the best merged architecture, not short-term legacy preservation.
- Prefer replacing brittle legacy paths with cleaner boundaries over layering new flags/branches.
- When refactoring behavior, update call sites and tests in the same change so the new structure becomes the default path.
- Avoid "temporary compatibility" unless explicitly required by product/runtime constraints.

## Testing Guidelines
- Framework: XCTest via Xcode test targets.
- Every feature change should ship with unit tests (happy path, state transitions, and failure paths).
- File I/O tests should use temporary directories, not real app data under `~/Library/Application Support/Dochi`.
- Run full tests before opening a PR; run smoke test for app initialization, startup flow, or integration-heavy changes.

## Commit & Pull Request Guidelines
- Follow existing history style: `feat:` / `fix:` prefixes, often with milestone tags like `[K-6]`, and PR refs like `(#179)`.
- Keep commit messages imperative and scoped to one logical change.
- PRs should include: concise summary, linked issue/milestone, test evidence (commands run), and screenshots for UI updates.
- Add a **Spec Impact** section and link affected docs in `spec/` when behavior or interfaces change.

## Security & Configuration Tips
- Never commit API keys or service-role credentials.
- Use environment variables for sensitive scripts (for example, `SUPABASE_SERVICE_ROLE_KEY` for migration).
