classdef test_run_detect_noise < matlab.unittest.TestCase
    % tests validate the stage 0 orchestrator on synthetic audio scenes.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(genpath(fullfile(root_dir, 'src', 'noise')));
        end
    end
    % the test block covers broadband burst detection and ridge rejection.

    methods (Test)
        function detects_broadband_bursts(tc)
            rng(0);
            fs = 48000;
            duration = 0.9;
            t = (0:round(duration * fs) - 1).' / fs;
            y = zeros(size(t));
            burst1 = t >= 0.20 & t < 0.32;
            burst2 = t >= 0.55 & t < 0.68;
            y(burst1) = 0.8 * randn(sum(burst1), 1);
            y(burst2) = 0.8 * randn(sum(burst2), 1);

            params = NoiseParams(fs);
            params.BandThresholds.kEnter = 0.8;
            params.BandThresholds.kExit = 0.6;
            params.BandCoincidence.NRequired = 1;
            params.BandCoincidence.RequireOOB = false;
            params.Coverage.CoverageMin = 0.25;
            params.Flatness.FlatnessMin = 0.30;
            params.OOB.RatioMin = 0.3;
            params.TonalityGuard.Enable = false;
            params.Output.WriteNoiseLabels = true;
            params.Output.LabelPath = fullfile(tempdir, ['noise_' char(java.util.UUID.randomUUID()) '.txt']);
            cleaner = onCleanup(@() delete_if_exists(params.Output.LabelPath));

            [mask, segments, meta] = run_detect_noise(y, fs, params);

            tc.verifyTrue(any(mask));
            tc.verifyGreaterThanOrEqual(size(segments, 1), 2);
            tc.verifyTrue(all(segments(:, 2) - segments(:, 1) > 0));

            firstSeg = segments(1, :);
            tc.verifyGreaterThan(firstSeg(1), 0.12);
            tc.verifyLessThan(firstSeg(1), 0.32);

            tc.verifyTrue(any(meta.CoincidenceFrames));
            tc.verifyTrue(isfield(meta, 'FeatureFrames'));

            tc.verifyEqual(exist(params.Output.LabelPath, 'file'), 2);
            contents = strsplit(strtrim(fileread(params.Output.LabelPath)), {'\r', '\n'});
            contents = contents(~cellfun('isempty', contents));
            tc.verifyEqual(numel(contents), size(segments, 1));
        end

        function narrowband_ridge_rejected(tc)
            fs = 48000;
            duration = 0.8;
            t = (0:round(duration * fs) - 1).' / fs;
            tone = sin(2 * pi * 8000 * t);
            params = NoiseParams(fs);
            params.Coverage.CoverageMin = 0.4;
            params.Flatness.FlatnessMin = 0.4;
            params.OOB.RatioMin = 0.6;

            [mask, segments, meta] = run_detect_noise(tone, fs, params);

            tc.verifyFalse(any(mask));
            tc.verifyEqual(size(segments, 1), 0);
            tc.verifyEqual(sum(meta.FusedFrames), 0);
        end
    end
end

function delete_if_exists(path)
if exist(path, 'file') == 2 %#ok<EXIST>
    delete(path);
end
end
