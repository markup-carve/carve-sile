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

For a reproducible end-to-end test using SILE's official container image:

```sh
./test/container.sh
```

## Current scope

This prototype intentionally reuses Resilient's Pandoc renderer. Constructs with
a native Pandoc representation retain their structure. Carve-specific constructs
follow pandoc-carve's documented, warning-producing degradation rules. A future
direct Carve-AST renderer can replace `carve/bridge.lua` without changing the
`.crv` inputter interface.

Because the adapter owns no renderer, what a construct becomes on the page is
decided entirely by the two layers underneath it: the Carve engine pandoc-carve
depends on, and pandoc-carve's mapping to the Pandoc AST. A construct either
layer does not know about cannot be recovered here.

### Composite figures are not grouped floats yet

A bare `::: figure` container is one figure of ordered panels under a single
caption (Carve PART 9 section 4c). This pipeline does not typeset it as one
float today, and the reason is worth stating precisely, because two separate
layers have to move first.

Input:

```
{#fig-x .columns-2}
::: figure
{#fig-x-a}
![one](a.png)
^ (a) One

{#fig-x-b}
![two](b.png)
^ (b) Two
:::
^ Figure #: Group caption

See </#fig-x> and </#fig-x-a>.
```

What reaches SILE today, with the published engine:

- the container is an ordinary `Div` carrying the `admonition`, `figure` and
  `columns-2` classes, holding the two panels as separate Pandoc figures;
- the group caption is a PARAGRAPH whose text is the literal `^ Figure #: Group
  caption`, caret and placeholder included, because a caption after a container
  closer is section 4c's rule and the published engine predates it;
- both cross-references degrade to their bare target text, since nothing
  numbered the group.

The order of the gate:

1. an `@markup-carve/carve` release containing the `figure_group` node - it is
   implemented in carve-js but is not in 0.1.3, the newest published version and
   the one pandoc-carve resolves;
2. pandoc-carve mapping `figure_group` to a Pandoc figure containing the panel
   figures, so the group caption and the panel captions arrive as captions
   rather than as text;
3. Resilient's `pandocast` renderer placing that as a float, at which point the
   `columns-N` hint has something to act on.

Nothing in this repository sits between those steps, so there is no adapter-side
workaround: code here that recognized a grouped figure would be matching a shape
no layer below it emits.
