# Observed by Guardian

Guardian retains a small metadata record whenever an existing config or skills
attention gate selects a new event. This does not change alerts, decisions,
baselines, enrollment, or the current state location.

Each `observed-events/<UUID>.json` under Guardian's state directory contains
`formatVersion`, `id`, `observedAt`, `channel` (`config` or `skills`), and
`fingerprint`. Time is stored in UTC with milliseconds and displayed locally.
The config fingerprint is the proposed file SHA-256. The skills fingerprint is
the SHA-256 of the existing combined attention-state fingerprint; it is not an
aggregate directory hash. No config values, skill contents, paths, or diagnostic
messages are copied into the event record.

The timestamp means **Observed by Guardian**, not the exact write time, actor,
cause, or approval time. Records follow existing attention deduplication. They
are not a history of every filesystem write; maintenance-mode config rewrites
continue using the separate existing maintenance observation log.

Records survive marker reset and relaunch. There is no automatic deletion or
rotation. Each record is a small JSON file, but disk usage and startup scanning
work grow with retained history. The UI shows only the latest record. Malformed
records remain on disk and produce an incomplete-history warning. Recording or
reading failures warn separately and do not block existing alerts or decisions.
