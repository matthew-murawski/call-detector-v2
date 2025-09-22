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
            [frame_in, stats] = adaptive_hysteresis(data.feats.energy, data.feats.entropy, data.feats.flux, data.feats.tonal_ratio, data.self_mask, params);
            intervals = frames_to_segments(frame_in, data.hop_seconds);
            intervals = postprocess_segments(intervals, params);
            intervals = filter_by_entropy_coverage(intervals, data.feats.entropy, data.hop_seconds, stats.entropy_thr, params.MinEntropyCoverage);

            tc.verifyEqual(size(intervals, 1), size(data.expected_segments, 1));
            tc.verifyEqual(size(intervals, 2), 2);
            delta = abs(intervals - data.expected_segments);
            tc.verifyLessThanOrEqual(max(delta, [], 'all'), 0.080);
        end

        function masks_remove_detections(tc)
            data = test_hysteresis.synth_fixture();
            params = test_hysteresis.default_params();
            self_mask = data.self_mask;
            second_seg = data.expected_segments(2, :);
            mask_frames = data.frame_centers >= second_seg(1) & data.frame_centers <= second_seg(2);
            self_mask(mask_frames) = true;

            [frame_in, stats] = adaptive_hysteresis(data.feats.energy, data.feats.entropy, data.feats.flux, data.feats.tonal_ratio, self_mask, params);
            tc.verifyFalse(any(frame_in(self_mask)));

            intervals = frames_to_segments(frame_in, data.hop_seconds);
            intervals = postprocess_segments(intervals, params);
            intervals = filter_by_entropy_coverage(intervals, data.feats.entropy, data.hop_seconds, stats.entropy_thr, params.MinEntropyCoverage);
            tc.verifyEqual(size(intervals, 1), 2);
            for k = 1:size(intervals, 1)
                mid_point = mean(intervals(k, :));
                tc.verifyFalse(mid_point >= second_seg(1) && mid_point <= second_seg(2));
            end
        end

        function flux_gate_blocks_low_flux_frames(tc)
            energy = [1 1 1 1 1 1 10 10].';
            entropy = [2 2 2 2 2 2 0.1 0.1].';
            flux = zeros(size(energy));
            params = test_hysteresis.default_params();
            tonal_ratio = zeros(size(energy));
            frame_in = adaptive_hysteresis(energy, entropy, flux, tonal_ratio, false(size(energy)), params);

            tc.verifyFalse(any(frame_in));
        end

        function trimming_handles_preceding_noise_burst(tc)
            data = test_hysteresis.burst_then_tone_fixture();
            params = test_hysteresis.default_params();
            params.FluxQuantileEnter = 0.95;

            params.BackgroundTrim = 1.0;
            frame_in_no_trim = adaptive_hysteresis(data.energy, data.entropy, data.flux, data.tonal_ratio, data.self_mask, params);
            tc.verifyFalse(any(frame_in_no_trim(data.call_frames)));

            params.BackgroundTrim = 0.95;
            frame_in_trim = adaptive_hysteresis(data.energy, data.entropy, data.flux, data.tonal_ratio, data.self_mask, params);
            tc.verifyTrue(all(frame_in_trim(data.call_frames)));
            tc.verifyFalse(any(frame_in_trim(data.noise_frames)));
        end

        function tonal_call_survives_broadband_noise(tc)
            data = test_hysteresis.tonal_noise_fixture();
            params = test_hysteresis.default_params();

            frame_in = adaptive_hysteresis(data.energy, data.entropy, data.flux, data.tonal_ratio, data.self_mask, params);
            tc.verifyTrue(all(frame_in(data.call_frames)));
            tc.verifyFalse(any(frame_in(data.noise_frames)));
        end

        function broadband_twitter_recovered(tc)
            twitter = test_hysteresis.broadband_twitter_fixture();
            params = test_hysteresis.default_params();

            frame_in_twitter = adaptive_hysteresis(twitter.energy, twitter.entropy, twitter.flux, twitter.tonal_ratio, twitter.self_mask, params);
            tc.verifyTrue(all(frame_in_twitter(twitter.call_frames)));

            noise = test_hysteresis.burst_then_tone_fixture();
            frame_in_noise = adaptive_hysteresis(noise.energy, noise.entropy, noise.flux, noise.tonal_ratio, noise.self_mask, params);
            tc.verifyFalse(any(frame_in_noise(noise.noise_frames)));
        end
    end

    methods (Static, Access = private)
        function params = default_params()
            params.MAD_Tlow = 2.0;
            params.MAD_Thigh = 3.5;
            params.EntropyQuantile = 0.40;
            params.FluxQuantileEnter = 0.70;
            params.FluxQuantileStay = 0.40;
            params.TonalityQuantileEnter = 0.78;
            params.TonalityQuantileStay = 0.55;
            params.BroadbandEntropySlack = 0.35;
            params.BroadbandTonalityQuantile = 0.10;
            params.MinDur = 0.05;
            params.MaxDur = 0.80;
            params.MergeGap = 0.040;
            params.CloseHole = 0.020;
            params.MinEntropyCoverage = 0.35;
            params.BackgroundTrim = 0.95;
            params.Coherence = test_hysteresis.coherence_params();
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

        function data = burst_then_tone_fixture()
            quiet_frames = 90;
            noise_frames = 5;
            call_frames = 5;
            total_frames = quiet_frames + noise_frames + call_frames;

            energy = ones(total_frames, 1);
            energy(quiet_frames + (1:noise_frames)) = 12;
            energy(quiet_frames + noise_frames + (1:call_frames)) = 4;

            entropy = ones(total_frames, 1) * 1.2;
            entropy(quiet_frames + (1:noise_frames)) = 1.4;
            entropy(quiet_frames + noise_frames + (1:call_frames)) = 0.2;

            flux = ones(total_frames, 1) * 0.1;
            flux(quiet_frames + (1:noise_frames)) = 7;
            flux(quiet_frames + noise_frames + (1:call_frames)) = 3;

            tonal_ratio = zeros(total_frames, 1);
            tonal_ratio(quiet_frames + (1:noise_frames)) = 0.5;
            tonal_ratio(quiet_frames + noise_frames + (1:call_frames)) = 8;

            data.energy = energy;
            data.entropy = entropy;
            data.flux = flux;
            data.tonal_ratio = tonal_ratio;
            data.self_mask = false(total_frames, 1);
            data.call_frames = (quiet_frames + noise_frames + 1):total_frames;
            data.noise_frames = (quiet_frames + 1):(quiet_frames + noise_frames);
        end

        function data = tonal_noise_fixture()
            noise_frames = 97;
            call_frames = 3;
            total_frames = noise_frames + call_frames;

            energy = ones(total_frames, 1) * 8;
            energy(noise_frames + (1:call_frames)) = 12;

            entropy = ones(total_frames, 1) * 1.5;
            entropy(noise_frames + (1:call_frames)) = 0.3;

            flux = ones(total_frames, 1) * 0.5;
            flux(noise_frames + (1:call_frames)) = 1.5;

            tonal_ratio = ones(total_frames, 1) * 0.4;
            tonal_ratio(noise_frames + (1:call_frames)) = 8;

            data.energy = energy;
            data.entropy = entropy;
            data.flux = flux;
            data.tonal_ratio = tonal_ratio;
            data.self_mask = false(total_frames, 1);
            data.call_frames = (noise_frames + 1):total_frames;
            data.noise_frames = (1:noise_frames).';
        end

        function data = broadband_twitter_fixture()
            quiet_frames = 80;
            twitter_frames = 12;
            tail_frames = 8;
            total_frames = quiet_frames + twitter_frames + tail_frames;

            energy = ones(total_frames, 1) * 1.0;
            energy(quiet_frames + (1:twitter_frames)) = 7.5;

            entropy = ones(total_frames, 1) * 0.6;
            entropy(quiet_frames + (1:twitter_frames)) = 0.92;

            flux = ones(total_frames, 1) * 0.3;
            flux(quiet_frames + (1:twitter_frames)) = 3.8;

            tonal_ratio = ones(total_frames, 1) * 0.25;
            tonal_ratio(quiet_frames + (1:twitter_frames)) = 0.05;

            data.energy = energy;
            data.entropy = entropy;
            data.flux = flux;
            data.tonal_ratio = tonal_ratio;
            data.self_mask = false(total_frames, 1);
            data.call_frames = (quiet_frames + 1):(quiet_frames + twitter_frames);
        end

        function params = coherence_params()
            params = struct(...
                'Enabled', true, ...
                'LogOffset', 1e-8, ...
                'GradKernel', 'central', ...
                'SigmaTime', 1.0, ...
                'SigmaFreq', 1.0, ...
                'TruncationRadius', 3, ...
                'Gain', 1.0, ...
                'Exponent', 1.0, ...
                'Clip', [0 1] ...
                );
        end
    end
end
