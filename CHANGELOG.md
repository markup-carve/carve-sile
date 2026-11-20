# Changelog

All notable changes to carve-sile are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Nothing released yet. The initial capability set:

### Changed

- Ported to Carve 0.2: the bridge runs `carve ast` (and `carve diagnostics`
  for include warnings) and the renderer reads the 0.2 tree (AST contract
  2.0). A 0.1 CLI no longer works. The image installs carve-js `next2` by
  commit.
- Include warnings carry the engine's codes `include-not-found`,
  `include-outside-root` and `include-cycle`.

### Added

- A SILE inputter (`inputters.carve`) that typesets `.crv` files directly:
  `carve ast` produces the Carve tree and a native Lua renderer
  maps it to SILE and resilient.sile commands. No Pandoc conversion involved.
- `converter=` inputter option to point at a non-default `carve` executable.
- Carve files can be included from a Resilient master document once the
  inputter is loaded.
- Resolved Carve include targets are registered with SILE's `--makedeps`
  dependency writer.
- Substitution old and new halves retain their inline markup, with compatibility
  for the string-shaped node emitted by the published 0.1.6 CLI.
- `carve-sile-dev-1.rockspec` for `luarocks make`, plus a Dockerfile pinning an
  engine build new enough to emit `figure_group` (composite figures).
