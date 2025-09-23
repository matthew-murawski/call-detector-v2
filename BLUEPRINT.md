
# BLUEPRINT.md — Marmoset Call Detector (MATLAB)

## 1) What we want to do (short version)
Detect **perceived calls** (calls from any animal other than the target) in colony-room audio recorded from a **single reference microphone**. We will **mask** time around the target animal’s **produced** calls (which we have fully labeled), then run a **transparent rule‑based detector** with adaptive thresholds to propose call segments, optionally followed by a **lightweight machine‑learning calibrator** to reduce false positives. We export **Audacity label tracks** (onset/offset in seconds) for downstream neural analyses.

---

## 2) Why we want to do this
- We need **as many perceived calls as possible** to study neural responses in frontal cortex during natural calling contexts.
- Manual labeling is slow and inconsistent. A transparent baseline with light learning gives **high recall** early, and **precision** improves as we add labels.
- The pipeline must be **robust across sessions**, **easy to tune**, and **auditable** (clear parameters, deterministic tests, and interpretable steps).

---

## 3) Scope and constraints
- **Scope**: onset/offset **detection** of non‑target calls using a reference mic. **No caller ID** and **no call‑type classification** in v1.
- **Inputs**: `.wav` audio for each session; Audacity‑style labels for the target animal’s **produced** calls; optional human labels for **perceived** and **silence** (for training/calibration).
- **Outputs**: Audacity label file with detected **HEARD** segments.
- **Constraints**: colony noise, overlapping calls, variable SNR, and session‑to‑session drift. Favor **recall**. Keep methods simple, tested, and fast.

---

## 4) Success criteria (measurable)
- **Functional**: end‑to‑end script detects heard calls and writes valid Audacity labels; easy to run on a folder of sessions.
- **Quantitative** (on labeled sessions):
  - **Recall ≥ 0.85** at working threshold (tuneable), **Precision ≥ 0.65** for MVP + calibrator (targets initial; improved later).
  - **Onset error** median ≤ 40 ms; **Offset error** median ≤ 80 ms.
- **Quality**: deterministic unit tests for each module; synthetic fixtures pass **e2e** tests; clear parameterization and logging.

---

## 5) System architecture (folders and responsibilities)
```
marmoset-detector/
  scripts/                 % entry points (single session & batch)
  src/
    io/                    % read audio, read/write labels
    mask/                  % build self mask from produced labels
    detect/                % bandpass, frame features, hysteresis, postprocess
    features/              % segment descriptors for ML calibrator
    learn/                 % train/apply calibrator; active learning selection
    eval/                  % metrics, onset/offset error
    util/                  % time↔frame helpers, interval ops, config
  tests/                   % matlab.unittest suites (fast, deterministic)
  models/                  % saved calibrator(s)
  examples/                % demo scripts and plots
  README.md                % usage, parameters, troubleshooting
```
**Design principles**
- Pure functions; pass parameters explicitly.
- Tests first; small, composable modules.
- Clear defaults; all thresholds centralized.

---

## 6) Detection pipeline (v1 MVP)
1. **Read inputs**: audio `(x, fs)` and **produced** labels (onset/offset seconds).
2. **Resample** to a standard rate (e.g., 24 kHz) for consistency (optional if already suitable).
3. **Band‑pass** filter to 5–14 kHz (zero‑phase) to focus on marmoset energy.
4. **Frame** with 25 ms window, 10 ms hop; compute spectrogram.
5. **Frame features**:
   - **Band‑limited energy** (5–14 kHz)
   - **Band‑limited spectral entropy** (6–10 kHz)
   - **Spectral flux** (emphasize positive changes/onsets)
6. **Self mask**: mark frames within `[onset−pad_pre, offset+pad_post]` around **produced** calls to suppress target animal. Start with `pad_pre=1.0 s`, `pad_post=0.5 s`.
7. **Adaptive hysteresis**:
   - Estimate **median** and **MAD** of energy on **non‑masked** frames (session‑specific noise floor).
   - Enter a candidate when `energy > Thigh` **AND** `entropy < Ethr`.
   - Stay inside while `energy > Tlow` **OR** `entropy < Ethr`.
   - Thresholds: `Tlow = median + a*MAD`, `Thigh = median + b*MAD` (defaults `a=2.0, b=3.5`); `Ethr` as the 20th percentile of entropy over non‑masked frames.
8. **Frames → segments**: contiguous runs → `[onset, offset]` seconds.
9. **Post‑processing**:
   - Remove segments `< MinDur` or `> MaxDur` (start with `0.05–3.0 s`).
   - **Merge** gaps ≤ 40 ms; **close holes** ≤ 20 ms.
10. **Subtract self**: discard any segment overlapping the self mask.
11. **Write Audacity labels**: tab‑separated with `onset`, `offset`, `label` (e.g., `HEARD`).

**Audacity label format** (TSV; 6 decimal places):
```
<onset_seconds>    <offset_seconds>    HEARD
```
Example:
```
12.345000    12.812000    HEARD
```

---

## 7) Optional ML calibrator (v1.5)
- **Goal**: reduce false positives with minimal recall loss.
- **Inputs**: MVP segments (candidates), plus labeled **perceived** (positives) and **silence** (negatives). Add “hard negatives” from typical false positives (e.g., cage clangs).
- **Features** (per segment; 20–40 dims):
  - Duration; energy stats (mean, p10/p50/p90) 5–14 kHz; entropy stats 6–10 kHz; flux stats.
  - Sub‑band ratios (e.g., 6–9 kHz / 9–12 kHz).
  - Envelope shape: rise/fall times, max slope.
  - Δ‑features vs a 1–2 s rolling median.
- **Model**: logistic regression or linear SVM with z‑scoring.
- **CV**: leave‑one‑session‑out. Choose threshold τ to hit target recall (e.g., 0.85) on validation. Save to `models/calibrator.mat`.
- **Inference**: score each candidate and keep those with `score ≥ τ`.

---

## 8) Parameters (initial defaults)
```
FsTarget         = 24000
BP               = [5000 14000]     % band-pass Hz
Win              = 0.025            % frame window (s)
Hop              = 0.010            % frame hop (s)
EntropyBand      = [6000 10000]     % Hz
MAD_Tlow         = 2.0
MAD_Thigh        = 3.5
EntropyQuantile  = 0.20             % threshold from quantile of entropy
MinDur           = 0.05             % s
MaxDur           = 3.00             % s
MergeGap         = 0.040            % s
CloseHole        = 0.020            % s
SelfPadPre       = 1.00             % s
SelfPadPost      = 0.50             % s
UseCalibrator    = true
CalibratorPath   = 'models/calibrator.mat'
ScoreThreshold   = 0.45             % tuned via CV
```

---

## 9) Right‑sized iterative plan

### Milestones → Tasks → Small steps (each step testable)

**M1 — Repo & utilities**
- Create layout; small helpers (`timevec`, `merge_intervals`); synthetic audio fixture (`make_synth_colony_track`).

**M2 — IO**
- Read/write Audacity labels; read audio (path or struct).

**M3 — Self mask**
- Frame‑grid mask from produced labels with padding.

**M4 — Preprocess**
- Resample; band‑pass with verified frequency response.

**M5 — Frame features**
- Spectrogram; energy/entropy/flux per frame.

**M6 — Hysteresis**
- MAD thresholds on non‑masked frames; entropy gate; frames→segments.

**M7 — Post‑process & subtract self**
- Min/Max duration; merge & close gaps; remove any segment overlapping self.

**M8 — End‑to‑end MVP**
- Single entry point; write Audacity labels; e2e test on synthetic track.

**M9 — Segment features (ML)**
- 20–40 feature vector per segment.

**M10 — Train/apply calibrator**
- Fit logistic/SVM with LOSO‑CV; save model; pipeline filter with τ.

**M11 — Evaluation**
- Event F1/precision/recall with IoU≥0.5; onset/offset errors; session tables.

**M12 — Active learning**
- Uncertainty (≈0.5 scores) and novelty (Mahalanobis) selection; export review lists.

**M13 — Batch/config**
- Batch detect over a folder; JSON config → params struct; session summaries.

**M14 — Examples/docs**
- Demo script; visual overlays; README.

**Review for size**: Every step is small, testable, and useful alone. Each milestone ends with at least one passing e2e or integration test; there are no orphaned modules.

---

## 10) Testing strategy
- **Unit**: utilities, mask, preprocess, features, hysteresis, postprocess, IO.
- **Integration**: MVP on synthetic track (known truth; assert detection count and timing).
- **Model**: calibrator LOSO‑CV; sanity AUC and threshold behavior.
- **System**: batch over two synthetic sessions; produce outputs and summary.
- **Determinism**: synthetic fixtures with fixed seeds; explicit tolerances (e.g., ±20 ms).

---

## 11) Risks and mitigations
- **Overlapping calls** → hole‑closing + gap‑merging; entropy gate; consider intra‑segment entropy peaks for later splitting.
- **Impulsive noises** → add as hard negatives; calibrator learns to reject.
- **Drifting noise floors** → Δ‑features vs rolling median; MAD thresholds per session.
- **Self leakage** → widen `SelfPadPre/Post`; always subtract self overlaps before output.
- **Parameter brittleness** → centralize defaults; add config; evaluate per session and log metrics.

---

## 12) Logging & reproducibility
- Runner returns a **log struct**: thresholds, counts, durations, merge stats, % frames masked, and timing per stage.
- Save params used into each output folder.
- Version control; tests in CI (future: MATLAB GitHub Actions).

---

## 13) Pseudocode (runner)
```matlab
function heard_labels = run_detect_heard(input, produced, outPath, P)

% io
[x, fs] = read_audio(input);
[x, fs] = resample_if_needed(x, fs, P.FsTarget);
y = bandpass_5to14k(x, fs);

% frames and features
[S, f, t] = frame_spectrogram(y, fs, P.Win, P.Hop);
fe = feat_energy_entropy_flux(S, f, struct('energy',P.BP, 'entropy',P.EntropyBand));

% self mask
nFrames = numel(t);
mask = build_self_mask(nFrames, P.Hop, produced, P.SelfPadPre, P.SelfPadPost);

% detection
frame_in = adaptive_hysteresis(fe.energy, fe.entropy, fe.flux, fe.tonal_ratio, fe.flatness, mask, P);
segs = frames_to_segments(frame_in, P.Hop);
segs = postprocess_segments(segs, P);
segs = remove_overlaps(segs, produced);

% optional ML filter
if P.UseCalibrator && isfile(P.CalibratorPath)
    X = features_for_segments(x, fs, segs);    % wrapper on segment_features
    [keep, scores] = apply_calibrator(load(P.CalibratorPath), X);
    segs = segs(keep, :);
end

% write output
labels = repmat("HEARD", size(segs,1), 1);
if ~isempty(outPath), write_audacity_labels(outPath, segs, labels); end
heard_labels = segs;
end
```

---

## 14) What “done” looks like (v1 and v1.5)
- **v1 (MVP)**: `run_detect_heard` produces high‑recall heard labels from reference audio; tests pass; parameters adjustable via config; batch script works.
- **v1.5 (Calibrated)**: trained logistic/SVM model filters MVP candidates; improved precision with small recall loss; evaluation reports available; active‑learning export exists.

---

## 15) Glossary
- **Perceived call**: a call produced by any animal **other than** the target; detected on a reference mic.
- **Produced call**: a call produced by the target animal (fully labeled per session).
- **Self mask**: padded windows around produced calls, used to prevent detecting the target animal.
- **Hysteresis**: two‑threshold logic (enter high, exit low) to stabilize detections.
- **MAD**: median absolute deviation; robust spread estimate for adaptive thresholds.
- **IoU**: intersection‑over‑union between predicted and true segments.
