% ingest_all_sessions.m
% scan the labels directory for sessions with heard/silence/produced files,
% pair each with its matching wav, and run ingest_session_chunks on all.
% saves per-session feature tables in ../models and an optional combined file.

%% setup paths and io locations
% note: adjust these if your layout changes
setup_paths();  % uses your helper from the example script

labels_dir = '/Users/matt/Documents/GitHub/vocalization/data/labels';
wav_dir    = '/Volumes/Zhao/JHU_Data/Recording_Colony_Neural/M93A';
models_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'models');

% create models dir if needed
if exist(models_dir, 'dir') ~= 7
    mkdir(models_dir);
end

% optional detector params and ingest options
params = struct();
ingest_opts = struct();  % SessionID will be filled per session

%% discover eligible sessions
% find sessions that have heard, silence, and produced label files
fprintf('scanning labels in: %s\n', labels_dir);
sessions = find_sessions_with_all_labels(labels_dir);

if isempty(sessions)
    warning('no eligible sessions found (need heard/silence/produced triplets).');
    return;
end

fprintf('found %d eligible sessions: %s\n', numel(sessions), strjoin(sessions, ', '));

%% iterate over sessions and ingest
all_tbls = {};
all_meta = {};
n_ok = 0; n_skip = 0;

for i = 1:numel(sessions)
    sid = sessions{i};                         % e.g., 'S178'
    sid_num = sscanf(sid, 'S%d');              % numeric, for wav naming
    wav_name = sprintf('voc_M93A_c_S%d.wav', sid_num);
    wav_path = fullfile(wav_dir, wav_name);

    % build label paths
    produced_labels_path = fullfile(labels_dir, sprintf('M93A_%s_produced.txt', sid));
    heard_labels_path    = fullfile(labels_dir, sprintf('M93A_%s_heard.txt', sid));
    silence_labels_path  = fullfile(labels_dir, sprintf('M93A_%s_silence.txt', sid));

    % sanity checks
    if ~isfile(wav_path)
        warning('missing wav for %s → %s (skipping)', sid, wav_path);
        n_skip = n_skip + 1;
        continue;
    end
    if ~isfile(produced_labels_path) || ~isfile(heard_labels_path) || ~isfile(silence_labels_path)
        warning('missing one or more labels for %s (skipping)', sid);
        n_skip = n_skip + 1;
        continue;
    end

    % set session id for metadata
    local_ingest_opts = ingest_opts;
    local_ingest_opts.SessionID = sid;

    % run ingestion with five-minute chunks (as in your example)
    try
        [chunk_tbl, chunk_meta] = ingest_session_chunks( ...
            wav_path, produced_labels_path, heard_labels_path, silence_labels_path, ...
            params, local_ingest_opts);

        fprintf('session %s → %d rows across %d chunks (original candidates: %d)\n', ...
            chunk_meta.session_id, chunk_meta.total_rows, chunk_meta.num_chunks, chunk_meta.total_candidates);

        % save per-session output
        out_path = fullfile(models_dir, sprintf('features_%s.mat', chunk_meta.session_id));
        save(out_path, 'chunk_tbl', 'chunk_meta');

        % collect for optional combined save
        if ~isempty(chunk_tbl)
            all_tbls{end+1} = chunk_tbl; %#ok<AGROW>
        end
        all_meta{end+1} = chunk_meta; %#ok<AGROW>
        n_ok = n_ok + 1

    catch ME
        warning('ingestion failed for %s: %s', sid, ME.message);
        n_skip = n_skip + 1;
        continue;
    end
end

%% optional: save combined table/metadata (if at least one succeeded)
if ~isempty(all_tbls)
    combined_tbl = vertcat(all_tbls{:});
    combined_meta = all_meta;  % cell array of per-session meta structs

    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    out_all = fullfile(models_dir, sprintf('features_ALL_%s.mat', stamp));
    save(out_all, 'combined_tbl', 'combined_meta');
    fprintf('saved combined table: %s (total rows: %d)\n', out_all, height(combined_tbl));
else
    fprintf('no per-session tables to combine.\n');
end

fprintf('done. ok: %d, skipped: %d\n', n_ok, n_skip);

%% ------------------------------------------------------------------------
function sessions = find_sessions_with_all_labels(labels_dir)
% scan labels_dir for files like M93A_S<session>_<label>.txt and return session
% ids (e.g., 'S31') that have heard, silence, and produced.

    % list all txts matching the animal prefix to keep the search tight
    d = dir(fullfile(labels_dir, 'M93A_S*_*.txt'));
    if isempty(d)
        sessions = {};
        return;
    end

    % parse filenames with a regex and tally labels per session
    % pattern groups:
    %   1: session number
    %   2: label (heard|silence|produced)
    pat = '^M93A_S(\d+)_([a-zA-Z]+)\.txt$';
    have = containers.Map('KeyType', 'char', 'ValueType', 'any');

    for k = 1:numel(d)
        fname = d(k).name;
        tokens = regexp(fname, pat, 'tokens', 'once');
        if isempty(tokens)
            continue; % ignore non-matching files
        end
        s_num = tokens{1};
        lbl = lower(tokens{2});

        sid = sprintf('S%s', s_num);
        if ~isKey(have, sid)
            have(sid) = struct('heard', false, 'silence', false, 'produced', false);
        end
        rec = have(sid);
        switch lbl
            case 'heard',    rec.heard = true;
            case 'silence',  rec.silence = true;
            case 'produced', rec.produced = true;
            otherwise
                % ignore other label types
        end
        have(sid) = rec;
    end

    % filter sessions with complete triplets
    keys = have.keys;
    eligible = {};
    for i = 1:numel(keys)
        sid = keys{i};
        rec = have(sid);
        if rec.heard && rec.silence && rec.produced
            eligible{end+1} = sid; %#ok<AGROW>
        end
    end

    % sort by numeric session id
    if isempty(eligible)
        sessions = {};
        return;
    end
    nums = cellfun(@(s) sscanf(s, 'S%d'), eligible);
    [~, order] = sort(nums);
    sessions = eligible(order);
end

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