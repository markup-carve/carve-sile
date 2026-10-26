# carve-sile

Experimental Carve 0.1 input support for SILE and resilient.sile. It reads the Carve CLI exchange AST and typesets with a Lua renderer. See the [Carve documentation](https://markup-carve.github.io/carve/).

## Install

```sh
luarocks make carve-sile-dev-1.rockspec
```

## Usage

```sh
sile -u inputters.carve examples/smoke.crv
```

## Documentation

- [Carve documentation](https://markup-carve.github.io/carve/)
- [Guide](docs/guide.md)
- [Documentation index](docs/README.md)

## License

[MIT](LICENSE).
