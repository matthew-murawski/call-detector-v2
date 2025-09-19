% Example script to ingest a single hand-labeled session and save its feature table.

setup_paths();

% TODO: set these paths to your actual files before running.
wav_path = '/Volumes/Zhao/JHU_Data/Recording_Colony_Neural/M93A/voc_M93A_c_S178.wav';
produced_labels_path = '/Users/matt/Documents/GitHub/vocalization/data/labels/M93A_S178_produced.txt';
heard_labels_path = '/Users/matt/Documents/GitHub/vocalization/data/labels/M93A_S178_heard.txt';
silence_labels_path = '/Users/matt/Documents/GitHub/vocalization/data/labels/M93A_S178_silence.txt';

% Optional detector parameter tweaks; start with defaults from run_detect_heard.
params = struct();

% Options controlling ingestion behaviour.
ingest_opts = struct('SessionID', 'Session001');

% Build feature table and metadata for this session using five-minute chunks.
[chunk_tbl, chunk_meta] = ingest_session_chunks(wav_path, produced_labels_path, ...
    heard_labels_path, silence_labels_path, params, ingest_opts);

fprintf('Session %s produced %d candidate rows across %d chunks (original candidates: %d)\n', ...
    chunk_meta.session_id, chunk_meta.total_rows, chunk_meta.num_chunks, chunk_meta.total_candidates);

% Ensure models directory exists and save the table for later training.
models_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'models');
if exist(models_dir, 'dir') ~= 7
    mkdir(models_dir);
end
save(fullfile(models_dir, sprintf('features_%s.mat', chunk_meta.session_id)), 'chunk_tbl', 'chunk_meta');

%% ------------------------------------------------------------------------
function setup_paths()
script_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(script_dir);
addpath(fullfile(root_dir, 'src', 'learn'));
addpath(fullfile(root_dir, 'src', 'features'));
addpath(fullfile(root_dir, 'src', 'detect'));
addpath(fullfile(root_dir, 'src', 'io'));
addpath(fullfile(root_dir, 'src', 'label'));
addpath(fullfile(root_dir, 'src', 'mask'));
end

function [tbl_all, meta] = ingest_session_chunks(wav_path, produced_path, heard_path, silence_path, params, ingest_opts)
chunk_seconds = 5 * 60;

[x_full, fs_full] = read_audio(wav_path);
total_duration = (numel(x_full) - 1) / fs_full;
chunk_starts = 0:chunk_seconds:total_duration;
if chunk_starts(end) < total_duration
    chunk_starts = [chunk_starts, total_duration]; %#ok<AGROW>
end

produced_all = load_label_intervals(produced_path);
heard_all = load_label_intervals(heard_path);
silence_all = load_label_intervals(silence_path);

tbl_cells = {};
total_candidates = 0;
total_rows = 0;
processed_chunks = 0;

for idx = 1:numel(chunk_starts)-1
    t0 = chunk_starts(idx);
    t1 = chunk_starts(idx + 1);
    if t1 <= t0
        continue;
    end
    sample_start = max(1, floor(t0 * fs_full) + 1);
    sample_end = min(numel(x_full), ceil(t1 * fs_full));
    audio_chunk = struct('x', x_full(sample_start:sample_end), 'fs', fs_full);

    produced_chunk = crop_intervals(produced_all, t0, t1);
    heard_chunk = crop_intervals(heard_all, t0, t1);
    silence_chunk = crop_intervals(silence_all, t0, t1);

    chunk_opts = ingest_opts;
    chunk_opts.SessionID = ingest_opts.SessionID;

    [tbl_chunk, meta_chunk] = ingest_session_for_calibrator(audio_chunk, produced_chunk, ...
        heard_chunk, silence_chunk, params, chunk_opts);

    total_candidates = total_candidates + meta_chunk.num_candidates;
    total_rows = total_rows + height(tbl_chunk);
    processed_chunks = processed_chunks + 1;

    if ~isempty(tbl_chunk)
        tbl_cells{end+1} = tbl_chunk; %#ok<AGROW>
    end
end

if isempty(tbl_cells)
    tbl_all = table();
else
    tbl_all = vertcat(tbl_cells{:});
end
meta = struct('session_id', string(ingest_opts.SessionID), ...
    'num_chunks', processed_chunks, ...
    'total_rows', total_rows, ...
    'total_candidates', total_candidates);
end

function intervals = load_label_intervals(path)
if isempty(path)
    intervals = zeros(0, 2);
    return;
end
if ischar(path) || (isstring(path) && isscalar(path))
    tbl = read_audacity_labels(path);
    intervals = double([tbl.onset, tbl.offset]);
else
    error('ingest_session_example:InvalidLabelPath', 'Label paths must be char or string scalars.');
end
end

function out = crop_intervals(intervals, t0, t1)
if isempty(intervals)
    out = zeros(0, 2);
    return;
end
mask = intervals(:, 2) > t0 & intervals(:, 1) < t1;
if ~any(mask)
    out = zeros(0, 2);
    return;
end
subset = intervals(mask, :);
subset(:, 1) = max(subset(:, 1), t0);
subset(:, 2) = min(subset(:, 2), t1);
subset = subset - t0;
subset(subset(:, 2) <= subset(:, 1), :) = [];
if isempty(subset)
    out = zeros(0, 2);
else
    out = subset;
end
end
