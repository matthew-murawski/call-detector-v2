classdef test_band_energy_envelopes < matlab.unittest.TestCase
    % tests target per-band energy integration over the spectrogram grid.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(genpath(fullfile(root_dir, 'src', 'noise')));
        end
    end
    % the test block covers slabs and narrowband ridges.

    methods (Test)
        function slab_low_and_in(tc)
            f = (0:100:20000).';
            numFrames = 4;
            S = zeros(numel(f), numFrames);
            low_mask = f >= 0 & f <= 800;
            in_mask = f >= 5000 & f <= 14000;
            S(low_mask | in_mask, :) = 1;
            bands = struct('Low', [0 800], 'In', [5000 14000], 'High', [16000 20000]);

            [energy, ~] = band_energy_envelopes(S, f, bands);

            tc.verifyEqual(energy.Low, ones(1, numFrames));
            tc.verifyEqual(energy.In, ones(1, numFrames));
            tc.verifyEqual(energy.High, zeros(1, numFrames));
        end

        function slab_in_and_high(tc)
            f = (0:100:20000).';
            numFrames = 3;
            S = zeros(numel(f), numFrames);
            in_mask = f >= 5000 & f <= 14000;
            high_mask = f >= 16000 & f <= 20000;
            S(in_mask | high_mask, :) = 2;
            bands = struct('Low', [0 800], 'In', [5000 14000], 'High', [16000 20000]);

            [energy, ~] = band_energy_envelopes(S, f, bands);

            tc.verifyEqual(energy.Low, zeros(1, numFrames));
            tc.verifyEqual(energy.In, 2 * ones(1, numFrames));
            tc.verifyEqual(energy.High, 2 * ones(1, numFrames));
        end

        function ridge_in_band(tc)
            f = (0:50:20000).';
            numFrames = 5;
            S = zeros(numel(f), numFrames);
            ridge_freq = 6000;
            [~, idx] = min(abs(f - ridge_freq));
            S(idx, :) = 100;
            bands = struct('Low', [0 800], 'In', [5000 14000], 'High', [16000 20000]);

            [energy, ~] = band_energy_envelopes(S, f, bands);

            tc.verifyGreaterThan(min(energy.In), 0.5);
            tc.verifyEqual(energy.Low, zeros(1, numFrames));
            tc.verifyEqual(energy.High, zeros(1, numFrames));
        end
    end
end
