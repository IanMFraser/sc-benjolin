# Benjolin SuperCollider Patch — Changelog

---

## [7] 2026-04-13 — Spatial Panning

**File:** `benjolin_gui.scd`

### Added
- **Spatial section** — `Pan2`-based stereo positioning with modulation routing
  - `pan` knob — base position in stereo field (-1 hard left, 0 centre, +1 hard right)
  - `panMod` knob — scales how far the mod source moves the pan position (0 = no modulation effect, 1 = full swing)
  - **PAN MOD SOURCE** PopUpMenu — same 8 internal signals as existing routing matrix, plus **CHAOS** as index 8; added to `routes` Event so it is captured and recalled by the preset system automatically

### Notes
- Width control was explored and removed — genuinely useful stereo width from a mono source requires two distinct signals; the Benjolin's two oscillators (triA/triB) are a natural candidate if true stereo is wanted later
- `panDepth` renamed to `panMod` for clarity: the knob scales modulation only, not the manual pan position

---

## [6] 2026-04-06 — Preset Matrix: Active Slot Highlight + Clear All

**File:** `benjolin_gui.scd`

### Added
- **Active slot highlight** — clicking any preset slot selects it exclusively; active slot displays in cyan, all others revert to their filled/empty state. Makes it immediately clear which preset is loaded
- **CLEAR ALL button** — two-click confirm pattern: first click arms the button (turns red, label changes to CONFIRM CLEAR), second click wipes all 16 presets and resets the grid; auto-disarms after 3 seconds if not confirmed

### Changed
- Slot buttons now have three visual states: empty (dim grey `·`), filled (amber `●`), active (cyan, either filled or empty)
- `refreshAll` helper added to redraw all 16 slots at once (used on slot selection and after clear)
- Save and recall both set `activeSlot` and call `refreshAll` so selection tracks automatically

---

## [5] 2026-04-06 — Preset Matrix

**File:** `benjolin_gui.scd`

### Added
- **Preset Matrix** — separate window with a 4×4 grid of 16 slots
- **SAVE: ARMED toggle** — arms save mode (red); clicking a slot while armed captures all knob values, route selections, filter mode, loop switch, and chaos source, then writes to disk
- **Recall** — clicking any filled slot (amber `●`) with save disarmed instantly restores all GUI controls and updates the live synth
- Presets persist across sessions via `Object.writeArchive` / `Object.readArchive` stored in `Platform.userAppSupportDir/benjolin_presets.archive`
- Slot buttons show filled (`●`) vs empty (`·`) state; existing presets restored on re-evaluate

---

## [4] 2026-04-06 — Chaos Automaton

**File:** `benjolin_gui.scd`

### Added
- **Chaos Automaton section** in the SynthDef and GUI
  - Three attractor sources selectable via radio buttons: **Hénon** (`HenonC`), **Gingerbread Man** (`GbmanN`), **Standard Map** (`StandardN`), plus **OFF**
  - `chaosRate` knob (0.1–200 Hz) controls attractor iteration speed
  - `chaosOscA` / `chaosOscB` knobs: direct exponential FM on each oscillator from the chaos signal (0–3 octave range)
  - `chaosRunA` / `chaosRunB` / `chaosRunF` knobs: chaos offsets Rungler depth in real time, modulating how strongly the Rungler affects oscillators and filter
- GUI window expanded to accommodate new chaos row (winH 470 → 615)
- Reset button now also resets chaos source to OFF

### Fixed
- `~benjoBus` setup was accidentally commented out — uncommented
- `StandardMapN` → correct class name `StandardN`
- Chaos UGens are audio-rate only — changed `Select.kr` / `.kr` calls to `.ar` throughout

---

## [3] 2026-04-05 — Waveset Processor (WavesetsEvent)

**File:** `benjolin_waveset.scd` (full rewrite)

### Changed
- Replaced manual zero-crossing + `PlayBuf` pipeline with `WavesetsEvent` (Wslib quark)
- Sliders now update global variables (`~wsRepeats`, `~wsRate`, `~wsLegato`, `~wsProb`) polled live by a `Tdef` — changes take effect on the next waveset event without re-recording
- **LOOP** button now simply starts/stops `Tdef(\wsPlay)` — no longer triggers re-recording
- **RECORD** captures a fresh chunk and hot-swaps `~wavesets`; the running Tdef picks it up seamlessly

### Added
- **Repeats** slider — each waveset played N times (integer time-stretch)
- **Rate** slider — playback speed (0.25–4×)
- **Legato** slider — overlap / gap between wavesets
- **Omission** slider — probabilistic waveset dropping (0 = silent, 1 = play all)
- `minLength: 8` passed to `WavesetsEvent.read` to discard zero-length wavesets
- Nil guard on `event[\dur]` to prevent `nil.wait` crash from degenerate rest events

---

## [2] 2026-04-05 — Waveset Processor (initial, manual pipeline)

**File:** `benjolin_waveset.scd` (new file)

### Added
- `SynthDef(\wsRecorder)` — records one channel from `~benjoBus` into a buffer via `RecordBuf`
- `SynthDef(\wsPlayer)` — plays back processed buffer via `PlayBuf`
- Language-side waveset algorithms operating on `FloatArray`:
  - `~wsFind` — upward zero-crossing detector
  - `~wsRepeat` — time-stretch by repeating each waveset N times (probabilistic fractional factors)
  - `~wsDistort` — per-waveset normalise + `tanh` saturation (Wishart-style waveset distortion)
- `~wsRun` pipeline using `Routine` + disk I/O (`Buffer.write` → `s.sync` → `SoundFile.openRead`) to avoid OSC buffer transfer hangs
- Silent recording detector (peak < 0.001) with diagnostic status message
- GUI: chunk duration, transform selector (REPEAT / DISTORT), amount slider, RECORD / PLAY / LOOP buttons, status line

### Fixed (during development)
- `Buffer.alloc` completion function called synchronously — caused `nil.bufnum` error; removed completion function, used `s.sync` in Routine instead
- `loadToFloatArray` hangs on large buffers — replaced with `Buffer.write` + `SoundFile.openRead` (synchronous file I/O)
- `Condition` reuse after `unhang` — `test` stays true, second `hang` doesn't block; eliminated all `Condition` usage
- Node ordering: `wsRecorder` added with `\addToHead` ran before Benjolin wrote to `~benjoBus`, reading a silent bus — fixed with `\addToTail`
- Inline `var peak` declaration after executable statements — moved to top of Routine var block

---

## [1] 2026-04-05 — Epoch Modular Benjolin GUI

**File:** `benjolin_gui.scd` (new file, evolved from `benjolin_rungler.scd`)

### Added
- Full **Epoch Modular Benjolin** SynthDef (`\benjolin`) with panel-accurate parameter set:
  - `oscA`, `oscB` — oscillator base frequencies
  - `runA`, `runB`, `runF` — Rungler modulation depth per destination
  - `modA`, `modB`, `modF` — external modulation depth per destination
  - `modARoute`, `modBRoute`, `modFRoute` — routing matrix (PopUpMenu per MOD input)
  - `freq`, `res` — filter cutoff and resonance
  - `loop`, `loopSwitch` — loop circuit depth and enable
  - `filterMode` — LP / BP / HP selection
  - `amp` — output level
- **8-channel LocalIn/LocalOut feedback bus**: `[runglerCV, loopBit, triA, triB, pulseA, pulseB, xorOut, pwm]`
- **Modulation routing matrix**: any of 8 sources (NONE, TRI A, TRI B, PULSE A, PULSE B, XOR, RUNGLER, PWM) routable to any MOD input via `Select.ar`
- Clock source corrected to **OSC B rising edges** (`HPZ1.ar(pulseB) > 0`) per Epoch manual
- **PWM** output: `(triA > triB) * 2 - 1` (beat-frequency pulse width)
- **Loop circuit**: recirculates shift register MSB back to data input when `loopSwitch` on and `loop > 0`
- **Anti-logarithmic resonance curve**: `rq = (0.01 ** res).clip(0.005, 1.0)` per manual
- Filter input: PWM + Rungler mix into `tanh`
- `~benjoBus` private stereo bus + `~benjoMonitor` pass-through synth for signal tapping
- **GUI**: dark theme, panel-style EZKnob layout, PopUpMenu route selectors, filter mode buttons, loop switch, Randomize / Reset buttons
- **Randomize** button maps random values through each knob's ControlSpec
- **Reset** button restores all knobs and routes to defaults

### Fixed (during development)
- SC var-after-expression syntax errors — all `var` declarations moved to top of enclosing scope
- `EZSlider` in `VLayout` — requires `.view`; switched to explicit `Rect` positioning
- Keyword syntax `\chaos: 0.5` in `.set` calls — changed to `\chaos, 0.5`

---

## [0] 2026-04-05 — Initial Rungler Exploration

**File:** `benjolin_rungler.scd` (kept for reference)

### Added
- Basic Benjolin / Rungler SynthDef with:
  - Two `LFTri` oscillators with asymmetric Rungler FM
  - XOR clock (later corrected to OSC B clock in v1)
  - 8-stage shift register with `Latch` + `Delay1`
  - R-2R DAC weighted sum → Rungler CV
  - `RLPF` with exponential cutoff modulation
- Usage examples: frequency ratio exploration, chaos depth, filter tuning, golden-ratio sweet spot
- `Tdef(\drift)` — slow oscillator ratio drift pattern
- Dual Benjolin example — two instances panned L/R
