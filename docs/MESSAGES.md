# Mission messages and DCS logs

Updated: 2026-10-07

This catalogue shows the actual English message bodies with concrete example values. Names, mission IDs, coordinates, counts and scores are illustrative, not captures from a live DCS run. Timing and wording follow the current implementation.

The four F10 task commands are `Task: Intercept`, `Task: CAP`, `Task: SEAD`, and `Task: DEAD`. Retry and site-release messages refer to these labels. Acceptance, spawning, objectives, recovery and scoring follow the existing behavior.

## Output channels

| Channel | Delivery |
|---|---|
| Screen | Mission Group, including all wing members for individual settlement |
| DCS message log | Same body as the screen message, prefixed with `[DynamicTraining] MESSAGE [BLUE_HORNET_INCIRLIK_01]` |
| Global screen/message log | Startup messages; log prefix `[DynamicTraining] MESSAGE [ALL]` |
| DCS debug log | `[DynamicTraining] [DEBUG]`; countdowns, Intercept start information plus Pilots, SEAD HARM instructions |
| Other DCS logs | Assignment, objective, observation, cleanup and persistence events |

Screen durations: default 10 seconds, coordinate briefings 60 seconds, settlements 20 seconds. Mission polling: 1 second. Takeoff checks: 2 seconds. Spawn delay: 20 seconds after all registered pilots are observed airborne. Recovery: speed at or below 5 knots for 10 consecutive seconds after a valid landing.

The supplied MOOSE returns DDM on one line, with the `LL DDM` prefix and three decimal places in minutes. The coordinate examples below use that exact format.

## Screen: Intercept

### Ground acceptance — 10 seconds, once per accepted assignment

```text
Intercept mission armed. Registered pilots: 2.
Waiting for ALL registered pilots to take off.
```

No screen message at countdown start or reset. The 20-second delay still applies.

### Successful spawn — 15 seconds, once

For airborne acceptance this is immediate. For ground acceptance it follows the takeoff delay.

```text
Intercept MISSION START
Range: 70 NM
Altitude: 20000 ft
Aspect: HOT
```

### All hostile aircraft destroyed — 20 seconds, once

```text
Intercept PRIMARY OBJECTIVE COMPLETE
All hostile aircraft destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

## Screen: SEAD

### Acceptance — 10 seconds, once

```text
SEAD mission accepted.
Mission planning in progress.
```

TOO and PB share this acceptance message. The selected MODE first appears on screen in the completed planning briefing; acceptance MODE is debug-only.

### TOO planning complete — 60 seconds, once automatically

```text
SEAD MISSION
MODE: TOO
THREAT AREA: LL DDM 034° 39.420'N   037° 57.180'E
TARGET TYPE: UNKNOWN
Reward per pilot: 150 points.
Registered pilots: 2.
```

### PB planning complete — 60 seconds, once automatically

```text
SEAD MISSION
MODE: PB
THREAT AREA: Palmyra
THREAT: SA-6
ESTIMATED LOCATION: LL DDM 034° 39.420'N   037° 57.180'E
HARM PB CODE: 108
Reward per pilot: 150 points.
Registered pilots: 2.
```

SA-8 PB uses `THREAT: SA-8` and `HARM PB CODE: 117`.
TOO/PB screen briefings and Mission Status contain no HARM instruction paragraph.
TOO still hides the SAM type, exact site and PB code. PB still hides the exact site.

No screen message at countdown start or reset. Airborne acceptance can produce acceptance, planning complete and start notifications close together.

### Successful SAM spawn — 25 seconds, once

```text
SEAD TRAINING START
Objective: destroy primary emitter, or damage it and keep radar OFF for 60 seconds; then RTB.
```

### Destroyed result — 20 seconds, once

```text
SEAD Objective Complete
Enemy radar destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

### Suppressed result — 20 seconds, once

```text
SEAD Objective Complete
Enemy radar suppressed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

No automatic screen message when suppression timing starts, resets, or progresses. Use Mission Status for the emitter state and observed OFF duration.

## Screen: Site actions and Immediate DEAD

### Preserve Site for DEAD — 20 seconds

```text
SAM site preserved for follow-on DEAD.
Keeper: Hawk 1
Site remains reserved for your wing after SEAD settlement.
Return to base and rearm.
Site will be cleaned when the keeper disconnects.
```

### Continue as DEAD — 20 seconds, once

```text
Immediate DEAD started.
Destroy all remaining SAM site vehicles.
Remaining targets: 3
Additional DEAD reward per pilot: 150 points.
SEAD reward also retained.
```

### Immediate DEAD complete — 20 seconds, once

```text
DEAD Objective Complete
SAM site destroyed.
Return to base.
DEAD reward per pilot: 150 points; recovery failure: 90 points.
SEAD reward also retained.
```

### Release Site Reservation after source settlement — 20 seconds

```text
SAM site reservation released.
Available to all wings via 'Task: DEAD'.
Cleanup after 30 minutes without a reservation.
```

Before source SEAD settlement:

```text
SAM site reservation released.
Available to other wings after SEAD settlement.
Cleanup after 30 minutes without a reservation.
```

Cleanup has no screen notification. Private RETAIN sites have no idle timeout. Public AVAILABLE sites start the 30-minute timer only when no assignment is using them.

## Screen: Follow-on DEAD

### No eligible preserved/public site — 15 seconds

```text
No preserved SAM sites available for DEAD.
```

### Successful acceptance — 10 seconds, once

```text
DEAD mission accepted.
```

### Site briefing — 60 seconds, once at acceptance

```text
DEAD MISSION
AREA: Palmyra
TARGET SITE: SA-6
STATUS: Primary radar destroyed
OBJECTIVE: Destroy all remaining SAM site vehicles.
SITE LOCATION:
LL DDM 034° 39.420'N   037° 57.180'E
Reward per pilot: 150 points.
Registered pilots: 2.
```

A suppressed emitter instead produces `STATUS: Previously suppressed`.

### Activation after takeoff / airborne acceptance — 25 seconds, once

```text
DEAD TRAINING START
Objective: destroy all remaining SAM site vehicles; then RTB.
```

There is no 20-second delay and no respawn. Both ground and airborne acceptance use the SEAD notification pattern: acceptance, one automatic coordinate briefing, then a short activation message. Ground acceptance waits for all registered pilots before activation. Coordinates are not repeated at activation; Mission Status can recall them.

### Follow-on DEAD complete — 20 seconds, once

```text
DEAD Objective Complete
SAM site destroyed.
Return to base.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

## Screen: Individual settlement — 20 seconds per pilot

Every participant's result is sent to the original assignment Group. MP2 therefore receives separate messages for both pilots. The examples below assume persistence is attached and the new revision is awaiting acknowledgement.

### Successful Intercept recovery

```text
Intercept RTB_SUCCESS: Hawk 1
Safe recovery confirmed (100%).
Points: +150
Total Score: 150
Persistence pending; not yet saved.
```

### SEAD recovery failure after primary completion

```text
SEAD RTB_FAILURE: Hawk 1
Ejection before safe recovery (60%).
Points: +90
Total Score: 90
Persistence pending; not yet saved.
```

The event word can also be `Crash`, `Dead`, `PilotDead` or `UnitLost`.

### Follow-on DEAD failure before completion

```text
DEAD FAILED: Hawk 1
Crash before primary completion (0 points).
Points: +0
Total Score: 150
Persistence pending; not yet saved.
```

### Individual abort

```text
SEAD ABORT: Hawk 1
Individual sortie aborted. No reward.
Points: +0
Total Score: 150
Persistence pending; not yet saved.
```

Wing abort uses `Wing mission aborted. No reward.` and generates one settlement per participant.
Before Intercept/SEAD spawning, no scoring ID exists, so the settlement body has only its heading and reason. A whole-assignment abort before spawning also sends `SEAD reservation cancelled.` or `Intercept reservation cancelled.` for 10 seconds.

### Immediate DEAD incomplete, safe RTB

```text
SEAD RTB_SUCCESS: Hawk 1
Safe recovery confirmed (100%).
SEAD Points: +150
DEAD Points: +0
Points: +150
Total Score: 150
Persistence pending; not yet saved.
```

### Immediate DEAD complete, safe RTB

```text
SEAD RTB_SUCCESS: Hawk 1
Safe recovery confirmed (100%).
SEAD Points: +150
DEAD Points: +150
Points: +300
Total Score: 300
Persistence pending; not yet saved.
```

### Unverified UCID

```text
SEAD RTB_SUCCESS: Hawk 1
Safe recovery confirmed (100%).
Unscored sortie (UCID unavailable).
```

Landing, LANDING_CHECK entry, the recovery hold countdown, and a go-around have no automatic screen notification. Successful recovery produces settlement only after the stable hold finishes.

## Screen: Mission Status — requested manually

### Idle — 10 seconds

```text
Intercept: Idle.
SEAD: Idle.
DEAD: Idle.
```

### Intercept ACTIVE — 20 seconds

```text
Intercept: ACTIVE
Wing: BLUE_HORNET_INCIRLIK_01
Lead reference: Hawk 1
Hawk 1 [BLUE_HORNET_INCIRLIK_01-1]: ACTIVE
Hawk 2 [BLUE_HORNET_INCIRLIK_01-2]: ACTIVE
```

### SEAD SUPPRESSION_PENDING — 60 seconds

```text
SEAD: ACTIVE
Wing: BLUE_HORNET_INCIRLIK_01
Lead reference: Hawk 1
SEAD MISSION
MODE: TOO
THREAT AREA: LL DDM 034° 39.420'N   037° 57.180'E
TARGET TYPE: UNKNOWN
Emitter state: SUPPRESSION PENDING
Radar 1 OFF: 35 / 60 seconds
Site state: ACTIVE
Site disposition: CLEANUP
Follow-on DEAD available: NO
Hawk 1 [BLUE_HORNET_INCIRLIK_01-1]: ACTIVE
Hawk 2 [BLUE_HORNET_INCIRLIK_01-2]: ACTIVE
```

Planning SEAD uses 20 seconds and `THREAT AREA: Planning in progress`, with `Site checks: 4` instead of emitter/site details.
Planning PB uses `ESTIMATED LOCATION: Planning in progress`. Once coordinates exist, SEAD Status uses 60 seconds.
SEAD Status never adds the `Spawn in ... seconds.` line during TAKEOFF_DELAY. Spawn countdowns and resets remain DEBUG-only; Intercept Status retains its countdown.

### Immediate DEAD ACTIVE — 60 seconds

```text
SEAD: COMPLETE
Follow-on: DEAD ACTIVE
Remaining targets: 3
Wing: BLUE_HORNET_INCIRLIK_01
SEAD MISSION
MODE: TOO
THREAT AREA: LL DDM 034° 39.420'N   037° 57.180'E
TARGET TYPE: UNKNOWN
SEAD Primary result: DESTROYED
Emitter state: DESTROYED
Site state: SUPPRESSED
Site remaining vehicles: 3
Site disposition: IN USE
Follow-on DEAD available: NO
Hawk 1 [BLUE_HORNET_INCIRLIK_01-1]: DEAD_ACTIVE
DEAD objective: INCOMPLETE
Hawk 2 [BLUE_HORNET_INCIRLIK_01-2]: DEAD_ACTIVE
DEAD objective: INCOMPLETE
```

After Immediate DEAD completion the assignment remains SEAD and shows `SEAD: RTB_PENDING`, `DEAD objective: COMPLETE` and the original SEAD briefing.

### Follow-on DEAD ACTIVE — 60 seconds

```text
DEAD: ACTIVE
Area: Palmyra
Remaining targets: 3
DEAD MISSION
AREA: Palmyra
TARGET SITE: SA-6
STATUS: Primary radar destroyed
OBJECTIVE: Destroy all remaining SAM site vehicles.
SITE LOCATION:
LL DDM 034° 39.420'N   037° 57.180'E
Site state: SUPPRESSED
Site remaining vehicles: 3
Site disposition: IN USE
Follow-on DEAD available: NO
Hawk 1 [BLUE_HORNET_INCIRLIK_01-1]: ACTIVE
Hawk 2 [BLUE_HORNET_INCIRLIK_01-2]: ACTIVE
```

Other states appear literally, for example `DEAD: ARMED` and `DEAD: RTB PENDING`.
A pending spawn adds `Spawn in 12 seconds.`; an unknown site count displays `Site remaining vehicles: UNKNOWN`.
Status shows all matching assignments in one message. Any coordinate-bearing assignment selects the coordinate duration.

## Screen: CAP acceptance, patrol and completion

`Task: CAP` uses the existing group menu. Acceptance is shown for 10 seconds:

```text
CAP mission accepted.
```

The accepted area briefing is then shown once for `coordinateBriefingSeconds` (default 60 seconds):

```text
CAP AREA: LL DDM 035° 00.000'N   035° 30.000'E
Objective: patrol inside for 120 seconds AND destroy all hostiles.
Registered pilots: 2.
Reward per pilot: 150 points.
```

The following group messages last 10 seconds. Clock messages appear on transitions; each progress threshold appears once per assignment:

| Trigger | Message |
|---|---|
| First eligible entry | `CAP on station.` |
| All eligible pilots leave | `CAP patrol paused. Return to the assigned area.` |
| Reentry | `CAP patrol resumed.` |
| 24/48/72/96 seconds | `CAP patrol progress: 20%` / `40%` / `60%` / `80%` |
| 120 seconds, hostiles alive | `CAP patrol progress: 100%` followed by `Patrol time complete. Destroy all remaining hostiles.` |
| 120 seconds, hostiles gone | `CAP patrol progress: 100%` followed by `Patrol time complete.` |

Both objectives complete — 20 seconds:

```text
CAP PRIMARY OBJECTIVE COMPLETE
Patrol time complete and all hostile aircraft destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

`Mission Status` lasts 60 seconds for CAP and appends the accepted briefing, `Patrol: 40% (48/120 seconds)`, `Clock: RUNNING` / `WAITING / PAUSED` / `TIME COMPLETE`, and `Hostiles remaining: 2` / `0` / `NOT SPAWNED`. It does not redraw or reroll the area.
CAP settlement uses the existing `CAP RTB_SUCCESS` / `RTB_FAILURE` / `FAILED` / `ABORT` participant messages, points, totals and persistence status. Setup failure shows `ERROR: CAP setup failed. See DCS log; select 'Task: CAP' to retry.` for 20 seconds. A monitor/spawn failure settles each registered participant with `CAP setup/spawn failed. No reward.` for 20 seconds.
Acceptance selection and actual spawn details are DEBUG only: `CAP accepted; zone=<name> template=<name> enemy at on-station second <n>` and `CAP enemy spawned; template=<name> units=<n> altitude=<n> ft`. No separate hostile spawn message appears on screen. Normal CAP group messages are mirrored to the DCS MESSAGE log.
Idle Status and Abort Mission use the same Intercept / SEAD / DEAD / CAP list, including `CAP: Idle.`.

## Screen: Player Statistics — 25 seconds, requested manually

```text
PLAYER STATISTICS: Hawk 1 [BLUE_HORNET_INCIRLIK_01-1]
Total Score: 450
Career Points: 450
Settled Missions: 2
Primary Success: 2
RTB Success: 2
Recovery Failure: 0
Death Count: 0
Persistent scores saved.
```

An unverified participant instead shows:

```text
PLAYER STATISTICS: Hawk 1
UCID unavailable; unscored.
Session only; persistence hook not connected.
```

All current human pilots are included with player and aircraft names when UCID is verified. Persistence status is appended once after the statistics. Category scores (Intercept, CAP, SEAD, DEAD) are omitted from the screen and its MESSAGE log copy; category accounting, persistence, and restoration continue. This display change is implemented; in-DCS screen verification is pending.

## Screen: Initialization and persistence status

Startup — global, 10 seconds:

```text
Dynamic Training ready. Wing UCID scoring.
Persistence initialization pending.
```

Startup reports initialization pending while the asynchronous Hook is still connecting. It does not report a storage result. Settlement and Statistics use the current persistence status. A disabled configuration still shows the disabled line at startup.

Other persistence lines, used at settlement or statistics (disabled also at startup):

```text
Session only; persistence disabled.
Persistence unavailable; scores not confirmed saved.
Persistence pending; not yet saved.
Persistent scores saved.
```

These are alternative status lines, not one combined message. Hook attachment and acknowledgement do not send new screen messages by themselves.

## Screen: Rejection and error examples

Each table row is one actual message body. Different mission categories produce their own category name.

| Trigger | Actual output example | Seconds |
|---|---|---:|
| Duplicate script load, global | `Dynamic Training is already loaded.` | 10 |
| Missing MOOSE, global | `ERROR: Load MOOSE before DynamicTraining.` | 15 |
| Armed blocker | `Intercept mission is already armed. Wing assignment blocked.` | 10 |
| Active blocker | `SEAD mission is already active (including return to base). Wing assignment blocked.` | 10 |
| Missing group | `Player group unavailable.` | 10 |
| No human participant | `At least one human pilot is required.` | 10 |
| Missing pilot | `Human pilot unavailable.` | 10 |
| Wrong aircraft/coalition | `A BLUE F/A-18C player aircraft is required.` | 10 |
| Missing aircraft identity | `Player aircraft identity unavailable.` | 10 |
| Duplicate participant UCID | `The same UCID cannot occupy two participating aircraft.` | 10 |
| UCID API unavailable at acceptance | `Hawk 1: Server UCID API unavailable; this sortie is unscored.` | 15 |
| UCID verification failed at acceptance | `Hawk 1: UCID could not be verified; this sortie is unscored.` | 15 |
| SEAD planning cancelled | `SEAD selection cancelled. Player aircraft changed or unavailable.` | 10 |
| Pre-start aircraft/occupant changed | `Intercept reservation cancelled. Player aircraft changed or unavailable.` | 10 |
| Ground DEAD cancelled | `DEAD reservation cancelled. Player aircraft changed or unavailable.` | 10 |
| Intercept spawn failed | `ERROR: Intercept enemy spawn failed. Select 'Task: Intercept' to retry.` | 15 |
| Intercept enemy deletion pending at assignment close | `ERROR: Enemy cleanup. See DCS log.` | 15 |
| SEAD setup failed | `ERROR: SEAD setup failed. See DCS log; select 'Task: SEAD' to retry.` | 15 |
| SEAD spawn failed | `ERROR: SEAD spawn failed. Select 'Task: SEAD' to retry; see DCS log.` | 20 |
| DEAD preparation failed | `ERROR: DEAD setup failed. Site reservation rolled back; see DCS log.` | 20 |
| Stale Continue/Preserve | `Follow-on DEAD is no longer available for this SEAD mission.` | 10 |
| Stale/unauthorized site release | `This site reservation is no longer available to release.` | 10 |
| Closed personal sortie | `This sortie is already closed.` | 10 |
| Ambiguous old assignment | `Multiple earlier wing missions found. Use the named Abort Sortie command.` | 10 |
| Unauthorized abort | `Only registered mission participants may abort this mission.` | 10 |
| Other pilot's personal abort | `Only your own sortie may be aborted from another wing.` | 10 |
| Wing abort from another wing | `Use Abort Sortie for your own pilot; wing abort is available in the original wing.` | 10 |
| Protected monitor exception | `ERROR: Mission monitor. See DCS log.` | 15 |

Ground DEAD cancellation also sends each participant a FAILED settlement with `DEAD reservation cancelled. No reward.`.
Other protected exceptions use their operation name, such as `ERROR: Task: SEAD. See DCS log.`. Internal operations with no Group have no screen delivery.
An Intercept deletion retry adds no screen message. At assignment close the initial deletion failure displays the cleanup error once; when setup fails after spawning, the existing spawn-error notification is used. Pending/recovered deletion is logged separately, and retries continue every 5 mission seconds by default.

Placement failure — 25 seconds; this example assumes all 50 attempts failed the height-range check:

```text
ERROR: SEAD placement failed.
Area: Palmyra
No safe site in 50 attempts.
Uneven terrain (height range > 20 m): 50
Largest height range sampled before rejection: 24.3 m.
Select 'Task: SEAD' to retry.
```

Placement API exception — 25 seconds:

```text
ERROR: SEAD placement failed.
Site check error. See DCS log.
Select 'Task: SEAD' to retry.
```

## DCS log: normal message mirror

Example of the exact body recorded for a screen notification:

```text
[DynamicTraining] MESSAGE [BLUE_HORNET_INCIRLIK_01]
Intercept MISSION START
Range: 70 NM
Altitude: 20000 ft
Aspect: HOT
```

Global example:

```text
[DynamicTraining] MESSAGE [ALL]
Dynamic Training ready. Wing UCID scoring.
Persistence initialization pending.
```

DCS adds its own timestamp/severity outside these bodies. User-requested Status and Statistics are also mirrored. They may repeat when requested again.

## DCS log: debug-only notifications

### Countdown start — once per start, no screen message

Before Intercept scoring begins, the assignment number identifies the log:

```text
[DynamicTraining] [DEBUG] Intercept assignment 1
All registered pilots airborne. Hostiles will spawn in 20 seconds.
```

SEAD already has a mission ID:

```text
[DynamicTraining] [DEBUG] run7:SEAD:2
All registered pilots airborne. Hostiles will spawn in 20 seconds.
```

### Countdown reset — once per reset, no screen message

```text
[DynamicTraining] [DEBUG] Intercept assignment 1
Intercept countdown reset. Waiting for all registered pilots to take off.
```

```text
[DynamicTraining] [DEBUG] run7:SEAD:2
SEAD countdown reset. Waiting for all registered pilots to take off.
```

### Intercept start details — once per successful spawn, Hostiles and Pilots only in debug

```text
[DynamicTraining] [DEBUG] run7:Intercept:1
Intercept MISSION START
Hostiles: 2 x MiG-29A
Range: 70 NM
Altitude: 20000 ft
Aspect: HOT
Pilots: Hawk 1 (reward: 150), Hawk 2 (reward: 150)
```

Hostiles and Pilots are debug-only; Range, Altitude and Aspect also appear on screen.

### SEAD acceptance MODE — once at acceptance

```text
[DynamicTraining] [DEBUG] run7:SEAD:2
SEAD mission accepted.
MODE: TOO
Mission planning in progress.
```

### SEAD start Pilots — once at spawn

```text
[DynamicTraining] [DEBUG] run7:SEAD:2
SEAD TRAINING START
Objective: destroy primary emitter, or damage it and keep radar OFF for 60 seconds; then RTB.
Pilots: Hawk 1 (reward: 150), Hawk 2 (reward: 150)
```

### DEAD site reservation details — once at acceptance

```text
[DynamicTraining] [DEBUG] run7:DEAD:3
DEAD MISSION
AREA: Palmyra
TARGET SITE: SA-6
STATUS: Primary radar destroyed
OBJECTIVE: Destroy all remaining SAM site vehicles.
SITE LOCATION:
LL DDM 034° 39.420'N   037° 57.180'E
Reward per pilot: 150 points.
Registered pilots: 2.
Remaining targets: 3
Site reserved. Waiting for ALL registered pilots to take off.
```

The final waiting line is omitted when all participants are already airborne.

### DEAD activation details — once at activation, coordinates only in debug

```text
[DynamicTraining] [DEBUG] run7:DEAD:3
DEAD MISSION
AREA: Palmyra
TARGET SITE: SA-6
STATUS: Primary radar destroyed
OBJECTIVE: Destroy all remaining SAM site vehicles.
SITE LOCATION:
LL DDM 034° 39.420'N   037° 57.180'E
DEAD TRAINING START
Objective: destroy all remaining SAM site vehicles; then RTB.
Remaining targets: 3
```

### TOO plan and instructions — once per completed plan

This debug entry combines the normal plan briefing with its removed instruction paragraph. The ordinary briefing is separately mirrored as a MESSAGE entry.

```text
[DynamicTraining] [DEBUG] run7:SEAD:2
SEAD MISSION
MODE: TOO
THREAT AREA: LL DDM 034° 39.420'N   037° 57.180'E
TARGET TYPE: UNKNOWN
Reward per pilot: 150 points.
Registered pilots: 2.
Ground acceptance: SAM spawns 20 seconds after ALL registered pilots take off.
INSTRUCTIONS:
Search near the reported area and engage the hostile radar emitter using HARM TOO mode.
```

### PB plan and instructions — once per completed plan

```text
[DynamicTraining] [DEBUG] run7:SEAD:2
SEAD MISSION
MODE: PB
THREAT AREA: Palmyra
THREAT: SA-6
ESTIMATED LOCATION: LL DDM 034° 39.420'N   037° 57.180'E
HARM PB CODE: 108
Reward per pilot: 150 points.
Registered pilots: 2.
Ground acceptance: SAM spawns 20 seconds after ALL registered pilots take off.
INSTRUCTIONS:
Engage the emitter using HARM PB mode, then RTB.
```

## DCS log: lifecycle and diagnostics

Initialization adds `[DynamicTraining] Runtime initialized; version=training-4; MOOSE event subscriber retained.` once to the DCS log. It has no screen output and identifies the deployed version. Repeated bundle loading does not reinitialize or add a subscriber.

Each row is an example of a separate log entry. No screen duration applies.

| Timing | Actual output example | Frequency |
|---|---|---|
| Intercept starts | `[DynamicTraining] run7:Intercept:1 started; registered pilots=2 template=TPL_INT_MIG29A_2 formation=WEDGE/Open` | Once |
| Missing SEAD zone | `[DynamicTraining] SEAD zone missing; skipped SEAD_ZONE_PALMYRA` | Per missing candidate during setup |
| SEAD plan ready | `[DynamicTraining] SEAD planned TPL_SEAD_SA6 in SEAD_ZONE_PALMYRA after 3 attempts` | Once |
| SEAD starts | `[DynamicTraining] run7:SEAD:2 started; mode=TOO template=TPL_SEAD_SA6 zone=SEAD_ZONE_PALMYRA` | Once |
| Emitter transition | `[DynamicTraining] SEAD emitter ACTIVE -> SUPPRESSION_PENDING (DT_SEAD_2#001)` | On each state change |
| Emitter observation lost | `[DynamicTraining] SEAD emitter observation unavailable; suppression timer reset` | On transition into unknown |
| SEAD primary complete | `[DynamicTraining] run7:SEAD:2 primary objective complete (DESTROYED); awaiting individual RTB` | Once |
| Intercept primary complete | `[DynamicTraining] run7:Intercept:1 primary objective complete; awaiting individual RTB` | Once |
| Follow-on DEAD primary complete | `[DynamicTraining] run7:DEAD:3 primary objective complete; awaiting individual RTB` | Once |
| Continue selected | `[DynamicTraining] run7:SEAD:2 continued as DEAD using original site` | Once |
| Immediate DEAD complete | `[DynamicTraining] run7:SEAD:2 immediate DEAD complete; awaiting SEAD and DEAD recovery settlement` | Once |
| Follow-on DEAD starts | `[DynamicTraining] run7:DEAD:3 started using retained site run7:SEAD:2` | Once; public sites use the same wording |
| DEAD observation lost | `[DynamicTraining] DEAD target observation unavailable; site=run7:SEAD:2: DEAD target life observation unavailable.` | Per target on transition into unknown; Lua may prepend a source line |
| Site observation lost | `[DynamicTraining] SAM site observation unavailable: run7:SEAD:2: SAM site life observation unavailable.` | Per site on transition into unknown; Lua may prepend a source line |
| SEAD settlement | `[DynamicTraining] run7:SEAD:2 RTB_SUCCESS points=150 scored=true` | Per scored-ID participant, once |
| Immediate DEAD additional settlement | `[DynamicTraining] run7:DEAD:3 RTB_SUCCESS points=150 scored=true` | Additional entry per participant |
| Assignment closes | `[DynamicTraining] run7:SEAD:2 closed; wing assignment released` | Once |
| Private keeper disconnects | `[DynamicTraining] Preserved SAM site cleanup: keeper disconnected; site=run7:SEAD:2` | Once |
| Public site idle timeout | `[DynamicTraining] SAM site cleanup: unreserved timeout; site=run7:SEAD:2` | Once |
| Site destroyed by cleanup | `[DynamicTraining] SEAD site cleaned: run7:SEAD:2` | Once |
| Destroy returns false | `[DynamicTraining] SEAD site cleanup pending: run7:SEAD:2: false` | First failure only; retries continue |
| Intercept enemy deletion fails or cannot be confirmed | `[DynamicTraining] Intercept enemy cleanup pending: DT_INTERCEPT_1#001: Destroy returned false.` | First failure per group only; Lua may prepend a source line. Retry after `intercept.cleanupRetrySeconds` (default 5 mission seconds) |
| Pending Intercept deletion succeeds | `[DynamicTraining] Intercept enemy cleaned: DT_INTERCEPT_1#001` | Once after disappearance is confirmed; immediate successful deletion has no extra entry |
| Intercept spawn fails | `[DynamicTraining] Spawn: Intercept enemy spawn failed.` | Per failure |
| SEAD setup fails | `[DynamicTraining] SEAD setup: Invalid SEAD mode.` | Per failure; Lua may prepend a source line |
| SEAD spawn fails | `[DynamicTraining] SEAD spawn: SEAD SpawnFromVec2 returned nil.` | Per failure |
| DEAD setup fails | `[DynamicTraining] DEAD setup: Invalid DEAD full reward.` | Per failure; actual reason can include a Lua source line |
| Other protected exception | `[DynamicTraining] Task: SEAD: Invalid SEAD full reward.` | Per exception, no general deduplication; Lua may prepend a source line |

Matching placement failure diagnostic:

```text
[DynamicTraining] SEAD selection: No suitable position in SEAD_ZONE_PALMYRA after 50 attempts; last rejection=uneven terrain
Area: Palmyra
No safe site in 50 attempts.
Uneven terrain (height range > 20 m): 50
Largest height range sampled before rejection: 24.3 m.
```

Exception reason examples illustrate the variable error text. Lua source-line prefixes depend on the generated bundle version.

Persistence Hook entries use logger `DynamicTrainingPersistence`:

| Timing | Message body | Frequency |
|---|---|---|
| Hook attachment | `Connected via mission/a_do_script+scalar-sentinel; storage and acknowledgement confirmed.` | Once after the first successful storage/acknowledgement cycle |
| Run allocation saved | `BOOTSTRAP_COMMITTED: run=<number>; source=<new/primary/backup>` | Once after the bootstrap file is verified |
| Settlement snapshot saved | `SNAPSHOT_COMMITTED: run=<number>; revision=<number>` | Once per newly committed revision; acknowledgement is a separate step |
| Backup recovery | `Recovered score backup` | When bootstrapping from the backup |
| Missing bridge API | `DCS persistence bridge API unavailable` | On failure; prefixed with `phase=PROTOCOL` and a Lua source line |
| Invalid bridge reply | `DCS mission bridge rejected/invalid reply; replyType=<type>; replyBytes=<length>; status=<value>` | On failure; may append the fixed type-only `DTBRIDGE_INVALID:first=<type>;second=<type>` diagnostic, never payload content |
| Storage load failure | `Score storage unreadable; primary/backup preserved; primary=<state>; backup=<state>; primaryDetail=<detail>; backupDetail=<detail>` | On failure; I/O details identify numeric errno or directory inspection failure, never score contents |
| Native write failure | `Score write/flush/close failed; <operation return/error types>` | On failure; does not log snapshot contents |
| Acknowledgement rejected | `Persistence acknowledgement rejected` | On failure; Lua may prepend a source line |

Errors carry `phase=<PROTOCOL/DIRECTORY/LOAD/BOOTSTRAP/ATTACH/SNAPSHOT/VALIDATE/SAVE/ACK>`. The Hook polls approximately once per real-time second after Mission Load End, on the host. Repeated identical errors are suppressed until a different error or successful poll occurs. Idle polls and acknowledgements have no separate log entry. Stop performs a final attempt only for an attached host session and disables later polling.

Persistence connection diagnostics use the separate INFO logger `DynamicTrainingPersistenceDiagnostic`:

| Timing | Message body | Frequency |
|---|---|---|
| Callback registration | `HOOK_REGISTERED: control=<Sim/DCS>; net.dostring_in=<type>; transport=mission/a_do_script+scalar-sentinel` | Once when the Hook loads |
| Mission load begins | `MISSION_LOAD_BEGIN: Persistence connection state reset.` | Once per load callback |
| Mission load finishes | `MISSION_LOAD_END: Persistence polling enabled.` | Once per load-end callback |
| First simulation frame | `FIRST_SIMULATION_FRAME: Persistence callback received.` | Once per loaded mission |
| Non-host execution | `NOT_SERVER: Persistence only runs on the host.` | On state transition |
| Endpoint absent or incompatible | `WAITING_ENDPOINT: protocol=<value>; endpoint=<type>; trigger=<type>; timer=<type>; coalition=<type>; a_do_script=<type>` | On state transition; `type probe unavailable` if the optional probe fails |
| Endpoint attachment | `CONNECTED: Mission endpoint attached; storage and acknowledgement confirmed.` | On state transition after acknowledgement |
| Native I/O compatibility | `IO_COMPATIBILITY: writeReturn=<type>; writeError=<type>; flushReturn=<type>; flushError=<type>; closeReturn=<type>; closeError=<type>` | Once when successful calls omit returns; `flush=unavailable` replaces the flush fields if that method is absent. This is not a save acknowledgement |
| Stop without attachment | `STOPPED: No attached session to flush.` | Once per stop |
| Stop without host role | `STOPPED: Host unavailable; prior saves preserved.` | Once per stop |
| Confirmed final flush | `STOPPED: Final snapshot and acknowledgement confirmed.` | Once per stop |
| SSE unavailable during stop | `STOP_FLUSH_UNAVAILABLE: phase=<phase>; lastCommittedRevision=<number>` | Once per stop; previously committed saves remain valid |

Diagnostics inspect SSE types only, do not log account/score data, and do not create storage before attachment. Repeated waiting frames are silent. They add no screen messages and dispatch through the mission manager. A trailing scalar preserves the tagged reply when the native dispatcher shifts returns and drops the last value.

## Repetition and silent transitions

- SEAD and Follow-on DEAD automatically show coordinates once. Activation does not repeat them on screen.
- MP2 settlements display each pilot's result to the whole original Group.
- Manual Mission Status recalls the same briefing and is logged again.
- A valid stale Preserve callback may repeat the preservation message; the normal menu hides Preserve after selection.
- Countdown start/reset details now repeat only in debug logs when the countdown actually changes.
- Cleanup, recovery hold entry/reset, and intermediate kill counts have no automatic screen notification.
- DCS ground crew, ATC, radio responses and MOOSE framework trace output are outside this catalogue.

## Sources and verification

- [Main entry](../src/main.lua): acceptance, start, settlement, menu, monitoring. The bundle and embedded entry remain named DynamicTraining.lua.
- [SEAD](../src/sead.lua): visible briefing and debug instructions.
- [SEAD objective](../src/sead_objective.lua): emitter transitions.
- [DEAD](../src/dead.lua) and [Sites](../src/sead_sites.lua): targets, briefing, cleanup.
- [Persistence](../src/persistence.lua) and [Hook](../server/DynamicTrainingPersistenceHook.lua): persistence state and server logs.
- [Config](../src/config.lua): durations and timers.
- [Testing](TESTING.md): INT-16 and SEAD-62 verify visible/debug separation, repetition, coordinates and durations.

Implementation and mock tests are distinct from live DCS verification.
