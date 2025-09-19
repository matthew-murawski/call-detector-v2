% Example script to train a calibrator from ingested feature tables and save it for detection.

setup_paths();

% TODO: list the feature table MAT files you want to include (add real paths).
feature_files = [
    "models/features_Session001.mat"
    % "models/features_Session002.mat"
    % "models/features_Session003.mat"
];

if isempty(feature_files)
    error('train_calibrator_example:NoFiles', 'Add at least one feature file path.');
end

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
