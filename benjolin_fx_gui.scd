// ============================================================
// Benjolin — FX Window
// Loaded by benjolin_gui.scd via .load — do not evaluate directly.
//
// Returns a factory function with signature:
//   { |btn, screen, winW, winH, presetWinW, onClose| -> Window }
//
//   btn         — the FX toggle Button (reset to 0 when window closes)
//   screen      — Window.screenBounds
//   winW/winH   — main window dimensions (used for positioning)
//   presetWinW  — preset window width (used for x offset)
//   onClose     — zero-arg function called after window closes
//                 (lets the caller nil its fxWin reference)
// ============================================================

{ |btn, screen, winW, winH, presetWinW, onClose|
    var fxWinW = 410, fxWinH = 440;
    var fxX    = (screen.width - winW - 8 - presetWinW) / 2;
    var fxY    = (screen.height - winH) / 2 + winH + 8;
    var fxWin;

    var mkFXKnob = { |name, lo, hi, warp, step, def, x, y|
        var spec = ControlSpec(lo, hi, warp, step, def);
        var k = EZKnob(
            fxWin, Rect(x, y, 80, 90),
            name.asString, spec,
            { |ez| ~benjoFX !? { ~benjoFX.set(name, ez.value) } },
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
        k
    };

    var mkFXLabel = { |text, x, y|
        StaticText(fxWin, Rect(x, y, 380, 20))
            .string_(text)
            .font_(Font.sansSerif(9))
            .stringColor_(Color(0.4, 0.6, 0.9));
    };

    var mkOnBtn = { |paramName, x, y|
        Button(fxWin, Rect(x, y, 80, 34))
            .states_([
                ["OFF", Color(0.5, 0.5, 0.5), Color(0.13, 0.13, 0.15)],
                ["ON",  Color(0.3, 1.0, 0.5),  Color(0.08, 0.2,  0.1) ]
            ])
            .font_(Font.sansSerif(10, true))
            .action_({ |b| ~benjoFX !? { ~benjoFX.set(paramName, b.value) } })
    };

    fxWin = Window("Benjolin FX",
        Rect(fxX, fxY, fxWinW, fxWinH)
    ).background_(Color(0.07, 0.07, 0.09)).front;

    StaticText(fxWin, Rect(15, 10, 200, 20))
        .string_("EFFECTS")
        .font_(Font.sansSerif(13, true))
        .stringColor_(Color.white);

    // ── DELAY ────────────────────────────────────────
    mkFXLabel.("── DELAY ─── ping-pong ─────────────────────", 15, 42);
    mkOnBtn.(\delayOn,        15, 70);
    mkFXKnob.(\delayTime,     10, 1000, \exp, 0,     250,  110, 52);
    mkFXKnob.(\delayFeedback,  0, 0.95, \lin, 0.001, 0.4,  205, 52);
    mkFXKnob.(\delayMix,       0, 1.0,  \lin, 0.001, 0.3,  300, 52);

    // ── REVERB ───────────────────────────────────────
    mkFXLabel.("── REVERB ───────────────────────────────────", 15, 160);
    mkOnBtn.(\reverbOn,      15, 188);
    mkFXKnob.(\reverbRoom,    0, 1.0, \lin, 0.001, 0.6, 110, 170);
    mkFXKnob.(\reverbDamp,    0, 1.0, \lin, 0.001, 0.5, 205, 170);
    mkFXKnob.(\reverbMix,     0, 1.0, \lin, 0.001, 0.3, 300, 170);

    // ── RESONATOR ────────────────────────────────────
    mkFXLabel.("── RESONATOR ─── harmonic Ringz bank ────────", 15, 278);
    mkOnBtn.(\resonOn,       15, 306);
    mkFXKnob.(\resonFreq,   20, 2000, \exp, 0,     200,  110, 288);
    mkFXKnob.(\resonDecay,   0.1, 8.0, \exp, 0,    1.5,  205, 288);
    mkFXKnob.(\resonMix,     0,   1.0, \lin, 0.001, 0.25, 300, 288);

    fxWin.onClose = { btn.value_(0); onClose.() };

    fxWin  // return the window so the caller can hold a reference
}
