// ============================================================
// Benjolin — with modulation routing matrix
// Evaluate entire block: Cmd+Shift+Return
// ============================================================
(
s.waitForBoot {

    // ----------------------------------------------------------
    // SynthDef
    //
    // All internal signals are carried on a feedback bus so they
    // can be routed to any MOD input (as you would with patch cables).
    //
    // LocalIn/Out bus layout (8 channels):
    //   [0] runglerCV   [1] loopBit   [2] triA    [3] triB
    //   [4] pulseA      [5] pulseB    [6] xorOut  [7] pwm
    //
    // Route indices (modARoute / modBRoute / modFRoute):
    //   0=NONE  1=TRI A  2=TRI B  3=PULSE A  4=PULSE B
    //   5=XOR   6=RUNGLER  7=PWM
    //
    // Defaults mirror the hardware normalized connections:
    //   MOD A ← TRI B (2)
    //   MOD B ← TRI A (1)
    //   MOD F ← TRI B (2)
    // ----------------------------------------------------------
    SynthDef(\benjolin, {
        | out=0, gate=1,
          oscA=200, oscB=271.5,
          runA=0.3, runB=0.3, runF=0.4,
          modA=0.2, modB=0.2, modF=0.2,
          modARoute=2, modBRoute=1, modFRoute=2,
          freq=800, res=0.5,
          loop=0.0, loopSwitch=0,
          filterMode=0, amp=0.86,
          chaosSource=0, chaosRate=5.0,
          chaosOscA=1.0, chaosOscB=1.0,
          chaosRunA=0.0, chaosRunB=0.0, chaosRunF=0.0,
          pan=0.0, panMod=1.0, panRoute=0 |

        var fb, runglerCV, loopBit, prevTriA, prevTriB;
        var prevPulseA, prevPulseB, prevXor, prevPwm;
        var sources, modASig, modBSig, modFSig;
        var freqA, freqB, triA, triB, pulseA, pulseB;
        var xorOut, pwmSig, clockTrig, loopActive, dataIn;
        var bits, weights, runglerRaw, newRunglerCV;
        var filterIn, filterCutoff, rq;
        var lpOut, bpOut, hpOut, filtered, env;
        var chaosRaw, effRunA, effRunB, effRunF;
        var panPos, mono;

        // Previous block's signals via feedback bus
        fb          = LocalIn.ar(8);
        runglerCV   = fb[0];
        loopBit     = fb[1];
        prevTriA    = fb[2];
        prevTriB    = fb[3];
        prevPulseA  = fb[4];
        prevPulseB  = fb[5];
        prevXor     = fb[6];
        prevPwm     = fb[7];

        // Modulation source matrix — patch any output to any MOD input
        // Uses previous block's values (1-block delay, ~1.45ms — negligible)
        sources = [DC.ar(0), prevTriA, prevTriB, prevPulseA, prevPulseB,
                   prevXor,  runglerCV, prevPwm];
        modASig = Select.ar(modARoute, sources);
        modBSig = Select.ar(modBRoute, sources);
        modFSig = Select.ar(modFRoute, sources);

        // Chaos attractor — all three run simultaneously; Select.kr picks the active one
        // GbmanN and StandardMapN can have large excursions — clip keeps them in -1..1
        chaosRaw = Select.ar(chaosSource, [
            DC.ar(0),                                          // 0 = OFF
            HenonC.ar(chaosRate, 1.4, 0.3).clip(-1, 1),       // 1 = Hénon
            GbmanN.ar(chaosRate).clip(-1, 1),                  // 2 = Gingerbread Man
            StandardN.ar(chaosRate, 1.0).clip(-1, 1),          // 3 = Standard Map
        ]);

        // Chaos offsets the Rungler depth — the attractor literally rewires the patch
        // NB: parentheses required — SC evaluates binary ops left-to-right, no precedence
        effRunA = (runA + (chaosRaw * chaosRunA)).clip(0, 1);
        effRunB = (runB + (chaosRaw * chaosRunB)).clip(0, 1);
        effRunF = (runF + (chaosRaw * chaosRunF)).clip(0, 1);

        // Oscillator frequencies — Rungler FM + MOD routing + direct chaos FM
        freqA = (oscA * (2 ** (runglerCV * effRunA * 3 + modASig * modA * 2 + (chaosRaw * chaosOscA) * 3))).clip(0.1, 12000);
        freqB = (oscB * (2 ** (runglerCV.neg * effRunB * 3 + modBSig * modB * 2 + (chaosRaw * chaosOscB) * 3))).clip(0.1, 12000);

        triA   = LFTri.ar(freqA);
        triB   = LFTri.ar(freqB);
        pulseA = (triA > 0);
        pulseB = (triB > 0);

        // XOR output (available as modulation source)
        xorOut = pulseA + pulseB - (2 * pulseA * pulseB);

        // PWM: compare the two triangle waves — width varies at beat frequency
        pwmSig = ((triA > triB) * 2 - 1);

        // Clock from OSC B rising edges (per Epoch manual)
        clockTrig = HPZ1.ar(pulseB) > 0;

        // Loop: recirculate MSB when loopSwitch on AND loop offset > 0
        loopActive = loopSwitch * (loop > 0);
        dataIn     = Select.ar(loopActive, [pulseA, loopBit]);

        // 8-stage shift register — data from OSC A, clock from OSC B
        bits = Array.new(8);
        bits.add(Latch.ar(dataIn, clockTrig));
        7.do { |i| bits.add(Latch.ar(Delay1.ar(bits[i]), clockTrig)) };

        // R-2R DAC → Rungler CV (-1..1)
        weights      = Array.geom(8, 0.5, 0.5);
        runglerRaw   = bits.collect({ |b, i| b * weights[i] }).sum;
        newRunglerCV = (runglerRaw * 2) - 1;

        // Push all signals onto the feedback bus for next block
        LocalOut.ar([newRunglerCV, bits[7], triA, triB,
                     pulseA, pulseB, xorOut, pwmSig]);

        // Filter input: PWM mix + rungler (per manual)
        filterIn = (pwmSig * 0.6 + newRunglerCV * 0.4).tanh;

        // Filter cutoff — RUN F and routed MOD F both modulate exponentially
        filterCutoff = (freq * (2 ** (
            newRunglerCV * effRunF * 3 +
            modFSig      * modF * 2
        ))).clip(20, 18000);

        // Resonance — anti-logarithmic curve (per manual)
        rq = (0.01 ** res).clip(0.005, 1.0);

        lpOut    = BLowPass.ar(filterIn, filterCutoff, rq);
        hpOut    = BHiPass.ar(filterIn, filterCutoff, rq);
        bpOut    = BBandPass.ar(filterIn,  filterCutoff, rq);
        filtered = Select.ar(filterMode, [lpOut, bpOut, hpOut]).tanh;

        env  = EnvGen.kr(Env.asr(0.01, 1, 0.05), gate, doneAction: 2);
        mono = filtered * amp * env;

        // ── Spatial ────────────────────────────────────────────
        // Pan position: base knob + any routing source (internal signals or chaos)
        panPos = (pan + Select.ar(panRoute, sources ++ [chaosRaw]) * panMod).clip(-1, 1);

        Out.ar(out, Pan2.ar(mono, panPos));
    }).add;

    s.sync;

    // ----------------------------------------------------------
    // GUI
    // ----------------------------------------------------------
    {
        var win, synth, loopSwBtn, filterBtns, chaosBtns, startBtn;
        var presetWin, saveModeBtn, slotBtns;
        var knobs   = ();  // symbol → EZKnob
        var routes  = ();  // symbol → PopUpMenu
        var screen  = Window.screenBounds;
        var winW    = 720, winH = 760;
        var presetWinW = 290, presetWinH = 390;
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
                ["LOOP OFF", Color(0.55, 0.55, 0.55), Color(0.13, 0.13, 0.15)],
                ["LOOP ON",  Color(0.3,  1.0,  0.5),  Color(0.08, 0.2,  0.1) ]
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

        chaosBtns = ["OFF", "HÉNON", "GBMAN", "STDMAP"].collect({ |label, i|
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

        // Depth knobs — label at 592 clears rate knob bottom at 572
        mkLabel.("── CHAOS DEPTH ─── osc = direct FM   run = Rungler depth ──", 20, 592);
        mkKnob.(\chaosOscA, 0, 3, \lin, 0.01,  0.0,  20, 610);
        mkKnob.(\chaosOscB, 0, 3, \lin, 0.01,  0.0, 115, 610);
        mkKnob.(\chaosRunA, 0, 1, \lin, 0.001, 0.0, 210, 610);
        mkKnob.(\chaosRunB, 0, 1, \lin, 0.001, 0.0, 305, 610);
        mkKnob.(\chaosRunF, 0, 1, \lin, 0.001, 0.0, 400, 610);

        // Bottom buttons
        Button(win, Rect(20, 722, 120, 22))
            .states_([["⚡ Randomize", Color(1, 0.9, 0.2), Color(0.14, 0.13, 0.08)]])
            .font_(Font.sansSerif(10))
            .action_({
                knobs.keysValuesDo { |name, k|
                    var v = k.controlSpec.map(1.0.rand);
                    k.value_(v);
                    synth !? { synth.set(name, v) };
                };
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

        // 2×8 grid — 16 slots
        slotBtns = Array.new(16);
        16.do { |idx|
            var col = idx % 2;
            var row = idx / 2;
            var btn = Button(presetWin,
                Rect(15 + (col * 135), 70 + (row * 38), 125, 30));
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
            synth.free; synth = nil;
            ~benjoMonitor.free;
            ~benjoBus.free;
            presetWin.close;
        };

    }.defer;
};
)
