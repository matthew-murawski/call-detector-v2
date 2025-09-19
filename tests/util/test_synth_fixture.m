classdef test_synth_fixture < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_fixture_to_path(tc)
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'tests', 'fixtures'));
        end
    end

    %% tests
    methods (Test)
        function fixture_properties(tc)
            [x, fs, self_labels, heard_truth] = make_synth_colony_track();

            tc.verifyEqual(size(x, 2), 1);
            tc.verifyEqual(fs, 24000);

            duration = numel(x) / fs;
            tc.verifyLessThanOrEqual(abs(duration - 30), 0.1);

            tc.verifyEqual(size(self_labels, 1), 2);
            tc.verifyEqual(size(heard_truth, 1), 3);

            self_durations = self_labels(:, 2) - self_labels(:, 1);
            heard_durations = heard_truth(:, 2) - heard_truth(:, 1);

            tc.verifyGreaterThanOrEqual(min(self_durations), 0.2);
            tc.verifyLessThanOrEqual(max(self_durations), 0.6);

            tc.verifyGreaterThanOrEqual(min(heard_durations), 0.2);
            tc.verifyLessThanOrEqual(max(heard_durations), 0.6);
        end
    end
end
