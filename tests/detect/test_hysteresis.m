classdef test_hysteresis < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'detect'));
        end
    end

    %% tests
    methods (Test)
        function detects_three_segments_from_synth(tc)
            data = test_hysteresis.synth_fixture();
            params = test_hysteresis.default_params();
            frame_in = adaptive_hysteresis(data.feats.energy, data.feats.entropy, data.self_mask, params);
            intervals = frames_to_segments(frame_in, data.hop_seconds);

            tc.verifyEqual(size(intervals, 1), size(data.expected_segments, 1));
            tc.verifyEqual(size(intervals, 2), 2);
            delta = abs(intervals - data.expected_segments);
            tc.verifyLessThanOrEqual(max(delta, [], 'all'), 0.040);
        end

        function masks_remove_detections(tc)
            data = test_hysteresis.synth_fixture();
            params = test_hysteresis.default_params();
            self_mask = data.self_mask;
            second_seg = data.expected_segments(2, :);
            mask_frames = data.frame_centers >= second_seg(1) & data.frame_centers <= second_seg(2);
            self_mask(mask_frames) = true;

            frame_in = adaptive_hysteresis(data.feats.energy, data.feats.entropy, self_mask, params);
            tc.verifyFalse(any(frame_in(self_mask)));

            intervals = frames_to_segments(frame_in, data.hop_seconds);
            tc.verifyEqual(size(intervals, 1), 2);
            for k = 1:size(intervals, 1)
                mid_point = mean(intervals(k, :));
                tc.verifyFalse(mid_point >= second_seg(1) && mid_point <= second_seg(2));
            end
        end
    end

    methods (Static, Access = private)
        function params = default_params()
            params.MAD_Tlow = 2.0;
            params.MAD_Thigh = 3.5;
            params.EntropyQuantile = 0.20;
        end

        function data = synth_fixture()
            rng(7);
            fs = 48000;
            tone_freq = 7000;
            segments = [0.30 0.55; 0.90 1.15; 1.40 1.70];
            total_duration = 2.0;
            n = round(total_duration * fs);
            t = (0:n-1).' / fs;
            x = 0.004 * randn(n, 1);
            for idx = 1:size(segments, 1)
                seg = segments(idx, :);
                mask = t >= seg(1) & t < seg(2);
                tone_t = t(mask) - seg(1);
                x(mask) = x(mask) + 0.18 * sin(2 * pi * tone_freq * tone_t);
            end

            win_length = 1024;
            hop = 256;
            [S, f, ~] = frame_spectrogram(x, fs, win_length, hop);

            bands.energy = [5000 14000];
            bands.entropy = [6000 10000];
            feats = feat_energy_entropy_flux(S, f, bands);

            frame_centers = ((0:size(S, 2) - 1) * hop + win_length / 2) / fs;

            data.feats = feats;
            data.self_mask = false(size(frame_centers(:)));
            data.hop_seconds = hop / fs;
            data.expected_segments = segments;
            data.frame_centers = frame_centers(:);
        end
    end
end
