# BLUEPRINT: Stage 0 Noise‑Event Detection for the Marmoset Heard‑Call Pipeline

**Purpose:** Add a **pre‑call Stage 0** that detects **broadband noise events** in raw audio **before** any band‑pass or call‑specific processing. The stage outputs a **noise mask** and **noise segments** that are *unioned* with the existing produced/self mask so the heard‑call detector avoids labeling noise as calls.

**Motivation / problem to solve:** The current pipeline yields **false positives** when broadband noise plumes (vertical, wideband “slabs” in the spectrogram) are misinterpreted as calls. Detecting and masking these noise events upfront should **reduce false positives** without materially harming recall of true calls—even when noise and calls co‑occur.

---

## Scope

**In‑scope**
- A new **Stage 0: noise detection** that runs after audio I/O/resampling, **before** band‑pass, coherence boosting, and call detection.
- Two complementary, rule‑based detectors:
  1. **Multi‑band coincidence** (LOW / IN‑BAND / HIGH)
  2. **Coverage + flatness + OOB ratio** (spectral coverage, spectral flatness/entropy, out‑of‑band energy ratio)
- Fusion logic (OR by default) with an optional **tonality guard** to avoid masking genuine calls.
- Chunked processing support and stitching, matching the call pipeline.
- Tests: unit, synthetic end‑to‑end, and integration/e2e on real clips.
- Optional writer for **Audacity‑style NOISE labels** to aid QA.

**Out‑of‑scope (for now)**
- Heavy ML models. If needed later, a lightweight classifier can replace or augment rules.
- Re‑tuning the downstream call detector beyond accepting the new mask.

---

## High‑Level Dataflow

```
wav → (I/O, resample) → STAGE 0 (wideband STFT) →
   Detector (1): multi‑band coincidence ┐
                                        ├─ fuse (+ tonality guard) → noise frames → segments → noise mask
   Detector (2): coverage + flatness + OOB ┘

produced/self mask ∪ noise mask → final mask → STFT/coherence → features → call hysteresis → segments → (optional ML calibrator) → outputs
```

---

## Definitions and Signals

- **Wideband STFT**: single computation used by both detectors (no band‑pass).
- **Bands**:
  - **LOW**: below the in‑band vocal range (e.g., 0–5 kHz or 0.3–5 kHz)
  - **IN‑BAND**: ≈ **5–14 kHz**
  - **HIGH**: above in‑band up to Nyquist (subject to the device/sample rate)
- **Detector (1) Multi‑band coincidence**: a frame is noise if **≥N of 3** band gates are ON and **at least one** is out‑of‑band (LOW or HIGH). Gates are derived from **MAD‑based** energy thresholds per band.
- **Detector (2) Coverage + flatness + OOB**: a frame is noise if **coverage ≥ Cmin** AND **flatness ≥ Fmin** AND **OOB ratio ≥ Rmin**.
- **Tonality guard** (optional): if **in‑band tonality/peakiness** is strong, require stricter fusion (e.g., both detectors must agree) or demote to “soft mask.”
- **Hysteresis & morphology**: enter/exit thresholds + min duration + gap closing + pre/post padding to produce stable **segments**.
- **Noise outputs**: `noise_mask` (frame‑level), `noise_segments` (Nx2 seconds), optional NOISE label file.

---

## Parameters (NoiseParams)

- `BandsHz.Low = [L1 L2]` (e.g., `[0 5000]` or `[300 5000]`)
- `BandsHz.In  = [5000 14000]`
- `BandsHz.High = [H1 H2]` where `H2 ≤ Nyquist`; `H1 = 14000`
- `BandCoincidence.NRequired = 2`
- `BandCoincidence.RequireOOB = true` (require LOW or HIGH participation)
- `BandThresholds.method = "MAD"`
- `BandThresholds.kEnter = 1.2` (MAD multipliers; tune)
- `BandThresholds.kExit  = 0.8`
- `BandThresholds.RollingWindowSec = []` (global by default; set for rolling if needed)
- `Coverage.BinK = 1.0` (per‑frame median + K·MAD on (log‑)magnitude)
- `Coverage.CoverageMin = 0.60`
- `Flatness.FlatnessMin = 0.40` (or use entropy with EntropyMax)
- `OOB.RatioMin = 0.70` (outside/inside in‑band energy ratio)
- `Hysteresis.MinEventSec = 0.08`
- `Hysteresis.MaxEventSec = 5.00`
- `Hysteresis.GapCloseSec = 0.04`
- `Hysteresis.PrePadSec = 0.05`
- `Hysteresis.PostPadSec = 0.05`
- `TonalityGuard.Enable = true`
- `TonalityGuard.InBandTonalityThresh = <set experimentally>`
- `TonalityGuard.Mode = "soft" or "strict"` (start with “strict” → both detectors required when tonality is high)
- `Output.WriteNoiseLabels = false`

**Guidance:** Start with conservative thresholds that **prefer precision** on noise (better to miss some noise than to hide calls).

---

## Risks and Mitigations

- **Risk: masking true calls during overlap with noise.**  
  *Mitigations*: tonality guard; modest pre/post pads; conservative thresholds; evaluate recall on call‑heavy clips.
- **Risk: environment variability (rooms, cages, devices).**  
  *Mitigations*: MAD‑based robust baselines; parameter sweeps; optional rolling baselines.
- **Risk: chunk boundary errors.**  
  *Mitigations*: match call pipeline overlap & stitching; boundary unit tests.

---

## Evaluation and Acceptance Criteria

- **Primary target**: ≥ **50% reduction** in false positives on curated noise‑heavy clips **after** introducing the noise mask.
- **Recall guard**: ≤ **5–10%** recall drop on call‑heavy clips (tunable).
- **Operational**: Stage 0 runs in chunked mode and stitches correctly; NOISE labels aid QA; parameters documented.

---

## Iterative Chunks (coarse‑to‑fine)

### Chunk A — Foundations & Interfaces
- New module `src/noise/` + params + validation.
- Wideband STFT helper (or reuse existing util).
- Unit tests for params and STFT shapes.

### Chunk B — Detector (1): Multi‑band coincidence
- Per‑band energy envelopes (LOW/IN/HIGH).
- MAD thresholds → per‑band gates + 1D hysteresis.
- N‑of‑3 + “must include OOB” rule → frame flags.
- Hysteresis/morphology → `noise_segments_1`.

### Chunk C — Detector (2): Coverage + flatness + OOB
- Per‑frame coverage, flatness (or entropy), OOB ratio.
- Joint gate → frame flags → segments (`noise_segments_2`).

### Chunk D — Fusion, Guards, Masking
- Framewise fusion (OR), optional tonality guard (strict/soft).
- Frames → segments → `noise_mask`; optional NOISE labels.
- Unit tests on overlapped call+noise scenarios.

### Chunk E — Pipeline Integration & E2E
- Insert Stage 0 into main runners (single & chunked).
- `final_mask = produced_mask ∪ noise_mask` for the call detector.
- E2E tests on synthetic and real regression clips.
- Debug/QA plotting helpers; parameter sweep script.

---

## Small, Safe Steps within Each Chunk

### Chunk A — steps
1. Create `src/noise/` and add a short README header (what/why/where).
2. Implement `NoiseParams` (defaults, docstrings).
3. Implement `validate_noise_params` (range checks, band sanity, Nyquist awareness).
4. Implement `noise_compute_spectrogram` (mono downmix; window/hop defaults; magnitude output).
5. Tests: params creation/validation; STFT shape & time/frequency vectors.

### Chunk B — steps
1. `band_energy_envelopes`: integrate magnitudes per band (normalize by bin count).
2. `robust_band_thresholds`: global (or rolling) median + MAD → enter/exit thresholds.
3. `band_gates`: boolean per band with 1D hysteresis.
4. `coincidence_gate`: count bands; require ≥N and (if enabled) at least one OOB band.
5. `hysteresis_and_segments`: min duration, gap‑closing, pre/post pad → segments.
6. Tests: synthetic slabs spanning bands trigger; pure in‑band ridge alone does not; segments are padded/merged correctly.

### Chunk C — steps
1. `spectral_coverage`: per‑frame fraction above adaptive bin threshold (median + K·MAD on log‑mag or mag—be consistent).
2. `spectral_flatness`: geometric/arith mean ratio (or entropy alternative).
3. `oob_ratio`: outside/inside in‑band energy (handle zero‑division).
4. `coverage_flatness_oob_gate`: joint gate + 1D hysteresis → frames→segments.
5. Tests: broadband slabs → high coverage/flatness/OOB; narrowband ridges → lower metrics.

### Chunk D — steps
1. `inband_tonality_score`: peakiness inside in‑band (e.g., peak/mean or peak/top‑K mean).
2. `fuse_noise_frames`: OR of detectors; if tonality strong and guard enabled, require agreement (strict) or mark as “soft.”
3. `frames_to_noise_segments` and `noise_segments_to_mask`: produce segments/mask aligned to time frames.
4. Optional `write_noise_labels`: Audacity label file (“NOISE”).
5. Tests: fusion logic with and without tonality guard; overlap behaviors; mask correctness; label file sanity.

### Chunk E — steps
1. Update main call runners to invoke Stage 0 and union masks.
2. Synthetic e2e: injected broadband bursts reduce call FPs; verify calls remain.
3. Real e2e regression: known noise‑FP clip improves; track metrics.
4. Debug plots: wideband spectrogram with overlays (produced/calls/noise).
5. Parameter sweep script for quick tuning; print table & recommended preset.

---

## Ready‑to‑Use Prompts for a Code‑Generation LLM

Each prompt is self‑contained, incremental, and test‑first. Paste and run them in order. Replace paths only if your repo layout differs.

```text
[PROMPT 1 — create module scaffold & params]

Goal: create a new Stage 0 "noise detection" module scaffold with params.

Tasks:
1) Create folder src/noise and add a brief README-style header in a new file src/noise/README_NOISE_DETECTOR.m that explains the goal of Stage 0 and where it sits in the pipeline.
2) Create src/noise/NoiseParams.m as a function that returns a struct with documented defaults:
   - BandsHz: struct with fields Low=[L1 L2], In=[5000 14000], High=[H1 H2]; choose L1=0 (or 300) and H2 = min(0.45*fs, nyquist) at runtime
   - BandCoincidence: NRequired=2, RequireOOB=true
   - BandThresholds: method="MAD", kEnter=1.2, kExit=0.8, RollingWindowSec=[]
   - Coverage: BinK=1.0 (MAD multiplier), CoverageMin=0.60
   - Flatness: FlatnessMin=0.4 (or EntropyMax option if implemented)
   - OOB: RatioMin=0.7
   - Hysteresis: MinEventSec=0.08, MaxEventSec=5.0, GapCloseSec=0.04, PrePadSec=0.05, PostPadSec=0.05
   - TonalityGuard: Enable=true, InBandTonalityThresh= [describe], Mode="soft"
   - Output: WriteNoiseLabels=false
3) Provide a validate function src/noise/validate_noise_params.m that checks ranges, ensures bands do not overlap improperly, and warns if sample rate is too low for the configured High band.
4) Add unit tests in tests/noise/test_noise_params.m covering default creation and validation failures.

Style: follow my MATLAB comment rules (lowercase section comments; concise inline comments only when needed). Use clear, intention-revealing function names.

Deliverables:
- src/noise/README_NOISE_DETECTOR.m
- src/noise/NoiseParams.m
- src/noise/validate_noise_params.m
- tests/noise/test_noise_params.m
```

```text
[PROMPT 2 — wideband spectrogram helper]

Goal: implement a single wideband spectrogram utility for Stage 0.

Tasks:
1) Create src/noise/noise_compute_spectrogram.m with signature:
   [S, f, t] = noise_compute_spectrogram(y, fs, opts)
   - Use stft or spectrogram with window/hop matching the main pipeline defaults if available; otherwise default to 25 ms window, 10 ms hop, hann window. Return magnitude (not power).
   - Ensure S is real, non-negative magnitudes; handle mono or stereo by downmixing to mono (mean).
   - Provide opts.WindowSec, opts.HopSec, opts.NFFT optional overrides.
2) Add defensive checks for short signals and NaNs.
3) Unit tests in tests/noise/test_noise_spectrogram.m:
   - shape correctness
   - time/frequency vectors monotonicity
   - consistent duration accounting (reconstruct approx number of frames)

Deliverables:
- src/noise/noise_compute_spectrogram.m
- tests/noise/test_noise_spectrogram.m
```

```text
[PROMPT 3 — band energy envelopes]

Goal: compute per-frame band energy for LOW / IN / HIGH.

Tasks:
1) Create src/noise/band_energy_envelopes.m:
   [bandEnergy, bandsUsed] = band_energy_envelopes(S, f, bandsHz)
   - Integrate |S| across frequency bins within each band (LOW/IN/HIGH) to produce a T-length vector per band.
   - Normalize by number of bins to be robust to different band widths.
   - Return bandEnergy as a table or struct with fields Low, In, High, each 1xT.
2) Unit tests in tests/noise/test_band_energy_envelopes.m with synthetic S:
   - A slab occupying LOW+IN lights up Low and In but not High.
   - A slab occupying IN+HIGH lights up In and High but not Low.
   - Pure in-band ridge lights In >> Low/High.

Deliverables:
- src/noise/band_energy_envelopes.m
- tests/noise/test_band_energy_envelopes.m
```

```text
[PROMPT 4 — robust thresholds & band gates]

Goal: convert band energy envelopes to boolean band-on signals with MAD-based thresholds.

Tasks:
1) Create src/noise/robust_band_thresholds.m:
   thresholds = robust_band_thresholds(bandEnergy, method, k, rollingWindowFrames)
   - method="MAD" supported initially; compute baseline median and MAD (global or rolling if window provided).
   - Return per-band enter/exit thresholds; allow distinct kEnter/kExit.
2) Create src/noise/band_gates.m:
   [gateLow, gateIn, gateHigh] = band_gates(bandEnergy, thresholds)
   - gate = energy >= thresholdEnter; provide a simple 1D hysteresis so frames only drop when below thresholdExit.
3) Unit tests in tests/noise/test_band_gates.m:
   - With synthetic envelopes and injected bursts, gates rise and fall as expected.
   - Rolling window behavior (if used) maintains stability.

Deliverables:
- src/noise/robust_band_thresholds.m
- src/noise/band_gates.m
- tests/noise/test_band_gates.m
```

```text
[PROMPT 5 — N-of-3 coincidence rule + OOB constraint]

Goal: implement the multi-band coincidence detector.

Tasks:
1) Create src/noise/coincidence_gate.m:
   noiseFrames = coincidence_gate(gateLow, gateIn, gateHigh, NRequired, requireOOB)
   - Count how many bands are ON; require ≥ NRequired and (if requireOOB) at least one of Low or High ON.
2) Create src/noise/hysteresis_and_segments.m:
   segments = hysteresis_and_segments(noiseFrames, t, params)
   - Apply min duration, gap-closing, pre/post pad (all from NoiseParams.Hysteresis).
   - Return Nx2 start/stop times in seconds.
3) Unit tests in tests/noise/test_coincidence_detector.m:
   - Simulated slabs spanning multiple bands are detected.
   - Pure in-band ridge alone is NOT detected unless Low or High also fires.
   - Hysteresis yields coherent segments with correct padding.

Deliverables:
- src/noise/coincidence_gate.m
- src/noise/hysteresis_and_segments.m
- tests/noise/test_coincidence_detector.m
```

```text
[PROMPT 6 — coverage, flatness, oob features]

Goal: implement features for the coverage+flatness+OOB rule.

Tasks:
1) Create src/noise/spectral_coverage.m:
   coverage = spectral_coverage(S, method)
   - For each frame, compute the fraction of bins with magnitude above (per-frame median + K*MAD) on log-magnitude or magnitude scale (choose and document).
2) Create src/noise/spectral_flatness.m:
   flatness = spectral_flatness(S)
   - Use geometric mean / arithmetic mean per frame (on power or magnitude^2; choose and be consistent).
3) Create src/noise/oob_ratio.m:
   ratio = oob_ratio(S, f, inBandHz)
   - ratio = energy outside inBand / energy inside inBand, per frame (handle zero-division).
4) Unit tests in tests/noise/test_noise_features.m using synthetic frames:
   - Broadband slab → high coverage, high flatness, high OOB when slab is outside in-band.
   - Narrowband ridge → lower coverage, lower flatness, low OOB.

Deliverables:
- src/noise/spectral_coverage.m
- src/noise/spectral_flatness.m
- src/noise/oob_ratio.m
- tests/noise/test_noise_features.m
```

```text
[PROMPT 7 — coverage+flatness+OOB gate + segments]

Goal: turn features into a second detector with hysteresis.

Tasks:
1) Create src/noise/coverage_flatness_oob_gate.m:
   noiseFrames2 = coverage_flatness_oob_gate(coverage, flatness, oob, params)
   - Use params.Coverage.CoverageMin, params.Flatness.FlatnessMin, params.OOB.RatioMin.
   - Boolean AND of the three; add simple 1D hysteresis (enter/exit).
2) Reuse hysteresis_and_segments.m to produce segments2.
3) Unit tests in tests/noise/test_coverage_flatness_oob_detector.m with synthetic slabs vs ridges.

Deliverables:
- src/noise/coverage_flatness_oob_gate.m
- tests/noise/test_coverage_flatness_oob_detector.m
```

```text
[PROMPT 8 — optional tonality guard]

Goal: avoid masking genuine calls that have strong in-band tonality.

Tasks:
1) Create src/noise/inband_tonality_score.m:
   tonality = inband_tonality_score(S, f, inBandHz)
   - Suggest: peak-to-mean or (max bin)/(mean of top-K) inside in-band per frame.
2) Create src/noise/fuse_noise_frames.m:
   fusedFrames = fuse_noise_frames(noiseFrames1, noiseFrames2, tonality, params)
   - Default: OR of noiseFrames1 and noiseFrames2.
   - If params.TonalityGuard.Enable and tonality >= threshold, then either:
     (a) require both detectors to agree (stricter), or
     (b) demote to "soft mask" (return both a hard fusedFrames and a softNoiseFrames if you support soft masking downstream).
   - Start with option (a) for simplicity and document behavior.
3) Unit tests in tests/noise/test_fuse_noise_frames.m covering high-tonality in-band events.

Deliverables:
- src/noise/inband_tonality_score.m
- src/noise/fuse_noise_frames.m
- tests/noise/test_fuse_noise_frames.m
```

```text
[PROMPT 9 — frames→mask and label writer]

Goal: convert frames to segments/mask and optional labels for QA.

Tasks:
1) Create src/noise/frames_to_noise_segments.m:
   segments = frames_to_noise_segments(fusedFrames, t, params)
   - reuse hysteresis_and_segments internally or factor shared utilities.
2) Create src/noise/noise_segments_to_mask.m:
   noiseMask = noise_segments_to_mask(segments, t)
   - Return a logical vector aligned with t.
3) Create src/noise/write_noise_labels.m (optional):
   write_noise_labels(segments, outPath)
   - Write Audacity-style label file with text "NOISE".
4) Unit tests in tests/noise/test_mask_and_labels.m:
   - Mask covers the intended frames.
   - Label file has expected number of rows and ascending times.

Deliverables:
- src/noise/frames_to_noise_segments.m
- src/noise/noise_segments_to_mask.m
- src/noise/write_noise_labels.m
- tests/noise/test_mask_and_labels.m
```

```text
[PROMPT 10 — Stage 0 orchestrator (single file)]

Goal: provide a single entry point to run noise detection on an audio vector.

Tasks:
1) Create src/noise/run_detect_noise.m:
   [noiseMask, noiseSegments, noiseMeta] = run_detect_noise(y, fs, noiseParams)
   - Steps: spectrogram → band energies → gates → coincidence frames → segments1
            spectral coverage/flatness/OOB → frames2 → segments2
            fuse frames (with optional tonality guard) → segments → mask
   - Return timings, params used, and feature snippets in noiseMeta for debugging.
   - If noiseParams.Output.WriteNoiseLabels and a path is supplied, write labels.
2) Unit tests in tests/noise/test_run_detect_noise.m:
   - Synthetic broadband bursts are detected into segments.
   - Narrowband ridges alone do not trigger unless overlapping with out-of-band.

Deliverables:
- src/noise/run_detect_noise.m
- tests/noise/test_run_detect_noise.m
```

```text
[PROMPT 11 — Chunked version + stitching]

Goal: support long recordings via chunked processing with overlap.

Tasks:
1) Create src/noise/run_detect_noise_chunked.m:
   [noiseMask, noiseSegments, meta] = run_detect_noise_chunked(wavPathOrAudio, noiseParams, chunkOpts)
   - Mirror your heard-call chunker: fixed window length, overlap, edge guards.
   - Stitch per-chunk masks/segments into global time.
2) Tests in tests/noise/test_run_detect_noise_chunked.m:
   - Ensure events near chunk boundaries are not split or dropped.
   - Compare chunked vs non-chunked on a moderate-length synthetic.

Deliverables:
- src/noise/run_detect_noise_chunked.m
- tests/noise/test_run_detect_noise_chunked.m
```

```text
[PROMPT 12 — Pipeline integration: mask union]

Goal: integrate Stage 0 into the existing heard-call pipeline.

Tasks:
1) Identify the main entry points for call detection (single-file and chunked).
2) Add a toggle in the call runner params: UseNoiseMask=true/false and NoiseParams=NoiseParams().
3) Compute produced/self mask as you do today. Then call run_detect_noise (or chunked) to get noiseMask.
4) Union masks: finalMask = producedMask | noiseMask. Pass finalMask into the subsequent call-detection stages exactly where producedMask was previously used.
5) If you support label outputs already, offer an optional NOISE label output path for QA.
6) Add integration tests in tests/e2e/test_pipeline_with_noise_mask.m:
   - Curated clip where the current pipeline mislabels noise as calls: assert FP reduction after adding noise.
   - Clip with overlapping faint twitter + broadband: assert recall remains within an acceptable delta; log overlap for review.

Deliverables:
- Updated call-detection runner(s) to insert Stage 0 and union masks
- tests/e2e/test_pipeline_with_noise_mask.m
```

```text
[PROMPT 13 — Debug visualization helpers]

Goal: make QA easy.

Tasks:
1) Create scripts/plot_noise_mask_overlay_script.m:
   - Inputs: wavPath, optional produced labels path, optional noise labels path
   - Show wideband spectrogram, overlay noise segments (semi-transparent), produced segments, and later call segments for comparison.
2) Create a convenience script scripts/run_noise_on_wav_script.m to run Stage 0 on a WAV and write NOISE labels.

Deliverables:
- scripts/plot_noise_mask_overlay_script.m
- scripts/run_noise_on_wav_script.m
```

```text
[PROMPT 14 — Parameter sweeps & report]

Goal: quick tuning feedback.

Tasks:
1) Create scripts/tune_noise_params_script.m:
   - Sweep key thresholds (NRequired, CoverageMin, FlatnessMin, RatioMin, kEnter/kExit).
   - On a small dev set (synthetic + 2–3 real clips), compute:
     - Noise precision/recall vs hand labels (if available) OR proxy metrics (FP reduction in call detector).
   - Print a short table and recommend a default preset.

Deliverables:
- scripts/tune_noise_params_script.m
```

```text
[PROMPT 15 — Documentation]

Goal: keep the project coherent.

Tasks:
1) Update or create docs/NOISE_DETECTOR.md:
   - What the stage does, where it sits, parameters, guardrails, limitations.
   - Instructions to run the visualization and tuning scripts.
2) Add a short section in your main README referencing Stage 0 and how to enable it.

Deliverables:
- docs/NOISE_DETECTOR.md
- README updates
```

---

## Implementation Order and Rationale

1. **Scaffold & params** → everything else can plug into a consistent config.
2. **Wideband STFT** → single source of truth for both detectors.
3. **Detector (1)** → simple, fast, high‑precision on obvious broadband slabs.
4. **Detector (2)** → catches tricky broadband cases with flatness/coverage/OOB.
5. **Fusion + guard** → conservative behavior to protect calls.
6. **Mask + labels** → concrete outputs for quick QA.
7. **Chunked + stitching** → ready for long recordings.
8. **Pipeline integration** → FP reduction where it matters.
9. **Debug plots & tuning** → iterate thresholds quickly.
10. **Docs** → durability and onboarding.

---

## Final Notes for the Implementer (LLM or human)

- Keep sections small and testable. Avoid big leaps.
- Prefer **precision** on noise; start strict, then relax if recall allows.
- Always compare before/after FP rates on curated clips and watch call recall on “hard” clips with overlapping faint twitters.
- Keep thresholds and band edges documented and easily tunable.
