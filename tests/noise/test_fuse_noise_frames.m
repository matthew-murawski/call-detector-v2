classdef test_fuse_noise_frames < matlab.unittest.TestCase
    % tests confirm tonality guard behaviour when fusing noise detectors.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(genpath(fullfile(root_dir, 'src', 'noise')));
        end
    end
    % the test block covers default or fusion and tonality guard suppression.

    methods (Test)
        function high_tonality_requires_both(tc)
            params = NoiseParams(48000);
            params.TonalityGuard.Enable = true;
            params.TonalityGuard.InBandTonalityThresh = 3.0;

            numFrames = 60;
            noise1 = false(1, numFrames);
            noise2 = false(1, numFrames);
            tonality = ones(1, numFrames);

            noise1(20:30) = true;
            tonality(20:30) = 4.0;

            fused = fuse_noise_frames(noise1, noise2, tonality, params);
            tc.verifyFalse(any(fused(20:30)));
        end

        function low_tonality_allows_or(tc)
            params = NoiseParams(48000);
            params.TonalityGuard.Enable = true;
            params.TonalityGuard.InBandTonalityThresh = 2.5;

            numFrames = 80;
            noise1 = false(1, numFrames);
            noise2 = false(1, numFrames);
            tonality = zeros(1, numFrames);

            noise1(30:40) = true;
            tonality(30:40) = 1.0;

            fused = fuse_noise_frames(noise1, noise2, tonality, params);
            tc.verifyTrue(all(fused(30:40)));
        end

        function disabled_guard_keeps_or(tc)
            params = NoiseParams(48000);
            params.TonalityGuard.Enable = false;

            numFrames = 50;
            noise1 = false(1, numFrames);
            noise2 = false(1, numFrames);
            tonality = 5 * ones(1, numFrames);

            noise2(10:15) = true;

            fused = fuse_noise_frames(noise1, noise2, tonality, params);
            tc.verifyTrue(all(fused(10:15)));
        end

        function tonality_score_detects_peaks(tc)
            fs = 48000;
            f = linspace(0, fs / 2, 257).';
            inBand = [5000 14000];
            numFrames = 3;
            S = zeros(numel(f), numFrames);
            ridgeIdx = find(f >= 8000 & f <= 8200, 1);
            S(:, 1) = 0.5;
            S(ridgeIdx, 2) = 10;
            S(:, 3) = 0.1;

            tone = inband_tonality_score(S, f, inBand);
            tc.verifyLessThan(tone(1), 2.0);
            tc.verifyGreaterThan(tone(2), 4.5);
            tc.verifyLessThan(tone(3), 2.0);
        end
    end
end
