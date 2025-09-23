classdef test_noise_features < matlab.unittest.TestCase
    % tests quantify coverage, flatness, and out-of-band ratios on synthetic spectra.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(genpath(fullfile(root_dir, 'src', 'noise')));
        end
    end
    % the test block compares broadband slabs against narrow ridges.

    methods (Test)
        function broadband_has_high_metrics(tc)
            numBins = 128;
            f = linspace(0, 20000, numBins).';
            frames = 3;
            broadband = abs(1 + 0.2 * randn(numBins, 1));
            broadband = max(broadband, 0.001);
            oob_mask = (f < 5000) | (f > 14000);
            oob_slab = zeros(numBins, 1);
            oob_slab(oob_mask) = 2.5;
            narrow = zeros(numBins, 1);
            [~, idx] = min(abs(f - 8000));
            narrow(idx) = 5;

            S = [broadband, oob_slab, narrow];

            coverage = spectral_coverage(S);
            flatness = spectral_flatness(S);
            ratio = oob_ratio(S, f, [5000 14000]);

            tc.verifyGreaterThan(coverage(1), 0.10);
            tc.verifyGreaterThan(flatness(1), 0.55);
            tc.verifyGreaterThan(ratio(2), 20);
        end

        function narrowband_is_sparse_and_in_band(tc)
            numBins = 256;
            f = linspace(0, 20000, numBins).';
            narrow = zeros(numBins, 1);
            [~, idx] = min(abs(f - 9000));
            narrow(idx) = 4;
            narrow(idx+1) = 2;
            S = [narrow, narrow / 2];

            coverage = spectral_coverage(S);
            flatness = spectral_flatness(S);
            ratio = oob_ratio(S, f, [5000 14000]);

            tc.verifyLessThan(coverage(1), 0.05);
            tc.verifyLessThan(flatness(1), 0.2);
            tc.verifyLessThan(ratio(1), 0.5);
            tc.verifyLessThan(ratio(2), 0.5);
        end
    end
end
