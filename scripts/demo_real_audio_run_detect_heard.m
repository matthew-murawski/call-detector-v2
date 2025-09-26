function demo_real_audio_run_detect_heard()
% quick demo that runs detection and writes outputs on real audio.

% setup paths and output folder.
script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(script_dir);
addpath(fullfile(repo_root, 'src', 'detect'));
addpath(fullfile(repo_root, 'src', 'io'));
addpath(fullfile(repo_root, 'src', 'mask'));
addpath(fullfile(repo_root, 'src', 'label'));
addpath(genpath(fullfile(repo_root, 'src', 'noise')));
output_dir = fullfile(repo_root, 'output');
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end

% wav_path = '/Users/matt/Documents/Zhao Lab/audio/M93A_S105_little_clip.wav';

wav_path = '/Users/matt/Documents/Zhao Lab/audio/test clips/S178_test.wav';

T = read_audacity_labels('/Users/matt/Documents/Zhao Lab/audio/test clips/S178_test_produced.txt');
produced = zeros(size(T, 1), 2);
produced(:, 1) = T.onset;
produced(:, 2) = T.offset;

addpath(genpath(fullfile(repo_root, 'src', 'noise')));
  params.UseNoiseMask = true;
  params.NoiseHandlingMode = "hard";      % or "hard"
  params.NoiseParams = NoiseParams(48000);   % customise thresholds as needed
  params.NoiseDecision = struct( ...
      'MinOverlapFrac', 0.6, ...
      'MaxStartDiff',   0.12, ...
      'MaxEndDiff',     0.12);
  params.NoiseLabelPath = fullfile(output_dir, 'demo_noise_labels.txt');


% run detector and write outputs.
params = struct( ...
    'SelfPadPre', 0.05, ...
    'SelfPadPost', 0.05, ...
    'MAD_Tlow', 0.5, ...
    'MAD_Thigh', 1.2, ...
    'EntropyQuantile', 0.35, ...
    'MinEntropyCoverage', 0, ...
    'UseCalibrator', false, ...
    'CalibratorPath', 'models/calibrator.mat', ...
    'BroadbandEntropySlack', 0.8, ...
    'BroadbandTonalityQuantile', 0.5, ...
    'TonalityQuantileEnter', 0.5, ...
    'TonalityQuantileStay', 0.5, ...
    'UseNoiseMask', false, ...
    'NoiseHandlingMode', "overlap", ...
    'NoiseLabelPath', fullfile(output_dir, 'demo_noise_labels.txt'));
params.NoiseParams = NoiseParams(48000);
params.NoiseParams.BandCoincidence.NRequired = 2;
params.NoiseParams.BandCoincidence.RequireOOB = true;
params.NoiseParams.BandThresholds.kEnter = 0.99;
params.NoiseParams.BandThresholds.kExit = 0.9;
params.NoiseParams.Coverage.CoverageMin = 0.12;
params.NoiseParams.Flatness.FlatnessMin = 0.18;
params.NoiseParams.OOB.RatioMin = 0.15;
params.NoiseParams.TonalityGuard.Enable = false;
params.NoiseDecision = struct('MinOverlapFrac', 0.60, ...
    'MaxStartDiff', 0.12, ...
    'MaxEndDiff', 0.12);
label_path = fullfile('/Users/matt/Documents/Zhao Lab/audio/test clips/S178_test_heard_auto.txt');
heard = run_detect_heard(wav_path, produced, label_path, params);
produced_path = fullfile(output_dir, 'demo_produced_labels.txt');
write_audacity_labels(produced_path, produced, repmat("SELF", size(produced, 1), 1));
fprintf('wrote %d detected segments to %s\n', size(heard, 1), label_path);
if exist(params.NoiseLabelPath, 'file') == 2
    fprintf('wrote noise labels to %s\n', params.NoiseLabelPath);
end
end