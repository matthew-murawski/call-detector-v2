% Example script to train a calibrator from ingested feature tables and save it for detection.

setup_paths();

% list the feature table MAT files you want to include (add real paths).
feature_files = [
    "models/features_S178.mat"
    % "models/features_S66.mat"
    % "models/features_Session003.mat"
];

% feature_files = list_feature_files('models');
% 
% if isempty(feature_files)
%     error('train_calibrator_example:NoFiles', 'Add at least one feature file path.');
% end

% Load and concatenate all tables.
tables = cell(numel(feature_files), 1);
for idx = 1:numel(feature_files)
    file_path = feature_files(idx);
    if exist(file_path, 'file') ~= 2
        error('train_calibrator_example:MissingFile', 'Feature file not found: %s', file_path);
    end
    data = load(file_path);
    if ~isfield(data, 'chunk_tbl')
        error('train_calibrator_example:MissingTable', 'Feature file %s does not contain chunk_tbl.', file_path);
    end
    tables{idx} = data.chunk_tbl;
end

feat_tbl = vertcat(tables{:});
if isempty(feat_tbl)
    error('train_calibrator_example:EmptyTable', 'No feature rows found; check the inputs.');
end

% Separate feature matrix, labels, and session IDs.
feature_cols = feat_tbl{:, 1:16};
labels = feat_tbl.label;
session_ids = feat_tbl.session_id;

% Train the calibrator with a target recall and save path.
calibrator_path = 'models/calibrator.mat';
opts = struct('TargetRecall', 0.90, 'SavePath', calibrator_path);
model = train_calibrator(feature_cols, labels, session_ids, opts);

fprintf('Calibrator trained: AUC %.3f, threshold %.3f\n', model.AUC, model.Threshold);
fprintf('Saved model to %s\n', calibrator_path);

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

function feature_files = list_feature_files(models_dir)
% return string array of feature-table .mat files under models_dir

    % choose default models_dir if not provided
    if nargin < 1 || isempty(models_dir)
        models_dir = 'models';
    end

    % validate models_dir exists
    if ~isfolder(models_dir)
        error('list_feature_files:NotFound', 'models directory not found: %s', models_dir);
    end

    pat_primary = fullfile(models_dir, 'features_*.mat');
    pat_fallback = fullfile(models_dir, '*features*.mat');

    % search for primary pattern first
    d = dir(pat_primary);

    % fallback to looser match if needed
    if isempty(d)
        d = dir(pat_fallback);
    end

    % handle no matches
    if isempty(d)
        warning('list_feature_files:Empty', ...
            'no feature .mat files found under %s (patterns: %s, %s).', ...
            models_dir, erase(pat_primary, pwd), erase(pat_fallback, pwd));
        feature_files = strings(0,1);
        return
    end

    % sort by name for stable order
    names = {d.name}';
    paths = fullfile({d.folder}', names);

    % convert to relative paths when possible (nicer in repos/scripts)
    repo_root = pwd; % assume called from repo root or desired base
    rel_paths = strings(numel(paths),1);
    for i = 1:numel(paths)
        try
            rel = strrep(paths{i}, [repo_root filesep], '');
        catch
            rel = paths{i}; %#ok<*NASGU>
        end
        rel_paths(i) = string(rel);
    end

    % ensure forward slashes for portability in string arrays
    rel_paths = replace(rel_paths, filesep, '/');

    % filter out anything that doesn't end with .mat just in case
    keep = endsWith(lower(rel_paths), ".mat");
    rel_paths = rel_paths(keep);

    % return as a column string array
    feature_files = rel_paths;
end