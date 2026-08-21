# Changelog

All notable changes to carve-sile are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Nothing released yet. The initial capability set:

### Added

- A SILE inputter (`inputters.carve`) that typesets `.crv` files directly:
  `carve --json` produces the normative exchange AST and a native Lua renderer
  maps it to SILE and resilient.sile commands. No Pandoc conversion involved.
- `converter=` inputter option to point at a non-default `carve` executable.
- Carve files can be included from a Resilient master document once the
  inputter is loaded.
- `carve-sile-dev-1.rockspec` for `luarocks make`, plus a Dockerfile pinning an
  engine build new enough to emit `figure_group` (composite figures).
