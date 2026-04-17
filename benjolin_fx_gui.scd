// ============================================================
// Benjolin — FX Window
// Loaded by benjolin_gui.scd via .load — do not evaluate directly.
//
// Returns a factory function with signature:
//   { |btn, screen, winW, winH, presetWinW, onClose, fxState, fxKnobs| -> Window }
//
// Chain reorder UI:
//   Five labelled buttons at the top show the current processing
//   order. Click one to select it (turns green). Click a second to
//   swap those two effects and update the server node graph via
//   Synth.moveAfter / moveBefore. Click the same button twice to
//   deselect without swapping.
//
//   Chain order is not saved in presets; resets when window closes.
// ============================================================

{ |btn, screen, winW, winH, presetWinW, onClose, fxState, fxKnobs|
    var fxWinW = 500, fxWinH = 840;
    var eqLimitDB = 24;
    var eqGainsDbs;
    var fxX    = (screen.width - winW - 8 - presetWinW) / 2;
    var fxY    = (screen.height - winH) / 2 + winH + 8;
    var fxWin;

    // chainOrder[slot] = effect index: 0=delay 1=reverb 2=eq 3=resonator
    var chainOrder   = [0, 1, 2, 3];
    var chainNames   = ["RES","DELAY", "REVERB", "EQ"];
    var chainBtns    = [nil, nil, nil, nil];
    var selectedSlot = nil;   // slot index of the currently armed button, or nil

    var applyChainOrder = {
        var synths  = [~benjoResonator, ~benjoDelay, ~benjoReverb, ~benjoEQ];
        var ordered = chainOrder.collect({ |ei| synths[ei] });
        ordered[0] !? {
            ordered[0].moveBefore(~benjoOut);
            ordered[1] !? { ordered[1].moveAfter(ordered[0]) };
            ordered[2] !? { ordered[2].moveAfter(ordered[1]) };
            ordered[3] !? { ordered[3].moveAfter(ordered[2]) };
            ~benjoOut  !? { ~benjoOut.moveAfter(ordered[3])  };
        };
    };

    // Redraw all four chain buttons to reflect chainOrder and selectedSlot.
    var refreshChainBtns = {
        4.do { |i|
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

    // First click arms a slot; second click on a different slot swaps;
    // clicking the armed slot again disarms.
    var selectSlot = { |slot|
        case
        { selectedSlot.isNil  } { selectedSlot = slot }
        { selectedSlot == slot } { selectedSlot = nil  }
        {
            reorderChain.(selectedSlot, slot);
            selectedSlot = nil;
        };
        refreshChainBtns.();
    };

    // getSynth is a zero-arg function { ~benjoRes } etc.
    var mkFXKnob = { |name, lo, hi, warp, step, def, x, y, getSynth|
        var spec    = ControlSpec(lo, hi, warp, step, def);
        var initVal = fxState[name] ?? def;
        var k = EZKnob(
            fxWin, Rect(x, y, 80, 90),
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
        StaticText(fxWin, Rect(x, y, 380, 20))
            .string_(text)
            .font_(Font.sansSerif(9))
            .stringColor_(Color(0.4, 0.6, 0.9));
    };

    var mkOnBtn = { |paramName, x, y, getSynth|
        var b = Button(fxWin, Rect(x, y, 80, 34))
            .states_([
                ["OFF", Color(0.5, 0.5, 0.5), Color(0.13, 0.13, 0.15)],
                ["ON",  Color(0.3, 1.0, 0.5),  Color(0.08, 0.2,  0.1) ]
            ])
            .font_(Font.sansSerif(10, true))
            .value_(fxState[paramName] ?? 0)
            .action_({ |btn|
                getSynth.() !? { |s| s.set(paramName, btn.value) };
                fxState[paramName] = btn.value;
            });
        fxKnobs[paramName] = b;
        b
    };

    // Phase polarity toggle for resonator bands. fxState stores 0=normal / 1=inverted.
    // The synth receives ±1 (converted in the action); Button .value_ works with 0/1 directly.
    var mkPolBtn = { |band, x, y|
        var paramName = ("pol" ++ band).asSymbol;
        var initVal   = fxState[paramName] ?? 0;
        var b = Button(fxWin, Rect(x, y, 80, 28))
            .states_([
                ["+", Color(0.72, 0.72, 1.0), Color(0.15, 0.15, 0.22)],
                ["−", Color(1.0,  0.5,  0.5), Color(0.25, 0.08, 0.08)]
            ])
            .font_(Font.sansSerif(14, true))
            .value_(initVal)
            .action_({ |btn|
                var polVal = (btn.value == 0).if(1, -1);
                ~benjoResonator !? { ~benjoResonator.set(paramName, polVal) };
                fxState[paramName] = btn.value;
            });
        fxKnobs[paramName] = b;
        b
    };

    // Initialize EQ dB array from fxState (stored as 0-1 UI values, 0.5 = 0 dB)
    eqGainsDbs = (fxState[\eqGains] ?? Array.fill(31, 0.5)).collect { |v| v * (eqLimitDB * 2) - eqLimitDB };

    // ── Build window ──────────────────────────────────────
    fxWin = Window("Benjolin FX",
        Rect(fxX, fxY, fxWinW, fxWinH)
    ).background_(Color(0.07, 0.07, 0.09)).front;

    StaticText(fxWin, Rect(15, 10, 200, 20))
        .string_("EFFECTS")
        .font_(Font.sansSerif(13, true))
        .stringColor_(Color.white);

    // ── DELAY ─────────────────────────────────────────────
    mkFXLabel.("── DELAY ─── ping-pong ─────────────────────", 15, 484);
    mkOnBtn.(\delayOn,        15, 512, { ~benjoDelay });
    mkFXKnob.(\delayTime,     10, 1000, \exp, 0,     250,  110, 494, { ~benjoDelay });
    mkFXKnob.(\delayFeedback,  0, 0.95, \lin, 0.001, 0.4,  205, 494, { ~benjoDelay });
    mkFXKnob.(\delayMix,       0, 1.0,  \lin, 0.001, 0.3,  300, 494, { ~benjoDelay });

    // ── REVERB ────────────────────────────────────────────
    mkFXLabel.("── REVERB ───────────────────────────────────", 15, 602);
    mkOnBtn.(\reverbOn,      15, 630, { ~benjoReverb });
    mkFXKnob.(\reverbRoom,    0, 1.0, \lin, 0.001, 0.6, 110, 612, { ~benjoReverb });
    mkFXKnob.(\reverbDamp,    0, 1.0, \lin, 0.001, 0.5, 205, 612, { ~benjoReverb });
    mkFXKnob.(\reverbMix,     0, 1.0, \lin, 0.001, 0.3, 300, 612, { ~benjoReverb });

    // ── GRAPHIC EQ ────────────────────────────────────────
    // 31 ISO octave bands, ±24 dB. MultiSliderView maps 0.0–1.0 → −24..+24 dB.
    // Stored in fxState[\eqGains] as 0–1 values; eqGainsDbs[] holds live dB values.
    mkFXLabel.("── GRAPHIC EQ ─── ±24 dB per band ─────────", 15, 720);
    mkOnBtn.(\eqOn, 15, 736, { ~benjoEQ });

    Button(fxWin, Rect(15, 778, 80, 26))
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
        var sliderW = 385;
        var msv = MultiSliderView(fxWin, Rect(100, 736, sliderW, 70))
            .size_(31)
            .indexThumbSize_(sliderW / 31)
            .isFilled_(true)
            .drawLines_(false)
            .value_((fxState[\eqGains] ?? Array.fill(31, 0.5)))
            .background_(Color(0.10, 0.10, 0.13))
            .fillColor_(Color(0.4, 0.7, 1.0, 0.7))
            .strokeColor_(Color(0.3, 0.6, 0.9));

        // Centre line (0 dB reference)
        UserView(fxWin, Rect(100, 771, sliderW, 1))
            .background_(Color(0.4, 0.4, 0.5, 0.5));

        // Band frequency labels — every 3rd ISO band
        {
            var labelIdxs = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30];
            var labelStrs = ["20", "40", "80", "160", "315", "630", "1.25k", "2.5k", "5k", "10k", "20k"];
            var bandW     = sliderW / 31;
            var font      = Font.sansSerif(7);
            UserView(fxWin, Rect(100, 810, sliderW, 14))
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
            fxState[\eqGains] !? { fxState[\eqGains][idx] = val } ?? { fxState[\eqGains] = sl.value.copy };
            ~benjoEQ !? { ~benjoEQ.set(\channelGain, eqGainsDbs) };
        };

        fxKnobs[\eqGains] = msv;
    }.value;

    // ── RESONATOR ─────────────────────────────────────────
    // 4 parallel Ringz filters. Per-band: freq, decay (ring time), amp, phase polarity.
    // Bands add on top of the dry signal; tanh prevents summing distortion.
    // Inspired by Xaoc Oradea quadruple voltage-controlled resonator.
    mkFXLabel.("── RESONATOR ─── 4-band Ringz ──────────", 15, 80);
    mkOnBtn.(\resOn, 15, 96, { ~benjoResonator });
    mkFXKnob.(\resMix, 0, 1.0, \lin, 0.001, 0.5, 100, 80, { ~benjoResonator });

    // Band column headers
    ["A", "B", "C", "D"].do { |letter, i|
        StaticText(fxWin, Rect(90 + (i * 95) + 28, 136, 24, 16))
            .string_(letter)
            .font_(Font.sansSerif(10, true))
            .stringColor_(Color(0.72, 0.72, 1.0))
            .align_(\center);
    };

    // Row labels
    [["FREQ",  154], ["DECAY", 248], ["AMP", 342], ["PHASE", 436]].do { |pair|
        StaticText(fxWin, Rect(15, pair[1], 72, 16))
            .string_(pair[0])
            .font_(Font.sansSerif(8))
            .stringColor_(Color(0.4, 0.6, 0.9))
            .align_(\right);
    };

    // Per-band knobs and polarity buttons
    {
        var bands   = ["A", "B", "C", "D"];
        var freqDefs  = [200, 500, 1200, 3000];
        var decayDefs = [0.17, 0.18, 0.15, 0.13];
        var ampDefs   = [0.07, 0.13, 0.11, 0.08];
        bands.do { |band, i|
            var col_x = 90 + (i * 95);
            mkFXKnob.(("freq"  ++ band).asSymbol, 20,   10000, \exp, 0,     freqDefs[i],  col_x, 152, { ~benjoResonator });
            mkFXKnob.(("decay" ++ band).asSymbol, 0.01, 8.0,   \exp, 0,     decayDefs[i], col_x, 246, { ~benjoResonator });
            mkFXKnob.(("amp"   ++ band).asSymbol, 0,    1.0,   \lin, 0.001, ampDefs[i],   col_x, 340, { ~benjoResonator });
            mkPolBtn.(band, col_x, 436);
        };
    }.value;

    fxWin.onClose = { btn.value_(0); onClose.() };

    // ── Chain order row ─── built last so errors can't hide sections ──────
    // 6 buttons + 5 arrows; buttons are 55 px wide, spaced 64 px apart.
    StaticText(fxWin, Rect(15, 41, 50, 18))
        .string_("CHAIN:")
        .font_(Font.sansSerif(9))
        .stringColor_(Color(0.5, 0.5, 0.5));

    4.do { |pos|
        var b = Button(fxWin, Rect(68 + (pos * 64), 37, 55, 26))
            .font_(Font.sansSerif(7, true))
            .action_({ selectSlot.(pos) });
        chainBtns[pos] = b;
    };
    refreshChainBtns.();   // set initial labels and colours

    [125, 189, 253].do { |ax|
        StaticText(fxWin, Rect(ax, 41, 14, 18))
            .string_("→")
            .font_(Font.sansSerif(10))
            .stringColor_(Color(0.35, 0.35, 0.45));
    };

    fxWin
}
