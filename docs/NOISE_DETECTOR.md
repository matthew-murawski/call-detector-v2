# Stage 0 Noise Detector

Stage 0 is a broadband noise gate that runs ahead of the heard‑call detector. It scans the raw waveform for high-energy broadband spans, derives per-band statistics, and produces a mask of time intervals that downstream stages treat as preexisting noise. When Stage 0 is enabled, its mask is unioned with the existing produced/self mask so the main detector ignores regions that are dominated by broadband clutter.

## Pipeline placement

1. **Input** – mono audio vector (resampled to the detector rate).
2. **Wideband spectrogram** – see `src/noise/spectrogram/noise_compute_spectrogram.m`.
3. **Band energy envelopes** – Stage 0 integrates low/in/high subbands (`src/noise/features/band_energy_envelopes.m`).
4. **Robust thresholds + coincidence** – MAD-based band thresholds and N-of-3 coincidence gating (`src/noise/gating`).
5. **Feature gates** – coverage/flatness/out-of-band checks add a second opinion (`src/noise/gating/coverage_flatness_oob_gate.m`).
6. **Tonality guard + fusion** – prevents purely tonal in-band events from being masked (`src/noise/gating/fuse_noise_frames.m`).
7. **Hysteresis + segments/mask** – produces merged intervals and a frame-aligned logical mask (`src/noise/segments`).
8. **Output** – mask, segments, metadata, optional NOISE label file (`src/noise/pipeline` + `src/noise/output`).

These outputs are consumed by `run_detect_heard` (and the chunked variant), which merge Stage 0’s mask with the produced/self mask before hysteresis.

## Parameters and guardrails

`NoiseParams(fs)` returns the default configuration. Key groups:

- **BandsHz** – low/in/high edges adjust to the provided sample rate.
- **BandCoincidence** – `NRequired` (default 2) and `RequireOOB` enforce how many subbands must fire and whether an out-of-band band must participate.
- **BandThresholds** – MAD method, entry/exit multipliers, and an optional rolling window (seconds) for adaptive baselines.
- **Coverage / Flatness / OOB** – thresholds applied to coverage fraction, spectral flatness (0–1), and out-of-band energy ratio.
- **Hysteresis** – min/max event length, gap closing, and pre/post padding in seconds.
- **TonalityGuard** – enables a soft guard that requires both detectors to agree when strong tonal ridges are present.
- **Output** – `WriteNoiseLabels` + `LabelPath` control optional NOISE label emission during orchestration.

Validation is enforced by `validate_noise_params` to catch overlapping bands, invalid thresholds, and Nyquist violations. Stage 0 always clamps negative or NaN features to safe defaults.

## Limitations

- Designed for broadband clutter; extremely narrowband interference should be handled via tonality guard settings.
- The default MAD thresholds assume moderate broadband coverage; for extremely quiet recordings tune `CoverageMin`/`FlatnessMin` upward.
- Currently single-channel; ensure multi-channel audio is downmixed prior to the stage (handled automatically in orchestrators).
- Label exporting is optional; if you need per-chunk labels during chunked runs, pass a `NoiseLabelPath` to `run_detect_heard_chunked`.

## Running Stage 0 manually

- **Single file orchestration**: `run_detect_noise(x, fs, noiseParams)` returns mask, segments, and rich metadata.
- **Chunked orchestration**: `run_detect_noise_chunked(wavPathOrAudio, noiseParams, chunkOpts)` handles long recordings with overlaps and edge guards.
- **CLI helper**: `scripts/run_noise_on_wav_script.m` wraps the chunked path and writes NOISE labels for a WAV file:
  ```matlab
  segments = run_noise_on_wav_script('input.wav', 'noise_labels.txt');
  ```

## Visualization and tuning

1. **Inspect metadata** – `run_detect_noise` returns `noiseMeta` containing band energies, thresholds, masks, and tonality scores. Plot these against `noiseMeta.Time` to visualise gating behaviour.
2. **Adjust parameters** – clone the struct from `NoiseParams(fs)` and tweak the relevant sub-struct fields (coverage, flatness, thresholds) before re-running the stage.
3. **Use the CLI script** – iterate on WAV files with `run_noise_on_wav_script` while adjusting `noiseParams` and `chunkOpts` for quick QA.
4. **End-to-end tune** – enable Stage 0 in the heard detector (see README Stage 0 section) and leverage existing calibration/tuning scripts. When running `tune_detector_params`, pass the same `NoiseParams` via your detector function to evaluate the impact across a corpus.

Refer to `docs/detector_tuning.md` for broader calibration guidance; Stage 0 integrates seamlessly with that workflow once enabled.
