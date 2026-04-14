// ============================================================
// Benjolin — FX Window
// Loaded by benjolin_gui.scd via .load — do not evaluate directly.
//
// Returns a factory function with signature:
//   { |btn, screen, winW, winH, presetWinW, onClose, fxState, fxKnobs| -> Window }
//
// Chain reorder UI:
//   Three labelled buttons at the top show the current processing
//   order. Click one to select it (turns green). Click a second to
//   swap those two effects and update the server node graph via
//   Synth.moveAfter / moveBefore. Click the same button twice to
//   deselect without swapping.
//
//   Chain order is not saved in presets; resets when window closes.
// ============================================================

{ |btn, screen, winW, winH, presetWinW, onClose, fxState, fxKnobs|
    var fxWinW = 410, fxWinH = 480;
    var fxX    = (screen.width - winW - 8 - presetWinW) / 2;
    var fxY    = (screen.height - winH) / 2 + winH + 8;
    var fxWin;

    // chainOrder[slot] = effect index: 0=resonator 1=delay 2=reverb
    var chainOrder   = [0, 1, 2];
    var chainNames   = ["RESONATOR", "DELAY", "REVERB"];
    var chainBtns    = [nil, nil, nil];
    var selectedSlot = nil;   // slot index of the currently armed button, or nil

    var applyChainOrder = {
        var synths  = [~benjoRes, ~benjoDelay, ~benjoReverb];
        var ordered = chainOrder.collect({ |ei| synths[ei] });
        ordered[0] !? {
            ordered[0].moveBefore(~benjoOut);
            ordered[1] !? { ordered[1].moveAfter(ordered[0]) };
            ordered[2] !? { ordered[2].moveAfter(ordered[1]) };
            ~benjoOut  !? { ~benjoOut.moveAfter(ordered[2])  };
        };
    };

    // Redraw all three chain buttons to reflect chainOrder and selectedSlot.
    var refreshChainBtns = {
        3.do { |i|
            chainBtns[i] !? { |b|
                var armed = (i == selectedSlot);
                b.states_([[
                    chainNames[chainOrder[i]],
                    armed.if(Color.white,           Color(0.72, 0.72, 1.0)),
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

    // ── Build window ──────────────────────────────────────
    fxWin = Window("Benjolin FX",
        Rect(fxX, fxY, fxWinW, fxWinH)
    ).background_(Color(0.07, 0.07, 0.09)).front;

    StaticText(fxWin, Rect(15, 10, 200, 20))
        .string_("EFFECTS")
        .font_(Font.sansSerif(13, true))
        .stringColor_(Color.white);

    // ── RESONATOR ─────────────────────────────────────────
    mkFXLabel.("── RESONATOR ─── harmonic Ringz bank ────────", 15, 80);
    mkOnBtn.(\resonOn,       15, 108, { ~benjoRes });
    mkFXKnob.(\resonFreq,   20, 2000, \exp, 0,      200,  110, 90, { ~benjoRes });
    mkFXKnob.(\resonDecay,   0.1, 8.0, \exp, 0,     1.5,  205, 90, { ~benjoRes });
    mkFXKnob.(\resonMix,     0,   1.0, \lin, 0.001, 0.25, 300, 90, { ~benjoRes });

    // ── DELAY ─────────────────────────────────────────────
    mkFXLabel.("── DELAY ─── ping-pong ─────────────────────", 15, 198);
    mkOnBtn.(\delayOn,        15, 226, { ~benjoDelay });
    mkFXKnob.(\delayTime,     10, 1000, \exp, 0,     250,  110, 208, { ~benjoDelay });
    mkFXKnob.(\delayFeedback,  0, 0.95, \lin, 0.001, 0.4,  205, 208, { ~benjoDelay });
    mkFXKnob.(\delayMix,       0, 1.0,  \lin, 0.001, 0.3,  300, 208, { ~benjoDelay });

    // ── REVERB ────────────────────────────────────────────
    mkFXLabel.("── REVERB ───────────────────────────────────", 15, 316);
    mkOnBtn.(\reverbOn,      15, 344, { ~benjoReverb });
    mkFXKnob.(\reverbRoom,    0, 1.0, \lin, 0.001, 0.6, 110, 326, { ~benjoReverb });
    mkFXKnob.(\reverbDamp,    0, 1.0, \lin, 0.001, 0.5, 205, 326, { ~benjoReverb });
    mkFXKnob.(\reverbMix,     0, 1.0, \lin, 0.001, 0.3, 300, 326, { ~benjoReverb });

    fxWin.onClose = { btn.value_(0); onClose.() };

    // ── Chain order row ─── built last so errors can't hide sections ──────
    StaticText(fxWin, Rect(15, 41, 50, 18))
        .string_("CHAIN:")
        .font_(Font.sansSerif(9))
        .stringColor_(Color(0.5, 0.5, 0.5));

    3.do { |pos|
        var b = Button(fxWin, Rect(68 + (pos * 114), 37, 100, 26))
            .font_(Font.sansSerif(10, true))
            .action_({ selectSlot.(pos) });
        chainBtns[pos] = b;
    };
    refreshChainBtns.();   // set initial labels and colours

    [172, 286].do { |ax|
        StaticText(fxWin, Rect(ax, 41, 16, 18))
            .string_("→")
            .font_(Font.sansSerif(10))
            .stringColor_(Color(0.35, 0.35, 0.45));
    };

    fxWin
}
