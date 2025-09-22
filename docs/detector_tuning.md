# Detector Parameter Tuning

`tune_detector_params` explores detection hyperparameters by running `run_detect_heard` across a corpus of sessions that include audio plus human "heard", "produced", and "silence" label intervals. Each parameter combination is scored with recall (fraction of heard intervals covered by detections) and precision (true positives over total predicted segments). Segments that overlap produced or silence annotations count toward false positives, so the search emphasises quiet-call recall without letting precision collapse.

## Running the tuner

1. Assemble a corpus struct array where each element exposes:
   - `audio`: wav path or struct with fields `x` (column vector) and `fs` (Hz).
   - `heard`, `produced`, `silence`: `n×2` numeric onset/offset arrays (seconds) or tables with those columns.
2. Define the parameter grid as a struct whose fields list candidate values (numeric vectors or cell arrays).
3. Optionally set options such as `MinPrecision`, `OverlapThreshold`, `BaseParams`, and `SavePath`.
4. Invoke the tuner from MATLAB:

```matlab
corpus = struct('audio', struct('x', audio_samples, 'fs', 48000), ...
    'heard', heard_intervals, ...
    'produced', produced_intervals, ...
    'silence', silence_intervals);
paramGrid = struct('MAD_Tlow', 0.7:0.1:1.0, 'MAD_Thigh', 1.3:0.1:1.6);
opts = struct('MinPrecision', 0.75);
results = tune_detector_params(corpus, paramGrid, opts);
```

By default the best-performing parameter set is saved to `models/detector_params.json`. Supply a different `SavePath` (or an empty string) when you want to write elsewhere or skip persistence.

## Regenerating shipped parameters

Recreate the checked-in parameter file by rerunning the tuner with the same corpus and grid definition that were used to generate it. Capture the corpus assembly (e.g., collecting per-session audio and label paths) and the grid configuration in a MATLAB script, then execute:

```matlab
results = tune_detector_params(corpus, paramGrid, struct());
```

The `results` struct contains per-combination precision/recall values, making it easy to audit trade-offs before updating `models/detector_params.json`.
