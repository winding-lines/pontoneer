# pontoneer

[![CodeQL](https://github.com/winding-lines/pontoneer/workflows/CodeQL/badge.svg)](https://github.com/winding-lines/pontoneer/actions/workflows/codeql.yml)

Mojo library providing mapping, sequence, number protocol and rich comparison
extensions for Python extension modules.

**Full documentation:** https://pontoneer.dev


## Installation

Add pontoneer as a git submodule and point the Mojo compiler at it with `-I`:

```bash
git submodule add https://github.com/winding-lines/pontoneer external/pontoneer
git -C external/pontoneer checkout v1.0.0+mojo1.0.0-2   # pin the release
```

Your project needs Mojo 1.0 from the stable Modular channel — in `pixi.toml`:

```toml
channels = ["https://conda.modular.com/max/", "conda-forge"]

[dependencies]
mojo = "==1.0.0"
```

Then include the submodule path when building your extension module:

```bash
mojo build --emit shared-lib -I external/pontoneer my_module.mojo -o my_module.so
```

Prebuilt artifacts (`pontoneer.mojoc` and conda packages for osx-arm64 /
linux-64) are also attached to each
[GitHub release](https://github.com/winding-lines/pontoneer/releases).

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
