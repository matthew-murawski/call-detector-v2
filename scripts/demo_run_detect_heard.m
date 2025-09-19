function demo_run_detect_heard()
% quick demo that builds synthetic audio, runs detection, and writes outputs.

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

% build synthetic waveform.
rng(42);
fs = 48000;
duration = 2.6;
n_samples = round(duration * fs);
noise_level = 1e-4;
noise = noise_level * randn(n_samples, 1);
truth = [
    0.30 0.60;
    0.95 1.35;
    1.80 2.20;
];
x = noise;
tone_gain = noise_level * 2.0;  % keep synthetic tone about 6 dB above background
for idx = 1:size(truth, 1)
    onset = truth(idx, 1);
    offset = truth(idx, 2);
    start_idx = max(1, floor(onset * fs) + 1);
    stop_idx = min(n_samples, ceil(offset * fs));
    t = (start_idx:stop_idx).' / fs;
    tone = tone_gain * sin(2 * pi * 7000 * (t - onset));
    window = hann(numel(t));
    x(start_idx:stop_idx) = x(start_idx:stop_idx) + tone .* window;
end
produced = [
    0.10 0.18;
    1.45 1.60;
];
wav_path = fullfile(output_dir, 'demo_synth.wav');
audiowrite(wav_path, x, fs);

% run detector and write outputs.
params = struct();
label_path = fullfile(output_dir, 'demo_detected_labels.txt');
heard = run_detect_heard(wav_path, produced, label_path, params);
truth_path = fullfile(output_dir, 'demo_truth_labels.txt');
write_audacity_labels(truth_path, truth, repmat("HEARD", size(truth, 1), 1));
produced_path = fullfile(output_dir, 'demo_produced_labels.txt');
write_audacity_labels(produced_path, produced, repmat("SELF", size(produced, 1), 1));
fprintf('wrote %d detected segments to %s\n', size(heard, 1), label_path);
end
