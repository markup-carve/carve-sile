# carve-sile

Experimental [Carve](https://markup-carve.github.io/carve/) input support for
[SILE](https://sile-typesetter.org/) and
[resilient.sile](https://github.com/Omikhleia/resilient.sile).

The inputter consumes Carve's normative exchange AST directly:

```text
.crv -> carve --json -> Carve AST -> native Lua renderer -> SILE -> PDF
```

No Pandoc conversion is involved.

## Requirements

- SILE 0.15.13 or later
- resilient.sile 4.2.0 or later
- `carve` on `PATH`

Install the Carve CLI from npm:

```sh
npm install -g @markup-carve/carve
```

Composite figures need an engine that emits the `figure_group` node, which the
newest npm release (0.1.3) predates: until the next engine release, that means
a carve-js build from source at `bde69f85` or later, which is what `Dockerfile`
pins. On an older engine everything else still works; a bare `::: figure`
arrives as an admonition and typesets as a plain div.

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
sile -u 'inputters.carve[converter=/path/to/carve]' book.crv
```

File includes are disabled for anonymous source by default. Enable contained
includes by passing an absolute source path, with an optional absolute root:

```sh
sile -u 'inputters.carve[source_path=/srv/book/main.crv,include_root=/srv/book]' /srv/book/main.crv
```

The source path gives nested directives their file identity. The root defaults
to that file's directory; set it to widen or narrow the filesystem boundary.
The file's bytes must match the source SILE supplies, preventing a configured
path from silently replacing preprocessed or included input.
Traversal and symlink escapes remain literal and produce sanitized warnings
from the Carve CLI. Supplying `include_root` without a source path enables
includes for stdin-like input and resolves top-level paths from that root.
Supplied exchange AST input is unchanged because it has already passed the
processor boundary.

Carve files may also be included from a Resilient master document after the
inputter has been loaded.

## Test

```sh
./test/renderer.sh
./test/smoke.sh
```

`test/renderer.sh` asserts on what the renderer puts into the SILE AST. It runs
its assertions inside SILE, so `SU.ast` is the real one, and it parses every
fixture with the `carve` CLI, so the AST under assertion is the engine's own
output. `test/smoke.sh` checks the exchange AST whenever `carve` is installed -
including that the installed engine emits `figure_group` at all - and
additionally typesets `examples/smoke.crv` and `examples/composite-figure.crv`
when SILE is available.

For a reproducible end-to-end run of both using SILE's official container image:

```sh
./test/container.sh
```

## Current scope

The renderer maps the stable Carve exchange format directly to Resilient's SILE
commands. Unknown node types are errors rather than silently discarded content;
documented fallbacks warn when no first-class Resilient command exists.

The renderer can only map what the engine emits, so what a construct becomes on
the page is still decided one layer down. A construct the published Carve engine
does not produce as its own node cannot be recovered here.

### Composite figures render as one numbered unit

A bare `::: figure` container is one figure of ordered panels under a single
caption (Carve PART 9 section 4c). The engine hands it over as a
`figure_group` node: the panels are the `figure` and `table` children in
source order, any other child is stray group content kept in place, and the
caption after the closing fence belongs to the whole group.

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

The renderer maps the group to one `markdown:internal:captioned-figure`.
Resilient numbers every captioned figure and table it typesets, so left alone
a two-panel group would consume three numbers and file three list entries; the
panels therefore carry `unnumbered` and `notoc`, two classes Resilient's
captioned commands already read. What comes out:

- the group is the numbered element - its caption, which the engine already
  resolved to `Figure 1: Two panels, one figure`, closes the figure, and the
  list of figures gains exactly one entry per group;
- each panel keeps its own caption, unnumbered and out of the lists, through
  `markdown:internal:captioned-figure` for figure panels and
  `markdown:internal:captioned-table` for table panels;
- stray group content typesets in place between the panels - a layout hint
  decides arrangement, never content;
- a captioned figure nested deeper than a direct child (inside a `::: note`,
  say) is not a panel and keeps its own number, which is the engine's rule
  too.

### What a composite figure is still not

Two halves of the paged-output contract sit below this repository, in
Resilient:

- **Not a float.** Resilient's captioned elements are not floats - its book
  class says so of itself - so the group typesets in the text flow where it
  was written and a page break may still fall inside it. That is the
  contract's degradation floor: a vertical stack of panels with their captions
  in source order, group caption last.
- **Not columns.** No layer below acts on a `columns-N` class, so panels stack
  vertically whatever the hint says. The class survives on the emitted
  options, where a future Resilient float or column mechanism would find it.

One caveat is shared with every captioned element here rather than specific to
groups: Resilient prefixes captions with its own `Figure N.` label from its
own counter, while Carve resolves the `#` placeholder from its figure
sequence. The two counters agree only in a document where every caption
carries a placeholder, and deduplicating the label is a decision about which
layer owns figure numbers, deliberately not taken in a composite-figure
change.
