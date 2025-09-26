function heard = run_detect_heard_for_session(session)
% wrapper: run heard-call detection for an M93A session by number/id.
%
% usage:
%   heard = run_detect_heard_for_session(178)
%   heard = run_detect_heard_for_session('178')
%   heard = run_detect_heard_for_session('S178')
%
% outputs:
%   heard : [n x 2] double (onset, offset) detected segments (seconds)

    % resolve repo paths and add needed subfolders
    script_dir = fileparts(mfilename('fullpath'));
    repo_root = fileparts(script_dir);
    addpath(fullfile(repo_root, 'src', 'detect'));
    addpath(fullfile(repo_root, 'src', 'io'));
    addpath(fullfile(repo_root, 'src', 'mask'));
    addpath(fullfile(repo_root, 'src', 'label'));

    % normalize the session id (accept 178, '178', or 'S178' → 'S178')
    sess = normalize_session_id(session);

    % build absolute paths from your conventions
    wav_dir = '/Volumes/Zhao/JHU_Data/Recording_Colony_Neural/M93A';
    wav_path = fullfile(wav_dir, sprintf('voc_M93A_c_%s.wav', sess));
    labels_dir = '/Users/matt/Documents/GitHub/vocalization/data/labels';
    produced_labels_path = fullfile(labels_dir, sprintf('M93A_%s_produced.txt', sess));

    % ensure output folder exists under repo_root
    output_dir = fullfile(repo_root, 'output');
    if exist(output_dir, 'dir') ~= 7
        mkdir(output_dir);
    end
    heard_label_path    = fullfile(output_dir, sprintf('M93A_%s_heard_detected.txt', sess));
    produced_label_path = fullfile(output_dir, sprintf('M93A_%s_produced_labels.txt', sess));

    % read produced/self labels (onset/offset in seconds); empty if not found
    produced = read_intervals_or_empty(produced_labels_path);

    % set detector params (same recipe as your demo)
    params = struct( ...
        'SelfPadPre', 0.05, ...
        'SelfPadPost', 0.05, ...
        'MAD_Tlow', 0.5, ...
        'MAD_Thigh', 1.2, ...
        'EntropyQuantile', 0.35, ...
        'MinEntropyCoverage', 0.4, ...
        'UseCalibrator', false, ...
        'CalibratorPath', 'models/calibrator.mat', ...
        'BroadbandEntropySlack', 0.8, ...
        'BroadbandTonalityQuantile', 0.5, ...
        'TonalityQuantileEnter', 0.5, ...
        'TonalityQuantileStay', 0.5);

    % run detector and write heard labels (run_detect_heard writes to heard_label_path)
    heard = run_detect_heard_chunked(wav_path, produced, heard_label_path, params);

    % also mirror the produced/self labels into output for convenience
    if ~isempty(produced)
        write_labels_or_fallback(produced_label_path, produced);
    end

    % print a short summary for quick feedback
    fprintf('[%s] wrote %d heard segments → %s\n', sess, size(heard,1), heard_label_path);
    if ~isempty(produced)
        fprintf('[%s] copied %d produced segments → %s\n', sess, size(produced,1), produced_label_path);
    else
        fprintf('[%s] no produced labels found at %s (skipped copy)\n', sess, produced_labels_path);
    end
end

% --- helpers ---------------------------------------------------------------

function sess = normalize_session_id(s)
% accept numeric 178, char '178', or 'S178' and return 'S178'
    if isnumeric(s)
        n = s;
    else
        s = string(s);
        if startsWith(upper(s), "S")
            n = str2double(extractAfter(s, 1));
        else
            n = str2double(s);
        end
    end
    if ~isfinite(n) || n ~= floor(n)
        error('session must be an integer like 178 or a string like ''S178''.');
    end
    sess = sprintf('S%d', n);
end

function intervals = read_intervals_or_empty(p)
% read audacity-style label file (start<TAB>end[<TAB>label]); return [n x 2] double.
% returns [] if file missing or unreadable.
    if exist(p, 'file') ~= 2
        intervals = [];
        return;
    end

    % try project reader first if available
    if exist('read_audacity_labels', 'file') == 2
        try
            L = read_audacity_labels(p);   % expected to return table or struct
            intervals = extract_first_two(L);
            return;
        catch
            % fall through to generic parser
        end
    end

    % generic, robust parser for tab/space-delimited start/end/label
    try
        opts = detectImportOptions(p, 'FileType', 'text', 'Delimiter', {'\t',' '}, ...
            'NumHeaderLines', 0, 'MultipleDelimsAsOne', true);
        opts.VariableNames = {'start','stop','label'};
        opts.SelectedVariableNames = {'start','stop'};
        T = readtable(p, opts);
        intervals = sortrows([T.start, T.stop], 1);
    catch
        warning('failed to read produced labels from %s', p);
        intervals = [];
    end
end

function ab = extract_first_two(L)
% normalize outputs from read_audacity_labels to [n x 2] double
    if istable(L)
        vars = string(L.Properties.VariableNames);
        % look for any two columns that can be coerced to numeric
        cand = [];
        for v = vars
            x = L.(v);
            if isnumeric(x)
                cand = [cand, v]; %#ok<AGROW>
            end
        end
        if numel(cand) >= 2
            a = double(L.(cand(1)));
            b = double(L.(cand(2)));
            ab = sortrows([a(:), b(:)], 1);
            return;
        end
    elseif isstruct(L)
        if all(isfield(L, {'start','stop'}))
            ab = sortrows([double(L.start(:)), double(L.stop(:))], 1);
            return;
        end
    elseif isnumeric(L) && size(L,2) >= 2
        ab = sortrows(double(L(:,1:2)), 1);
        return;
    end
    error('unrecognized output from read_audacity_labels');
end

function write_labels_or_fallback(out_path, intervals)
% try project writer, else write a simple 3-column tsv
    if exist('write_audacity_labels', 'file') == 2
        try
            write_audacity_labels(out_path, intervals);
            return;
        catch
            % fall through to tsv
        end
    end
    fid = fopen(out_path, 'w');
    if fid < 0
        warning('could not open %s for writing', out_path);
        return;
    end
    c = onCleanup(@() fclose(fid));
    for i = 1:size(intervals,1)
        fprintf(fid, '%.6f\t%.6f\t%s\n', intervals(i,1), intervals(i,2));
    end
end
