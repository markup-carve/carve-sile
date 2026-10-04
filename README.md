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

Composite figures need an engine that emits the `figure_group` node, which
means release 0.1.4 or later. On an older engine everything else still works;
a bare `::: figure` arrives as an admonition and typesets as a plain div.

Current engines preserve inline markup in both halves of editorial
substitutions. The published 0.1.6 CLI still supplies plain strings, which the
inputter continues to render for compatibility.

Release 0.1.8 gave an escaped space and a generated-content opener
(`::: toc`, `::: footnotes` and the rest) their own AST nodes, and moved a
footnote reference's label onto the same field its definition uses. The inputter
reads all three, and still reads the older spellings, so a document typesets on
either side of that release. A generated region is not built here: this target
has no table-of-contents builder to hand it to, so the opener degrades to a div
carrying its kind.

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

## Includes

`{{ path }}` directives in a `.crv` file expand before typesetting. A path
resolves against the file that writes it, and nothing outside the containment
root is read. By default the root is the directory of the file SILE is
processing; `include_root` sets another one, and it must be absolute:

```sh
sile -u 'inputters.carve[include_root=/srv/book]' /srv/book/chapters/one.crv
```

`includes=false` leaves directives literal. Source that SILE does not hand over
as an unchanged file has no directory, so its directives stay literal unless
`include_root` is set.

A directive that does not resolve stays in the output, and SILE prints a warning
naming it with the file path relative to the root. Includes need a `carve` CLI with
include support, which no published `@markup-carve/carve` release has yet. With
an older CLI the directives stay literal and a warning says so, and setting
`include_root` is an error.

When SILE runs with `--makedeps`, resolved include targets are added to its
dependency file. Missing targets remain warnings because SILE's dependency
writer accepts only files that already exist.

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

### Engine pin

The `Dockerfile` installs two engines: the current lane, which the tests
measure against, and a `0.1.6` fixture lane the include probes need because
that release refuses `--include-root`. Both are hand-edited version literals,
so a check watches them:

```sh
./scripts/check-engine-pin.sh
```

It reads the current-lane version out of the `Dockerfile` and the newest
release from the npm registry, and fails when they differ. The two values come
from different places on purpose: a check that derived both from the
`Dockerfile` could never fail. It also fails when the fixture lane drifts out
of agreement with itself - the version it installs, the prefix it installs
into, its wrapper script and the name the tests invoke all have to name the
same release.

The fixture-lane agreement is what this repository controls, so `local` mode
runs it on every push and pull request. The comparison with the npm registry
is upstream moving, not a fault in a pull request, so `drift` mode runs it daily
from `.github/workflows/pin-drift.yml`. In `drift` mode a stale pin exits 3,
which files or updates one tracking issue and leaves the run green; a clean run
closes the issue, and any other failure, such as an unreachable registry, turns
the run red. No argument runs both.

### Upstream source pins

The image also clones resilient.sile, two of its libraries and ten addons at a
40-hex revision each. Those are not version literals a registry can answer for,
so each one carries a ruling in `scripts/upstream-pins.tsv` saying what it
follows and why, and a second check enforces the ruling:

```sh
./scripts/check-upstream-pins.sh
```

Two policies exist. `release-tag` means the revision has to be the newest
semver tag of that repository, which is what the twelve libraries and addons
use: they are installed with `luarocks make`, so a tagged release is what
upstream treats as consumable, and a commit landing on the default branch past
that tag is not staleness. `default-branch` means the revision has to be the
tip of the default branch, which only resilient.sile uses, because this
project's rockspec floor is `resilient.sile >= 4.2.0` and upstream has not
tagged 4.2.0 yet.

The modes split the same way: `local` (every push and pull request) checks that
every cloned source has a valid row and that the built resilient.sile rockspec
meets the floor at the pinned revision; `drift` (the daily `pin-drift.yml` run)
compares each pin with its upstream target.

The pinned revisions are read from the `Dockerfile` and the targets from the
GitHub API, so the two compared values never share a source. A repository the
`Dockerfile` clones but the policy file does not name is a failure, which keeps
a new source from entering the image unwatched. The check also confirms the
`resilient.sile` rockspec the image builds meets the floor and exists at the
revision actually cloned.

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
