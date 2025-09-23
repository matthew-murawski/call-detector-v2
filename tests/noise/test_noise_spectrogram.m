classdef test_noise_spectrogram < matlab.unittest.TestCase
    % tests ensure the noise spectrogram helper behaves under varied signals.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'noise'));
        end
    end
    % the test block checks shape, monotonicity, and duration assumptions.

    methods (Test)
        function returns_expected_shape(tc)
            fs = 48000;
            duration = 0.5;
            t = (0:round(duration * fs) - 1).' / fs;
            y = [sin(2 * pi * 1200 * t), cos(2 * pi * 3200 * t)];

            [S, f, tvec] = noise_compute_spectrogram(y, fs);

            tc.verifyEqual(size(S, 1), numel(f));
            tc.verifyEqual(size(S, 2), numel(tvec));
            tc.verifyGreaterThan(size(S, 1), 0);
            tc.verifyGreaterThan(size(S, 2), 0);
            tc.verifyGreaterThanOrEqual(min(S(:)), 0);
        end

        function vectors_are_monotonic(tc)
            fs = 44100;
            y = randn(fs * 2, 1);
            opts = struct('WindowSec', 0.020, 'HopSec', 0.005, 'NFFT', 2048);

            [~, f, tvec] = noise_compute_spectrogram(y, fs, opts);

            tc.verifyTrue(all(diff(f) > 0));
            tc.verifyTrue(all(diff(tvec) > 0));
        end

        function duration_matches_samples(tc)
            fs = 32000;
            duration = 0.73;
            num_samples = max(1, round(duration * fs));
            y = randn(num_samples, 1);
            window_sec = 0.025;
            hop_sec = 0.010;
            [~, ~, tvec] = noise_compute_spectrogram(y, fs);

            win_samples = max(2, round(window_sec * fs));
            hop_samples = max(1, round(hop_sec * fs));
            if hop_samples >= win_samples
                hop_samples = max(1, win_samples - 1);
            end
            signal_len = max(numel(y), win_samples);
            expected_frames = floor((signal_len - win_samples) / hop_samples) + 1;
            approx_duration = (expected_frames - 1) * hop_sec + window_sec;

            tc.verifyEqual(numel(tvec), expected_frames);
            tc.verifyLessThanOrEqual(abs(approx_duration - numel(y) / fs), hop_sec);
        end
    end
end
