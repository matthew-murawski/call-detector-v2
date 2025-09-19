classdef test_pipeline_with_calibrator < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_paths(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'scripts'));
            addpath(fullfile(root_dir, 'src', 'detect'));
            addpath(fullfile(root_dir, 'src', 'features'));
            addpath(fullfile(root_dir, 'src', 'learn'));
            addpath(fullfile(root_dir, 'src', 'io'));
            addpath(fullfile(root_dir, 'src', 'mask'));
        end
    end

    %% tests
    methods (Test)
        function calibrator_filters_false_positives(tc)
            data = test_pipeline_with_calibrator.synthetic_with_impulses();

            params = data.params;
            params.UseCalibrator = false;
            params.CalibratorPath = "";

            base_segs = run_detect_heard(data.audio, data.produced, [], params);
            tc.assertNotEmpty(base_segs, 'Baseline detection produced no segments.');

            labels = zeros(size(base_segs, 1), 1);
            for idx = 1:size(base_segs, 1)
                labels(idx) = any(test_pipeline_with_calibrator.overlaps(base_segs(idx, :), data.truth));
            end

            feature_rows = zeros(size(base_segs, 1), 16);
            for idx = 1:size(base_segs, 1)
                feature_rows(idx, :) = segment_features(data.audio.x, data.audio.fs, base_segs(idx, :), struct());
            end

            sessions = test_pipeline_with_calibrator.assign_sessions(size(base_segs, 1));

            opts = struct('TargetRecall', 0.95, 'SavePath', [tempname(), '.mat']);
            model = train_calibrator(feature_rows, labels, sessions, opts);
            tc.addTeardown(@() test_pipeline_with_calibrator.cleanup_file(opts.SavePath));
            tc.assertTrue(exist(opts.SavePath, 'file') == 2, 'Expected calibrator file to be saved.');
            tc.verifyGreaterThan(model.Threshold, 0);
            tc.verifyLessThan(model.Threshold, 1);

            params.UseCalibrator = true;
            params.CalibratorPath = opts.SavePath;
            filtered_segs = run_detect_heard(data.audio, data.produced, [], params);

            tc.verifyEqual(size(filtered_segs, 1), size(data.truth, 1));
            for idx = 1:size(filtered_segs, 1)
                tc.verifyTrue(any(test_pipeline_with_calibrator.overlaps(filtered_segs(idx, :), data.truth)));
            end

            removed = setdiff(base_segs, filtered_segs, 'rows');
            tc.assertGreaterThanOrEqual(size(removed, 1), sum(labels == 0), 'Calibrator failed to remove noise segments.');
        end
    end

    methods (Static, Access = private)
        function data = synthetic_with_impulses()
            rng(8);
            fs = 48000;
            duration = 2.4;
            n = round(duration * fs);
            noise = 1e-4 * randn(n, 1);

            truth = [
                0.30 0.60;
                0.95 1.30;
                1.70 2.00;
            ];

            x = noise;
            tone_amp = 4e-4;
            for k = 1:size(truth, 1)
                seg = truth(k, :);
                idx1 = max(1, floor(seg(1) * fs) + 1);
                idx2 = min(n, ceil(seg(2) * fs));
                t = (idx1:idx2).' / fs;
                win = hann(numel(t));
                x(idx1:idx2) = x(idx1:idx2) + tone_amp * sin(2 * pi * 7200 * (t - seg(1))) .* win;
            end

            junk = [0.15 0.24; 0.72 0.82; 1.20 1.30; 2.05 2.15];
            for k = 1:size(junk, 1)
                seg = junk(k, :);
                idx1 = max(1, floor(seg(1) * fs) + 1);
                idx2 = min(n, ceil(seg(2) * fs));
                t = (idx1:idx2).' / fs;
                burst = 6e-4 * randn(numel(t), 1);
                x(idx1:idx2) = x(idx1:idx2) + burst + 2e-4 * sin(2 * pi * (4000 + 3000 * rand()) * (t - seg(1)));
            end

            params = struct();
            params.FsTarget = 48000;
            params.Win = 0.020;
            params.Hop = 0.010;
            params.BP = [5000 14000];
            params.EntropyBand = [6000 10000];
            params.MAD_Tlow = 0.1;
            params.MAD_Thigh = 0.25;
            params.EntropyQuantile = 0.45;
            params.BackgroundTrim = 0.99;
            params.FluxQuantileEnter = 0.40;
            params.FluxQuantileStay = 0.20;
            params.TonalityQuantileEnter = 0.60;
            params.TonalityQuantileStay = 0.40;
            params.MinEntropyCoverage = 0.35;
            params.MinDur = 0.02;
            params.MaxDur = 0.80;
            params.MergeGap = 0.060;
            params.CloseHole = 0.040;
            params.SelfPadPre = 0.0;
            params.SelfPadPost = 0.0;

            data.audio = struct('x', x, 'fs', fs);
            data.produced = zeros(0, 2);
            data.truth = truth;
            data.params = params;
        end

        function tf = overlaps(seg, intervals)
            if isempty(intervals)
                tf = false;
                return;
            end
            overlaps = min(seg(2), intervals(:, 2)) - max(seg(1), intervals(:, 1));
            tf = any(overlaps > 0);
        end

        function sessions = assign_sessions(n)
            ids = repmat(1:3, 1, ceil(n / 3));
            ids = ids(1:n);
            lab = arrayfun(@(k) sprintf('S%d', k), ids, 'UniformOutput', false);
            sessions = categorical(lab(:));
        end

        function cleanup_file(path)
            if exist(path, 'file') == 2
                delete(path);
            end
        end
    end
end
