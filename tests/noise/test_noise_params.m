classdef test_noise_params < matlab.unittest.TestCase
    % tests confirm the noise parameter defaults stay consistent and validation guards edge cases.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(genpath(fullfile(root_dir, 'src', 'noise')));
        end
    end

    methods (Test)
        function defaults_are_valid(tc)
            fs = 48000;
            params = NoiseParams(fs);
            expected_high_upper = min(0.45 * fs, fs / 2);

            tc.verifyEqual(params.BandsHz.Low, [0 800]);
            tc.verifyEqual(params.BandsHz.In, [5000 14000]);
            tc.verifyEqual(params.BandsHz.High(2), expected_high_upper);
            tc.verifyTrue(params.TonalityGuard.Enable);
            tc.verifyWarningFree(@() validate_noise_params(params, fs));
        end

        function overlapping_bands_error(tc)
            fs = 48000;
            params = NoiseParams(fs);
            params.BandsHz.Low(2) = params.BandsHz.In(1);

            tc.verifyError(@() validate_noise_params(params, fs), 'validate_noise_params:LowInOverlap');
        end

        function high_band_nyquist_warning(tc)
            fs = 48000;
            params = NoiseParams(fs);
            params.BandsHz.High(2) = fs;

            tc.verifyWarning(@() validate_noise_params(params, fs), 'validate_noise_params:HighBandBeyondNyquist');
        end

        function sample_rate_mismatch(tc)
            fs = 48000;
            params = NoiseParams(fs);
            params.SampleRate = fs + 10;

            tc.verifyError(@() validate_noise_params(params, fs), 'validate_noise_params:SampleRateMismatch');
        end

        function nrequired_too_large(tc)
            fs = 48000;
            params = NoiseParams(fs);
            params.BandCoincidence.NRequired = 5;

            tc.verifyError(@() validate_noise_params(params, fs), 'validate_noise_params:NRequiredTooHigh');
        end
    end
end
