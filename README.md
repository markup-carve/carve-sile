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
- `pandoc-carve` on `PATH`, built from a checkout that maps `figure_group`
  (pandoc-carve `af285cc` or later, which is what `Dockerfile` pins)

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

The test runs the `carve.figuregroup` unit test whenever a Lua interpreter is
available, checks conversion whenever `pandoc-carve` is installed, and
additionally typesets `examples/smoke.crv`, `examples/composite-figure.crv` and
`examples/composite-figure-nested.crv` when SILE is available. For the two
composite examples it reads back the list entries SILE wrote and checks that
the group is one unit and that group content which is not a panel is not.

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

### Composite figures number as one unit

A bare `::: figure` container is one figure of ordered panels under a single
caption (Carve PART 9 section 4c). The group is one numbering unit and only the
group produces a list-of-figures entry; its panels take neither a number nor an
entry, and a number placeholder in a panel caption stays literal.

Input, `examples/composite-figure.crv` in short:

````
{#fig-mixed .columns-2}
::: figure
| Kind | N |
|------|---|
| a    | 1 |
^ (a) A table panel

``` js
const x = 1
```
^ (b) A listing panel
:::
^ Figure #: Two panels, one figure
````

pandoc-carve maps that to a Pandoc `Figure` whose direct `Figure` and `Table`
children are the panels. Resilient's `pandocast` renderer turns each of those
into its own captioned float, so left alone a two-panel group consumes three
figure numbers, files three list-of-figures entries, and ends up numbered
`Figure 3` while the caption Carve resolved still reads `Figure 1:`.

`carve/figuregroup.lua` closes that gap. It walks the parsed tree, and on every
captioned figure it marks the direct captioned children `unnumbered` and
`notoc`, which are classes Resilient's `markdown:internal:captioned-figure` and
`markdown:internal:captioned-table` commands already read. The group is then
the only numbered element, its number agrees with the one Carve wrote into the
caption, and the list of figures has one entry per group.

Only direct children are panels. A captioned figure inside group content, in
a `::: note` or in the generic div a nested bare `::: figure` degrades to,
keeps its own number, which is what corpus documents `318-composite-figures-9`
and `-11` pin. An opener carrying a quoted title or a `[label]` is not this
production at all: it stays a generic container, and what it holds numbers on
its own.

#### What is still missing

The group numbers as one unit, but it is not yet laid out as one.

- Resilient's captioned elements are, in its own words, not floats. There is no
  float mechanism to place a group into, so a composite figure sits in the text
  flow where it was written.
- The `columns-N` layout hint arrives as a class on the group and nothing below
  acts on it. Two panels stack vertically rather than sitting side by side.
  Turning that into a real multi-column arrangement needs a renderer, which is
  the one thing this adapter deliberately does not own.
- Carve resolves the caption placeholder before the text reaches SILE, and
  Resilient prepends its own `Figure N.` to every caption. A caption written
  `^ Figure #: ...` therefore renders its label twice. This is not specific to
  composite figures; a single captioned image does the same.
- The two counters only agree in a document where every captioned figure
  carries a placeholder. Resilient numbers every captioned figure it typesets;
  Carve numbers only the captions that carry one. A caption written without a
  placeholder still consumes a Resilient number, and everything after it is
  numbered one higher than Carve thinks. `examples/composite-figure-nested.crv`
  is deliberately such a document, which is why its check asserts entries
  rather than numbers.

