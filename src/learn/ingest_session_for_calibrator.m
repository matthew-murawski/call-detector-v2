function [tbl, extras] = ingest_session_for_calibrator(wavPath, producedLabels, heardLabels, silenceLabels, params, opts)
% ingest_session_for_calibrator builds a feature table for calibrator training.

narginchk(4, 6);
if nargin < 5 || isempty(params)
    params = struct();
end
if nargin < 6 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts) || ~isscalar(opts)
    error('ingest_session_for_calibrator:InvalidOpts', 'opts must be a scalar struct.');
end

opts = fill_ingest_defaults(opts);

add_ingest_paths();

[x, fs] = read_audio(wavPath);
[x, fs] = resample_if_needed(x, fs, opts.FsTarget);
x_struct = struct('x', x, 'fs', fs);

produced = load_intervals(producedLabels);
heard = load_intervals(heardLabels);
silence = load_intervals(silenceLabels);

session_id = determine_session_id(wavPath, opts);

if ~isfield(params, 'FsTarget') || isempty(params.FsTarget)
    params.FsTarget = opts.FsTarget;
end

function add_ingest_paths()
persistent has_added
if isempty(has_added)
    here = fileparts(mfilename('fullpath'));
    root_dir = fileparts(here);
    addpath(fullfile(root_dir, 'detect'));
    addpath(fullfile(root_dir, 'features'));
    addpath(fullfile(root_dir, 'io'));
    addpath(fullfile(root_dir, 'mask'));
    addpath(fullfile(root_dir, 'label'));
    has_added = true;
end
end

if ~isempty(opts.DetectorCandidates)
    candidates = opts.DetectorCandidates;
else
    candidates = run_detect_heard(x_struct, produced, [], params);
end

candidate_rows = build_rows_from_segments(x, fs, candidates, heard, silence, session_id, opts, 'detected');
silence_rows = build_rows_from_segments(x, fs, silence, heard, silence, session_id, opts, 'silence');

candidate_rows = candidate_rows(:);
silence_rows = silence_rows(:);
all_rows = [candidate_rows; silence_rows];

if isempty(all_rows)
    tbl = table();
    extras = struct('session_id', session_id, 'num_candidates', size(candidates, 1));
    return;
end

feature_names = {'duration', 'energy_mean', 'energy_p10', 'energy_p50', 'energy_p90', ...
    'entropy_mean', 'entropy_p10', 'entropy_p50', 'entropy_p90', ...
    'flux_mean', 'flux_p50', 'flux_p90', 'subband_ratio', 'rise_time', 'fall_time', 'max_slope'};

feature_matrix = vertcat(all_rows.features);

tbl = array2table(feature_matrix, 'VariableNames', feature_names);
session_id_values = string({all_rows.session_id}.');
tbl.session_id = categorical(session_id_values);
tbl.onset = vertcat(all_rows.onset);
tbl.offset = vertcat(all_rows.offset);
tbl.label = vertcat(all_rows.label);
tbl.source = categorical({all_rows.source}.');

extras = struct('session_id', session_id, ...
    'num_candidates', size(candidates, 1), ...
    'num_rows', height(tbl));
end

function opts = fill_ingest_defaults(opts)
defaults = struct(...
    'FsTarget', 48000, ...
    'MinOverlapFraction', 0.10, ...
    'MinSilenceDuration', 0.10, ...
    'IgnoreUnlabeled', true, ...
    'DetectorCandidates', [] ...
    );
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(opts, name) || isempty(opts.(name))
        opts.(name) = defaults.(name);
    end
end
validateattributes(opts.FsTarget, {'numeric'}, {'scalar', 'positive'});
validateattributes(opts.MinOverlapFraction, {'numeric'}, {'scalar', '>=', 0, '<=', 1});
validateattributes(opts.MinSilenceDuration, {'numeric'}, {'scalar', '>=', 0});
validateattributes(opts.IgnoreUnlabeled, {'numeric', 'logical'}, {'scalar'});
opts.IgnoreUnlabeled = logical(opts.IgnoreUnlabeled);
if ~isempty(opts.DetectorCandidates)
    opts.DetectorCandidates = validate_candidates(opts.DetectorCandidates);
else
    opts.DetectorCandidates = [];
end
end

function intervals = load_intervals(input)
if isempty(input)
    intervals = zeros(0, 2);
    return;
end
if isnumeric(input)
    validateattributes(input, {'numeric'}, {'2d', 'ncols', 2});
    intervals = double(input);
    return;
end
if isa(input, 'table')
    if all(ismember({'onset', 'offset'}, input.Properties.VariableNames))
        intervals = double([input.onset, input.offset]);
        return;
    end
end
if ischar(input) || (isstring(input) && isscalar(input))
    tbl = read_audacity_labels(input);
    intervals = double([tbl.onset, tbl.offset]);
    return;
end
error('ingest_session_for_calibrator:UnsupportedIntervalInput', 'unsupported label input type.');
end

function segments = validate_candidates(value)
if isa(value, 'table')
    if all(ismember({'onset', 'offset'}, value.Properties.VariableNames))
        value = [value.onset, value.offset];
    else
        error('ingest_session_for_calibrator:InvalidCandidateTable', 'detector candidates need onset and offset columns.');
    end
end
validateattributes(value, {'numeric'}, {'2d', 'ncols', 2});
segments = double(value);
if any(~isfinite(segments(:)))
    error('ingest_session_for_calibrator:InvalidCandidateValues', 'detector candidates must be finite.');
end
end

function session_id = determine_session_id(wavPath, opts)
if isfield(opts, 'SessionID') && ~isempty(opts.SessionID)
    session_id = string(opts.SessionID);
else
    [~, name, ~] = fileparts(char(wavPath));
    session_id = string(name);
end
end

function rows = build_rows_from_segments(x, fs, segments, heard, silence, session_id, opts, source)
rows = struct('session_id', {}, 'onset', {}, 'offset', {}, 'label', {}, 'source', {}, 'features', {});
if isempty(segments)
    return;
end

segments = double(segments);

for idx = 1:size(segments, 1)
    seg = segments(idx, :);
    if strcmp(source, 'silence')
        if diff(seg) < opts.MinSilenceDuration
            continue;
        end
    end

    feats = segment_features(x, fs, seg, struct());

    duration = max(0, seg(2) - seg(1));
    overlap = max_overlap_fraction(seg, heard, duration);
    silence_overlap = max_overlap_fraction(seg, silence, duration);

    if strcmp(source, 'detected') && opts.IgnoreUnlabeled && overlap <= 0 && silence_overlap <= 0
        continue;
    end

    if strcmp(source, 'silence')
        label = 0;
    else
        label = overlap >= opts.MinOverlapFraction;
        if ~label && silence_overlap > opts.MinOverlapFraction
            label = 0;
        elseif ~label && isempty(heard)
            label = 0;
        end
    end

    row.session_id = session_id;
    row.onset = seg(1);
    row.offset = seg(2);
    row.label = double(label);
    row.source = source;
    row.features = feats;

    rows(end+1) = row; %#ok<AGROW>
end
end

function frac = max_overlap_fraction(seg, intervals, duration)
if isempty(intervals) || duration <= 0
    frac = 0;
    return;
end
start = seg(1);
stop = seg(2);
overlaps = min(stop, intervals(:, 2)) - max(start, intervals(:, 1));
overlaps = max(overlaps, 0);
frac = max(overlaps) / duration;
end
