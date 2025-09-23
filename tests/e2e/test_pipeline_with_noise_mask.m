classdef test_pipeline_with_noise_mask < matlab.unittest.TestCase
    % tests verify the noise mask integrates cleanly with the heard-call pipeline.

    methods (TestClassSetup)
        function add_paths(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'scripts'));
            addpath(fullfile(root_dir, 'src', 'detect'));
            addpath(fullfile(root_dir, 'src', 'features'));
            addpath(fullfile(root_dir, 'src', 'io'));
            addpath(fullfile(root_dir, 'src', 'mask'));
            addpath(genpath(fullfile(root_dir, 'src', 'noise')));
        end
    end

    methods (Test)
        function noise_mask_suppresses_broadband(tc)
            rng(42);
            fs = 48000;
            duration = 2.0;
            n = round(duration * fs);
            x = 1e-4 * randn(n, 1);

            bursts = [0.40 0.62; 1.05 1.28];
            for idx = 1:size(bursts, 1)
                seg = bursts(idx, :);
                s = max(1, floor(seg(1) * fs) + 1);
                e = min(n, ceil(seg(2) * fs));
                x(s:e) = x(s:e) + 6e-4 * randn(e - s + 1, 1);
            end

            params = test_pipeline_with_noise_mask.base_params(fs);
            params.UseNoiseMask = false;

            base_segs = run_detect_heard(struct('x', x, 'fs', fs), zeros(0, 2), [], params);
            tc.assertGreaterThan(size(base_segs, 1), 0, 'baseline detector missed the broadband bursts.');

            params.UseNoiseMask = true;
            params.NoiseParams = test_pipeline_with_noise_mask.aggressive_noise_params(fs);
            noise_label_path = [tempname(), '.txt'];
            tc.addTeardown(@() test_pipeline_with_noise_mask.cleanup_file(noise_label_path));
            params.NoiseLabelPath = noise_label_path;

            masked_segs = run_detect_heard(struct('x', x, 'fs', fs), zeros(0, 2), [], params);
            tc.verifyLessThan(size(masked_segs, 1), size(base_segs, 1), 'noise mask failed to suppress extra detections.');
            tc.verifyLessThanOrEqual(size(masked_segs, 1), 1, 'too many segments remain after masking.');
            tc.verifyEqual(exist(noise_label_path, 'file'), 2, 'noise label file not written.');

            labels = read_audacity_labels(noise_label_path);
            tc.verifyGreaterThan(height(labels), 0);
            tc.verifyTrue(all(labels.onset < labels.offset));
        end

        function noise_mask_preserves_recall(tc)
            rng(51);
            fs = 48000;
            duration = 2.5;
            n = round(duration * fs);
            base_noise = 8e-5 * randn(n, 1);

            truth = [0.55 0.95; 1.40 1.80];
            tone_amp = 4e-4;
            x = base_noise;
            for idx = 1:size(truth, 1)
                seg = truth(idx, :);
                s = max(1, floor(seg(1) * fs) + 1);
                e = min(n, ceil(seg(2) * fs));
                t = (s:e).' / fs;
                window = hann(numel(t));
                x(s:e) = x(s:e) + tone_amp * sin(2 * pi * 7100 * (t - seg(1))) .* window;
            end

            broadband = [0.80 1.05; 1.55 1.95];
            for idx = 1:size(broadband, 1)
                seg = broadband(idx, :);
                s = max(1, floor(seg(1) * fs) + 1);
                e = min(n, ceil(seg(2) * fs));
                x(s:e) = x(s:e) + 5e-4 * randn(e - s + 1, 1);
            end

            params = test_pipeline_with_noise_mask.base_params(fs);
            params.UseNoiseMask = false;

            segs_no_mask = run_detect_heard(struct('x', x, 'fs', fs), zeros(0, 2), [], params);
            cov_no_mask = test_pipeline_with_noise_mask.coverage(segs_no_mask, truth);
            tc.assertGreaterThan(min(cov_no_mask), 0.25, 'baseline recall too low for comparison.');

            params.UseNoiseMask = true;
            params.NoiseParams = NoiseParams(fs);
            params.NoiseParams.TonalityGuard.Enable = true;
            params.NoiseLabelPath = "";

            segs_mask = run_detect_heard(struct('x', x, 'fs', fs), zeros(0, 2), [], params);
            cov_mask = test_pipeline_with_noise_mask.coverage(segs_mask, truth);

            tc.verifyGreaterThanOrEqual(min(cov_mask), min(cov_no_mask) - 0.10, 'noise mask degraded recall excessively.');
            tc.verifyGreaterThan(max(cov_mask), 0.30, 'noise mask failed to keep core recall.');
        end
    end

    methods (Static, Access = private)
        function params = base_params(fs)
            params = struct();
            params.FsTarget = fs;
            params.Win = 0.020;
            params.Hop = 0.010;
            params.BP = [5000 14000];
            params.EntropyBand = [6000 10000];
            params.MAD_Tlow = 0.2;
            params.MAD_Thigh = 0.6;
            params.EntropyQuantile = 0.40;
            params.BackgroundTrim = 0.98;
            params.FluxQuantileEnter = 0.45;
            params.FluxQuantileStay = 0.25;
            params.TonalityQuantileEnter = 0.60;
            params.TonalityQuantileStay = 0.45;
            params.MinEntropyCoverage = 0.30;
            params.MinDur = 0.05;
            params.MaxDur = 0.90;
            params.MergeGap = 0.050;
            params.CloseHole = 0.030;
            params.SelfPadPre = 0.00;
            params.SelfPadPost = 0.00;
            params.UseNoiseMask = false;
            params.NoiseParams = NoiseParams(fs);
            params.NoiseLabelPath = "";
        end

        function noiseParams = aggressive_noise_params(fs)
            noiseParams = NoiseParams(fs);
            noiseParams.BandCoincidence.NRequired = 1;
            noiseParams.BandCoincidence.RequireOOB = false;
            noiseParams.Coverage.CoverageMin = 0.25;
            noiseParams.Flatness.FlatnessMin = 0.30;
            noiseParams.OOB.RatioMin = 0.25;
            noiseParams.TonalityGuard.Enable = false;
        end

        function cov = coverage(segs, truth)
            cov = zeros(size(truth, 1), 1);
            if isempty(segs)
                return;
            end
            for k = 1:size(truth, 1)
                ref = truth(k, :);
                overlaps = min(ref(2), segs(:, 2)) - max(ref(1), segs(:, 1));
                overlaps = overlaps(overlaps > 0);
                cov(k) = sum(overlaps) / max(ref(2) - ref(1), eps);
            end
        end

        function cleanup_file(path)
            if exist(path, 'file') == 2 %#ok<EXIST>
                delete(path);
            end
        end
    end
end
