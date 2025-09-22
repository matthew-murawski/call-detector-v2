function demo_real_audio_run_detect_heard()
% quick demo that runs detection and writes outputs on real audio.

% setup paths and output folder.
script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(script_dir);
addpath(fullfile(repo_root, 'src', 'detect'));
addpath(fullfile(repo_root, 'src', 'io'));
addpath(fullfile(repo_root, 'src', 'mask'));
addpath(fullfile(repo_root, 'src', 'label'));
output_dir = fullfile(repo_root, 'output');
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end

% wav_path = '/Users/matt/Documents/Zhao Lab/audio/M93A_S105_little_clip.wav';

wav_path = '/Users/matt/Documents/Zhao Lab/audio/little_clip_M93A_c_S178.wav';

produced = [
    0.0 0.18;
    0.18 0.5;
];

% run detector and write outputs.
params = struct( ...
    'SelfPadPre', 0.05, ...
    'SelfPadPost', 0.05, ...
    'MAD_Tlow', 0.5, ...
    'MAD_Thigh', 1.2, ...
    'EntropyQuantile', 0.30, ...
    'MinEntropyCoverage', 0.40, ...
    'UseCalibrator', false, ...
    'CalibratorPath', 'models/calibrator.mat', ...
    'BroadbandEntropySlack', 0.8, ...
    'BroadbandTonalityQuantile', 0.25, ...
    'TonalityQuantileEnter', 0.5, ...
    'TonalityQuantileStay', 0.5);
label_path = fullfile(output_dir, 'demo_detected_labels.txt');
heard = run_detect_heard(wav_path, produced, label_path, params);
produced_path = fullfile(output_dir, 'demo_produced_labels.txt');
write_audacity_labels(produced_path, produced, repmat("SELF", size(produced, 1), 1));
fprintf('wrote %d detected segments to %s\n', size(heard, 1), label_path);
end
