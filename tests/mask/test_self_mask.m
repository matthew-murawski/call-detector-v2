classdef test_self_mask < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_paths(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'mask'));
            addpath(fullfile(root_dir, 'tests', 'fixtures'));
        end
    end

    %% tests
    methods (Test)
        function self_mask_covers_self_and_spares_far(tc)
            [x, fs, self_labels] = make_synth_colony_track();
            hop = 0.01;
            duration = numel(x) / fs;
            nFrames = ceil(duration / hop);

            pad_pre = 1.0;
            pad_post = 0.5;
            mask = build_self_mask(nFrames, hop, self_labels, pad_pre, pad_post);

            tc.verifySize(mask, [nFrames, 1]);
            tc.verifyClass(mask, 'logical');

            frame_starts = (0:nFrames-1).' * hop;
            frame_ends = frame_starts + hop;

            for idx = 1:size(self_labels, 1)
                coverage = (frame_starts < self_labels(idx, 2)) & (frame_ends > self_labels(idx, 1));
                if any(coverage)
                    tc.verifyTrue(all(mask(coverage)));
                end
            end

            near_frames = false(nFrames, 1);
            margin = 2.0;
            for idx = 1:size(self_labels, 1)
                expanded_start = self_labels(idx, 1) - margin;
                expanded_end = self_labels(idx, 2) + margin;
                near_frames = near_frames | ((frame_starts < expanded_end) & (frame_ends > expanded_start));
            end
            far_frames = ~near_frames;
            tc.verifyTrue(any(far_frames));
            tc.verifyFalse(any(mask(far_frames)));
        end
    end
end
