function heard_labels = run_detect_heard(wavInput, producedInput, outLabelPath, params)
% orchestrate the mvp heard-call detector.

narginchk(4, 4);
params = apply_defaults(params);

% decode inputs and prepare dependencies.
add_local_paths();
[x, fs] = read_audio(wavInput);
[x, fs] = ensure_sample_rate(x, fs, params.FsTarget);
produced = normalise_intervals(producedInput);

y = bandpass_5to14k(x, fs);
[win_samples, hop_samples] = window_parameters(params, fs);
hop_seconds = hop_samples / fs;
[S, f, ~] = frame_spectrogram(y, fs, win_samples, hop_samples);
features = feat_energy_entropy_flux(S, f, struct('energy', params.BP, 'entropy', params.EntropyBand));
self_mask = build_self_mask(size(S, 2), hop_seconds, produced, params.SelfPadPre, params.SelfPadPost);

% run hysteresis detection and tidy resulting segments.
frame_in = adaptive_hysteresis(features.energy, features.entropy, self_mask, params);
segs = frames_to_segments(frame_in, hop_seconds);
segs = postprocess_segments(segs, params);
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
    has_added = true;
end
end

function params = apply_defaults(params)
if ~isstruct(params) || ~isscalar(params)
    error('run_detect_heard:InvalidParams', 'params must be a scalar struct.');
end
defaults = struct(...
    'FsTarget', 48000, ...
    'Win', 0.025, ...
    'Hop', 0.010, ...
    'BP', [5000 14000], ...
    'EntropyBand', [6000 10000], ...
    'MAD_Tlow', 0.8, ...
    'MAD_Thigh', 1.4, ...
    'EntropyQuantile', 0.35, ...
    'MinDur', 0.05, ...
    'MaxDur', 3.00, ...
    'MergeGap', 0.040, ...
    'CloseHole', 0.020, ...
    'SelfPadPre', 0.001, ...
    'SelfPadPost', 0.001 ...
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
validateattributes(params.MAD_Tlow, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.MAD_Thigh, {'numeric'}, {'scalar', 'real', 'nonnegative', '>=', params.MAD_Tlow});
validateattributes(params.EntropyQuantile, {'numeric'}, {'scalar', '>', 0, '<', 1});
validateattributes(params.MinDur, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.MaxDur, {'numeric'}, {'scalar', 'real', 'positive', '>=', params.MinDur});
validateattributes(params.MergeGap, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.CloseHole, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.SelfPadPre, {'numeric'}, {'scalar', 'real', 'nonnegative'});
validateattributes(params.SelfPadPost, {'numeric'}, {'scalar', 'real', 'nonnegative'});
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
