classdef test_segment_features_sanity < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_feature_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'features'));
            addpath(fullfile(root_dir, 'src', 'detect'));
        end
    end

    %% tests
    methods (Test)
        function tone_vs_noise_segments(tc)
            fs = 48000;
            total_duration = 1.0;
            n = round(total_duration * fs);
            t = (0:n-1).' / fs;

            x = 0.003 * randn(n, 1);
            tone_mask = t >= 0.50 & t < 0.90;
            tone_t = t(tone_mask) - 0.50;
            x(tone_mask) = x(tone_mask) + 0.04 * sin(2 * pi * 7000 * tone_t);

            seg_noise = [0.05 0.35];
            seg_tone = [0.55 0.85];

            noise_feats = segment_features(x, fs, seg_noise, struct());
            tone_feats = segment_features(x, fs, seg_tone, struct());

            tc.verifySize(tone_feats, [1 16]);
            tc.verifySize(noise_feats, [1 16]);

            tc.verifyGreaterThan(tone_feats(2), noise_feats(2));
            tc.verifyLessThan(tone_feats(6), noise_feats(6));
            tc.verifyGreaterThan(tone_feats(13), noise_feats(13));
        end
    end
end
