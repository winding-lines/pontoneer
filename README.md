# pontoneer

[![CodeQL](https://github.com/winding-lines/pontoneer/workflows/CodeQL/badge.svg)](https://github.com/winding-lines/pontoneer/actions/workflows/codeql.yml) [![mojoshelf](https://mojoshelf.org/badge/pontoneer.svg)](https://mojoshelf.org/tins/pontoneer) [![mojo nightly](https://mojoshelf.org/badge/pontoneer/nightly.svg)](https://mojoshelf.org/tins/pontoneer)

Mojo library providing mapping, sequence, number protocol and rich comparison
extensions for Python extension modules.

**Full documentation:** https://pontoneer.dev


## Installation

pontoneer is published on [Mojo Shelf](https://mojoshelf.org/tins/pontoneer) —
see that page for the current version and the up-to-date install commands.
Maintainers release new versions with `shelf publish` (see
[getting started](https://mojoshelf.org/getting-started)).

```bash
pixi shelf add pontoneer     # pixi shelf mode
shelf add pontoneer          # git submodule mode
```

Then include the tin path when building your extension module:

```bash
mojo build --emit shared-lib -I external/pontoneer my_module.mojo -o my_module.so
```

Full installation notes — including the plain-`pixi` git dependency form and the
Mojo 1.0 channel setup — are in the
[documentation](https://pontoneer.dev/#installation).

## Development

### Release scripts

**`tools/bump-mojo.sh`** — updates the Mojo compiler version across all entries in `pixi.toml`.

```bash
# Fetch the latest nightly version automatically via pixi search
./tools/bump-mojo.sh

# Or pin to a specific version
./tools/bump-mojo.sh 0.26.3.0.dev2026041020
```

**`tools/tag-release.sh`** — creates and pushes a versioned git tag combining the pontoneer version and the Mojo dev stamp (e.g. `v0.6.4-dev2026041020`). Reads both versions from `pixi.toml` and `pixi.lock` automatically.

```bash
./tools/tag-release.sh
```

## License

Apache License v2.0 with LLVM Exceptilons — see [LICENSE](LICENSE).
