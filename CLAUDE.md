# Working notes

Remotes (since 2026-10-23):

| remote | repo | role |
|---|---|---|
| `origin` | `monovolt/OnStepX_MiniPCB2_Teensy40` | this user's (Mono, GitHub `monovolt`) GitHub fork — push here |
| `hjoungjoo` | `hjoungjoo/OpenX_pio_E4` | 하정주's repo this was forked from — **never push** |
| `upstream` | `hjd1964/OnStepX` | OnStepX original — **never push** |

Work happens on branch `minipcb2-teensy40` (the fork's default branch). `main` mirrors
하정주's main. Until 2026-10-23 these changes lived only as uncommitted working-tree
modifications; this file explains what was changed and why.

## Quick reference: test script

`scripts/onstep.ps1` sends one LX200 command over serial and prints the reply/log.

```powershell
.\scripts\onstep.ps1 <command-without-colon-or-hash>   # e.g. .\scripts\onstep.ps1 Ms
.\scripts\onstep.ps1 "Sa+10*00"                         # quote it if it has spaces/special chars
.\scripts\onstep.ps1 Ms -Port COM5 -Baud 115200 -WaitSeconds 15 -IdleMs 700
```
Defaults: `COM5`, `115200` baud. It exits ~0.7s after the reply goes quiet (not a fixed
wait), with a 15s hard cap for catching a full post-reset boot log.

### Handy commands tried this session
- `Ms` / `Mn` / `Me` / `Mw` — guide-rate move S/N/E/W (axis2/axis2/axis1/axis1) until `Q`
  or the 5s `GUIDE_TIME_NO_LIMITS` cap (see below).
- `Q` — stop all.
- Site/time (needed before any `:MA#` Alt/Az goto or the equatorial conversion fails with
  "6=outside limits"): for Seoul, 2026-09-15 ~04:00 KST this was:
  ```
  .\scripts\onstep.ps1 "St+37*34"      # latitude
  .\scripts\onstep.ps1 "Sg-126*59"     # longitude (OnStep: east is negative)
  .\scripts\onstep.ps1 "SG-09"         # UTC offset (KST = UTC+9)
  .\scripts\onstep.ps1 "SC09/15/2026"  # local date
  .\scripts\onstep.ps1 "SL04:00:00"    # local time
  ```
  All should reply `1`. Re-set `SC`/`SL` (and re-check the others are still `1`) each
  session since date/time isn't tracked live — this was a one-time manual set, not backed
  by an RTC/GPS.
- Alt/Az goto test (no star alignment needed, bypasses the RA/Dec path):
  ```
  .\scripts\onstep.ps1 "Sa+10*00"   # target altitude, SIGN REQUIRED (+/-) or returns 0=fail
  .\scripts\onstep.ps1 "Sz030*00"   # target azimuth, no sign
  .\scripts\onstep.ps1 MA           # goto that Alt/Az; 0=started, 6=outside limits, etc.
  ```
- `Te` / `Td` — tracking on/off.
- Tracking auto-starts once, on the very first GOTO after boot (`Goto.cpp`'s `firstGoto`
  flag) — it is NOT re-triggered by every subsequent goto. If tracking is off and you goto
  again, it stays off.

## Policy: track origin, patch only what we need

Follow origin (hjoungjoo) and upstream as closely as possible and keep our own changes
minimal. When origin solves something we had worked around locally, switch to origin's fix.
Only hardware-specific settings (steps, microsteps, current, decay, baud, board env) stay ours.

## Branch: minipcb2-teensy40

Board: custom MiniPCB v2 (Teensy 4.0) + TMC5160T Pro V1.0 drivers, Dobsonian Alt-Az GOTO
mount. axis1 = azimuth (motor 17HS6401S, 60mm, 1.5Ω/phase), axis2 = altitude (motor
17HS8401S, 48mm, 1.8Ω/phase + 5.18:1 planetary gearbox).

### 1. Teensy4 SW-SPI timing bug (critical — motors would not move at all)

TMCStepper's software-SPI bit-bang (`lib/TMCStepper/src/source/TMC_platforms.h`, vendored
here instead of pulled via `lib_deps`) has no settling delay on the generic `digitalWrite`
fallback path used by Teensy 4.0 (600MHz). SCK edges toggled faster than the TMC5160 could
sample, so register writes (e.g. `CHOPCONF`/`TOFF`) silently corrupted — the chip would
still respond to SPI reads and looked configured, but the chopper output stage never
engaged, so connected motors never produced torque or current, with no fault reported.

Fix: added a 2µs settling delay before each SCK edge on `__IMXRT1062__`/`__IMXRT1052__`
(Teensy 4.x). Verified via direct `CHOPCONF` register readback that writes land correctly,
and confirmed both axes actually drive their motors. `platformio.ini`'s `lib_deps` no
longer lists `teemuatlut/TMCStepper` since the patched copy lives under `lib/TMCStepper`.

This is a bug in the third-party `TMCStepper` library itself (by teemuatlut), not in
OnStepX — relevant to any Teensy 4.x project using that library's software SPI.

### 2. Dobsonian mount tuning (`Config.h`, `Tmc5160.cpp`)

Current state as of last upload:

| Setting | axis1 (azimuth) | axis2 (altitude) |
|---|---|---|
| `STEPS_PER_DEGREE` | 16000 | 66304 |
| `DRIVER_MICROSTEPS` (tracking) | 128 | 128 |
| `DRIVER_MICROSTEPS_GOTO` (slew) | OFF (=128) | 32 |
| `DRIVER_IRUN`/`IGOTO` | 1500mA | 1500mA |
| `DRIVER_DECAY` (tracking) | OFF (StealthChop) | OFF (StealthChop) |
| `DRIVER_DECAY_GOTO` (slew/guide) | OFF (SpreadCycle) | OFF (SpreadCycle) |

- Gear ratios used for `STEPS_PER_DEGREE` (= 200 full-steps/rev * µsteps * ratio / 360):
  axis1 = 2.5:1 belt (16T:40T) * 90:1 worm = 225:1 (was wrongly 2:1/180:1 = 12800 until 2026-10-01, which made azimuth move only 80% of commanded); axis2 = 5.18:1 planetary * 2:1 belt (20T:40T) * 90:1 worm =
  932.4:1.
- Microsteps were pushed up from 16 -> 32 -> tried 64 (no further improvement) -> 128,
  specifically to quiet the very slow **sidereal tracking** rate (~15"/s, far slower than
  any guide-rate test), which is the hardest speed to keep quiet on any stepper. axis1 was
  briefly tried at 256/64(goto) since the whine seemed to come from that axis, but was
  backed off to 128 to test whether it reduces motor heat (128 halves the driver switching
  rate vs 256) — **result of that heat comparison not yet confirmed**, pick up here.
  axis2 stays split (128 track / 32 goto) because 128 at full GOTO slew speed would hit
  ~200kHz step rate; axis1 didn't need the split at 128 (~48kHz at GOTO speed is fine).
- Current: 1800 (rated) -> 1200 (quieter, dominant factor in resonance/whine, more so than
  microstepping or decay mode) -> **1500 (current value)**, raised again once OTA
  (optical tube assembly) was attached, since altitude axis carries significant weight.
  Torque under real OTA load was being tested when this was last updated — if 1500mA
  isn't enough, go up toward 1800mA (rated), or split IRUN per axis if only one needs more.
- `AXIS2_REVERSE`: OFF -> **ON** (2026-10-16, measured: commanding -5° altitude raised the
  tube +4.9°). origin also has `AXIS2_REVERSE ON`.
- `AXIS1_REVERSE`: ON -> **OFF** (2026-10-18). In the field the user found azimuth reversed and
  flipped it in the SWS web UI, which switched the device to NV axis settings (`:SXAC,0#`,
  `:GXA1,4#` = 0). Config.h was changed to match. **Gotcha:** while the device is in NV mode,
  Config.h axis values (steps, microsteps, current, reverse, decay) are ignored at boot.
  `:SXAC,1#` + reboot goes back to Config.h mode. As of 2026-10-18 every other NV axis value
  matched Config.h.
- Home altitude (2026-10-16): `AXIS2_HOME_DEFAULT` **84.9**, `LIMIT_OVERHEAD` **85** (same as
  origin). Briefly tried home 90 / overhead 90, reverted: Alt-Az near zenith needs a runaway
  azimuth rate, and the user's tube physically struggles above ~85. Home must stay *below*
  the overhead limit: home 85.0 as double (1.4835298641951802) > 85 as float
  (1.483529806137085), which sets `error.altitude.max`, and in ALTAZM `Limits::poll()` then
  calls `stopAxis2(GA_FORWARD)` -> `goTo.abort()` every 100ms, so every goto from home dies.
  Device NV set with `:So85#` (`:Go#` = 85); boot `:GA#` = `+84*53:55`. User sets the tube to
  ~85° before power-on.
- `AXIS2_LIMIT_MAX`: 85 -> 90 (true zenith, per the mount's actual mechanical range).
- `LIMIT_HORIZON -10.0F` / `LIMIT_OVERHEAD 85.0F` added (2026-10-03, only these two lines taken
  from origin commit ace58a0; its steps/microsteps/current/REVERSE/slew-rate changes are for
  하정주's hardware and were deliberately NOT taken). These are the sky-altitude (goto
  rejection + motion stop) limits, separate from the `AXIS2_LIMIT_*` shaft limits. They're
  stored in NV (`LIMIT_SETTINGS`, `getOrInit`), so on an already-booted board the Config.h
  value is ignored — send `:So85#` (and `:Sh-10#`) once, check with `:Go#`/`:Gh#`.
- TMC5160 `PWM_FREQ` raised (~11.7kHz -> ~23.4kHz, out of audible range for StealthChop)
  and SpreadCycle hysteresis tuned (`HSTRT=4`, `HEND=1`) — both in `Tmc5160.cpp`.
- **Important gotcha**: `AXIS_DRIVER_DECAY` (tracking) vs `AXIS_DRIVER_DECAY_GOTO`
  (slewing) are separate settings that are easy to confuse. Hand-controller/guide/GOTO
  moves all go through `modeDecaySlewing()` (`Axis::autoSlew()` -> `motor->setSlewing(true)`)
  i.e. `DECAY_GOTO` — NOT `DECAY`. Only continuous sidereal tracking uses `modeDecayTracking()`
  i.e. plain `DECAY`. Wasted a lot of round-trips on this earlier in the session by changing
  `DECAY` and testing via hand controller, which is entirely governed by `DECAY_GOTO`.
- Noise is speed-dependent regardless of decay mode: fast = whine, slow = grinding/stutter,
  very slow (near sidereal-tracking speed) = a "singing"/warbling tone. This looks like
  ordinary stepper mid-band resonance through the belt/worm/planetary drivetrain, not a
  bug — current and microstep count both help but may not fully eliminate it. Mechanical
  damping (coupler rubber, belt tension) is the other lever, outside firmware scope.
- `Rsense` is **not** actually mismatched — it defaults to the correct `0.075F` for
  TMC5160 and was never overridden in `Config.h`; the boot log's "Rsense=0.08Ohms" is just
  that value rounded to 2 decimals when printed, not a real discrepancy.
- Power supply: currently a USB-PD power bank at 20V (deliberately staying at 20V instead
  of 24V since PD banks that support 24V+ need PD3.1 EPR, which most don't). TMC5160 is
  current-mode so 20V vs 24V mainly affects high-speed GOTO torque headroom, not
  tracking/guide torque. If GOTO struggles at 20V, lowering `SLEW_RATE_BASE_DESIRED`
  (currently 3.0 deg/s) is the fix to try before considering a voltage bump.
- Slew rate is one deg/s for both axes (no per-axis setting). `SLEW_RATE_MEMORY ON` keeps the
  run-time preset in NV: 2026-10-18 the device was found at the 50% preset (`:GX92#` 41.667us,
  `:GX97#` 1.5 deg/s), which made azimuth gotos feel sluggish; reset to 100% with `:SX93,3#`
  (3.0 deg/s), then the user asked for 150% (`:SX93,2#`, `:GX97#` = 4.5 deg/s). Presets: `:SX93,n#` 1=200% 2=150% 3=100% 4=66% 5=50%. Faster than 100% is
  limited by axis2 (932:1 -> ~930 rpm motor at 6 deg/s), not axis1 (~225 rpm).
- 2026-10-18 (uploaded, build `Oct 18 2026 23:10:00`): `AXIS2_SLEW_RATE_PERCENT 66.7` (upstream option,
  axis2 goto/max-guide rate relative to axis1 -> 4.5 / 3.0 deg/s at the 150% preset) and
  `SLEW_ACCELERATION_DIST` 1.0 -> 0.5 (user wanted button-release coast shorter; same value
  sets goto accel/decel, compile-time only). A `:R9#`+`:Me#` test logged ~22.5 deg in ~5 s
  (firmware rate is right), yet the user saw azimuth "barely moving" in the field —
  unresolved: low SHC rate selection, or motor/belt/pulley slip.

### 3. Wemos D1 Mini (WiFi) — deliberately not set up

**Update 2026-10-15:** the Wemos turned out to be already flashed with SmartWebServer (not by
us — presumably pre-flashed by 하정주/vendor). With the board powered it broadcasts the
`OnStep-SWS` AP and its web UI (192.168.0.1) loads, so it is live and talking to the Teensy
over `SERIAL_B`. Default AP password is likely still `password` — change it or disable AP
if it isn't going to be used. The original decision below is about not *configuring* it.
First connect showed "Serial Interface to OnStep is Down!" with nothing clickable; resetting
only the Wemos (Teensy left running) fixed it. Wemos runs SWS **2.10h** (= latest on
hjd1964/SmartWebServer as of 2026-10-15), shows OnStep 10.28x — no reflash needed. Suspected cause: the Teensy was rebooted
(firmware upload) after SWS had already started, and/or on MiniPCB2 the ESP RST/GPIO0 lines
share pins with the TMC SPI MISO lines (AUX2/AUX1), so Teensy boot-time SPI traffic can leave
the ESP in a bad state. If it recurs after a cold power-on, look into the shared-pin issue.

Decided against flashing/configuring the Wemos WiFi bridge (`SERIAL_B`, `:ESPFLASH#`).
Primary mount control will be a PiFinder (`D:\workspace\MF_PiFinderRPi5`, also 하정주's
project) connected via USB to the Teensy's native port, running an INDI server + a
PiFinder-specific "LX200 OnStepX" driver that speaks plain LX200 serial (same commands as
`onstep.ps1`) — INDI itself is a Pi-side-only abstraction, nothing INDI-specific crosses
the wire to the Teensy. See
`D:\workspace\MF_PiFinderRPi5\docs\mf_dev\mf_indi_mount_install_ko.md`. Default
`onstep_serial_baud` there is 9600 but our `SERIAL_A_BAUD_DEFAULT` is 115200 — use the
driver's "Auto (Find connected OnStep)" port setting on first connect.
ST4 hand controller (SHC, Teleran Industries) is the manual/emergency-fallback control
method instead of WiFi — zero setup, works instantly, and 하정주 noted PiFinder-OnStep
wireless was too interference-prone to rely on anyway.

### 4. Manually-applied upstream fixes (synced to hjd1964/OnStepX main @ 10.28x)

Branch diverged from upstream around `10.28v` (commit matching upstream's "Improved bissc
absolute encoder single turn behavior"). A general `upstream` remote
(`https://github.com/hjd1964/OnStepX.git`) was added to this repo for future diffing —
check with `git fetch upstream && git log upstream/main --oneline` and pull in fixes
manually (local changes here are too divergent for a straight merge).

Fixes pulled in so far:
- `Mount.cpp`: keep tracking-rate central difference in `double` instead of downcasting to
  `float` (upstream PR #126).
- `Home.cpp` / `Macros.h`: `degToArcsecF` divided by 3600 instead of multiplying, so the
  home sense-offset range `constrain()` collapsed to ~±0.05 arcsec instead of ±180°;
  replaced with the correct `degToArcsecL`. (A related `||`-should-be-`&&` bug in
  `Home.command.cpp`, fixed upstream and credited to this user's GitHub handle
  `hjoungjoo`, was already correct in this codebase — nothing to change there.)
- `Sound.h` / `Status.cpp` / `Status.h`: sound-enabled default-state fix so it's set
  correctly regardless of `STATUS_BUZZER_MEMORY`.
- `OnStepX.ino`: `FirmwareVersionPatch` bumped `"v"` -> `"x"` to match upstream.

### 5. Fixes taken from origin (hjoungjoo) main, 2026-10-14

- From `189dea5` (= upstream `ea3818c3`): `TmcStepDirDriver::init()` now sets
  `intpol.value = intpol.valueDefault` when NAN. `intpol` isn't a runtime axis parameter,
  so it stayed NAN and `Tmc5160.cpp`'s `driver->intpol(intpol.value == ON)` was false —
  i.e. TMC5160 MicroPlyer 256x interpolation was **disabled** on both axes until this fix.
  Possibly a big factor in the low-speed tracking noise; re-evaluate noise after this.
- From `2ee139b`: `StepDirMotor::setFrequencySteps()` compares against `lastFrequency`
  instead of `currentFrequency` (which is divided by the goto step size), so axis2
  (128 track / 32 goto) can't get stuck in the goto microstep mode after a slew.
- Their decay flip-flop (`f47392e`/`0643b94`, ending at SpreadCycle tracking on TMC2209)
  was NOT taken.
- Also applied (as patches, same day): `6072034` (command parameter validation,
  `CommandValidation.h`, invalid NV goto-rate recovery), `158920f` (Alt/Az pulse guide
  recomputes tracking rate immediately at pulse start/end), `d913c80` (ODrive code only),
  `9492862` (upstream 10.29c fixes, StartupAuthority diagnostics, `STRICT_LX200_DATE` in
  `Extended.config.h` — `:SC` now replies `1Updating planetary data#<32 spaces>#`),
  `af779dd` + all of origin's `docs/` (checked out from origin/main).
  Deliberately excluded from those commits: `SERIAL_A_BAUD_DEFAULT` 230400 (kept 115200),
  `platformio.ini` ESP32 upload/monitor speeds, and `FirmwareVersionPatch` bumps.
  The `NV.h`->`Nv.h` / `TLS.h`->`Tls.h` renames from `6072034` were then also taken (staged
  `git mv`) and our old untracked case symlinks (`Nv.h`, `Tls.h`, `src/lib/CanPlus`) deleted
  — origin's fix builds cleanly on Linux without them. `tests/host` + `tools/test_commands.sh`
  were added but not run (no g++ in WSL yet).

## Pending / not yet done

- **axis1 microstep/heat comparison in progress**: just dropped axis1 from 256 back to 128
  microsteps to see if it runs cooler (axis2, staying at 128 the whole time, runs
  noticeably cooler than axis1 did at 256 — motor model resistance doesn't explain it,
  since 8401S/axis2 is actually the *higher*-resistance motor at 1.8Ω vs 6401S/axis1's
  1.5Ω, so higher R isn't why axis2 runs cooler). Leading theories: axis2's metal planetary
  gearbox acts as a heatsink, and/or axis1's higher microstep count roughly doubles driver
  switching rate/losses. Next: reset, run tracking again, compare axis1 warmth and
  singing-noise level at 128 vs the earlier 256 test.
- Torque under real OTA load: was being tested (current raised 1200 -> 1500mA for this)
  when the session paused for the night. Resume by re-running tracking/GOTO with the OTA
  attached and checking for stall/insufficient-torque symptoms.
- axis1 intermittently showed `SPI test_connection` failures during early bring-up that
  axis2 didn't — never root-caused (axis2 was the debugging focus at the time, and the
  Teensy4 SPI timing fix above may have already resolved it as a side effect). Worth a
  fresh look if axis1 acts up again.
- Diagonal ST4 button behavior, PiFinder INDI integration, and Wemos (if ever reconsidered)
  are all untested from the OnStep side so far.
