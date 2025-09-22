classdef test_tune_detector_params < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_detect_paths(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'detect'));
            addpath(fullfile(root_dir, 'scripts'));
        end
    end

    %% tests
    methods (Test)
        function precision_constraint_enforced(tc)
            corpus = struct('audio', struct('x', zeros(4800, 1), 'fs', 48000), ...
                'heard', [0 1; 2 3], ...
                'produced', [1.4 1.6], ...
                'silence', [4 4.3]);
            corpus = repmat(corpus, 1, 1);

            paramGrid = struct('Gate', [0.1, 0.2]);
            savePath = [tempname '.json'];

            opts = struct('MinPrecision', 0.6, ...
                'DetectorFcn', @(audio, produced, outPath, params) test_tune_detector_params.stub_detector_precision(audio, produced, outPath, params), ...
                'SavePath', savePath);

            results = tune_detector_params(corpus, paramGrid, opts);

            tc.verifyEqual(results.BestParams.Gate, 0.2);
            tc.verifyEqual(results.AllResults(1).FPProduced, 1);
            tc.verifyEqual(results.AllResults(1).FPSilence, 1);
            tc.verifyEqual(results.AllResults(1).TruePositives, 2);
            tc.verifyEqual(results.AllResults(1).FalsePositives, 2);
            tc.verifyEqual(results.AllResults(2).TruePositives, 1);
            tc.verifyEqual(results.AllResults(2).FalsePositives, 0);
            tc.verifyGreaterThan(results.BestPrecision, 0.9);

            tc.verifyEqual(exist(savePath, 'file'), 2);
            payload = jsondecode(fileread(savePath));
            tc.verifyEqual(payload.Gate, 0.2);
        end

        function fallback_selects_highest_recall(tc)
            corpus = struct('audio', struct('x', zeros(4800, 1), 'fs', 48000), ...
                'heard', [0 1; 2 3], ...
                'produced', zeros(0, 2), ...
                'silence', zeros(0, 2));

            paramGrid = struct('Mode', [1, 2]);
            savePath = [tempname '.json'];

            opts = struct('MinPrecision', 0.99, ...
                'DetectorFcn', @(audio, produced, outPath, params) test_tune_detector_params.stub_detector_low_precision(audio, produced, outPath, params), ...
                'SavePath', savePath);

            results = tune_detector_params(corpus, paramGrid, opts);

            tc.verifyEqual(results.BestParams.Mode, 1);
            tc.verifyEqual(results.AllResults(1).Recall, 1);
            tc.verifyEqual(results.AllResults(2).Recall, 0.5);
            tc.verifyLessThan(results.AllResults(1).Precision, opts.MinPrecision);
            tc.verifyLessThan(results.AllResults(2).Precision, opts.MinPrecision);
        end

        function integrates_with_detector(tc)
            audio = struct('x', zeros(2400, 1), 'fs', 48000);
            heard = [0.02 0.05];
            corpus = struct('audio', audio, 'heard', heard, 'produced', zeros(0, 2), 'silence', zeros(0, 2));

            paramGrid = struct('MAD_Tlow', [0.8], 'MAD_Thigh', [1.4]);
            savePath = [tempname '.json'];

            opts = struct('MinPrecision', 0, 'SavePath', savePath);

            results = tune_detector_params(corpus, paramGrid, opts);

            tc.verifyEqual(numel(results.AllResults), 1);
            tc.verifyEqual(results.CorpusSize, 1);
            tc.verifyGreaterThanOrEqual(results.AllResults(1).PredTotal, 0);
            tc.verifyEqual(exist(savePath, 'file'), 2);
        end
    end

    methods (Static)
        function segs = stub_detector_precision(~, ~, ~, params)
            if params.Gate < 0.15
                segs = [0 1; 1.45 1.55; 2 3; 4.05 4.25];
            else
                segs = [0 1];
            end
        end

        function segs = stub_detector_low_precision(~, ~, ~, params)
            if params.Mode == 1
                segs = [0 1; 2 3; 3.5 3.9];
            else
                segs = [0 1; 3.5 3.9];
            end
        end
    end
end
