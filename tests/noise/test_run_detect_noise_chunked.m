classdef test_run_detect_noise_chunked < matlab.unittest.TestCase
    % tests ensure chunked noise detection matches single-pass behaviour across boundaries.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'noise'));
        end
    end
    % the test block checks boundary robustness and path handling.

    methods (Test)
        function chunks_cover_boundary_events(tc)
            rng(1);
            fs = 48000;
            duration = 3.0;
            t = (0:round(duration * fs) - 1).' / fs;
            y = zeros(size(t));

            bursts = [0.45 0.65; 1.00 1.18; 2.10 2.28];
            for k = 1:size(bursts, 1)
                mask = t >= bursts(k, 1) & t < bursts(k, 2);
                y(mask) = y(mask) + 0.7 * randn(sum(mask), 1);
            end

            params = NoiseParams(fs);
            params.BandThresholds.kEnter = 0.9;
            params.BandThresholds.kExit = 0.6;
            params.BandCoincidence.NRequired = 1;
            params.BandCoincidence.RequireOOB = false;
            params.Coverage.CoverageMin = 0.25;
            params.Flatness.FlatnessMin = 0.30;
            params.OOB.RatioMin = 0.3;
            params.TonalityGuard.Enable = false;

            chunkOpts = struct('ChunkSec', 1.0, 'OverlapSec', 0.25, 'EdgeGuardSec', 0.05, 'SampleRateOverride', fs);

            [maskChunk, segChunk, metaChunk] = run_detect_noise_chunked(y, params, chunkOpts);
            [maskFull, segFull, metaFull] = run_detect_noise(y, fs, params);

            tc.verifyGreaterThan(size(segChunk, 1), 0);
            tc.verifyEqual(size(segChunk, 2), 2);

            tc.verifyTrue(any(segChunk(:, 1) < 1.05 & segChunk(:, 2) > 0.95));
            tc.verifyTrue(any(segChunk(:, 1) < 2.15 & segChunk(:, 2) > 2.05));

            tc.verifyEqual(size(segChunk, 1), size(segFull, 1));
            tc.verifyLessThan(max(abs(segChunk(:, 1) - segFull(:, 1))), 0.12);
            tc.verifyLessThan(max(abs(segChunk(:, 2) - segFull(:, 2))), 0.12);

            maskFromSegments = noise_segments_to_mask(segChunk, metaChunk.Time);
            tc.verifyEqual(maskChunk, maskFromSegments);

            tc.verifyEqual(numel(metaChunk.Time), numel(maskChunk));
            tc.verifyGreaterThan(numel(metaChunk.Chunks), 1);

            diffMask = double(maskChunk) - double(noise_segments_to_mask(segFull, metaChunk.Time));
            tc.verifyLessThan(max(abs(diffMask)), 1);
        end

        function chunked_matches_path_input(tc)
            fs = 48000;
            t = (0:fs*2-1).' / fs;
            y = sin(2 * pi * 6000 * t);
            params = NoiseParams(fs);
            params.BandThresholds.kEnter = 0.8;
            params.BandThresholds.kExit = 0.6;
            params.BandCoincidence.NRequired = 1;
            params.BandCoincidence.RequireOOB = false;
            params.Coverage.CoverageMin = 0.20;
            params.Flatness.FlatnessMin = 0.25;
            params.OOB.RatioMin = 0.25;
            params.TonalityGuard.Enable = false;

            chunkOpts = struct('ChunkSec', 0.8, 'OverlapSec', 0.2, 'EdgeGuardSec', 0.05);

            chunkOptsArray = chunkOpts;
            chunkOptsArray.SampleRateOverride = fs;
            [maskArray, segArray, metaArray] = run_detect_noise_chunked(y, params, chunkOptsArray);
            tc.verifyEqual(numel(maskArray), numel(metaArray.Time));
            if ~isempty(segArray)
                tc.verifyEqual(size(segArray, 2), 2);
                tc.verifyTrue(all(segArray(:, 2) >= segArray(:, 1)));
            end

            if exist('audiowrite', 'file') == 2
                wavPath = fullfile(tempdir, ['noise_chunk_' char(java.util.UUID.randomUUID()) '.wav']);
                cleaner = onCleanup(@() delete_if_exists(wavPath)); %#ok<NASGU>
                audiowrite(wavPath, y, fs);
                [maskPath, segPath, metaPath] = run_detect_noise_chunked(wavPath, params, chunkOpts);
                tc.verifyEqual(numel(maskPath), numel(metaPath.Time));
                if ~isempty(segPath)
                    tc.verifyEqual(size(segPath, 2), 2);
                    tc.verifyTrue(all(segPath(:, 2) >= segPath(:, 1)));
                end
            end
        end
    end
end

function delete_if_exists(path)
if exist(path, 'file') == 2 %#ok<EXIST>
    delete(path);
end
end
