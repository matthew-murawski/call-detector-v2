classdef test_coherence_weight < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_detect_paths(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'detect'));
        end
    end

    %% tests
    methods (Test)
        function diagonal_ridge_has_high_coherence(tc)
            S = 0.05 * ones(64, 64);
            idx = 1:64;
            S(sub2ind(size(S), idx, idx)) = 10;
            params = test_coherence_weight.default_params();
            params.Gain = 1.0;

            [~, coherence] = coherence_weight_spectrogram(S, linspace(0, 1, 64).', 0.005, params);

            ridge_coh = diag(double(coherence));
            off_mask = true(64);
            off_mask(eye(64) == 1) = false;
            noise_coh = double(coherence(off_mask));

            tc.verifyGreaterThan(mean(ridge_coh), mean(noise_coh) + 0.15);
            tc.verifyLessThan(mean(noise_coh), 0.7);
        end

        function weighting_boosts_ridge_energy(tc)
            S = 0.02 * ones(48, 48);
            for k = 1:48
                col = max(1, min(48, k + round(sin(k / 6) * 3)));
                S(col, k) = 6;
            end

            params = test_coherence_weight.default_params();
            params.Gain = 1.5;

            [S_weighted, coherence] = coherence_weight_spectrogram(S, linspace(0, 1, 48).', 0.004, params);

            ridge_idx = sub2ind(size(S), 1:48, 1:48);
            ridge_energy_raw = mean(S(ridge_idx));
            ridge_energy_weighted = mean(S_weighted(ridge_idx));

            tc.verifyGreaterThan(ridge_energy_weighted, 1.2 * ridge_energy_raw);
            tc.verifyLessThanOrEqual(max(coherence(:)), params.Clip(2) + eps);
        end

        function disabled_mode_returns_original(tc)
            S = rand(16, 20);
            params = test_coherence_weight.default_params();
            params.Enabled = false;

            [S_weighted, coherence] = coherence_weight_spectrogram(S, linspace(0, 1, 16).', 0.01, params);

            tc.verifyEqual(S_weighted, S);
            tc.verifyEqual(size(coherence), size(S));
            tc.verifyEqual(max(coherence(:)), 0);
        end
    end

    methods (Static, Access = private)
        function params = default_params()
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
