# carve-sile

Experimental [Carve](https://markup-carve.github.io/carve/) input support for
[SILE](https://sile-typesetter.org/) and
[resilient.sile](https://github.com/Omikhleia/resilient.sile).

The current adapter takes the deliberately small integration path:

```text
.crv -> pandoc-carve -> Pandoc JSON -> resilient.sile pandocast -> SILE -> PDF
```

`pandoc-carve -t json` performs the conversion itself; a Pandoc installation is
not required.

## Requirements

- SILE 0.15.13 or later
- resilient.sile 4.2.0 or later
- `pandoc-carve` on `PATH`

`pandoc-carve` is not yet published in the npm registry. For now, install it
from its GitHub checkout:

```sh
git clone --recurse-submodules https://github.com/markup-carve/pandoc-carve.git
cd pandoc-carve
npm ci
npm run build
npm link
```

## Install from this checkout

```sh
luarocks make carve-sile-dev-1.rockspec
```

## Try it

SILE needs the third-party inputter loaded before it performs format detection:

```sh
sile -u inputters.carve examples/smoke.crv
```

This creates `smoke.pdf`. To use a non-default converter executable:

```sh
sile -u 'inputters.carve[converter=/path/to/pandoc-carve]' book.crv
```

Carve files may also be included from a Resilient master document after the
inputter has been loaded.

## Test

```sh
./test/smoke.sh
```

The test checks conversion whenever `pandoc-carve` is installed and additionally
checks PDF generation when SILE is available.

## Current scope

This prototype intentionally reuses Resilient's Pandoc renderer. Constructs with
a native Pandoc representation retain their structure. Carve-specific constructs
follow pandoc-carve's documented, warning-producing degradation rules. A future
direct Carve-AST renderer can replace `carve/bridge.lua` without changing the
`.crv` inputter interface.
