function heard_labels = run_detect_heard(wavInput, producedInput, outLabelPath, params)
% orchestrate the mvp heard-call detector.

narginchk(4, 4);
add_local_paths();
params = apply_defaults(params);

% decode inputs and prepare dependencies.
[x, fs] = read_audio(wavInput);
[x, fs] = ensure_sample_rate(x, fs, params.FsTarget);
produced = normalise_intervals(producedInput);

y = bandpass_5to14k(x, fs);
[win_samples, hop_samples] = window_parameters(params, fs);
hop_seconds = hop_samples / fs;
[S, f, frame_time] = frame_spectrogram(y, fs, win_samples, hop_samples);
[S_weighted, coherence_map] = coherence_weight_spectrogram(S, f, hop_seconds, params.Coherence);
S_focus = apply_spectral_focus(S_weighted, f, params.FocusBand);
features = feat_energy_entropy_flux(S_focus, f, struct('energy', params.BP, 'entropy', params.EntropyBand));
frame_time = frame_time(:).';
self_mask = build_self_mask(size(S_weighted, 2), hop_seconds, produced, params.SelfPadPre, params.SelfPadPost);

noise_mask = false(size(self_mask));
noise_segments_stage0 = zeros(0, 2);
if params.UseNoiseMask
    noiseParamsLocal = normalise_noise_params(params.NoiseParams, fs, params.NoiseLabelPath, params.UseNoiseMask);
    [noiseMaskStage0, noise_segments_stage0] = run_detect_noise(x, fs, noiseParamsLocal);
    noise_mask = reshape(logical(noiseMaskStage0(:)), [], 1);
    if numel(noise_mask) < numel(self_mask)
        noise_mask(end+1:numel(self_mask)) = false;
    elseif numel(noise_mask) > numel(self_mask)
        noise_mask = noise_mask(1:numel(self_mask));
    end
    if params.NoiseHandlingMode == "hard"
        self_mask = logical(self_mask) | noise_mask;
    else
        self_mask = logical(self_mask);
    end
else
    self_mask = logical(self_mask);
end

% run hysteresis detection and tidy resulting segments.
[frame_in, thresh] = adaptive_hysteresis(features.energy, features.entropy, features.flux, features.tonal_ratio, features.flatness, self_mask, params);
segs = frames_to_segments(frame_in, hop_seconds);
segs = filter_by_entropy_coverage(segs, features.entropy, hop_seconds, thresh.entropy_thr, params.MinEntropyCoverage, features.tonal_ratio, thresh.broadband_entropy_thr, thresh.broadband_tonal_thr);
segs = postprocess_segments(segs, params);
if params.UseCalibrator && ~isempty(params.CalibratorPath)
    model = load_calibrator(params.CalibratorPath);
    segs = filter_with_calibrator(segs, x, fs, model, params.Coherence);
end
if params.UseNoiseMask && params.NoiseHandlingMode == "overlap"
    segs = filter_with_noise_segments(segs, noise_segments_stage0, params.NoiseDecision);
end
segs = remove_overlaps(segs, produced);
heard_labels = segs;

% write outputs for downstream tools.
if should_write(outLabelPath)
    labels = repmat("HEARD", size(segs, 1), 1);
    write_audacity_labels(char(outLabelPath), segs, labels);
end
end

function add_local_paths()
persistent has_added
if isempty(has_added)
    script_dir = fileparts(mfilename('fullpath'));
    root_dir = fileparts(script_dir);
    addpath(fullfile(root_dir, 'src', 'detect'));
    addpath(fullfile(root_dir, 'src', 'io'));
    addpath(fullfile(root_dir, 'src', 'mask'));
    addpath(fullfile(root_dir, 'src', 'label'));
    addpath(fullfile(root_dir, 'src', 'features'));
    addpath(genpath(fullfile(root_dir, 'src', 'noise')));
    addpath(fullfile(root_dir, 'src', 'learn'));
    has_added = true;
end
end

function params = apply_defaults(params)
if ~isstruct(params) || ~isscalar(params)
    error('run_detect_heard:InvalidParams', 'params must be a scalar struct.');
end
% backgroundtrim keeps noisy bursts from skewing thresholds later on.
coherence_defaults = struct(...
    'Enabled', true, ...
    'LogOffset', 1e-8, ...
    'GradKernel', 'central', ...
    'SigmaTime', 1.0, ...
    'SigmaFreq', 1.0, ...
    'TruncationRadius', 3, ...
    'Gain', 1.0, ...
    'Exponent', 1.0, ...
    'Clip', [0 1] ...
    );
defaults = struct(...
    'FsTarget', 48000, ...
    'Win', 0.025, ...
    'Hop', 0.010, ...
    'BP', [6000 12000], ...
    'EntropyBand', [6500 10000], ...
    'FocusBand', [6500 11000], ...
    'FlatnessQuantile', 0.90, ...
    'FlatnessSlack', 0.10, ...
    'MAD_Tlow', 0.8, ...
    'MAD_Thigh', 1.4, ...
    'EntropyQuantile', 0.40, ...
    'BackgroundTrim', 0.95, ...
    'FluxQuantileEnter', 0.70, ...
    'FluxQuantileStay', 0.40, ...
    'TonalityQuantileEnter', 0.78, ...
    'TonalityQuantileStay', 0.55, ...
    'BroadbandEntropySlack', 0.35, ...
    'BroadbandTonalityQuantile', 0.10, ...
    'MinEntropyCoverage', 0.35, ...
    'MinDur', 0.05, ...
    'MaxDur', 3.00, ...
    'MergeGap', 0.040, ...
    'CloseHole', 0.020, ...
    'SelfPadPre', 0.001, ...
    'SelfPadPost', 0.001, ...
    'UseCalibrator', false, ...
    'CalibratorPath', "", ...
    'Coherence', coherence_defaults, ...
    'UseNoiseMask', false, ...
    'NoiseParams', [], ...
    'NoiseLabelPath', "", ...
    'NoiseHandlingMode', "hard", ...
    'NoiseDecision', struct() ...
    );
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(params, name) || isempty(params.(name))
        params.(name) = defaults.(name);
    end
end
validateattributes(params.FsTarget, {'numeric'}, {'scalar', 'real', 'positive'});
validateattributes(params.Win, {'numeric'}, {'scalar', 'real', 'positive'});
validateattributes(params.Hop, {'numeric'}, {'scalar', 'real', 'positive'});
validateattributes(params.BP, {'numeric'}, {'vector', 'numel', 2, 'real', 'positive'});
validateattributes(params.EntropyBand, {'numeric'}, {'vector', 'numel', 2, 'real', 'positive'});
validateattributes(params.FocusBand, {'numeric'}, {'vector', 'numel', 2, 'real', 'positive'});
if params.FocusBand(1) >= params.FocusBand(2)
    error('run_detect_heard:InvalidFocusBand', 'FocusBand must be increasing.');
end
if params.FocusBand(2) >= params.FsTarget / 2
    error('run_detect_heard:InvalidFocusBand', 'FocusBand upper edge must be below nyquist.');
end
validateattributes(params.FlatnessQuantile, {'numeric'}, {'scalar', '>', 0, '<=', 1});
validateattributes(params.FlatnessSlack, {'numeric'}, {'scalar', '>=', 0});
validateattributes(params.MAD_Tlow, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.MAD_Thigh, {'numeric'}, {'scalar', 'real', 'nonnegative', '>=', params.MAD_Tlow});
validateattributes(params.BackgroundTrim, {'numeric'}, {'scalar', '>', 0, '<=', 1});
validateattributes(params.EntropyQuantile, {'numeric'}, {'scalar', '>', 0, '<', 1});
validateattributes(params.FluxQuantileEnter, {'numeric'}, {'scalar', '>', 0, '<', 1});
validateattributes(params.FluxQuantileStay, {'numeric'}, {'scalar', '>', 0, '<', 1});
if params.FluxQuantileStay > params.FluxQuantileEnter
    error('run_detect_heard:InvalidFluxQuantiles', 'FluxQuantileStay must be <= FluxQuantileEnter.');
end
validateattributes(params.TonalityQuantileEnter, {'numeric'}, {'scalar', '>', 0, '<', 1});
validateattributes(params.TonalityQuantileStay, {'numeric'}, {'scalar', '>', 0, '<', 1});
if params.TonalityQuantileStay > params.TonalityQuantileEnter
    error('run_detect_heard:InvalidTonalityQuantiles', 'TonalityQuantileStay must be <= TonalityQuantileEnter.');
end
validateattributes(params.BroadbandEntropySlack, {'numeric'}, {'scalar', '>=', 0});
validateattributes(params.BroadbandTonalityQuantile, {'numeric'}, {'scalar', '>=', 0, '<=', 1});
validateattributes(params.MinEntropyCoverage, {'numeric'}, {'scalar', 'real', '>=', 0, '<=', 1});
validateattributes(params.MinDur, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.MaxDur, {'numeric'}, {'scalar', 'real', 'positive', '>=', params.MinDur});
validateattributes(params.MergeGap, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.CloseHole, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.SelfPadPre, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.SelfPadPost, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.UseCalibrator, {'logical', 'numeric'}, {'scalar'});
if params.UseCalibrator
    if ~(isstring(params.CalibratorPath) && isscalar(params.CalibratorPath)) && ~ischar(params.CalibratorPath)
        error('run_detect_heard:InvalidCalibratorPath', 'CalibratorPath must be a char vector or string scalar when UseCalibrator is true.');
    end
end
params.Coherence = fill_coherence_defaults(params.Coherence);

if ~isfield(params, 'UseNoiseMask') || isempty(params.UseNoiseMask)
    params.UseNoiseMask = false;
end
params.UseNoiseMask = logical(params.UseNoiseMask);

if ~isfield(params, 'NoiseParams') || isempty(params.NoiseParams)
    ensure_noise_path();
    params.NoiseParams = NoiseParams(params.FsTarget);
end
if ~isstruct(params.NoiseParams) || ~isscalar(params.NoiseParams)
    error('run_detect_heard:InvalidNoiseParams', 'NoiseParams must be a scalar struct.');
end

if ~isfield(params, 'NoiseLabelPath') || isempty(params.NoiseLabelPath)
    params.NoiseLabelPath = "";
end
if ~(ischar(params.NoiseLabelPath) || (isstring(params.NoiseLabelPath) && isscalar(params.NoiseLabelPath)))
    error('run_detect_heard:InvalidNoiseLabelPath', 'NoiseLabelPath must be a char vector or string scalar.');
end

if ~isfield(params, 'NoiseHandlingMode') || isempty(params.NoiseHandlingMode)
    params.NoiseHandlingMode = "hard";
end
params.NoiseHandlingMode = string(params.NoiseHandlingMode);
validNoiseModes = ["hard", "overlap"];
if ~any(params.NoiseHandlingMode == validNoiseModes)
    error('run_detect_heard:InvalidNoiseHandlingMode', 'NoiseHandlingMode must be "hard" or "overlap".');
end

if ~isfield(params, 'NoiseDecision') || isempty(params.NoiseDecision)
    params.NoiseDecision = struct();
end
params.NoiseDecision = fill_noise_decision_defaults(params.NoiseDecision);
end

function noiseParams = normalise_noise_params(noiseParams, fs, labelPath, useNoiseMask)
if ~isstruct(noiseParams) || ~isscalar(noiseParams)
    error('run_detect_heard:InvalidNoiseParams', 'NoiseParams must be a scalar struct.');
end
noiseParams.SampleRate = fs;
if ~isfield(noiseParams, 'Output') || isempty(noiseParams.Output)
    noiseParams.Output = struct();
end
if ~isfield(noiseParams.Output, 'WriteNoiseLabels') || isempty(noiseParams.Output.WriteNoiseLabels)
    noiseParams.Output.WriteNoiseLabels = false;
end
if ~isfield(noiseParams.Output, 'LabelPath') || isempty(noiseParams.Output.LabelPath)
    noiseParams.Output.LabelPath = "";
end

if nargin >= 3
    if isstring(labelPath)
        labelStr = string(labelPath);
    elseif ischar(labelPath)
        labelStr = string(labelPath);
    else
        labelStr = string("");
    end
    hasLabel = useNoiseMask && strlength(labelStr) > 0;
    noiseParams.Output.WriteNoiseLabels = hasLabel;
    if hasLabel
        noiseParams.Output.LabelPath = char(labelStr);
    else
        noiseParams.Output.LabelPath = "";
    end
else
    noiseParams.Output.WriteNoiseLabels = false;
    noiseParams.Output.LabelPath = "";
end
end

function ensure_noise_path()
if exist('NoiseParams', 'file') ~= 2
    script_dir = fileparts(mfilename('fullpath'));
    root_dir = fileparts(script_dir);
    addpath(genpath(fullfile(root_dir, 'src', 'noise')));
end
end

function decision = fill_noise_decision_defaults(decision)
defaults = struct('MinOverlapFrac', 0.60, ...
    'MaxStartDiff', 0.12, ...
    'MaxEndDiff', 0.12);
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(decision, name) || isempty(decision.(name))
        decision.(name) = defaults.(name);
    end
end
validateattributes(decision.MinOverlapFrac, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1}, mfilename, 'NoiseDecision.MinOverlapFrac');
validateattributes(decision.MaxStartDiff, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0}, mfilename, 'NoiseDecision.MaxStartDiff');
validateattributes(decision.MaxEndDiff, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0}, mfilename, 'NoiseDecision.MaxEndDiff');
decision.MinOverlapFrac = double(decision.MinOverlapFrac);
decision.MaxStartDiff = double(decision.MaxStartDiff);
decision.MaxEndDiff = double(decision.MaxEndDiff);
end

function segs = filter_with_noise_segments(segs, noiseSegments, decision)
if isempty(segs) || isempty(noiseSegments)
    return;
end
keep = true(size(segs, 1), 1);
for idx = 1:size(segs, 1)
    seg = segs(idx, :);
    duration = max(seg(2) - seg(1), eps);
    for j = 1:size(noiseSegments, 1)
        noiseSeg = noiseSegments(j, :);
        overlap = max(0, min(seg(2), noiseSeg(2)) - max(seg(1), noiseSeg(1)));
        if overlap <= 0
            continue;
        end
        overlapFrac = overlap / duration;
        startDiff = abs(seg(1) - noiseSeg(1));
        endDiff = abs(seg(2) - noiseSeg(2));
        if overlapFrac >= decision.MinOverlapFrac && ...
                startDiff <= decision.MaxStartDiff && ...
                endDiff <= decision.MaxEndDiff
            keep(idx) = false;
            break;
        end
    end
end
segs = segs(keep, :);
end

function coherence = fill_coherence_defaults(coherence)
defaults = struct(...
    'Enabled', true, ...
    'LogOffset', 1e-8, ...
    'GradKernel', 'central', ...
    'SigmaTime', 1.0, ...
    'SigmaFreq', 1.0, ...
    'TruncationRadius', 3, ...
    'Gain', 1.0, ...
    'Exponent', 1.0, ...
    'Clip', [0 1] ...
    );
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(coherence, name) || isempty(coherence.(name))
        coherence.(name) = defaults.(name);
    end
end
validateattributes(coherence.Enabled, {'logical', 'numeric'}, {'scalar'});
coherence.Enabled = logical(coherence.Enabled);
validateattributes(coherence.LogOffset, {'numeric'}, {'scalar', 'real', '>', 0});
if ischar(coherence.GradKernel) || (isstring(coherence.GradKernel) && isscalar(coherence.GradKernel))
    coherence.GradKernel = char(coherence.GradKernel);
else
    error('run_detect_heard:InvalidCoherenceKernel', 'Coherence.GradKernel must be a string.');
end
validateattributes(coherence.SigmaTime, {'numeric'}, {'scalar', '>=', 0});
validateattributes(coherence.SigmaFreq, {'numeric'}, {'scalar', '>=', 0});
validateattributes(coherence.TruncationRadius, {'numeric'}, {'scalar', 'integer', '>=', 1});
validateattributes(coherence.Gain, {'numeric'}, {'scalar', 'real', '>=', 0});
validateattributes(coherence.Exponent, {'numeric'}, {'scalar', 'real', '>=', 0});
if isempty(coherence.Clip)
    coherence.Clip = [-inf inf];
else
    validateattributes(coherence.Clip, {'numeric'}, {'vector', 'numel', 2, 'real'});
    if coherence.Clip(1) > coherence.Clip(2)
        error('run_detect_heard:InvalidCoherenceClip', 'Coherence.Clip bounds must be non-decreasing.');
    end
end
coherence.Clip = double(coherence.Clip);
end

function [x, fs] = ensure_sample_rate(x, fs, target)
validateattributes(target, {'numeric'}, {'scalar', 'real', 'positive'});
[x, fs] = resample_if_needed(x, fs, target);
end

function intervals = normalise_intervals(input)
if isa(input, 'table')
    required = {'onset', 'offset'};
    if ~all(ismember(required, input.Properties.VariableNames))
        error('run_detect_heard:InvalidTable', 'table input must include onset and offset columns.');
    end
    intervals = [input.onset, input.offset];
elseif isnumeric(input)
    intervals = input;
elseif ischar(input) || (isstring(input) && isscalar(input))
    tbl = read_audacity_labels(input);
    intervals = [tbl.onset, tbl.offset];
elseif isempty(input)
    intervals = zeros(0, 2);
else
    error('run_detect_heard:InvalidProducedInput', 'produced labels must be numeric array, table, or label path.');
end
validateattributes(intervals, {'numeric'}, {'2d', 'ncols', 2});
if isempty(intervals)
    intervals = zeros(0, 2);
    return;
end
intervals = double(intervals);
if any(~isfinite(intervals(:)))
    error('run_detect_heard:InvalidProducedValues', 'produced labels must be finite.');
end
if any(intervals(:, 2) < intervals(:, 1))
    error('run_detect_heard:InvalidProducedOrder', 'produced labels must satisfy onset <= offset.');
end
intervals = sortrows(intervals, 1);
end

function [win_samples, hop_samples] = window_parameters(params, fs)
win_samples = max(1, round(params.Win * fs));
hop_samples = max(1, round(params.Hop * fs));
if hop_samples >= win_samples
    win_samples = hop_samples + 1;
end
end


function tf = should_write(outLabelPath)
if isempty(outLabelPath)
    tf = false;
    return;
end
if isstring(outLabelPath)
    tf = any(strlength(outLabelPath) > 0);
elseif ischar(outLabelPath)
    tf = ~isempty(outLabelPath);
else
    error('run_detect_heard:InvalidOutputPath', 'outLabelPath must be a char, string, or empty.');
end
end

function model = load_calibrator(path)
persistent cache;
if isempty(cache)
    cache = containers.Map();
end
key = char(path);
if isKey(cache, key)
    model = cache(key);
    return;
end
if exist(path, 'file') ~= 2
    error('run_detect_heard:CalibratorNotFound', 'Calibrator file not found: %s', path);
end
data = load(path, 'model');
if ~isfield(data, 'model')
    error('run_detect_heard:InvalidCalibratorFile', 'Calibrator file missing model struct.');
end
model = data.model;
cache(key) = model;
end

function segs = filter_with_calibrator(segs, x, fs, model, coherence_params)
if isempty(segs)
    return;
end

num_segments = size(segs, 1);
feature_rows = zeros(num_segments, 16);
for idx = 1:num_segments
    feature_rows(idx, :) = segment_features(x, fs, segs(idx, :), struct('Coherence', coherence_params));
end

[keep_idx, ~] = apply_calibrator(model, feature_rows);
segs = segs(keep_idx, :);
end
