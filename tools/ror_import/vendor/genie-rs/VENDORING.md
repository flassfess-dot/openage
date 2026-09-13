# Vendored scenario reader

This directory contains only genie-cpx, genie-scx, and genie-support from
SiegeEngineers/genie-rs commit
a77200aef567b40b7db51cf47c1fda8db75e8e67.

The upstream and this project are GPL-3.0; the upstream license is preserved in
LICENSE.md. Test fixtures were intentionally omitted because they are not
required to build the source-owned RoR importer.

Local changes are deliberately limited to read-only accessors for player base
properties, starting/world resources, diplomacy, per-player object lists, and
the embedded build-list/city-plan/AI-rule payload already parsed by upstream.
They let the converter serialize source facts without exposing the old scenario
format to the runtime game.

The owned installation is Russian, so legacy strings are decoded deterministically
as Windows-1251, matching the Python asset importer. ASCII-only English sources
remain compatible.
