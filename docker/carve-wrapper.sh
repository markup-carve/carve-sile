#!/bin/sh
# The Carve 0.2 CLI, built from the pinned carve-js commit.
exec node /opt/carve/node_modules/@markup-carve/carve/dist/cli.js "$@"
