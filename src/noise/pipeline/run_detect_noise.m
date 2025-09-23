function [noiseMask, noiseSegments, noiseMeta] = run_detect_noise(y, fs, noiseParams)
% run_detect_noise orchestrates stage 0 noise detection over an audio vector.

narginchk(2, 3);
if nargin < 3 || isempty(noiseParams)
    noiseParams = NoiseParams(fs);
end

validateattributes(y, {'numeric'}, {'nonempty'}, mfilename, 'y');
validateattributes(fs, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'fs');
y = double(y);
fs = double(fs);
if size(y, 1) == 1 && size(y, 2) > 1
    y = y.';
end
if size(y, 2) > 1
    y = mean(y, 2);
end
y = y(:);

noiseParams.SampleRate = fs;
validate_noise_params(noiseParams, fs);

[S, f, t] = noise_compute_spectrogram(y, fs);
if isempty(S)
    noiseMask = false(1, numel(t));
    noiseSegments = zeros(0, 2);
    noiseMeta = struct('SampleRate', fs, 'Time', t(:).', 'Spectrogram', struct('S', S, 'f', f), ...
        'Params', noiseParams);
    return;
end

bandEnergy = band_energy_envelopes(S, f, noiseParams.BandsHz);
frameStep = estimate_frame_step(t);
rollingWindowFrames = [];
if ~isempty(noiseParams.BandThresholds.RollingWindowSec)
    rollingWindowFrames = max(1, round(noiseParams.BandThresholds.RollingWindowSec / frameStep));
end
kStruct = struct('Enter', noiseParams.BandThresholds.kEnter, 'Exit', noiseParams.BandThresholds.kExit);
bandThresholds = robust_band_thresholds(bandEnergy, noiseParams.BandThresholds.method, kStruct, rollingWindowFrames);
[gateLow, gateIn, gateHigh] = band_gates(bandEnergy, bandThresholds);

coincidenceFrames = coincidence_gate(gateLow, gateIn, gateHigh, noiseParams.BandCoincidence.NRequired, noiseParams.BandCoincidence.RequireOOB);
segmentsBand = hysteresis_and_segments(coincidenceFrames, t, noiseParams.Hysteresis);

coverage = spectral_coverage(S);
flatness = spectral_flatness(S);
oob = oob_ratio(S, f, noiseParams.BandsHz.In);
featureFrames = coverage_flatness_oob_gate(coverage, flatness, oob, noiseParams);
segmentsFeature = hysteresis_and_segments(featureFrames, t, noiseParams.Hysteresis);

tonality = inband_tonality_score(S, f, noiseParams.BandsHz.In);
fusedFrames = fuse_noise_frames(coincidenceFrames, featureFrames, tonality, noiseParams);
noiseSegments = frames_to_noise_segments(fusedFrames, t, noiseParams);
noiseMask = noise_segments_to_mask(noiseSegments, t);

noiseMeta = struct();
noiseMeta.SampleRate = fs;
noiseMeta.Time = t(:).';
noiseMeta.Params = noiseParams;
noiseMeta.Spectrogram = struct('S', S, 'f', f);
noiseMeta.BandEnergy = bandEnergy;
noiseMeta.BandThresholds = bandThresholds;
noiseMeta.BandGates = struct('Low', gateLow, 'In', gateIn, 'High', gateHigh);
noiseMeta.CoincidenceFrames = coincidenceFrames;
noiseMeta.CoincidenceSegments = segmentsBand;
noiseMeta.Coverage = coverage;
noiseMeta.Flatness = flatness;
noiseMeta.OOBRatio = oob;
noiseMeta.FeatureFrames = featureFrames;
noiseMeta.FeatureSegments = segmentsFeature;
noiseMeta.Tonality = tonality;
noiseMeta.FusedFrames = fusedFrames;
noiseMeta.Segments = noiseSegments;

if noiseParams.Output.WriteNoiseLabels && isfield(noiseParams.Output, 'LabelPath') && ~isempty(noiseParams.Output.LabelPath)
    write_noise_labels(noiseSegments, noiseParams.Output.LabelPath);
end
end

function step = estimate_frame_step(t)
t = double(t(:).');
if numel(t) < 2
    step = 0.010;
    return;
end
step = median(diff(t));
if ~isfinite(step) || step <= 0
    span = max(t) - min(t);
    if span <= 0
        step = 0.010;
    else
        step = span / max(1, numel(t) - 1);
    end
end
end
