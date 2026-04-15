# Benjolin — SuperCollider Implementation

### User Manual

---

## Background

### Rob Hordijk and the Rungler

The Benjolin was designed by Dutch synthesizer builder **Rob Hordijk** (1952–2022), one of the most original and underappreciated voices in electronic instrument design. Hordijk's instruments — including the Blippo Box, Benjolin, and various Eurorack modules — were built around a core circuit he called the **Rungler**: a shift register whose output is fed back into the oscillators that drive it, creating a closed loop of self-modifying behaviour.

The Rungler is not a random noise source. It is a **deterministic chaotic circuit**: given the same initial conditions it will always produce the same output, but in practice small variations in tuning make the pattern feel alive, unpredictable, and organic. Hordijk described the Rungler as a way of "teaching the oscillators to talk to each other" — the two oscillators clock and feed data into a shared shift register, and the register's output controls the oscillators' pitch in return. The result is a tangled feedback system that resists easy description but rewards exploration.

The hardware Benjolin is a standalone instrument, typically built into a wooden box with two oscillators, a filter, and a set of patch points. The **Epoch Modular Benjolin** is a Eurorack adaptation with a front-panel layout that exposes the core controls while adding CV inputs and a richer modulation structure.

This SuperCollider implementation follows the Epoch Modular design closely, then extends it with a Chaos Automaton, a spatial panning section, a preset matrix, and effects.

---

## Getting Started

**Requirements:**

- SuperCollider 3.12 or later
- No additional plugins required

### File Structure

The implementation is split across three files that must be kept in the same folder:

| File                     | Purpose                                                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `benjolin_gui.scd`       | **Entry point.** Open and evaluate this file. Loads the other two automatically.                             |
| `benjolin_synthdefs.scd` | SynthDef definitions (`\benjolin` and all FX SynthDefs). Loaded by the main file — do not evaluate directly. |
| `benjolin_fx_gui.scd`    | FX window code. Loaded by the main file — do not evaluate directly.                                          |

Only `benjolin_gui.scd` needs to be opened. It locates the other files relative to its own path and loads them automatically at startup.

**To launch:**

1. Open `benjolin_gui.scd` in SuperCollider
2. Press `Cmd+Shift+Return` (macOS) to evaluate the entire file
3. The main Benjolin panel and the Preset Matrix window will open
4. Press **▶ START** to begin audio

Press **■ STOP** to silence the synth without closing the window. All knob positions are preserved.

---

## Signal Flow Overview

```
OSC A ──→ Triangle A ──→ Pulse A ──→ [Shift Register data input]
              ↓                              ↓
OSC B ──→ Triangle B ──→ Pulse B ──→ [Shift Register clock]
              ↓
         [XOR of Pulse A & B]
              ↓
         [8-stage Shift Register]
              ↓
         [R-2R DAC] ──→ Rungler CV (−1 to +1)
              ↓                    ↓
         FM → OSC A          FM → OSC B (inverted)
              ↓                    ↓
         [Filter: LP/BP/HP] ←── PWM signal + Rungler CV
              ↓
         [Pan2] ──→ Stereo Output
```

The loop is the key: the Rungler CV modulates the very oscillators that generate the clock and data feeding the Rungler. This is not traditional LFO-based modulation — the circuit modulates itself.

---

## Controls

### OSCILLATORS

| Control  | Range           | Description                                                                                                                                                                          |
| -------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **oscA** | 0.1 – 10,000 Hz | Base frequency of Oscillator A. OSC A provides the **data** bit to the shift register (its pulse output) and is the primary pitch voice.                                             |
| **oscB** | 0.1 – 10,000 Hz | Base frequency of Oscillator B. OSC B provides the **clock** signal that steps the shift register. The relationship between oscA and oscB determines how the Rungler pattern cycles. |

**Tip:** The ratio between oscA and oscB is more important than their absolute values. Integer ratios (1:2, 2:3, 3:5) produce repeating patterns; irrational ratios produce longer, more complex cycles. Try tuning them close together for slow Rungler drift, or far apart for rapid stepping.

---

### FILTER

| Control         | Range          | Description                                                                                                                                                                                                                                                   |
| --------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **freq**        | 20 – 18,000 Hz | Base filter cutoff frequency. The Rungler CV and MOD F signal modulate this exponentially — small changes in RUN F have large timbral effects.                                                                                                                |
| **res**         | 0 – 1          | Filter resonance using an **anti-logarithmic curve** (matching the Epoch hardware). At low values resonance is subtle; above 0.7 it becomes prominent; approaching 1.0 the filter self-oscillates.                                                            |
| **FILTER MODE** | LP / BP / HP   | Selects the filter topology. **LP** (low-pass) is the warmest and most common starting point. **BP** (band-pass) emphasises a narrow frequency range — useful for nasal, vocal-like timbres. **HP** (high-pass) removes the body and exposes upper harmonics. |

The filter input is a mix of the **PWM signal** (60%) and the **Rungler CV** (40%), passed through a tanh softclipper. This means the filter is always processing a Rungler-influenced signal, even before any modulation routing is applied.

---

### RUNGLER MOD

These three knobs control how strongly the Rungler CV feeds back into each destination. This is the heart of the Benjolin's self-modifying character.

| Control  | Range | Description                                                                                                                                                                                    |
| -------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **runA** | 0 – 1 | Depth of Rungler FM on **Oscillator A**. The Rungler CV modulates oscA exponentially (up to ±3 octaves at full depth).                                                                         |
| **runB** | 0 – 1 | Depth of Rungler FM on **Oscillator B** — with **inverted** polarity. When runA pushes oscA up, runB pushes oscB down, creating a counter-movement that feeds back into a new Rungler pattern. |
| **runF** | 0 – 1 | Depth of Rungler FM on the **filter cutoff**. Rhythmically locked to the Rungler pattern — the same CV sequence that drives pitch also sweeps the filter.                                      |

---

### EXTERNAL MOD

Three additional modulation inputs, each with a depth knob and a source selector.

| Control  | Range | Description                                      |
| -------- | ----- | ------------------------------------------------ |
| **modA** | 0 – 1 | Depth of the routed signal on Oscillator A.      |
| **modB** | 0 – 1 | Depth of the routed signal on Oscillator B.      |
| **modF** | 0 – 1 | Depth of the routed signal on the filter cutoff. |

**Route selectors** (PopUpMenu below each depth knob):

| Index   | Source                              | Character                                                          |
| ------- | ----------------------------------- | ------------------------------------------------------------------ |
| NONE    | Silent                              | No modulation                                                      |
| TRI A   | Triangle wave from OSC A            | Smooth, continuous FM                                              |
| TRI B   | Triangle wave from OSC B            | Smooth, continuous FM at OSC B rate                                |
| PULSE A | Square wave from OSC A              | Hard, rhythmic FM — jumps between two frequencies                  |
| PULSE B | Square wave from OSC B              | Hard, rhythmic FM at OSC B rate                                    |
| XOR     | Exclusive OR of Pulse A and Pulse B | Complex rhythmic pattern; fires at the sum and difference rates    |
| RUNGLER | Rungler CV directly                 | The staircase output of the R-2R DAC — stepwise modulation         |
| PWM     | Pulse Width Modulation signal       | Comparison of TRI A and TRI B — width varies at the beat frequency |

**Default normalised connections** (matching the Epoch Modular hardware):

- MOD A ← TRI B
- MOD B ← TRI A
- MOD F ← TRI B

These defaults replicate the hardware's internal wiring and are a good starting point.

---

### LOOP

The loop circuit recirculates the most significant bit (MSB) of the shift register back to the data input, creating a self-sustaining pattern that no longer depends on OSC A for new data.

| Control     | Description                                                                                                                                                                          |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **loop**    | Sets the threshold above which the loop is active. Positive values activate the loop when the Rungler CV exceeds the threshold. Negative values activate it when the CV falls below. |
| **LOOP SW** | Master on/off for the loop circuit. When OFF, loop has no effect regardless of the knob position.                                                                                    |

**With loop active:** the shift register begins repeating a pattern determined by its current state. Adjusting oscB (the clock) while looping changes the speed of the pattern without changing its content. Switching loop off and on captures a new pattern.

---

### OUTPUT

| Control | Range | Description              |
| ------- | ----- | ------------------------ |
| **amp** | 0 – 1 | Master output amplitude. |

---

### CHAOS AUTOMATON

A software-only extension that drives Benjolin parameters from mathematical strange attractors — deterministic systems that produce behaviour which appears random but never repeats. Three attractors are available, each with a distinct character.

#### Source Selection

| Button     | Attractor                  | Character                                                                                                                                                                                                     |
| ---------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **OFF**    | None                       | Chaos system disabled; no CPU overhead.                                                                                                                                                                       |
| **HÉNON**  | Hénon map                  | Bounded, relatively tame. Oscillates within a constrained range — good for subtle, organic variation. The classic "strange attractor" shape.                                                                  |
| **GBMAN**  | Gingerbread Man map        | More angular and discontinuous. Tends to jump between regions — good for rhythmic, stuttering modulation.                                                                                                     |
| **STDMAP** | Standard map (Chirikov)    | Most variable. Can switch between quasi-periodic and fully chaotic regimes depending on the `chaosRate` value.                                                                                                |
| **GENDY**  | Gendy stochastic synthesis | Generates chaos through randomised breakpoint waveforms. Softer and more tonal than the map-based attractors; evolves gradually rather than jumping. `chaosRate` scales the frequency range of the generator. |

#### Chaos Rate

**chaosRate** (0.1 – 200 Hz) — How fast the attractor iterates.

- **< 1 Hz** — Slow drift; parameters wander gradually over many seconds
- **1–20 Hz** — Rhythmic territory; chaos has a perceivable pulse
- **20–100 Hz** — Fast modulation; begins to colour the timbre directly
- **> 100 Hz** — Pseudo audio-rate FM

#### Chaos Depth Controls

Two types of targets, with distinct musical effects:

**Direct oscillator FM** — Chaos signal added as exponential FM independent of the Rungler:

| Knob          | Range | Effect                                                                                                                                                     |
| ------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **chaosOscA** | 0 – 3 | Chaos FM depth on OSC A (in octaves). At 1.0, the attractor can swing oscA by ±1 octave from its base frequency.                                           |
| **chaosOscB** | 0 – 3 | Chaos FM depth on OSC B. Because OSC B is the Rungler clock, modulating it also changes how fast the Rungler pattern steps — indirect chaos on everything. |

**Rungler depth modulation** — Chaos offsets the RUN knob values in real time, changing how strongly the Rungler feeds back into each destination:

| Knob          | Range | Effect                                                                                       |
| ------------- | ----- | -------------------------------------------------------------------------------------------- |
| **chaosRunA** | 0 – 1 | Chaos modulates the effective runA amount. The Rungler's influence on OSC A waxes and wanes. |
| **chaosRunB** | 0 – 1 | Chaos modulates the effective runB amount.                                                   |
| **chaosRunF** | 0 – 1 | Chaos modulates the effective runF amount — the filter cutoff breathes with the attractor.   |

---

### SPATIAL

Controls the position of the output in the stereo field, with optional modulation from any internal signal or the chaos attractor.

| Control            | Range   | Description                                                                                                                                                            |
| ------------------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **pan**            | −1 – +1 | Base stereo position. −1 = hard left, 0 = centre, +1 = hard right.                                                                                                     |
| **panMod**         | 0 – 1   | How far the selected source can push the pan position away from the base. At 0, the source has no effect. At 1, the source has full range (up to ±1 from the base).    |
| **PAN MOD SOURCE** | 0 – 8   | The signal driving pan modulation. Same 8 internal sources as the MOD routing matrix, plus **CHAOS** (index 8) which uses the currently active chaos attractor output. |

---

## Effects

A separate effects window is opened by clicking the **⚙ FX** button in the bottom-left of the main panel. The effects run as four separate synths that sit after the Benjolin in the signal chain, reading from and writing back to the internal audio bus before the final output stage. All four effects are always present in the signal graph — each is bypassed by leaving its **ON** toggle off, which costs negligible CPU.

The default processing order is: **Resonator → Delay → Reverb → EQ**.

#### Reordering the Chain

The **CHAIN** strip at the top of the FX window shows the current processing order as four labelled buttons. To swap two effects:

1. Click the first button — it turns green (armed)
2. Click a second button — the two effects are swapped immediately in the server node graph
3. Click an armed button a second time to disarm without swapping

The chain order resets to default when the FX window is closed. It is not saved in presets.

---

### Resonator

A four-band resonant filter bank inspired by the **Xaoc Oradea** quadruple voltage-controlled resonator. Each band is a `Ringz` filter — a resonant bandpass with built-in gain compensation, meaning peak level stays constant as decay time increases, preventing blowout at high resonance settings.

Unlike the other effects which replace the dry signal with a processed version, the resonator bands are **additive**: each band's output is summed on top of the dry signal, emphasising resonant peaks rather than filtering through them. A tanh soft-saturation stage on the combined bands prevents distortion when multiple bands overlap.

Because the Benjolin's rungler transients and pulse edges are already in the signal, the resonators are **self-excited** — sharp transients naturally ping the Ringz filters without a dedicated trigger input.

| Control | Range  | Description                                                                                                                             |
| ------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| **ON**  | toggle | Enables the resonator. When disabled, a 2-second slow fade-out lets any ringing tails decay naturally rather than cutting off abruptly. |

#### Per-band controls (A / B / C / D)

| Control   | Range        | Description                                                                                                                                                                                                                              |
| --------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **FREQ**  | 20–10,000 Hz | Center frequency of the band. Tune this to a harmonic of your oscillator to emphasise that partial.                                                                                                                                      |
| **DECAY** | 0.01–8.0 s   | Ring decay time in seconds — how long the band continues resonating after being excited. Longer values produce pitched metallic ringing that outlasts the dry signal.                                                                    |
| **AMP**   | 0–1          | Level of this band's contribution to the sum. Adjust to balance the four bands relative to each other. At 0 the band is silent.                                                                                                          |
| **PHASE** | + / −        | Polarity of this band in the summed output. Flipping a band's phase creates cancellation or reinforcement with adjacent bands, shaping the combined frequency response — the same principle as Oradea's per-channel phase flip switches. |

---

### Delay

A ping-pong stereo delay. The left and right channels feed into each other across repeats, bouncing the signal between the stereo field.

| Control           | Range      | Description                                                                                                                         |
| ----------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **ON**            | toggle     | Enables the delay. When off, the feedback buffer drains cleanly — no burst on re-enable.                                            |
| **delayTime**     | 10–1000 ms | Time between repeats, displayed in milliseconds. The right channel delay is fixed at 1.33× the left, creating the ping-pong offset. |
| **delayFeedback** | 0–0.95     | How much of each repeat feeds back into the next. High values produce long trails; approaching 1.0 creates near-infinite repeats.   |
| **delayMix**      | 0–1        | Wet level added on top of the dry signal.                                                                                           |

---

### Reverb

A stereo algorithmic reverb based on FreeVerb.

| Control        | Range  | Description                                                                                 |
| -------------- | ------ | ------------------------------------------------------------------------------------------- |
| **ON**         | toggle | Enables the reverb.                                                                         |
| **reverbRoom** | 0–1    | Room size. Larger values produce longer, more diffuse tails.                                |
| **reverbDamp** | 0–1    | High-frequency damping. Higher values absorb treble in the tail, producing a warmer reverb. |
| **reverbMix**  | 0–1    | Wet/dry balance. At 0 the signal is unaffected; at 1 the output is fully wet.               |

---

### Graphic EQ

A 31-band graphic equaliser covering the full ISO octave series from 20 Hz to 20 kHz, with ±24 dB of cut or boost per band. Each band is implemented as a `MidEQ` parametric filter with a 1/6-octave bandwidth; all 31 are applied in series. Band changes are smoothed over 50 ms to prevent clicks.

| Control         | Range  | Description                                                                                                      |
| --------------- | ------ | ---------------------------------------------------------------------------------------------------------------- |
| **ON**          | toggle | Enables the EQ. Bypass crossfades smoothly over ~50 ms — no click when toggling.                                 |
| **Band slider** | 0 – 1  | Each of the 31 sliders maps to one ISO band. Centre position (0.5) = 0 dB. Full up = +24 dB. Full down = −24 dB. |
| **RESET**       | button | Sets all 31 bands back to 0 dB flat in one click.                                                                |

Frequency labels are shown below the slider at every third band: **20 / 40 / 80 / 160 / 315 / 630 / 1.25k / 2.5k / 5k / 10k / 20k**.

EQ settings are saved and recalled with presets.

---

## Preset Matrix

A separate floating window provides 16 preset slots arranged in a 4×4 grid. Presets capture all knob values, route selections, filter mode, loop switch, and chaos source. They are saved to disk automatically and persist across SuperCollider sessions.

### Slot States

| Appearance        | Meaning                      |
| ----------------- | ---------------------------- |
| Dim grey with `·` | Slot is empty                |
| Amber with `●`    | Slot contains a saved preset |
| Cyan highlight    | Currently active slot        |

### Saving a Preset

1. Dial in the sound you want to save
2. Click **✎ SAVE: OFF** — it turns red and reads **✎ SAVE: ARMED**
3. Click any slot to write the current state into it
4. The button disarms automatically after 3 seconds if you change your mind

You can keep SAVE ARMED and click multiple slots to quickly fill several presets in succession.

### Recalling a Preset

With SAVE disarmed, click any filled (amber) slot. All knobs, routes, and buttons update immediately. If the synth is running, parameter changes are applied to the live synth at the same time.

Clicking an empty slot simply highlights it — useful for designating where your next save will go.

### Clearing Presets

**✖ CLEAR ALL** uses a two-click confirmation: first click arms (button turns red, label reads CONFIRM CLEAR), second click wipes all 16 slots. Auto-disarms after 3 seconds.

### Exporting and Importing Presets

Presets can be saved to and loaded from arbitrary files, making it easy to back up a bank, share it with another user, or maintain separate sets for different sessions.

**↑ EXPORT** — Opens a save dialog. Choose any location and filename — no particular extension is required. The current 16 slots are written to that file. This does not affect the auto-save file.

**↓ IMPORT** — Opens a file picker. Select a previously exported `.archive` file. The 16 slots load immediately, the grid refreshes, and the imported bank is written to the auto-save location so it persists across restarts.

The auto-save file lives at:

```
~/Library/Application Support/SuperCollider/benjolin_presets.archive
```

---

## Utility Buttons

| Button           | Action                                                                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **⚡ Randomize** | Maps random values through each knob's control spec, respecting the defined range and warp curve. Useful for discovering unexpected patches. |
| **↺ Reset**      | Restores all knobs and routes to their default values and resets chaos to OFF.                                                               |

---

## Reference: Signal Sources (Routing Matrix)

| Index | Name    | Signal Description                              |
| ----- | ------- | ----------------------------------------------- |
| 0     | NONE    | Silence (DC 0)                                  |
| 1     | TRI A   | Triangle wave output of OSC A, audio rate       |
| 2     | TRI B   | Triangle wave output of OSC B, audio rate       |
| 3     | PULSE A | Square wave (pulse) from OSC A (0 or 1)         |
| 4     | PULSE B | Square wave (pulse) from OSC B (0 or 1)         |
| 5     | XOR     | Exclusive OR of Pulse A and Pulse B             |
| 6     | RUNGLER | R-2R DAC output (−1 to +1 staircase CV)         |
| 7     | PWM     | Comparison of TRI A and TRI B (−1 or +1)        |
| 8     | CHAOS   | Active chaos attractor output (pan source only) |

All sources except CHAOS use values from the **previous audio block** (approximately 1.45 ms at 44.1 kHz / 64-sample block size). This one-block delay is inherent to the feedback architecture and is inaudible in practice.

---

## Technical Notes

- The shift register is clocked by **rising edges of OSC B's pulse output**, matching the Epoch Modular hardware (not the XOR output as in some earlier Benjolin descriptions).
- Resonance uses an **anti-logarithmic mapping** (`rq = 0.01 ** res`) matching the Epoch Modular's resonance feel — the knob is subtle at low values and dramatic near the top.
- The chaos UGens (HenonC, GbmanN, StandardN, Gendy1) run at **audio rate** and are clipped to ±1. All four attractors run simultaneously inside the SynthDef; Select.ar picks the active one with negligible CPU overhead. When chaos is used as a **pan source**, its output is smoothed with a 50 ms lag to prevent audible noise from the discontinuous jumps produced by GbmanN and StandardN.
- The `~benjoBus` stereo bus is available for external processing.

---

_This implementation was developed in SuperCollider. The Benjolin circuit was designed by Rob Hordijk. The Eurorack adaptation is by Epoch Modular. The effects chain architecture — including the `ReplaceOut`-based reorderable synth graph and the 31-band graphic EQ using chained `MidEQ` filters — is based on techniques from **Tommi Keränen's Autohazard** SuperCollider synthesizer. The resonator is inspired by the **Xaoc Devices Oradea** quadruple voltage-controlled resonator; the `Ringz` UGen's gain compensation and additive band architecture follow the same principles described in the Oradea operator's manual._
