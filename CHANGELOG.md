# Changelog

All notable changes to the registry format, the builder and the update checker are documented here. Releases of individual resources are recorded in `resources/`, not here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is the update checker's `CHECKER_VERSION`.

## [Unreleased]

### Changed

- Links, badges and the update checker's registry address now point to the Pigeon Studios GitHub organisation, [pigeon-studios-uk](https://github.com/pigeon-studios-uk). Old WelshPigeon links still redirect, and copies already installed keep working.

## [2.0.0] - 2026-10-18

A new registry and update checker, replacing `pigeon-resource-versions` and every per-resource checker before it. Resources released before this version keep reading the archived `pigeon-resource-versions` repository.

### Added

- `resources/<slug>.json`: one hand-edited file per resource with its full release history.
- `api/v2/<slug>.json`: a small generated document per resource for the checker, and `registry.json` as an index.
- `tools/build.mjs`: validates every resource file and generates the API, with a `--check` mode for CI. No dependencies.
- `schema/resource.schema.json` for editor autocomplete and validation.
- `checker/version_check.lua`: one checker file, identical in every resource:
  - one line when up to date, and a short block with the release title, three highlights and a download link when an update is available;
  - security updates flagged whenever any newer release fixed a security problem;
  - minimum supported versions, deprecation and discontinuation notices;
  - full semantic version comparison, including pre-releases and build metadata;
  - one retry after 60 seconds if GitHub can't be reached, then a single calm line;
  - a `pigeon_update_check` convar (`on`, `quiet`, `off`) shared by every Pigeon Studios resource;
  - registry text cleaned of colour codes and control characters before printing.
- `tools/test/checker.test.lua`: 33 scenarios run against the real checker in Lua 5.4.
- CI that runs the builder check and the checker tests on every push and pull request.

[Unreleased]: https://github.com/pigeon-studios-uk/pigeon-versions/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/pigeon-studios-uk/pigeon-versions/releases/tag/v2.0.0
