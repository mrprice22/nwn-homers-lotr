# Crash party: running a stress event on purpose

A DM's idea — get as many players on as possible and see whether they can bring
the server down. This is the runbook for doing that *knowingly*: what to turn
on beforehand, which number actually says how close you are, and what to
collect if it does fall over.

**Admin document.** It is not on the public wiki and should not be — it names
control files, units and thresholds. Player-facing announcements are a separate
thing you write on the day.

---

## The one thing to understand first

**Tick rate is the verdict. CPU% is not.**

The live season already sits at ~98% of a core with a handful of players on it,
and has done for a long time without anyone complaining. That is a *saturated*
server, not a *failing* one: it is still completing every frame on time. What
players feel is **frame time** — the moment the loop can no longer finish its
work inside a frame, everything from spell timing to door opening starts to
lag, and only then does the server "feel bad".

So the question a crash party answers is not "can we get CPU to 100%" (it is
already there) but **"how far can frame time be pushed before the world stops
responding, and what runs out first"**.

Two instruments, and they answer different questions:

| Tool | Question | Cost |
|---|---|---|
| `bin/perfmon` (Anvil plugin) | *How much headroom is left right now?* Frame time, derived tick rate, players, CPU, memory. Also the in-game Palantir. | Negligible — safe to leave on. |
| `bin/perf-report` (NWNX_Profiler) | *Where did the frame go?* Per-scope: `AIMasterUpdateState`, `AIUpdateCreature`, `AIUpdateItem`, `RunScript`, pathing. | Coarse set is cheap; the per-script set is not (see below). |

Run both. The first tells you when to stop; the second tells you what to fix.

---

## Which realm

**This is your call, and neither option is free.**

- **Live (season 2)** is the honest test — real characters, real areas, the
  hardware weighting that actually applies (`nwnlive.slice`, `CPUWeight=10000`).
  It also risks the live season in front of the people you invited.
- **Dev** is safe to break, but it runs in `nwndev.slice` at `CPUWeight=30`
  against live's `10000`. If the live season is up and busy at the same time,
  a dev crash party is measuring a deliberately throttled server and the
  numbers will be pessimistic and hard to compare.

If you use dev, **stop the live season first** or accept that the result is a
floor, not a measurement.

---

## Before the event

1. **Confirm the collector and plugin are both live.**

   ```
   bin/perfmon                    # a fresh reading, not "STALE"
   bin/perf-report --window 5m    # non-empty scope table
   systemctl --user is-active nwn-season-perf-collect@<instance>.service
   ```

   If `perfmon` says the status file is missing, the plugin is not deployed:
   `bin/season-anvil-fix`, then let the season cycle.

2. **Take a quiet baseline.** An hour at normal population, so the event has
   something to be compared against. Without it you will have a number and no
   idea whether it is bad.

   ```
   bin/perf-report --window 1h --top 15   > baseline-scopes.txt
   bin/perf-report --window 1h --tickrate >> baseline-scopes.txt
   ```

3. **Decide whether to open the expensive profiler knobs.** The per-script and
   pathing options in `server.env` are commented out on purpose:

   ```
   #NWNX_PROFILER_ENABLE_SCRIPTS=y
   #NWNX_PROFILER_SCRIPTS_TYPE_TIMINGS=y
   #NWNX_PROFILER_SCRIPTS_AREA_TIMINGS=y
   #NWNX_PROFILER_ENABLE_PATHING=y
   ```

   They instrument **every script call and every path request**. On this
   hardware that is a measurement which changes what it measures, so it is the
   wrong default for an event whose whole point is a load number.

   Turn them on only for a **bounded window** — and prefer doing it *after* the
   party, replaying the same load, rather than during. If you do enable them,
   say so in your notes: the scope totals from that window are not comparable
   with any other.

4. **Start a recording** from the in-game Palantir (Start recording), or note
   the start time so `--since` can bracket it later. The Palantir is granted
   automatically on login to any CD key with `can_admin` in `admindb`.

---

## During

Watch `bin/perfmon watch` on a second screen, and add players in steps rather
than all at once — a step change you can attribute beats a cliff you cannot.

| Reading | What it means | What to do |
|---|---|---|
| tick rate steady, CPU high | Saturated but serving. | Keep going. |
| mean frame time climbing, p95 climbing faster | The loop is starting to miss. Players will report "lag" shortly. | Note the player count. This is the number the event exists to find. |
| `DEGRADED` (mean above `ANVIL_PERFMON_DEGRADED_MS`, default 50 ms) | Players are feeling it now. | One more step at most. |
| max frame time in seconds, tick rate collapsing | Something is stalling the loop outright, not merely loading it. | Stop adding players; capture and investigate. |
| memory climbing steadily and not returning | A leak, not a load limit — a different bug, and one a longer party will find. | Note it; it will not recover on its own. |

**Stop before the crash if you have the number.** "We degraded at N players" is
a more useful result than a core dump, and much cheaper to act on.

---

## After

```
bin/perfmon sessions                 # what was recorded
bin/perfmon report <name>            # tick rate vs player count, incl. at peak
bin/perf-report --since <start> --until <end> --top 20
bin/perf-report --since <start> --until <end> --counts
```

`--counts` is worth a look on its own: `AIUpdateListObjects [VERY_LOW]` is the
size of the engine's AI update list, and on this module it is ~23,400 objects
on **both** realms. That list is walked on every master update, which is why
the per-player cost is as steep as it is — the same walk that is nearly free
with nobody on costs 40-100x more once objects near a player wake up.

### If it did go down

```
bin/crash-archive --list
bin/crash-archive --apply
```

That pairs the core with the `logs.N` of the boot that produced it — nwserver
never records which — and keeps both past the host's 5-day coredump vacuum.

**The core contains the dm/admin passwords** (they are in nwserver's argv, so
they are in process memory and in `ps`). `crash-archive` redacts the metadata
and the daily backup deliberately excludes `core.zst`. Debug it locally; do not
hand it to anyone, and do not attach it to an upstream bug report.

---

## Known before you start

These came out of the first profiling pass and are worth knowing so the event
does not "discover" them as if they were new:

- **The AI update list is ~23,400 objects on both realms.** It is module-baked,
  not accumulated over uptime, and it is the amplifier behind the per-player
  cost.
- **`AIUpdateItem` costs ~92 ms/s on the live realm** against 0.8 ms/s on an
  empty one. Items are a surprisingly large share of AI cost here.
- **`nw_c2_default1.nss`** — the module's creature-heartbeat override — fake-casts
  at `GetObjectByTag("spells")`, and **no object in the module has that tag**.
  706 placed creatures do this every 6 seconds for no effect.
- **`d_cleartrash.nss`** (65 areas) sweeps every object in the area for *every*
  object that enters, with no `GetIsPC` guard, so NPC and summon movement
  triggers it too.

None of these has been fixed. They are filed in `roadmap.yaml`; the profiler
data from a real event is what should decide the order.
