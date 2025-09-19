function [x, fs, self_labels, heard_truth] = make_synth_colony_track()
%% parameters
fs = 24000;
duration_s = 30;
n_samples = round(fs * duration_s);

%% noise bed
white = randn(n_samples, 1);
pinkish = filter(1, [1 -0.99], white);
pinkish = pinkish / max(abs(pinkish));
x = 0.2 * pinkish;

%% event definitions
self_freq = 4000;
heard_freq = 7000;
self_starts = [5.0; 18.0];
self_durations = [0.4; 0.5];
heard_starts = [8.0; 12.5; 24.0];
heard_durations = [0.3; 0.4; 0.5];
self_labels = [self_starts, self_starts + self_durations];
heard_truth = [heard_starts, heard_starts + heard_durations];

%% synthesis
sample_times = (0:n_samples-1).' / fs;
for idx = 1:size(self_labels, 1)
    on = self_labels(idx, 1);
    off = self_labels(idx, 2);
    tone_idx = time_indices(on, off, fs, n_samples);
    tone_t = sample_times(tone_idx) - on;
    x(tone_idx) = x(tone_idx) + 0.3 * sin(2 * pi * self_freq * tone_t);
end

for idx = 1:size(heard_truth, 1)
    on = heard_truth(idx, 1);
    off = heard_truth(idx, 2);
    tone_idx = time_indices(on, off, fs, n_samples);
    tone_t = sample_times(tone_idx) - on;
    x(tone_idx) = x(tone_idx) + 0.25 * sin(2 * pi * heard_freq * tone_t);
end

%% helpers
    function idx = time_indices(onset, offset, rate, total_samples)
        start_sample = max(1, floor(onset * rate) + 1);
        end_sample = min(total_samples, ceil(offset * rate));
        idx = (start_sample:end_sample).';
    end
end
