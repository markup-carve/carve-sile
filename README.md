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
output. `test/smoke.sh` checks the exchange AST whenever `carve` is installed
and additionally checks PDF generation when SILE is available.

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

### Composite figures are not grouped floats yet

A bare `::: figure` container is one figure of ordered panels under a single
caption (Carve PART 9 section 4c). This pipeline does not typeset it as one
float today, and the reason is worth stating precisely, because the layers have
to move in order and only one of them is this repository.

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

What the exchange AST holds today, from `carve --json` at the newest published
engine (0.1.3):

- the container is an `admonition` node of kind `figure` carrying `#fig-x` and
  the `columns-2` class, holding the two panels as separate `figure` nodes -
  the renderer maps it through the admonition path, so it becomes a div and not
  a float;
- the two panels ARE proper captioned figures, each with its own `caption`;
- the group caption is a PARAGRAPH whose text is the literal `^ Figure #: Group
  caption`, caret and placeholder included, because a caption after a container
  closer is section 4c's rule and the published engine predates it;
- both cross-references arrive as `heading_ref` and render as their bare target
  text, since nothing numbered the group.

Every node in that document has a handler, so the file typesets - it just does
not typeset as one float.

The order of the gate:

1. an `@markup-carve/carve` release containing the `figure_group` node - it is
   implemented in carve-js but is not in 0.1.3, the newest published version;
2. a `figure_group` handler in `carve/renderer.lua`, so the group caption and
   the panel captions arrive as captions rather than as text. This step is not
   optional once step 1 lands: an unmapped node type is an error here, so the
   day the engine emits `figure_group` this pipeline stops with `Unsupported
   Carve AST node type 'figure_group'` rather than degrading quietly;
3. Resilient placing that as a float, at which point the `columns-N` hint has
   something to act on.

Step 2 is the one this repository owns. Writing it before step 1 would be
matching a shape no released engine emits, which is why the handler is absent
rather than speculative.
