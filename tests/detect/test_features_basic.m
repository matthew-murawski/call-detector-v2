classdef test_features_basic < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'detect'));
        end
    end

    %% tests
    methods (Test)
        function energy_rises_with_tone(tc)
            data = test_features_basic.synth_fixture();
            tone_energy = mean(data.feats.energy(data.tone_mask));
            noise_energy = mean(data.feats.energy(~data.tone_mask));
            tc.verifyGreaterThan(tone_energy, 5 * noise_energy);
        end

        function entropy_drops_with_tone(tc)
            data = test_features_basic.synth_fixture();
            tone_entropy = mean(data.feats.entropy(data.tone_mask));
            noise_entropy = mean(data.feats.entropy(~data.tone_mask));
            tc.verifyLessThan(tone_entropy, noise_entropy);
        end

        function flux_spikes_at_onset(tc)
            data = test_features_basic.synth_fixture();
            flux = data.feats.flux;
            onset_idx = find(data.tone_mask, 1);
            pre_noise_idx = 1:max(onset_idx - 1, 1);
            onset_window = max(1, onset_idx - 1):min(length(flux), onset_idx + 1);
            onset_peak = max(flux(onset_window));
            baseline = max(flux(pre_noise_idx));
            tc.verifyGreaterThan(onset_peak, 5 * baseline + 1e-9);
            tc.verifyGreaterThan(onset_peak, 1e-6);
        end
    end

    methods (Static, Access = private)
        function data = synth_fixture()
            rng(42);
            fs = 48000;
            noise_duration = 0.5;
            tone_duration = 0.5;
            noise = 0.01 * randn(round(fs * noise_duration), 1);
            t_tone = (0:round(fs * tone_duration) - 1).' / fs;
            tone = 0.2 * sin(2 * pi * 7000 * t_tone);
            tone = tone + 0.01 * randn(size(tone));
            x = [noise; tone];
            win_length = 1024;
            hop = 256;
            [S, f, t] = frame_spectrogram(x, fs, win_length, hop);
            tone_start = numel(noise) / fs;
            frame_centers = ((0:size(S, 2) - 1) * hop + win_length / 2) / fs;
            tone_mask = frame_centers >= tone_start;
            if ~any(tone_mask)
                tone_mask(end) = true;
            end
            if ~any(~tone_mask)
                tone_mask(1) = false;
            end
            tone_mask = tone_mask(:);
            bands.energy = [5000 14000];
            bands.entropy = [6000 10000];
            feats = feat_energy_entropy_flux(S, f, bands);
            data.feats = feats;
            data.t = t;
            data.tone_mask = tone_mask;
        end
    end
end
