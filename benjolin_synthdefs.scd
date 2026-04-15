// ============================================================
// Benjolin — SynthDefs
// Loaded by benjolin_gui.scd via .load — do not evaluate directly.
//
// LocalIn/Out bus layout (8 channels):
// [0] runglerCV [1] loopBit [2] triA [3] triB
// [4] pulseA [5] pulseB [6] xorOut [7] pwm
//
// Route indices (modARoute / modBRoute / modFRoute):
// 0=NONE 1=TRI A 2=TRI B 3=PULSE A 4=PULSE B
// 5=XOR 6=RUNGLER 7=PWM
//
// Defaults mirror the hardware normalized connections:
// MOD A ← TRI B (2)
// MOD B ← TRI A (1)
// MOD F ← TRI B (2)
//
// Effects chain (nine separate, reorderable synths + output stage):
// \distortion  — soft saturate + hard clip  (Tommi Keränen autohazard)
// \delay       — dual BufCombL comb delay, independent L/R times  (Tommi Keränen)
// \reverb      — FreeVerb2 stereo reverb
// \flanger     — BufCombC + LFTri comb flanger  (Tommi Keränen)
// \detuner     — BufCombC + LFDNoise3 chorus/detuner  (Tommi Keränen)
// \phasor      — BufAllpassC + SinOsc allpass phaser  (Tommi Keränen)
// \ringmod     — ring modulator, selectable carrier waveform  (Tommi Keränen)
// \pitchShifter — granular pitch shifter (PitchShift)
// \eq          — 31-band graphic EQ (MidEQ chain, Tommi Keränen)
// \benjoOut    — reads from ~benjoBus, clips, writes to hardware
//
// All FX synths use ReplaceOut.ar so they read from and write
// back to the same bus. Synth.moveAfter / moveBefore can reorder them
// at runtime without audio dropout.
// ============================================================

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

    // Chaos attractor — all four run simultaneously; Select picks the active one
    // GbmanN and StandardN can have large excursions — clip keeps them in -1..1
    chaosRaw = Select.ar(chaosSource, [
        DC.ar(0),                                                                     // 0 = OFF
        HenonC.ar(chaosRate, 1.4, 0.3).clip(-1, 1),                                  // 1 = Hénon
        GbmanN.ar(chaosRate).clip(-1, 1),                                             // 2 = Gingerbread Man
        StandardN.ar(chaosRate, 1.0).clip(-1, 1),                                    // 3 = Standard Map
        Gendy1.ar(2, 2, 1.0, 1.0, chaosRate * 0.5, chaosRate * 3, 0.5, 0.5, 12).clip(-1, 1), // 4 = Gendy stochastic
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
    // chaosRaw is smoothed here — GbmanN/StandardN produce instantaneous jumps
    // that cause audible noise when fed directly into Pan2 at audio rate.
    panPos = (pan + Select.ar(panRoute, sources ++ [Lag.ar(chaosRaw, 0.05)]) * panMod).clip(-1, 1);

    Out.ar(out, Pan2.ar(mono, panPos));

}).add;

// ── Effects SynthDefs ─────────────────────────────────────────
// Each reads from ~benjoBus (stereo) via In.ar, processes, and
// writes back via ReplaceOut.ar — so they can be reordered in
// the server node graph at runtime (Synth.moveAfter/moveBefore)
// without recompilation and without audio dropout.
//
// \benjoOut is the terminal stage: reads ~benjoBus, hard-clips,
// writes to hardware. It must always run last.

SynthDef(\distortion, {
| bus=0,
distOn=0, distDrive=1.0, distMix=1.0 |

    var sig  = In.ar(bus, 2);
    var wet  = (sig * distDrive).distort.clip2(1.0);
    var xmix = distMix * distOn * 2 - 1;
    ReplaceOut.ar(bus, XFade2.ar(sig, wet, xmix));

}).add;

SynthDef(\delay, {
| bus=0,
delayOn=0, delLeftTime=0.5, delRightTime=0.5,
delLeftDecay=0.0, delRightDecay=0.0, delayMix=0.5 |

    var sig  = In.ar(bus, 2);
    var lbuf = LocalBuf(SampleRate.ir * 5.0, 1);
    var rbuf = LocalBuf(SampleRate.ir * 5.0, 1);
    // LeakDC removes DC from comb resonance; tanh soft-limits so high decay
    // times can't blow out the signal before the XFade crossfade.
    var lWet = LeakDC.ar(BufCombL.ar(lbuf, sig[0], delLeftTime.clip(0.001, 5.0),  delLeftDecay)).tanh;
    var rWet = LeakDC.ar(BufCombL.ar(rbuf, sig[1], delRightTime.clip(0.001, 5.0), delRightDecay)).tanh;
    var xmix = delayMix * delayOn * 2 - 1;
    ReplaceOut.ar(bus, [
        XFade2.ar(sig[0], lWet, xmix),
        XFade2.ar(sig[1], rWet, xmix)
    ]);

}).add;

SynthDef(\reverb, {
| bus=0,
reverbOn=0, reverbRoom=0.6, reverbDamp=0.5, reverbMix=0.3 |

    var sig = In.ar(bus, 2);
    var smoothReverbMix = LagUD.kr(reverbMix * reverbOn, 0.3, 3.0);
    var revWet = FreeVerb2.ar(sig[0] * reverbOn, sig[1] * reverbOn, 1.0, reverbRoom, reverbDamp);
    ReplaceOut.ar(bus, sig + (revWet * smoothReverbMix));

}).add;

SynthDef(\flanger, {
| bus=0,
flangerOn=0, flangerRate=0.5, flangerRange=100.0,
flangerFeedback=0.0, flangerMix=0.5 |

    var sig      = In.ar(bus, 2);
    var lbuf     = LocalBuf.new(SampleRate.ir, 1);
    var rbuf     = LocalBuf.new(SampleRate.ir, 1);
    var delRange = flangerRange.max(1).reciprocal;
    var mod      = LFTri.kr(flangerRate, 0, delRange * 0.5, delRange * 0.5) + 0.0001;
    var lout     = LeakDC.ar(BufCombC.ar(lbuf, sig[0], mod, flangerFeedback));
    var rout     = LeakDC.ar(BufCombC.ar(rbuf, sig[1], mod, flangerFeedback));
    var wet      = [lout, rout];
    ReplaceOut.ar(bus, sig + ((wet - sig) * flangerMix * flangerOn));

}).add;

SynthDef(\eq, {
| bus=0, eqOn=0 |
var sig = In.ar(bus, 2);
var channelGain = Control.names([\channelGain]).kr(Array.fill(31, 0));
var freqs = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
200, 250, 315, 400, 500, 630, 800, 1000, 1250,
1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
10000, 12500, 16000, 20000];
var processed = sig;
freqs.do { |midfreq, i|
processed = MidEQ.ar(processed, midfreq, (1/6), Lag.kr(channelGain.at(i), 0.05));
};
ReplaceOut.ar(bus, sig + ((processed - sig) * eqOn.lag(0.05)));
}).add;

SynthDef(\pitchShifter, {
| bus=0,
pitchOn=0, pitchShift=1.0, pitchMix=0.5,
pitchWinSize=0.2, pitchPchD=0.0, pitchTimeD=0.0 |

    var sig = In.ar(bus, 2);
    // PitchShift needs winSize >= 0.02 to avoid clicks; shift must be > 0
    var wet = PitchShift.ar(sig, pitchWinSize.max(0.02), pitchShift.max(0.0001), pitchPchD, pitchTimeD);
    // Crossfade: pitchOn=0 → dry pass-through; pitchOn=1 → blend dry/wet via pitchMix
    ReplaceOut.ar(bus, sig + ((wet - sig) * pitchMix * pitchOn));

}).add;

SynthDef(\detuner, {
| bus=0,
detunerOn=0, detunerRate=50.0, detunerRange=500.0,
detunerFeedback=0.0, detunerMix=0.5 |

    var sig   = In.ar(bus, 2);
    var range = detunerRange.abs.max(10).reciprocal.min(0.1);
    var lbuf  = LocalBuf(SampleRate.ir, 1);
    var rbuf  = LocalBuf(SampleRate.ir, 1);
    var mod   = LFDNoise3.kr(detunerRate.max(0.01), range * 0.5, range * 0.5);
    var lWet  = LeakDC.ar(BufCombC.ar(lbuf, sig[0], mod.clip(0.0001, 0.099), detunerFeedback));
    var rWet  = LeakDC.ar(BufCombC.ar(rbuf, sig[1], mod.clip(0.0001, 0.099), detunerFeedback));
    var xmix  = detunerMix * detunerOn * 2 - 1;
    ReplaceOut.ar(bus, [XFade2.ar(sig[0], lWet, xmix), XFade2.ar(sig[1], rWet, xmix)]);

}).add;

SynthDef(\phasor, {
| bus=0,
phasorOn=0, phasorRate=0.5, phasorRange=100.0,
phasorFeedback=0.0, phasorMix=0.5 |

    var sig   = In.ar(bus, 2);
    var range = phasorRange.max(1).reciprocal;
    var lbuf  = LocalBuf(SampleRate.ir + 100, 1);
    var rbuf  = LocalBuf(SampleRate.ir + 100, 1);
    var mod   = (SinOsc.ar(phasorRate + 0.0001, 0, range * 0.5, range * 0.5) + 0.001).clip(0.001, 0.999);
    var lWet  = LeakDC.ar(BufAllpassC.ar(lbuf, sig[0], mod, phasorFeedback));
    var rWet  = LeakDC.ar(BufAllpassC.ar(rbuf, sig[1], mod, phasorFeedback));
    var xmix  = phasorMix * phasorOn * 2 - 1;
    ReplaceOut.ar(bus, [XFade2.ar(sig[0], lWet, xmix), XFade2.ar(sig[1], rWet, xmix)]);

}).add;

SynthDef(\ringmod, {
| bus=0,
ringOn=0, ringFreq=500.0, ringWave=0, ringPulseWidth=0.5, ringMix=0.5 |

    var sig     = In.ar(bus, 2);
    var carrier = Select.ar(ringWave, [
        SinOsc.ar(ringFreq),
        Pulse.ar(ringFreq, ringPulseWidth),
        Saw.ar(ringFreq)
    ]);
    var wet  = sig * carrier;
    var xmix = ringMix * ringOn * 2 - 1;
    ReplaceOut.ar(bus, XFade2.ar(sig, wet, xmix));

}).add;

SynthDef(\benjoOut, {
| in=0, out=0 |
// Terminal stage: hard-clip and write to hardware.
// Must always run after the nine FX synths.
Out.ar(out, In.ar(in, 2).clip2(0.95));
}).add;
