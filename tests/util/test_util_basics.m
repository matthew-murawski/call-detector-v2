classdef test_util_basics < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_source_to_path(tc)
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'util'));
        end
    end

    %% tests
    methods (Test)
        function timevec_basic(tc)
            fs = 1000;
            n = 5;
            expected = (0:n-1).' / fs;
            actual = timevec(n, fs);
            tc.verifyEqual(actual, expected, 'AbsTol', 1e-12);
        end

        function merge_intervals_cases(tc)
            intervals = [
                0.5 1.5;
                0.0 1.0;
                2.0 4.0;
                2.5 3.0;
                5.0 5.2;
                5.25 5.4;
                6.0 6.1
            ];

            merged = merge_intervals(intervals);
            expected_default = [
                0.0 1.5;
                2.0 4.0;
                5.0 5.2;
                5.25 5.4;
                6.0 6.1
            ];
            tc.verifyEqual(merged, expected_default);

            merged_gap = merge_intervals(intervals, 'GapMerge', 0.1);
            expected_gap = [
                0.0 1.5;
                2.0 4.0;
                5.0 5.4;
                6.0 6.1
            ];
            tc.verifyEqual(merged_gap, expected_gap);
        end
    end
end
