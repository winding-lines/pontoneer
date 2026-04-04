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

## License

Apache License v2.0 with LLVM Exceptilons — see [LICENSE](LICENSE).
