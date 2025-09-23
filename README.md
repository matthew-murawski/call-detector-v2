# Call Detector v2

This repository contains the second-generation heard-call detection pipeline, staging utilities, and tuning scripts. The detector consumes mono audio, applies a feature-rich hysteresis stack, and can optionally mask broadband noise via the Stage 0 noise detector.

## Stage 0 Noise Mask (optional)

Stage 0 runs before the heard-call detector to suppress broadband clutter. Enable it by setting the following fields in the parameters you pass to `run_detect_heard` or `run_detect_heard_chunked`:

```matlab
params.UseNoiseMask = true;
params.NoiseParams = NoiseParams(params.FsTarget); % customise as needed
params.NoiseLabelPath = 'noise_labels.txt';        % optional NOISE labels (set "" to skip)
```

To run Stage 0 on a waveform directly, use:

```matlab
segments = run_noise_on_wav_script('audio.wav', 'noise_labels.txt');
```

See `docs/NOISE_DETECTOR.md` for detailed documentation, parameter descriptions, and tuning guidance.

## Documentation

- [Stage 0 Noise Detector](docs/NOISE_DETECTOR.md)
- [Detector Tuning Guide](docs/detector_tuning.md)

## Tests

Run the full MATLAB suite:

```bash
./scripts/run_matlab_tests.sh
```
