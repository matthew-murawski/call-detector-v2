classdef test_mvp_e2e < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'detect'));
            addpath(fullfile(root_dir, 'src', 'io'));
            addpath(fullfile(root_dir, 'src', 'label'));
            addpath(fullfile(root_dir, 'src', 'mask'));
            addpath(fullfile(root_dir, 'scripts'));
        end
    end

    %% tests
    methods (Test)
        function pipeline_writes_expected_labels(tc)
            % run the public api and ensure saved labels match return value.
            data = test_mvp_e2e.synthetic_fixture();
            out_path = [tempname(), '.txt'];
            tc.addTeardown(@() test_mvp_e2e.cleanup_file(out_path));

            heard = run_detect_heard(data.audio, data.produced, out_path, data.params);
            tc.verifyGreaterThan(size(heard, 1), 0);

            for idx = 1:size(heard, 1)
                pred = heard(idx, :);
                best = max(arrayfun(@(j) test_mvp_e2e.interval_iou(pred, data.truth(j, :)), 1:size(data.truth, 1)));
                tc.verifyGreaterThan(best, 0.30);
                overlap = test_mvp_e2e.max_overlap(pred, data.produced);
                tc.verifyLessThanOrEqual(overlap, eps);
            end

            table_out = read_audacity_labels(out_path);
            tc.verifyEqual(height(table_out), size(heard, 1));
            file_intervals = [table_out.onset, table_out.offset];
            tc.verifyEqual(file_intervals, heard, 'AbsTol', 1e-9);
            tc.verifyEqual(table_out.label, repmat("HEARD", height(table_out), 1));
        end
    end

    methods (Static, Access = private)
        function data = synthetic_fixture()
            % build a synthetic waveform with three calls and background noise.
            rng(7);
            fs = 48000;
            duration = 2.6;
            n_samples = round(duration * fs);
            noise = 0.005 * randn(n_samples, 1);

            truth = [
                0.30 0.60;
                0.95 1.35;
                1.80 2.20;
            ];

            x = noise;
            for idx = 1:size(truth, 1)
                onset = truth(idx, 1);
                offset = truth(idx, 2);
                start_idx = max(1, floor(onset * fs) + 1);
                stop_idx = min(n_samples, ceil(offset * fs));
                t = (start_idx:stop_idx).' / fs;
                tone = 0.6 * sin(2 * pi * 7000 * (t - onset));
                window = hann(numel(t));
                x(start_idx:stop_idx) = x(start_idx:stop_idx) + tone .* window;
            end

            params = struct();
            params.FsTarget = 48000;
            params.Win = 0.025;
            params.Hop = 0.010;
            params.BP = [5000 14000];
            params.EntropyBand = [6000 10000];
            params.MAD_Tlow = 0.5;
            params.MAD_Thigh = 1.2;
            params.EntropyQuantile = 0.30;
            params.MinDur = 0.10;
            params.MaxDur = 0.90;
            params.MergeGap = 0.080;
            params.CloseHole = 0.060;
            params.SelfPadPre = 0.50;
            params.SelfPadPost = 0.30;

            produced = [
                0.10 0.18;
                1.45 1.60;
            ];

            data.audio = struct('x', x, 'fs', fs);
            data.produced = produced;
            data.truth = truth;
            data.params = params;
        end

        function val = interval_iou(a, b)
            inter = max(0.0, min(a(2), b(2)) - max(a(1), b(1)));
            union = max(a(2), b(2)) - min(a(1), b(1));
            val = inter / max(union, eps);
        end
        function val = max_overlap(seg, mask)
            if isempty(mask)
                val = 0.0;
                return;
            end
            overlaps = min(seg(2), mask(:, 2)) - max(seg(1), mask(:, 1));
            val = max([0.0; overlaps(:)]);
        end


        function cleanup_file(path)
            if exist(path, 'file') == 2
                delete(path);
            end
        end
    end
end
