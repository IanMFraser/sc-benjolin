// ============================================================
// Benjolin — FX Window
// Loaded by benjolin_gui.scd via .load — do not evaluate directly.
//
// Returns a factory function with signature:
//   { |btn, screen, winW, winH, presetWinW, onClose, fxState, fxKnobs| -> Window }
//
// Effects (9 slots, all reorderable):
//   0 DIST  → ~benjoDistortion
//   1 DELAY → ~benjoDelay
//   2 REVERB → ~benjoReverb
//   3 FLANGER → ~benjoFlanger
//   4 DETUNER → ~benjoDetuner
//   5 PHASOR → ~benjoPhasor
//   6 RING  → ~benjoRingmod
//   7 PITCH → ~benjoPitch
//   8 EQ    → ~benjoEQ
//
// Chain reorder UI:
//   Nine labelled buttons at the top. Click one to arm it (turns green).
//   Click a second to swap those two effects in the server node graph
//   via Synth.moveAfter / moveBefore.  Click the same button twice to
//   deselect without swapping.
//
//   Chain order is NOT saved in presets; resets when the window closes.
//
// The effect panels live inside a ScrollView — scroll vertically to
// reach panels below the visible area.
// ============================================================

{ |btn, screen, winW, winH, presetWinW, onClose, fxState, fxKnobs|
    var fxWinW = 600, fxWinH = 848;
    var eqLimitDB = 24;
    var eqGainsDbs;

    var fxX = (screen.width - winW - 8 - presetWinW) / 2;
    var fxY = min(
        (screen.height - winH) / 2 + winH + 8,
        screen.height - fxWinH - 30
    );
    var fxWin;

    // ── Chain order ──────────────────────────────────────────
    // Index → effect: 0=dist 1=delay 2=reverb 3=flanger 4=detuner 5=phasor 6=ring 7=pitch 8=eq
    var chainOrder   = [0, 1, 2, 3, 4, 5, 6, 7, 8];
    var chainNames   = ["DIST", "DELAY", "REVERB", "FLANGER", "DETUNER", "PHASOR", "RING", "PITCH", "EQ"];
    var chainBtns    = 9.collect { nil };
    var selectedSlot = nil;

    var applyChainOrder = {
        var synths = [
            ~benjoDistortion, ~benjoDelay, ~benjoReverb, ~benjoFlanger,
            ~benjoDetuner, ~benjoPhasor, ~benjoRingmod, ~benjoPitch, ~benjoEQ
        ];
        var ordered = chainOrder.collect { |ei| synths[ei] };
        ordered[0] !? {
            ordered[0].moveBefore(~benjoOut);
            ordered[1] !? { ordered[1].moveAfter(ordered[0]) };
            ordered[2] !? { ordered[2].moveAfter(ordered[1]) };
            ordered[3] !? { ordered[3].moveAfter(ordered[2]) };
            ordered[4] !? { ordered[4].moveAfter(ordered[3]) };
            ordered[5] !? { ordered[5].moveAfter(ordered[4]) };
            ordered[6] !? { ordered[6].moveAfter(ordered[5]) };
            ordered[7] !? { ordered[7].moveAfter(ordered[6]) };
            ordered[8] !? { ordered[8].moveAfter(ordered[7]) };
            ~benjoOut  !? { ~benjoOut.moveAfter(ordered[8])  };
        };
    };

    var refreshChainBtns = {
        9.do { |i|
            chainBtns[i] !? { |b|
                var armed = (i == selectedSlot);
                b.states_([[
                    chainNames[chainOrder[i]],
                    armed.if(Color.white,             Color(0.72, 0.72, 1.0)),
                    armed.if(Color(0.08, 0.35, 0.15), Color(0.15, 0.15, 0.22))
                ]]).value_(0);
            };
        };
    };

    var reorderChain = { |fromSlot, toSlot|
        var temp = chainOrder[fromSlot];
        chainOrder[fromSlot] = chainOrder[toSlot];
        chainOrder[toSlot]   = temp;
        applyChainOrder.();
        refreshChainBtns.();
    };

    var selectSlot = { |slot|
        case
        { selectedSlot.isNil   } { selectedSlot = slot }
        { selectedSlot == slot  } { selectedSlot = nil  }
        {
            reorderChain.(selectedSlot, slot);
            selectedSlot = nil;
        };
        refreshChainBtns.();
    };

    // ── Build window ──────────────────────────────────────────
    fxWin = Window("Benjolin FX",
        Rect(fxX, fxY, fxWinW, fxWinH)
    ).background_(Color(0.07, 0.07, 0.09)).front;

    StaticText(fxWin, Rect(15, 10, 200, 20))
        .string_("EFFECTS")
        .font_(Font.sansSerif(13, true))
        .stringColor_(Color.white);

    // ── Chain order row (in fxWin, above scroll) ───────────────
    // 9 buttons at width=48, spacing=56; arrows between them
    StaticText(fxWin, Rect(15, 41, 50, 18))
        .string_("CHAIN:")
        .font_(Font.sansSerif(9))
        .stringColor_(Color(0.5, 0.5, 0.5));

    9.do { |pos|
        var b = Button(fxWin, Rect(68 + (pos * 56), 37, 48, 26))
            .font_(Font.sansSerif(7, true))
            .action_({ selectSlot.(pos) });
        chainBtns[pos] = b;
    };

    // 8 arrows between buttons
    [118, 174, 230, 286, 342, 398, 454, 510].do { |ax|
        StaticText(fxWin, Rect(ax, 41, 12, 18))
            .string_("→")
            .font_(Font.sansSerif(10))
            .stringColor_(Color(0.35, 0.35, 0.45));
    };

    // ── ScrollView for effect panels ───────────────────────────
    // Section Y starts within the canvas (0 = top of scroll content):
    // sY: DIST=0, DELAY=118, REVERB=236, FLANGER=354, DETUNER=472,
    //     PHASOR=590, RING=708, PITCH=840, EQ=958
    {
        var totalContentH = 1090;
        var scrollArea = ScrollView(fxWin, Rect(0, 75, fxWinW, fxWinH - 75))
            .hasHorizontalScroller_(false)
            .background_(Color(0.07, 0.07, 0.09));
        var canvas = View(scrollArea, Rect(0, 0, fxWinW - 20, totalContentH))
            .background_(Color(0.07, 0.07, 0.09));

        // ── Helper functions (close over canvas) ─────────────
        var mkFXKnob = { |name, lo, hi, warp, step, def, x, y, getSynth|
            var spec    = ControlSpec(lo, hi, warp, step, def);
            var initVal = fxState[name] ?? def;
            var k = EZKnob(
                canvas, Rect(x, y, 80, 90),
                name.asString, spec,
                { |ez|
                    getSynth.() !? { |s| s.set(name, ez.value) };
                    fxState[name] = ez.value;
                },
                initVal, false
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
            fxKnobs[name] = k;
            k
        };

        var mkFXLabel = { |text, x, y|
            StaticText(canvas, Rect(x, y, fxWinW - 30, 20))
                .string_(text)
                .font_(Font.sansSerif(9))
                .stringColor_(Color(0.4, 0.6, 0.9));
        };

        var mkOnBtn = { |paramName, x, y, getSynth|
            var b = Button(canvas, Rect(x, y, 80, 34))
                .states_([
                    ["OFF", Color(0.5, 0.5, 0.5), Color(0.13, 0.13, 0.15)],
                    ["ON",  Color(0.3, 1.0, 0.5),  Color(0.08, 0.2,  0.1) ]
                ])
                .font_(Font.sansSerif(10, true))
                .value_(fxState[paramName] ?? 0)
                .action_({ |b|
                    getSynth.() !? { |s| s.set(paramName, b.value) };
                    fxState[paramName] = b.value;
                });
            fxKnobs[paramName] = b;
            b
        };

        // Initialize EQ dB array from fxState (0.5 UI → 0 dB)
        eqGainsDbs = (fxState[\eqGains] ?? Array.fill(31, 0.5)).collect { |v|
            v * (eqLimitDB * 2) - eqLimitDB
        };

        // ── DISTORTION  (sY = 0) ─────────────────────────────
        mkFXLabel.("── DISTORTION ─── soft saturate + clip ───────────", 15, 0);
        mkOnBtn.(\distOn,   15, 18, { ~benjoDistortion });
        mkFXKnob.(\distDrive, 0.1, 100.0, \exp, 0,     1.0,  110,  10, { ~benjoDistortion });
        mkFXKnob.(\distMix,   0,   1.0,   \lin, 0.001, 1.0,  205,  10, { ~benjoDistortion });

        // ── DELAY  (sY = 118) ────────────────────────────────
        mkFXLabel.("── DELAY ─── dual comb, independent L/R ──────────", 15, 118);
        mkOnBtn.(\delayOn, 15, 136, { ~benjoDelay });
        mkFXKnob.(\delLeftTime,   0.001, 5.0, \exp, 0,     0.5,  110, 128, { ~benjoDelay });
        mkFXKnob.(\delRightTime,  0.001, 5.0, \exp, 0,     0.5,  200, 128, { ~benjoDelay });
        mkFXKnob.(\delLeftDecay,  0,     60,  \lin, 0.001, 3.0,  290, 128, { ~benjoDelay });
        mkFXKnob.(\delRightDecay, 0,     60,  \lin, 0.001, 3.0,  380, 128, { ~benjoDelay });
        mkFXKnob.(\delayMix,      0,     1.0, \lin, 0.001, 0.5,  470, 128, { ~benjoDelay });

        // ── REVERB  (sY = 236) ───────────────────────────────
        mkFXLabel.("── REVERB ───────────────────────────────────────────", 15, 236);
        mkOnBtn.(\reverbOn,   15, 254, { ~benjoReverb });
        mkFXKnob.(\reverbRoom, 0, 1.0, \lin, 0.001, 0.6, 110, 246, { ~benjoReverb });
        mkFXKnob.(\reverbDamp, 0, 1.0, \lin, 0.001, 0.5, 205, 246, { ~benjoReverb });
        mkFXKnob.(\reverbMix,  0, 1.0, \lin, 0.001, 0.3, 300, 246, { ~benjoReverb });

        // ── FLANGER  (sY = 354) ──────────────────────────────
        mkFXLabel.("── FLANGER ─── BufCombC + LFTri ─────────────────", 15, 354);
        mkOnBtn.(\flangerOn, 15, 372, { ~benjoFlanger });
        mkFXKnob.(\flangerRate,     0.01, 20,  \exp, 0,     0.1,  110, 364, { ~benjoFlanger });
        mkFXKnob.(\flangerRange,    10,   500, \exp, 0,     100,  205, 364, { ~benjoFlanger });
        mkFXKnob.(\flangerFeedback, 0,    6.0, \lin, 0.001, 0.0,  300, 364, { ~benjoFlanger });
        mkFXKnob.(\flangerMix,      0,    1.0, \lin, 0.001, 0.5,  395, 364, { ~benjoFlanger });

        // ── DETUNER  (sY = 472) ──────────────────────────────
        mkFXLabel.("── DETUNER ─── BufCombC + LFDNoise3 ───────────────", 15, 472);
        mkOnBtn.(\detunerOn, 15, 490, { ~benjoDetuner });
        mkFXKnob.(\detunerRate,     0.01, 500, \exp, 0,     50.0, 110, 482, { ~benjoDetuner });
        mkFXKnob.(\detunerRange,    10,   1000,\exp, 0,     500,  205, 482, { ~benjoDetuner });
        mkFXKnob.(\detunerFeedback, 0,    5.0, \lin, 0.001, 0.0,  300, 482, { ~benjoDetuner });
        mkFXKnob.(\detunerMix,      0,    1.0, \lin, 0.001, 0.5,  395, 482, { ~benjoDetuner });

        // ── PHASOR  (sY = 590) ───────────────────────────────
        mkFXLabel.("── PHASOR ─── BufAllpassC + SinOsc ────────────────", 15, 590);
        mkOnBtn.(\phasorOn, 15, 608, { ~benjoPhasor });
        mkFXKnob.(\phasorRate,     0.001, 50,  \exp, 0,     0.5,  110, 600, { ~benjoPhasor });
        mkFXKnob.(\phasorRange,    1,     500, \exp, 0,     100,  205, 600, { ~benjoPhasor });
        mkFXKnob.(\phasorFeedback, 0,     3.0, \lin, 0.001, 0.0,  300, 600, { ~benjoPhasor });
        mkFXKnob.(\phasorMix,      0,     1.0, \lin, 0.001, 0.5,  395, 600, { ~benjoPhasor });

        // ── RING MOD  (sY = 708, height = 132) ───────────────
        mkFXLabel.("── RING MODULATOR ───────────────────────────────────", 15, 708);
        mkOnBtn.(\ringOn, 15, 726, { ~benjoRingmod });

        // Wave selector popup below the on button
        StaticText(canvas, Rect(15, 766, 80, 14))
            .string_("WAVEFORM")
            .font_(Font.sansSerif(8))
            .stringColor_(Color(0.5, 0.5, 0.5))
            .align_(\center);
        {
            var waveMenu = PopUpMenu(canvas, Rect(15, 780, 80, 22))
                .items_(["SINE", "PULSE", "SAW"])
                .value_(fxState[\ringWave] ?? 0)
                .font_(Font.sansSerif(9))
                .action_({ |m|
                    ~benjoRingmod !? { ~benjoRingmod.set(\ringWave, m.value) };
                    fxState[\ringWave] = m.value;
                });
            fxKnobs[\ringWave] = waveMenu;
        }.value;

        mkFXKnob.(\ringFreq,       0.5,  5000, \exp, 0,     500,  110, 718, { ~benjoRingmod });
        mkFXKnob.(\ringPulseWidth, 0,    1.0,  \lin, 0.001, 0.5,  220, 718, { ~benjoRingmod });
        mkFXKnob.(\ringMix,        0,    1.0,  \lin, 0.001, 0.5,  330, 718, { ~benjoRingmod });

        // ── PITCH SHIFTER  (sY = 840) ─────────────────────────
        mkFXLabel.("── PITCH SHIFTER ─────────────────────────────────────", 15, 840);
        mkOnBtn.(\pitchOn, 15, 858, { ~benjoPitch });
        mkFXKnob.(\pitchShift,   0.25, 4.0,  \exp, 0,     1.0, 110, 850, { ~benjoPitch });
        mkFXKnob.(\pitchMix,       0,  1.0,  \lin, 0.001, 0.5, 200, 850, { ~benjoPitch });
        mkFXKnob.(\pitchWinSize, 0.02, 2.0,  \exp, 0,     0.2, 290, 850, { ~benjoPitch });
        mkFXKnob.(\pitchPchD,      0,  1.0,  \lin, 0.001, 0.0, 380, 850, { ~benjoPitch });
        mkFXKnob.(\pitchTimeD,     0,  1.0,  \lin, 0.001, 0.0, 470, 850, { ~benjoPitch });

        // ── GRAPHIC EQ  (sY = 958) ────────────────────────────
        mkFXLabel.("── GRAPHIC EQ ─── ±24 dB per band ──────────────────", 15, 958);
        mkOnBtn.(\eqOn, 15, 976, { ~benjoEQ });

        Button(canvas, Rect(15, 1018, 80, 26))
            .states_([["RESET", Color(1.0, 0.6, 0.3), Color(0.13, 0.1, 0.07)]])
            .font_(Font.sansSerif(9, true))
            .action_({
                var flat = Array.fill(31, 0.5);
                eqGainsDbs = Array.fill(31, 0.0);
                fxState[\eqGains] = flat;
                fxKnobs[\eqGains] !? { |msv| msv.value_(flat) };
                ~benjoEQ !? { ~benjoEQ.set(\channelGain, eqGainsDbs) };
            });

        {
            var sliderW = 460;
            var msv = MultiSliderView(canvas, Rect(100, 976, sliderW, 70))
                .size_(31)
                .indexThumbSize_(sliderW / 31)
                .isFilled_(true)
                .drawLines_(false)
                .value_((fxState[\eqGains] ?? Array.fill(31, 0.5)))
                .background_(Color(0.10, 0.10, 0.13))
                .fillColor_(Color(0.4, 0.7, 1.0, 0.7))
                .strokeColor_(Color(0.3, 0.6, 0.9));

            // Centre line (0 dB reference)
            UserView(canvas, Rect(100, 1011, sliderW, 1))
                .background_(Color(0.4, 0.4, 0.5, 0.5));

            // Band frequency labels — every 3rd ISO band
            {
                var labelIdxs = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30];
                var labelStrs = ["20", "40", "80", "160", "315", "630", "1.25k", "2.5k", "5k", "10k", "20k"];
                var bandW     = sliderW / 31;
                var font      = Font.sansSerif(7);
                UserView(canvas, Rect(100, 1048, sliderW, 14))
                    .drawFunc_({
                        Pen.font_(font);
                        Pen.color_(Color(0.45, 0.6, 0.85));
                        labelIdxs.do { |bi, i|
                            var cx = (bi + 0.5) * bandW;
                            Pen.stringCenteredIn(labelStrs[i], Rect(cx - 18, 0, 36, 14));
                        };
                    });
            }.value;

            msv.action = { |sl|
                var idx = sl.index;
                var val = sl.value[idx];
                var db  = val * (eqLimitDB * 2) - eqLimitDB;
                eqGainsDbs[idx] = db;
                fxState[\eqGains] !? { fxState[\eqGains][idx] = val } ?? {
                    fxState[\eqGains] = sl.value.copy
                };
                ~benjoEQ !? { ~benjoEQ.set(\channelGain, eqGainsDbs) };
            };

            fxKnobs[\eqGains] = msv;
        }.value;

    }.value;  // end scroll/canvas block

    fxWin.onClose = { btn.value_(0); onClose.() };

    refreshChainBtns.();

    fxWin
}
