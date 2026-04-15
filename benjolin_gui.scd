// ============================================================
// Benjolin — Main GUI
// Evaluate entire block: Cmd+Shift+Return
//
// Loads:
// benjolin_synthdefs.scd — \benjolin + six FX SynthDefs
// benjolin_fx_gui.scd — FX window factory function
//
// Effects chain (six synths, addToTail after \benjolin):
// ~benjoRes \benjoResonator — harmonic Ringz bank
// ~benjoDelay \benjoDelay — ping-pong delay
// ~benjoReverb \benjoReverb — FreeVerb2 reverb
// ~benjoFlanger \benjoFlanger — comb-filter flanger
// ~benjoEQ \benjoEQ — 31-band graphic EQ
// ~benjoPitch \benjoPitch — granular pitch shifter
// ~benjoOut \benjoOut — output / clip stage (always last)
//
// All three FX synths use ReplaceOut on ~benjoBus so they can be
// reordered live via Synth.moveAfter / moveBefore (drag strips in
// the FX window).
// ============================================================
(
s.waitForBoot {
var makeFxWindow;
var dir = thisProcess.nowExecutingPath.dirname;

    // Load SynthDefs (adds \benjolin, \benjoResonator, \benjoDelay, \benjoReverb, \benjoFlanger, \benjoEQ, \benjoPitch, \benjoOut)
    (dir +/+ "benjolin_synthdefs.scd").load;

    s.sync;

    // Bus + effects chain — six synths, always tail after \benjolin
    ~benjoBus.free;
    ~benjoRes      !? { ~benjoRes.free      };
    ~benjoDelay    !? { ~benjoDelay.free    };
    ~benjoReverb   !? { ~benjoReverb.free   };
    ~benjoFlanger  !? { ~benjoFlanger.free  };
    ~benjoEQ       !? { ~benjoEQ.free       };
    ~benjoPitch    !? { ~benjoPitch.free    };
    ~benjoOut      !? { ~benjoOut.free      };
    ~benjoBus      = Bus.audio(s, 2);
    ~benjoRes      = Synth(\benjoResonator, [\bus, ~benjoBus.index],           addAction: \addToTail);
    ~benjoDelay    = Synth(\benjoDelay,     [\bus, ~benjoBus.index],           addAction: \addToTail);
    ~benjoReverb   = Synth(\benjoReverb,    [\bus, ~benjoBus.index],           addAction: \addToTail);
    ~benjoFlanger  = Synth(\benjoFlanger,   [\bus, ~benjoBus.index],           addAction: \addToTail);
    ~benjoEQ       = Synth(\benjoEQ,        [\bus, ~benjoBus.index],           addAction: \addToTail);
    ~benjoPitch    = Synth(\benjoPitch,     [\bus, ~benjoBus.index],           addAction: \addToTail);
    ~benjoOut      = Synth(\benjoOut,       [\in,  ~benjoBus.index, \out, 0],  addAction: \addToTail);

    // Load FX window factory — returns { |btn, screen, winW, winH, presetWinW, onClose, fxState, fxKnobs| }
    makeFxWindow = (dir +/+ "benjolin_fx_gui.scd").load;

    // ----------------------------------------------------------
    // GUI
    // ----------------------------------------------------------
    {
        var win, synth, loopSwBtn, filterBtns, chaosBtns, startBtn;
        var presetWin, saveModeBtn, slotBtns;
        var fxWin, fxKnobs;
        var fxState = (
            resonOn: 0, resonFreq: 200.0, resonDecay: 1.5, resonMix: 0.25,
            delayOn: 0, delayTime: 250, delayFeedback: 0.4, delayMix: 0.3,
            reverbOn: 0, reverbRoom: 0.6, reverbDamp: 0.5, reverbMix: 0.3,
            flangerOn: 0, flangerRate: 0.5, flangerRange: 100.0,
            flangerFeedback: 0.0, flangerMix: 0.5,
            eqOn: 0, eqGains: Array.fill(31, 0.5),  // 0.5 = 0 dB (centre)
            pitchOn: 0, pitchShift: 1.0, pitchMix: 0.5, pitchWinSize: 0.2,
            pitchPchD: 0.0, pitchTimeD: 0.0
        );
        var knobs   = ();  // symbol → EZKnob
        var routes  = ();  // symbol → PopUpMenu
        var screen  = Window.screenBounds;
        var winW    = 720, winH = 760;
        var presetWinW = 290, presetWinH = 420;
        var presets, presetPath, captureState, recallState, refreshSlot, refreshAll;
        var activeSlot = nil;
        var sourceNames = ["NONE", "TRI A", "TRI B",
                           "PULSE A", "PULSE B", "XOR", "RUNGLER", "PWM"];

        // Styled EZKnob at absolute position
        var mkKnob = { |name, lo, hi, warp, step, def, x, y|
            var spec = ControlSpec(lo, hi, warp, step, def);
            var k = EZKnob(
                win, Rect(x, y, 80, 90),
                name.asString, spec,
                { |ez| synth !? { synth.set(name, ez.value) } },
                def, false
            );
            k.labelView
                .font_(Font.sansSerif(10, true))
                .stringColor_(Color.white)
                .align_(\center);
            k.numberView
                .font_(Font.monospace(10))
                .background_(Color(0.1, 0.1, 0.12))
                .stringColor_(Color(0.85, 0.9, 1))
                .normalColor_(Color(0.85, 0.9, 1));
            knobs.put(name, k);
        };

        // Routing PopUpMenu below a MOD knob
        var mkRoute = { |name, default, x, y|
            var m = PopUpMenu(win, Rect(x, y, 88, 20))
                .items_(sourceNames)
                .value_(default)
                .font_(Font.sansSerif(9))
                .action_({ |menu| synth !? { synth.set(name, menu.value) } });
            routes.put(name, m);
        };

        // Section label
        var mkLabel = { |text, x, y|
            StaticText(win, Rect(x, y, 280, 20))
                .string_(text)
                .font_(Font.sansSerif(9))
                .stringColor_(Color(0.4, 0.6, 0.9));
        };

        win = Window(
            "Benjolin",
            Rect((screen.width - winW - 8 - presetWinW) / 2, (screen.height - winH) / 2, winW, winH)
        ).background_(Color(0.07, 0.07, 0.09)).front;

        // Title
        StaticText(win, Rect(20, 10, 440, 22))
            .string_("BENJOLIN")
            .font_(Font.sansSerif(14, true))
            .stringColor_(Color.white);

        // Start/Stop
        startBtn = Button(win, Rect(560, 8, 148, 28))
            .states_([
                ["▶  START", Color(0.3, 1, 0.45),  Color(0.1, 0.18, 0.1)],
                ["■  STOP",  Color(1,   0.4, 0.4),  Color(0.2, 0.1,  0.1)]
            ])
            .font_(Font.sansSerif(12, true))
            .action_({ |btn|
                if(btn.value == 1) {
                    var initArgs = [];
                    knobs.keysValuesDo  { |k, v| initArgs = initArgs ++ [k, v.value] };
                    routes.keysValuesDo { |k, v| initArgs = initArgs ++ [k, v.value] };
                    initArgs = initArgs ++ [
                        \loopSwitch, loopSwBtn.value,
                        \filterMode,  (filterBtns.detectIndex({ |b| b.value == 1 }) ? 0),
                        \chaosSource, (chaosBtns.detectIndex({ |b| b.value == 1 }) ? 0)
                    ];
                    initArgs = initArgs ++ [\out, ~benjoBus !? { ~benjoBus.index } ?? { 0 }];
                    synth = Synth(\benjolin, initArgs);
                } {
                    synth.free; synth = nil;
                };
            });

        // ── Row 1: Oscillators + Filter ─────────────────────────
        mkLabel.("── OSCILLATORS ──────", 20,  56);
        mkLabel.("── FILTER ─────────────────────────────", 310, 56);

        mkKnob.(\oscA, 0.1, 10000, \exp, 0,     200,    20,  74);
        mkKnob.(\oscB, 0.1, 10000, \exp, 0,     271.5,  115, 74);
        mkKnob.(\freq, 20,  18000, \exp, 0,     5000,   315, 74);
        mkKnob.(\res,  0,   1,     \lin, 0.001, 0.5,    410, 74);

        // Filter mode buttons
        StaticText(win, Rect(510, 74, 180, 18))
            .string_("FILTER MODE")
            .font_(Font.sansSerif(9))
            .stringColor_(Color(0.5, 0.5, 0.5));
        filterBtns = ["LP", "BP", "HP"].collect({ |label, i|
            Button(win, Rect(510 + (i * 60), 90, 52, 46))
                .states_([
                    [label, Color(0.5, 0.5, 0.5), Color(0.13, 0.13, 0.15)],
                    [label, Color(0.3, 0.75, 1),  Color(0.08, 0.18, 0.28)]
                ])
                .font_(Font.sansSerif(13, true))
        });
        filterBtns.do { |btn, i|
            btn.action_({ |b|
                if(b.value == 1) {
                    filterBtns.do { |other, j| (j != i).if { other.value_(0) } };
                    synth !? { synth.set(\filterMode, i) };
                } { b.value_(1) };
            });
        };
        filterBtns[0].value_(1);

        // ── Row 2: Rungler mod + External mod ───────────────────
        mkLabel.("── RUNGLER MOD ──────", 20,  184);
        mkLabel.("── EXTERNAL MOD ─── route ↓ ──────────", 310, 184);

        mkKnob.(\runA, 0, 1, \lin, 0.001, 0.3,  20,  202);
        mkKnob.(\runB, 0, 1, \lin, 0.001, 0.3,  115, 202);
        mkKnob.(\runF, 0, 1, \lin, 0.001, 0.4,  210, 202);
        mkKnob.(\modA, 0, 1, \lin, 0.001, 0.2,  315, 202);
        mkKnob.(\modB, 0, 1, \lin, 0.001, 0.2,  410, 202);
        mkKnob.(\modF, 0, 1, \lin, 0.001, 0.2,  505, 202);

        // Route selectors — below each MOD knob
        // Defaults: modA←TriB(2), modB←TriA(1), modF←TriB(2)
        mkRoute.(\modARoute, 2, 315, 296);
        mkRoute.(\modBRoute, 1, 410, 296);
        mkRoute.(\modFRoute, 2, 505, 296);

        // ── Row 3: Loop + Pan + Output ──────────────────────────
        mkLabel.("── LOOP ─────────────", 20,  336);
        mkLabel.("── PAN ─── OUTPUT ──────────────────────", 310, 336);

        mkKnob.(\loop,  0, 1, \lin, 0.001, 0.0,  20,  354);
        mkKnob.(\pan,  -1, 1, \lin, 0.001, 0.0,  315, 354);
        mkKnob.(\panMod, 0, 1, \lin, 0.001, 1.0, 410, 354);
        mkKnob.(\amp,   0, 1, \lin, 0.001, 0.86, 600, 354);

        // Loop switch
        StaticText(win, Rect(118, 354, 82, 18))
            .string_("LOOP SW")
            .font_(Font.sansSerif(9))
            .stringColor_(Color(0.5, 0.5, 0.5))
            .align_(\center);
        loopSwBtn = Button(win, Rect(118, 370, 82, 34))
            .states_([
                ["LOOP", Color(0.4, 0.4, 0.4), Color(0.13, 0.13, 0.15)],
                ["LOOP", Color(0.3, 1.0, 0.5), Color(0.08, 0.2,  0.1) ]
            ])
            .font_(Font.sansSerif(9, true))
            .action_({ |btn| synth !? { synth.set(\loopSwitch, btn.value) } });

        // Pan mod source — sits between panMod and amp knobs
        StaticText(win, Rect(505, 354, 88, 18))
            .string_("PAN SOURCE")
            .font_(Font.sansSerif(9))
            .stringColor_(Color(0.5, 0.5, 0.5));
        routes.put(\panRoute,
            PopUpMenu(win, Rect(505, 370, 88, 20))
                .items_(sourceNames ++ ["CHAOS"])
                .value_(0)
                .font_(Font.sansSerif(9))
                .action_({ |menu| synth !? { synth.set(\panRoute, menu.value) } })
        );

        // ── Row 4: Chaos Automaton ──────────────────────────────
        mkLabel.("── CHAOS AUTOMATON ─── source ↓ ──────────────", 20, 464);

        chaosBtns = ["OFF", "HÉNON", "GBMAN", "STDMAP", "GENDY"].collect({ |label, i|
            Button(win, Rect(20 + (i * 93), 482, 85, 28))
                .states_([
                    [label, Color(0.5,  0.5,  0.5),  Color(0.13, 0.13, 0.15)],
                    [label, Color(1.0,  0.75, 0.2),  Color(0.22, 0.14, 0.04)]
                ])
                .font_(Font.sansSerif(10, true))
        });
        chaosBtns[0].value_(1);
        chaosBtns.do { |btn, i|
            btn.action_({ |b|
                if(b.value == 1) {
                    chaosBtns.do { |other, j| (j != i).if { other.value_(0) } };
                    synth !? { synth.set(\chaosSource, i) };
                } { b.value_(1) };
            });
        };

        // Rate knob — aligned with source buttons; depth label clears below its bottom (482+90=572)
        mkKnob.(\chaosRate, 0.1, 200, \exp, 0, 5.0, 600, 482);

        // Depth knobs — x=20-480, so no horizontal overlap with rate knob at x=600
        mkLabel.("── CHAOS DEPTH ─── osc = direct FM   run = Rungler depth ──", 20, 518);
        mkKnob.(\chaosOscA, 0, 3, \lin, 0.01,  0.0,  20, 538);
        mkKnob.(\chaosOscB, 0, 3, \lin, 0.01,  0.0, 115, 538);
        mkKnob.(\chaosRunA, 0, 1, \lin, 0.001, 0.0, 210, 538);
        mkKnob.(\chaosRunB, 0, 1, \lin, 0.001, 0.0, 305, 538);
        mkKnob.(\chaosRunF, 0, 1, \lin, 0.001, 0.0, 400, 538);

        // Bottom buttons
        Button(win, Rect(20, 722, 120, 22))
            .states_([["⚡ Randomize", Color(1, 0.9, 0.2), Color(0.14, 0.13, 0.08)]])
            .font_(Font.sansSerif(10))
            .action_({
                var randFilter = 3.rand;
                knobs.keysValuesDo { |name, k|
                    var v = k.controlSpec.map(1.0.rand);
                    k.value_(v);
                    synth !? { synth.set(name, v) };
                };
                filterBtns.do { |b, i| b.value_(i == randFilter) };
                synth !? { synth.set(\filterMode, randFilter) };
            });

        Button(win, Rect(152, 722, 90, 22))
            .states_([["↺ Reset", Color(0.7, 0.7, 1), Color(0.11, 0.11, 0.18)]])
            .font_(Font.sansSerif(10))
            .action_({
                knobs.keysValuesDo { |name, k|
                    k.value_(k.controlSpec.default);
                    synth !? { synth.set(name, k.controlSpec.default) };
                };
                routes.keysValuesDo { |name, m|
                    var def = switch(name,
                        \modARoute, { 2 },
                        \modBRoute, { 1 },
                        \modFRoute, { 2 },
                        { 0 }
                    );
                    m.value_(def);
                    synth !? { synth.set(name, def) };
                };
                chaosBtns.do { |b, i| b.value_(i == 0) };
                synth !? { synth.set(\chaosSource, 0) };
            });

        // FX window toggle
        Button(win, Rect(260, 722, 70, 22))
            .states_([
                ["⚙ FX",  Color(0.75, 0.55, 1.0), Color(0.12, 0.08, 0.20)],
                ["⚙ FX",  Color(1.0,  0.85, 0.3),  Color(0.20, 0.15, 0.04)]
            ])
            .font_(Font.sansSerif(10, true))
            .action_({ |b|
                if(b.value == 1) {
                    fxKnobs = ();
                    fxWin = makeFxWindow.(b, screen, winW, winH, presetWinW, { fxWin = nil; fxKnobs = nil }, fxState, fxKnobs);
                } {
                    fxWin !? { fxWin.close; fxWin = nil; fxKnobs = nil };
                };
            });

        // ── Preset Matrix ────────────────────────────────────────
        presetPath = Platform.userAppSupportDir ++ "/benjolin_presets.archive";
        presets    = if(File.exists(presetPath)) {
            Object.readArchive(presetPath) ?? { Dictionary.new }
        } { Dictionary.new };

        // Snapshot all current GUI values into an Event
        captureState = {
            var state = ();
            knobs.keysValuesDo  { |k, v| state[k] = v.value };
            routes.keysValuesDo { |k, v| state[k] = v.value };
            state[\loopSwitch] = loopSwBtn.value;
            state[\filterMode] = filterBtns.detectIndex({ |b| b.value == 1 }) ? 0;
            state[\chaosSource] = chaosBtns.detectIndex({ |b| b.value == 1 }) ? 0;
            state[\fx] = fxState.copy;
            state
        };

        // Push a saved Event back into all GUI controls + live synth
        recallState = { |state|
            knobs.keysValuesDo { |k, v|
                state[k] !? { |val| v.value_(val); synth !? { synth.set(k, val) } };
            };
            routes.keysValuesDo { |k, v|
                state[k] !? { |val| v.value_(val); synth !? { synth.set(k, val) } };
            };
            state[\loopSwitch] !? { |val|
                loopSwBtn.value_(val);
                synth !? { synth.set(\loopSwitch, val) };
            };
            state[\filterMode] !? { |val|
                filterBtns.do { |b, i| b.value_(i == val) };
                synth !? { synth.set(\filterMode, val) };
            };
            state[\chaosSource] !? { |val|
                chaosBtns.do { |b, i| b.value_(i == val) };
                synth !? { synth.set(\chaosSource, val) };
            };
            state[\fx] !? { |fs|
                fs.keysValuesDo { |k, v| fxState[k] = v };
                // Route each parameter to the synth that owns it
                [\resonOn, \resonFreq, \resonDecay, \resonMix].do { |p|
                    fs[p] !? { ~benjoRes    !? { ~benjoRes.set(p,    fs[p]) } };
                };
                [\delayOn, \delayTime, \delayFeedback, \delayMix].do { |p|
                    fs[p] !? { ~benjoDelay  !? { ~benjoDelay.set(p,  fs[p]) } };
                };
                [\reverbOn, \reverbRoom, \reverbDamp, \reverbMix].do { |p|
                    fs[p] !? { ~benjoReverb !? { ~benjoReverb.set(p, fs[p]) } };
                };
                [\flangerOn, \flangerRate, \flangerRange, \flangerFeedback, \flangerMix].do { |p|
                    fs[p] !? { ~benjoFlanger !? { ~benjoFlanger.set(p, fs[p]) } };
                };
                [\eqOn].do { |p|
                    fs[p] !? { ~benjoEQ !? { ~benjoEQ.set(p, fs[p]) } };
                };
                fs[\eqGains] !? { |gains|
                    var dbs = gains.collect { |v| v * 48 - 24 };
                    ~benjoEQ !? { ~benjoEQ.set(\channelGain, dbs) };
                    fxKnobs !? { fxKnobs[\eqGains] !? { |msv| msv.value_(gains) } };
                };
                [\pitchOn, \pitchShift, \pitchMix, \pitchWinSize, \pitchPchD, \pitchTimeD].do { |p|
                    fs[p] !? { ~benjoPitch !? { ~benjoPitch.set(p, fs[p]) } };
                };
                // Update knob/button visuals if the FX window is open
                fxKnobs !? { fs.keysValuesDo { |k, v| fxKnobs[k] !? { |w| w.value_(v) } } };
            };
        };

        // Redraw one slot: 3 visual states — empty · / filled ● / active (highlighted)
        refreshSlot = { |idx|
            var filled   = presets.includesKey(idx);
            var isActive = (idx == activeSlot);
            var marker   = filled.if("●", "·");
            var label    = "% %".format((idx + 1).asString.padLeft(2, "0"), marker);
            slotBtns[idx].states_([
                [label, Color(0.35, 0.35, 0.38), Color(0.11, 0.11, 0.14)],  // 0 inactive+empty
                [label, Color(1.0,  0.82, 0.25), Color(0.20, 0.16, 0.04)],  // 1 inactive+filled
                [label, Color(0.2,  0.9,  1.0),  Color(0.05, 0.20, 0.28)]   // 2 active
            ]).value_(isActive.if(2, filled.asInteger));
        };

        refreshAll = { 16.do { |i| refreshSlot.(i) } };

        // ── Preset window — opens to the right of the main window ──
        presetWin = Window(
            "Benjolin Presets",
            Rect(
                (screen.width - winW - 8 - presetWinW) / 2 + winW + 8,
                (screen.height - presetWinH) / 2,
                presetWinW, presetWinH
            )
        ).background_(Color(0.07, 0.07, 0.09)).front;

        StaticText(presetWin, Rect(15, 10, 180, 18))
            .string_("PRESET MATRIX")
            .font_(Font.sansSerif(12, true))
            .stringColor_(Color.white);

        // CLEAR ALL — two-click confirm: first click arms, second click executes
        Button(presetWin, Rect(15, 36, 120, 24))
            .states_([
                ["✖  CLEAR ALL",  Color(1,    0.5,  0.5),  Color(0.18, 0.08, 0.08)],
                ["CONFIRM CLEAR", Color(1.0,  0.25, 0.25), Color(0.30, 0.05, 0.05)]
            ])
            .font_(Font.sansSerif(10, true))
            .action_({ |b|
                if(b.value == 1) {
                    // Armed — wait for second click; auto-disarm after 3 seconds
                    AppClock.sched(3, { { b.value_(0) }.defer; nil });
                } {
                    // Confirmed — clear everything
                    presets = Dictionary.new;
                    presets.writeArchive(presetPath);
                    activeSlot = nil;
                    refreshAll.();
                };
            });

        // SAVE ARMED toggle
        saveModeBtn = Button(presetWin, Rect(148, 36, 127, 24))
            .states_([
                ["✎  SAVE: OFF",   Color(0.5,  0.5,  0.5),  Color(0.13, 0.13, 0.15)],
                ["✎  SAVE: ARMED", Color(1.0,  0.35, 0.35), Color(0.22, 0.07, 0.07)]
            ])
            .font_(Font.sansSerif(10, true));

        // Export / Import
        Button(presetWin, Rect(15, 68, 120, 24))
            .states_([["↑  EXPORT", Color(0.5, 0.9, 0.6), Color(0.07, 0.18, 0.1)]])
            .font_(Font.sansSerif(10, true))
            .action_({
                Dialog.savePanel({ |path|
                    presets.writeArchive(path);
                });
            });

        Button(presetWin, Rect(148, 68, 127, 24))
            .states_([["↓  IMPORT", Color(0.5, 0.75, 1.0), Color(0.07, 0.13, 0.22)]])
            .font_(Font.sansSerif(10, true))
            .action_({
                Dialog.openPanel({ |path|
                    var loaded = Object.readArchive(path);
                    loaded !? {
                        presets = loaded;
                        presets.writeArchive(presetPath);
                        activeSlot = nil;
                        refreshAll.();
                    };
                });
            });

        // 2×8 grid — 16 slots
        slotBtns = Array.new(16);
        16.do { |idx|
            var col = idx % 2;
            var row = idx / 2;
            var btn = Button(presetWin,
                Rect(15 + (col * 135), 100 + (row * 38), 125, 30));
            btn.font_(Font.sansSerif(10, true));
            slotBtns.add(btn);
            refreshSlot.(idx);
            btn.action_({
                if(saveModeBtn.value == 1) {
                    // SAVE: store state, write to disk, select this slot
                    presets[idx] = captureState.();
                    presets.writeArchive(presetPath);
                    activeSlot = idx;
                    refreshAll.();
                } {
                    // RECALL: select and apply if filled, just highlight if empty
                    activeSlot = idx;
                    presets[idx] !? { |state| recallState.(state) };
                    refreshAll.();
                };
            });
        };

        win.onClose = {
            synth.free;         synth = nil;
            ~benjoRes.free;      ~benjoRes      = nil;
            ~benjoDelay.free;    ~benjoDelay    = nil;
            ~benjoReverb.free;   ~benjoReverb   = nil;
            ~benjoFlanger.free;  ~benjoFlanger  = nil;
            ~benjoEQ.free;       ~benjoEQ       = nil;
            ~benjoPitch.free;    ~benjoPitch    = nil;
            ~benjoOut.free;      ~benjoOut      = nil;
            ~benjoBus.free;     ~benjoBus    = nil;
            presetWin.close;
            fxWin !? { fxWin.close };
        };

    }.defer;

};
)
