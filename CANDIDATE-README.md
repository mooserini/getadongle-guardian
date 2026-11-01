# Guardian Zero — private pre-build candidate

Private local candidate built 2026-11-01 per Moose's Guardian-zero method.
Source exported from `getadongle-guardian` main @ 4ec84ab. **No .git, no
remote, no pushes.** The swap/adoption decision is separate and later.

## Run it

```sh
./try-candidate.sh
```

The live Guardian keeps running throughout — the candidate never quits it,
never touches its login item (`SMAppService` is removed from the candidate
entirely), and launches only with `HCG_*` overrides pointing inside this
folder (`state/`, `sandbox/`).

Trial: enroll the sandbox config → enroll the environment file → edit dummy
values → Accept/Reject → Clarify. Paste your OpenRouter key into the
candidate's Clarify section yourself at trial time; it stores only in
`state/guardian-settings.json` (0600). No key was supplied during the build.

## What changed vs 4ec84ab

- Display/bundle rename to Getadongle Guardian; bundle ID is the distinct
  candidate ID `org.getadongle.guardianzero`; module/target names, `HCG_*`
  vars, and data-path construction stay frozen. MenuBarExtra label
  construction untouched (HARD constraint).
- Deployment floor macOS 26 (Package.swift uses the string form
  `.macOS("26.0")` — the `.v26` enum needs a newer tools manifest),
  arm64-only by host build, built with the macOS 27.2 SDK. Yams 6.2.2
  unchanged (sole dependency, builds clean).
- `.env` enrollment at parity: `EnvInspector`/`EnvDiffer` (key-level diff,
  values redacted by key name), second `ApprovalStore` under
  `state/env-file/` with `.env` snapshot extension. The env target never
  defaults to a real file — without `HCG_TARGET_ENV` it points at
  `state/sandbox-dummy.env`.
- Clarify is agnostic: Hermes-oneshot resolution retired (source + tests
  removed). Generic-endpoint rebuild (2026-11-01, Moose's design): the
  cloud leg owns no provider title — two settings, endpoint URL + API key
  (0600 settings store). Configuring probes the endpoint's authenticated
  OpenAI-compatible models listing; acceptance populates the model picker
  from the returned catalog, rejection/failure marks the leg degraded
  through the existing machinery. The picked model is then called at the
  configured endpoint. OpenRouter works when its URL + key are the entered
  values. Visible prefer-cloud / prefer-local switch, Apple on-device leg,
  and deterministic floor unchanged. Pre-rebuild settings migrate: the
  key written under its OpenRouter-era name decodes as the endpoint key,
  endpoint defaulting to https://openrouter.ai/api/v1.
- Dialect amendment (2026-11-01, Moose's ruling): endpoint settings gain
  a DIALECT field — owner-chosen, stored with the endpoint, never quietly
  assumed. Three tongues: Chat Completions, Responses, Messages
  (Anthropic native: system separate, x-api-key + anthropic-version, no
  Bearer). Sensible inference where unambiguous (anthropic host -> Messages,
  /responses -> Responses, else Chat Completions); stored OpenRouter
  config infers Chat Completions, migration-tested. Catalog probe and
  completion calls speak the configured dialect; degraded machinery
  identical on any failure. Request/response translation per dialect is
  pure and offline-tested (shaping + extraction).
- Degraded Clarify: orthogonal flag (six Status cases untouched), distinct
  menu-bar silhouette, its own ORANGE Clarify-health row in the panel,
  receipt recorded regardless, silent, clears on a successful cloud call.

## Verification

- `swift test` full suite green in this tree: 69 tests (44 GuardianCore incl.
  5 new candidate tests, 25 HermesConfigGuardian).
- Candidate bundle builds: `build/Getadongle Guardian.app`
  (`CFBundleIdentifier org.getadongle.guardianzero`).
- Isolation smoke test: candidate launched (own PID), live Guardian kept
  its PID, SHA-256 of live `config.yaml`, `.env`, and live `current.json`
  identical before and after.

## Discard / adopt

Discard = quit the candidate and delete this folder (trial key copy dies
with it; revoke the key if a real one was pasted). Adopt = separate later
decision; repo work happens only after Moose's trial.
