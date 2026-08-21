# Execution plan: Issue #127 — shrink the HA recorder DB and right-size its backup

**Status:** approved plan, not yet executed.
**Executor:** Claude (Sonnet or Opus), working interactively with Neil.
**Repos involved:** `~/git/swintronics` (this repo) and `~/git/ha-claude-project`
(HA YAML + Makefile tooling; read its `CLAUDE.md` before touching anything there).

## Background

Issue #127 (read it first — the diagnosis there is complete and trustworthy):
the HA recorder DB at `/docker-data/volumes/homeassistant/home-assistant_v2.db`
is 3.52 GiB, and 99.4% of state rows come from the SPAN panel v2 custom
integration writing one row per sensor every ~5 s across 203 entities. Purge
retention is working correctly; the size is pure write rate. The DB dominates
the nightly restic upload because a churning SQLite file dedupes poorly.

Neil has the SPAN mobile app as the source of truth for whole-panel data. The
only circuits he uses in HA are: **EV charger, kiln, and the two HVAC
condensers**. The kiln and EV automations (session latches, utility meters,
dual-fuel work) depend on those circuits' sensors and on long-term statistics.

## Decisions already made by Neil — do not re-litigate

1. **Backup path:** keep the existing restic flow (stop HA+Z2M → btrfs snapshot
   → restic). Do **not** set up HA native backups or object-storage backup.
   The fix is to shrink the DB and tune retention.
2. **Unused SPAN circuits:** disable their entities in HA's entity registry
   (scripted via the HA API). Not just a recorder exclude — zero writes.
3. **`purge_keep_days: 7`** (down from the default 10).
4. **Restic retention for the HA+Z2M snapshots:** `--keep-daily 7
   --keep-weekly 2 --keep-monthly 1` (down from 7/4/3).

## Hard constraints

- **Long-term statistics live inside the same SQLite DB.** Never exclude the DB
  file from backups. Never `recorder: exclude:` or disable the
  `_energy_consumed` sensors for the kiln, EV charger, HVAC circuits, or the
  panel main-meter consumed sensor — that kills their long-term statistics and
  breaks the Energy dashboard and utility meters.
- **Do not raise the SPAN `snapshot_update_interval`** above the 5 s default.
  Kiln element bursts are ~5 s; `binary_sensor.span_panel_kiln_running` is a
  threshold sensor and would miss bursts (this failure mode already cost ten
  hours of a firing once).
- `configuration.yaml` is owned by **this repo** (`ansible/services/homeassistant/configuration.yaml.j2`),
  never edited live. `packages/` is owned by ha-claude-project.
- Never glob `.storage/`. This plan explicitly authorizes reading **one named
  file**, `.storage/energy` (see Phase 1), and nothing else in there.
- Git discipline (per repo rules + Neil's standing feedback): feature branch,
  **confirm with Neil before committing**, commit+push together, PR, squash
  merge (`gh pr merge <n> --squash --admin --delete-branch`). A merged PR is
  not done until deployed and verified.

---

## Phase 0 — Baseline and the one open question

### 0.1 Record a baseline (goes in the PR description and the issue close-out)

Query the most recent **btrfs backup snapshot**, not the live DB (HA writes in
WAL mode; the snapshot is quiescent because it was taken with HA stopped).
Snapshots live at `/docker-data/snapshots/homeassistant/<Weekday>/` — pick the
newest directory.

```bash
SNAP=$(sudo ls -td /docker-data/snapshots/homeassistant/*/ | head -1)
sudo du -h "${SNAP}home-assistant_v2.db"
sudo sqlite3 "file:${SNAP}home-assistant_v2.db?mode=ro&immutable=1" \
  "SELECT count(*) FROM states;
   SELECT count(*) FROM states s JOIN states_meta m ON s.metadata_id=m.metadata_id
     WHERE m.entity_id LIKE '%span%';"
```

Also record the size of the last few restic snapshots for the `homeassistant`
tag: `sudo -E restic snapshots --tag homeassistant` and
`sudo -E restic stats latest --tag homeassistant` (source `backup.env` vars
first — see repo CLAUDE.md, Restore section, for how).

### 0.2 Resolve the loose end before touching produced sensors

`sensor.span_panel_garage_kiln_energy_produced` climbed 5121.8 → 5293.7 kWh-ish
with 279 distinct values over 10.6 days, while the panel main meter shows no
export at all (constant 0.5). Investigate before disabling produced sensors:

- Compare its curve against `..._energy_consumed` for the same circuit over a
  kiln firing window (SQL against the snapshot DB, or HA history).
- Likely explanations: CT orientation/phase artifact on a 240 V circuit, or
  integration accounting quirk. If the "produced" values track consumed activity
  in time but the panel main meter never moves, it is an artifact.

**Decision rule:** if it's an artifact (expected), proceed to disable
produced/net sensors wholesale in Phase 1. If it looks like real export
(surprising — stop and ask Neil), keep that one sensor enabled and skip only it.

---

## Phase 1 — Cut the SPAN write rate at the source (HA side, no swintronics changes)

Work from `~/git/ha-claude-project`. Its `.env` provides `HA_URL` + `HA_TOKEN`;
`make snapshot` refreshes `snapshots/ha-entities.tsv`.

### 1.1 Build the keep-list (safety-critical — do this before disabling anything)

1. `make snapshot`, then extract all SPAN entities:
   `grep -i span snapshots/ha-entities.tsv`.
2. Find every SPAN entity actually referenced anywhere:
   - `grep -rn span packages/ ha-config/automations.yaml ha-config/scripts.yaml ha-config/scenes.yaml dashboards/`
   - Read `.storage/energy` (named file, authorized) in
     `/docker-data/volumes/homeassistant/` to list Energy-dashboard source
     entities.
   - Check for utility_meter helpers sourced from SPAN sensors (they'll be in
     `packages/` or the TSV).
3. The keep-list is: every referenced entity, plus all sensors (power +
   energy_consumed) and binary sensors for the **kiln, EV charger, and two HVAC
   condenser circuits**, plus panel-level main meter consumed/power and any
   panel status/diagnostic entities that are cheap (check their row counts in
   the issue — diagnostics that rarely change cost nothing and can stay).
4. Show Neil the keep-list and the disable-list (counts + names) and **get his
   confirmation before executing**. He knows circuit names; the executor does
   not. Ambiguity = ask, don't guess (house rule in ha-claude-project).

### 1.2 Disable net/produced sensors via integration options — Neil, in the UI

The SPAN v2 integration options (`ENABLE_CIRCUIT_NET_ENERGY_SENSORS`,
`ENABLE_PANEL_NET_ENERGY_SENSORS`) live in `.storage/core.config_entries`,
which we don't touch, and the options flow is UI-driven. Ask Neil to:
Settings → Devices & Services → SPAN Panel → Configure → uncheck circuit and
panel net-energy sensor options (subject to the Phase 0.2 decision rule).
This removes ~22% of write volume and the entities cease to exist entirely.

Verify afterwards: the `_energy_net` / `_energy_produced` entities disappear
from a fresh `make snapshot` TSV.

### 1.3 Disable unused-circuit entities via the WebSocket API

Entity-registry disabling is WebSocket-only (`config/entity_registry/update`
with `disabled_by: "user"`). Write a small one-shot Python script (stdlib +
`websockets` or `aiohttp`, whichever is installed; temp files in the session
scratchpad, not the repo):

```text
connect ws(s)://<HA_URL>/api/websocket
recv auth_required → send {"type":"auth","access_token":HA_TOKEN}
for each entity_id in disable-list:
    send {"id":N,"type":"config/entity_registry/update",
          "entity_id":<id>,"disabled_by":"user"}
    check result, log failures
```

Then verify nothing broke:

- `make tmpl T='{{ states("binary_sensor.span_panel_kiln_running") }}'` and the
  same for each kept EV/HVAC/kiln sensor — all must return real states, not
  `unknown`/`unavailable`.
- Check `home-assistant.log` for errors from automations referencing
  now-missing entities (there should be none if the keep-list was right).
- Energy dashboard still renders with data.

### 1.4 Measure the new write rate

Wait ≥1 hour, then against the **live** DB is unavoidable here — use a copied
file instead of querying in place:
`sudo cp /docker-data/volumes/homeassistant/home-assistant_v2.db* /tmp-copy-location/`
and count rows written in the last hour by `last_updated_ts`. Expect roughly a
90%+ reduction versus the ~1.7 M rows/day baseline. Record the number.

---

## Phase 2 — swintronics repo changes

One feature branch, one PR, referencing issue #127. Two small edits:

### 2.1 `ansible/services/homeassistant/configuration.yaml.j2`

Add a recorder block (top level, after `default_config:` is a sensible spot):

```yaml
# Recorder history retention. Long-term statistics are unaffected — the Energy
# dashboard and kiln/EV utility meters keep their full history (issue #127).
recorder:
  purge_keep_days: 7
```

No `exclude:` block — write reduction was done at the source in Phase 1.

### 2.2 `ansible/services/homeassistant/backup-remote`

Change the forget line's retention flags:

```bash
sudo -E restic forget --retry-lock 10m --tag homeassistant --keep-daily 7 --keep-weekly 2 --keep-monthly 1 --prune
```

Note in the PR: the first run after this change will forget ~2 weekly + 2
monthly snapshots and prune — a longer-than-usual prune is expected once.

### 2.3 PR and merge

Confirm the diff with Neil before committing. Branch → commit (signing stays
disabled in this repo — do not re-enable) → push → PR (body links #127 and
records the Phase 0 baseline) → Neil merges or approves merge.

---

## Phase 3 — Deploy and reclaim space

1. Deploy via the `/deploy-and-verify` skill (scope: `homeassistant`). This
   re-renders `configuration.yaml` and `backup-remote` and restarts HA.
2. Confirm the recorder setting took: `make validate` is slow, so instead check
   HA booted cleanly (`home-assistant.log`) and
   `configuration.yaml` on disk contains the recorder block.
3. **Repack now** to reclaim the 10→7-day purge immediately. SQLite never
   returns pages to the OS, and auto-repack only runs the second Sunday of the
   month. Call via REST:

   ```bash
   curl -sf -X POST -H "Authorization: Bearer ${HA_TOKEN}" \
     -H 'Content-Type: application/json' \
     -d '{"repack": true}' "${HA_URL}/api/services/recorder/purge"
   ```

   Free-space requirement ≈ current DB size — trivially satisfied (220 GB
   free). The DB is locked during repack; run it at a quiet moment and warn
   Neil the History panel may stall for a few minutes.
4. Note for the close-out: the **full** size benefit lands ~8 days later, once
   the pre-change high-rate rows age past `purge_keep_days` and the next repack
   runs (auto on the second Sunday, or repeat step 3 manually after day 8).

---

## Phase 4 — Verify, close out

1. **Next morning:** confirm the nightly backup succeeded — Gatus
   `backups_home-assistant` endpoint green, healthchecks.io heartbeat fine.
2. `sudo -E restic snapshots --tag homeassistant` — retention now trims to
   7d/2w/1m (full effect over the following weeks as old snapshots age).
3. **After day 8 + repack:** re-run the Phase 0.1 baseline queries. Success
   criteria:
   - DB file **< 500 MB** (expect 200–400 MB: ~10% of prior write rate × 7 days
     + statistics tables).
   - SPAN share of state rows no longer ~99%.
   - Nightly restic upload for the HA snapshot visibly smaller
     (`restic stats`, or compare snapshot-to-snapshot added data).
4. Kiln/EV sanity check with Neil: automations, Energy dashboard, and utility
   meters all behaving across at least one EV-charge or kiln session.
5. Comment on issue #127 with before/after numbers (DB size, rows/day, upload
   size) and close it. If any memory-worthy lesson emerged (e.g., the produced-
   sensor anomaly explanation), record it per the memory instructions.

## Explicitly out of scope

- HA native/object-storage backups (considered, rejected — see Decisions).
- Any change to `snapshot_update_interval`, Z2M, Mosquitto, or other services'
  retention.
- MariaDB/PostgreSQL recorder migration — not worth it at post-fix write rates.
- Deleting existing restic snapshot history beyond what the new `forget`
  policy trims naturally.
