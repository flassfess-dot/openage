# Periodic AI and presentation stalls — 2026-10-06

## Evidence and scope

The preceding investigation of the current package and the original heavy-save checkpoint is preserved under `.tmp/periodic-diagnosis-20261006/`. In the warm true Release sample, one recursive AI-input validation averaged 80.112 ms; the maximum simulation hold was 249.525 ms. The owner captured and repeatedly checked large navigation arrays, started planning at its application deadline, and held simulation throughout calculation. Placement enrichment could synchronously wait for worker searches. Render publication rebuilt already immutable resource-memory records. The full-build script also copied the Godot editor as the shipped executable.

These are measurements of the preceding version. This change has not been benchmarked and does not establish a new frame-time bound.

## Final contracts

* `IsolatedTaskData.freeze_detached` validates producer-owned DTOs and recursively freezes their containers. A mutex-protected bounded identity registry permits sharing immutable roots. Tokens on unrelated dictionaries do not confer trust. Typed Vector2/Vector2i arrays can be validated without inspecting every element. Mutable factual state is copied by `capture`; immutable map publications retain their identities. An owned planning input is sealed once before dispatch.
* Navigation bucket arrays use typed points and copy on write. Readonly typed buckets are safe by construction and need no retaining registry entry; only DTO roots are registered. Revised wrappers do not force point traversal or copying, even after registry eviction. Registries retain at most 12 immutable roots and 12 sealed roots; eviction retains full validation as a safe fallback.
* The owner prepares at most one player observation per rendered frame. The nearest AI deadline is prepared up to eight fixed ticks in advance. A batch has one fixed snapshot boundary and target tick, in player order. Once capture/submission is complete, simulation advances while the worker runs. Incomplete capture holds its source boundary; exceptionally late work holds only its application deadline. Early completion never publishes state or commands early. Sequential/reference mode uses the same source and target boundaries. Thread timing never chooses an application tick.
* Placement capture collects detached topology, occupancy and requested profiles once for the batch. Searches run directly within its planning worker, with a private planner shared between kinds. It submits no nested jobs and waits on no worker pool. Ordered candidate filtering remains equivalent to the synchronous path. Compact cache updates are accepted only when current workers, occupancy, exploration, technology and affordability still match. Empty searches are retained. Build commands additionally validate live placement at execution.
* Saves include the pending batch's source/target boundaries and already captured inputs, encoded as object-free binary Variants inside the JSON archive. This preserves vector types, packed arrays, floating-point values and integer keys. Restore validates player definitions/state and snapshot boundaries before publishing the restored world. Results are recomputed from the saved inputs rather than newer observations. AI state is saved without replay-hash quantization and JSON is written with full floating-point precision, so pending-state comparison cannot fail after rounding. Older archives without a pending queue remain supported. A capture still in preparation may resume only at its original source boundary.
* Immutable render-memory records are reused directly. Live entity changes create replacement records; projecting an older fog-memory record cannot overwrite the live render cache. Visible building memory uses the retained projector. Selected/control data remains independently enriched. The render schema marker does not bypass worker-isolation validation.
* `tools/ror-full-build.ps1` exports with `--export-release` using the Windows Release template, copies the native Release library, rejects script compilation errors reported despite a zero process status, and rejects an executable identical to the editor. Missing local templates can be extracted from the existing template archive. `tools/build-game.ps1` already used Release export.

The lookahead intentionally changes the AI observation tick, keeping application cadence stable. Network lockstep still transmits authoritative commands; replay playback applies recorded commands. No save version change is required because pending planning is optional controller state.

## Prepared regression coverage

`test_immutable_ai_capture`, `test_ai_lookahead_deadline`, `test_ai_pending_plan_save`, `test_deferred_ai_build_sites`, `test_render_memory_reuse`, and integration `test_pending_ai_save_resume` cover map identity/mutable-state isolation, bounded registries, forged markers, a semaphore-controlled worker deadline, reference parity, pending-plan serialization/validation, placement equivalence and stale-result rejection, immutable fog memory, and full checkpoint continuation hashes/command order.

**Tests were prepared but not executed, as explicitly requested.** Resource import/script compilation and Release export are build steps; neither starts the game or the test suite. Performance improvements remain unmeasured in this revision.

## Release artifact

Final build: `prototype/qa/dev-scripts/full-build-20261006-234345.log`, completed 2026-10-06 23:52:12 Moscow, exit 0. Import/export logs contain no script or export errors. All 18 recorded implementation/build/test source files remained unchanged during this final build. An earlier export was intentionally stopped after source changes, and is not the delivered package.

Artifacts in `dist/Rise of Rome Prototype/`:

* EXE: 109127680 bytes; SHA-256 `4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668`.
* PCK: 275812648 bytes; SHA-256 `70cb8b26ed3c4b3958d475f5181a5f25430b2ff84f4c754fd78e7e4b565d721a`.
* Native Release DLL: 686592 bytes; SHA-256 `59d366e9ca7badc0f999c519ac6039efa2d1952358d4e61a5379efb54cf24cf9`.

Static PE inspection confirms that the executable's code section matches the Windows Release template and differs from the editor. Packaged and freshly built native libraries are identical. The game and tests were not launched. Build source/artifact manifests are under `.tmp/periodic-diagnosis-20261006/release-build-*-234345.json`.

## Requested regression run — 2026-10-06

After the Release build, the user explicitly requested execution of the six prepared regression files. All six passed in separate headless processes using the existing test-suite supervisor: 6 passed / 0 failed, runner exit 0, no engine errors or timeouts. Total child-process elapsed time: 20.613 seconds. No implementation changes or additional test runs were needed; the Release artifact above remains current.

Coverage: immutable map capture and bounded registries; AI lookahead/deadline and reference parity; precise pending-plan serialization; deferred placement equivalence and cache invalidation; render-memory reuse; full checkpoint continuation with matching world hashes, AI state and command order.

Summary: `.tmp/periodic-stutter-tests-20261006/summary.json`. Combined log: `.tmp/periodic-stutter-tests-20261006/runner.log`; each test also has its own log in that directory. This is a targeted six-file regression run, not a full-suite or frame-pacing benchmark.
