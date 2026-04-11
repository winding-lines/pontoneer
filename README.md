# pontoneer

[![CodeQL](https://github.com/winding-lines/pontoneer/workflows/CodeQL/badge.svg)](https://github.com/winding-lines/pontoneer/actions/workflows/codeql.yml)

Mojo library providing mapping, sequence, number protocol and rich comparison
extensions for Python extension modules.

**Full documentation:** https://pontoneer.dev


## Installation

```bash
pixi add --channel https://prefix.dev/pontoneer --channel https://conda.modular.com/max-nightly pontoneer
```

Or in your `pixi.toml`:

```toml
channels = ["https://prefix.dev/pontoneer", "https://conda.modular.com/max-nightly/", "conda-forge"]

[dependencies]
pontoneer = ">=0.6.4"
```

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
