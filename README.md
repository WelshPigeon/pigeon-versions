<div align="center">
  <h1>Pigeon Versions</h1>
  <p><strong>The version registry and update checker for Pigeon Studios FiveM resources.</strong></p>
  <p>
    <a href="https://pigeonstudios.co.uk">Website</a> ·
    <a href="registry.json">Registry</a> ·
    <a href="checker/version_check.lua">Update checker</a> ·
    <a href="CHANGELOG.md">Changelog</a>
  </p>
</div>

---

Every Pigeon Studios resource, free or paid, checks this repository once when it starts and prints one clear line in the server console telling the owner whether they're up to date. This repository holds the release information it reads, the tool that builds and validates it, and the master copy of the checker that ships inside each resource.

No source code for any resource is kept here, only public release information.

## Contents

- [What server owners see](#what-server-owners-see)
- [How it works](#how-it-works)
- [Adding the checker to a resource](#adding-the-checker-to-a-resource)
- [Adding a resource to the registry](#adding-a-resource-to-the-registry)
- [Publishing a release](#publishing-a-release)
- [Security releases, minimum versions and notices](#security-releases-minimum-versions-and-notices)
- [Settings for server owners](#settings-for-server-owners)
- [The API](#the-api)
- [Tools and tests](#tools-and-tests)
- [Rules](#rules)
- [Layout](#layout)

## What server owners see

Up to date, one line:

```text
[script:pigeon-dice] [Pigeon Studios] Pigeon Dice v1.2.0 is up to date.
```

An update, with the release title, up to three highlights and where to get it:

```text
[script:pigeon-dice] [Pigeon Studios] Update available for Pigeon Dice: v1.1.2 -> v1.2.0 (released 2026-11-02)
[script:pigeon-dice]                  Smoother rolling
[script:pigeon-dice]                  - Rolls now animate for nearby players
[script:pigeon-dice]                  - Cooldown resets correctly after reconnecting
[script:pigeon-dice]                  - German translation
[script:pigeon-dice]                  Get it: https://github.com/pigeon-studios-uk/pigeon-dice/releases/tag/v1.2.0
```

| Situation | What's printed | Colour |
|---|---|---|
| Up to date | `<Name> v1.2.0 is up to date.` | Green |
| Update available | `Update available for <Name>: v1.1.2 -> v1.2.0 (released …)` and details | Yellow |
| A newer release fixes a security problem | `Security update available for <Name>: …` and a line asking them to update soon | Red |
| Installed version is below the minimum supported | `Important update available for <Name>: …` and `v… is no longer supported` | Red |
| Installed version is newer than the latest release | `<Name> v1.3.0-dev is a development build (latest release: v1.2.0).` | Cyan |
| Resource deprecated or discontinued | A notice line saying so, with what to do | Yellow / red |
| GitHub can't be reached | One retry after 60 seconds, then `Couldn't check for updates (…). The resource works normally.` | Default |
| Not in the registry, or set up wrongly | One line saying what's missing | Yellow |

## How it works

```text
resources/<slug>.json ──(node tools/build.mjs)──▶ api/v2/<slug>.json ──(raw.githubusercontent.com)──▶ checker in the resource
        you edit this                               generated                                            prints one line
```

1. Each resource has one hand-edited file, `resources/<slug>.json`, listing every release, newest first.
2. `tools/build.mjs` validates every file and generates `api/v2/<slug>.json` (small, just what the checker needs) and `registry.json` (an index of everything).
3. When a resource starts, its copy of `checker/version_check.lua` waits 2 to 6 seconds, fetches `api/v2/<slug>.json` once, compares versions using [semantic versioning](https://semver.org/), and prints the result.

The checker sends one GET request with no information about the server, its players or its configuration. GitHub receives the server's IP address, as it would for any download.

## Adding the checker to a resource

1. Copy [`checker/version_check.lua`](checker/version_check.lua) into the resource's `server/` folder **unchanged**. Every resource uses the identical file, so an improvement to the checker is a straight copy.
2. In `fxmanifest.lua`, set the version and the registry slug, and load the checker as a server script:

   ```lua
   version '1.2.0'
   pigeon_slug 'pigeon-dice'

   server_scripts {
       'server/version_check.lua',
       -- the resource's other server scripts
   }
   ```

3. Add the resource to the registry (next section) **before** its first release, or the console will say it isn't in the registry.

The checker needs nothing else: no dependencies, no configuration file, no exports. It's wrapped in its own scope, so it can't clash with the resource's code. For escrowed resources it can be escrowed or left open; it contains nothing secret.

## Adding a resource to the registry

Create `resources/<slug>.json`. The slug is the resource's permanent ID: lowercase letters, numbers and hyphens, the same as `pigeon_slug` in its `fxmanifest.lua`, and normally the same as its folder name. **Never change a slug once a release is out**; servers in the wild look it up by that name.

```json
{
  "$schema": "../schema/resource.schema.json",
  "slug": "pigeon-dice",
  "name": "Pigeon Dice",
  "kind": "free",
  "status": "active",
  "notice": null,
  "links": {
    "repository": "https://github.com/pigeon-studios-uk/pigeon-dice",
    "store": null,
    "support": "https://pigeonstudios.co.uk/support/"
  },
  "minimum_version": null,
  "releases": [
    {
      "version": "1.0.0",
      "date": "2026-11-02",
      "title": "First release",
      "security": false,
      "url": "https://github.com/pigeon-studios-uk/pigeon-dice/releases/tag/v1.0.0",
      "notes": [
        "Roll any dice with /roll, such as /roll 2d6+3.",
        "Results show above the player's head for everyone nearby."
      ]
    }
  ]
}
```

| Field | What it's for |
|---|---|
| `slug` | Permanent ID; must match the file name and `pigeon_slug` |
| `name` | Display name in the console |
| `kind` | `free` or `paid`. Paid resources must have a `store` link |
| `status` | `active`, `deprecated` (works, but owners should move on) or `discontinued` (no longer supported). Anything but `active` needs a `notice` |
| `notice` | Optional message printed on every start, such as what to move to |
| `links.repository` | Public repository, or `null` for private and paid resources |
| `links.store` | Store page for paid resources |
| `links.support` | Where owners get help |
| `minimum_version` | Versions older than this are told the update is important. `null` for none |
| `releases` | Every release, **newest first** |
| `releases[].version` | Semantic version without a `v`, such as `1.2.0` or `2.0.0-beta.1` |
| `releases[].date` | Release date, `YYYY-MM-DD` |
| `releases[].title` | One-line summary, up to 100 characters |
| `releases[].security` | `true` if the release fixes a security problem |
| `releases[].url` | Release page or download, or `null` to fall back to the store, repository or support link |
| `releases[].notes` | What changed, for server owners. The checker shows the first three; the API includes the first five |

Editors that understand JSON Schema (such as VS Code) will autocomplete and check these files using [`schema/resource.schema.json`](schema/resource.schema.json).

## Publishing a release

Do this **after** the release is published in the resource's own repository or store, so the "Get it" link works when owners see it:

1. Add the new release at the **top** of `releases` in `resources/<slug>.json`.
2. Run the builder:

   ```bash
   node tools/build.mjs
   ```

3. Commit the resource file and the generated files together, as `release(<slug>): v1.2.0`, and push.

GitHub can take up to five minutes to serve the new files to every server. CI rejects any push where the generated files don't match the resource files.

## Security releases, minimum versions and notices

- **Security fix:** set `"security": true` on the release. Every server on an older version, however far behind, is told it's a security update until it upgrades. Describe the fix in the notes without explaining how to exploit it.
- **Old versions that must not be used:** set `minimum_version`. Servers below it get a red "Important update" message.
- **Deprecating or discontinuing:** change `status`, and set `notice` to say what owners should do instead, such as "Pigeon Dice is replaced by Pigeon Dice 2: https://…".
- **A one-off message:** set `notice` on an active resource, and set it back to `null` when it's no longer needed. Use this sparingly; it prints on every start.

## Settings for server owners

Server owners control every Pigeon Studios resource's checker with one convar in `server.cfg`:

```cfg
set pigeon_update_check "on"      # default: one short line per resource
set pigeon_update_check "quiet"   # only print when an update, notice or problem needs attention
set pigeon_update_check "off"     # never check
```

## The API

`https://raw.githubusercontent.com/pigeon-studios-uk/pigeon-versions/main/api/v2/<slug>.json`

```json
{
  "schema": 2,
  "slug": "pigeon-dice",
  "name": "Pigeon Dice",
  "status": "active",
  "notice": null,
  "latest": {
    "version": "1.2.0",
    "date": "2026-11-02",
    "title": "Smoother rolling",
    "security": false,
    "highlights": ["…", "…"],
    "url": "https://github.com/pigeon-studios-uk/pigeon-dice/releases/tag/v1.2.0"
  },
  "minimum_version": null,
  "security_releases": [],
  "links": {
    "download": "https://github.com/pigeon-studios-uk/pigeon-dice/releases/tag/v1.2.0",
    "repository": "https://github.com/pigeon-studios-uk/pigeon-dice",
    "store": null,
    "support": "https://pigeonstudios.co.uk/support/"
  }
}
```

`schema` only changes for breaking changes. A checker that sees a schema newer than it understands says it needs updating, rather than misreading the data. New fields can be added within schema 2 without breaking existing checkers.

[`registry.json`](registry.json) lists every resource with its latest version, for the website and other tools.

## Tools and tests

| Command | What it does | Needs |
|---|---|---|
| `node tools/build.mjs` | Validates every resource file and writes the generated files | Node.js 18+ |
| `node tools/build.mjs --check` | Validates and fails if generated files are out of date (CI runs this) | Node.js 18+ |
| `lua tools/test/checker.test.lua` | Runs the checker against 33 scenarios with stand-ins for FiveM's functions | Lua 5.4 |
| `lua tools/test/checker.test.lua --show` | The same, printing each scenario's console output | Lua 5.4 |

The builder enforces, among other things: valid slugs matching file names, semantic versions newest first, real dates, no colour codes or control characters in any text, https links only, a store link for paid resources, and a notice for anything not active.

## Rules

- **Never change a slug** after a release. Make a new resource instead and deprecate the old one with a notice pointing to it.
- **Never edit `api/` or `registry.json` by hand.** Edit `resources/` and run the builder.
- **Never remove a resource file** for something that's been released. Set its status to `discontinued` instead, so servers still running it get told.
- **Keep the checker identical** in every resource. Change it here, bump `CHECKER_VERSION` and record it in the changelog, run the tests, then copy it out.
- Everything is published under Pigeon Studios only, with no attribution lines for tools.

## Layout

```text
.
├── README.md
├── CHANGELOG.md
├── LICENSE.md
├── resources/                 one hand-edited file per resource
├── api/v2/                    generated: what the checker reads
├── registry.json              generated: index of every resource
├── schema/
│   └── resource.schema.json   editor validation for resources/*.json
├── checker/
│   └── version_check.lua      master copy of the checker shipped in every resource
├── tools/
│   ├── build.mjs              validator and generator
│   └── test/
│       └── checker.test.lua   checker tests
└── .github/workflows/ci.yml   runs the builder check and the tests
```

---

© 2019–2026 Pigeon Studios. See [LICENSE.md](LICENSE.md).
