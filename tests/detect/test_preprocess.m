classdef test_preprocess < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'detect'));
        end
    end

    %% tests
    methods (Test)
        function bandpass_targets_high_band(tc)
            fs = 48000;
            t = (0:fs-1).' / fs;
            low = sin(2 * pi * 1000 * t);
            high = sin(2 * pi * 7000 * t);
            y_low = bandpass_5to14k(low, fs);
            y_high = bandpass_5to14k(high, fs);
            low_rms = sqrt(mean(y_low .^ 2));
            high_rms = sqrt(mean(y_high .^ 2));
            tc.verifyLessThan(low_rms, 1e-3);
            tc.verifyGreaterThan(high_rms, 0.6);
        end

        function resample_matches_expected_length(tc)
            fs_in = 48000;
            fs_target = 24000;
            duration = 0.75;
            n = round(fs_in * duration);
            t = (0:n-1).' / fs_in;
            x = sin(2 * pi * 2500 * t);
            [y, fs_out] = resample_if_needed(x, fs_in, fs_target);
            tc.verifyEqual(fs_out, fs_target);
            expected_length = round(n * fs_target / fs_in);
            tc.verifyLessThanOrEqual(abs(length(y) - expected_length), 1);
            [y_same, fs_same] = resample_if_needed(x, fs_in, fs_in);
            tc.verifyEqual(y_same, x);
            tc.verifyEqual(fs_same, fs_in);
        end

        function spectral_focus_prioritises_band(tc)
            freqs = linspace(0, 24000, 256).';
            S = ones(numel(freqs), 5);
            focus_band = [7000 9000];
            S_focus = apply_spectral_focus(S, freqs, focus_band);
            in_band = freqs >= focus_band(1) & freqs <= focus_band(2);
            below_band = freqs <= focus_band(1) - 2000;
            in_vals = S_focus(in_band, :);
            out_vals = S_focus(below_band, :);
            tc.assertNotEmpty(in_vals);
            tc.assertNotEmpty(out_vals);
            in_power = mean(in_vals(:));
            out_power = mean(out_vals(:));
            tc.verifyGreaterThan(in_power, out_power * 5);
        end
    end
end
