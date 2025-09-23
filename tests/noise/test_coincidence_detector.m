classdef test_coincidence_detector < matlab.unittest.TestCase
    % tests validate band coincidence logic and segment hysteresis.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'noise'));
        end
    end
    % the test block hits oob enforcement and simple hysteresis padding.

    methods (Test)
        function coincidence_requires_two_with_oob(tc)
            numFrames = 120;
            gateLow = false(1, numFrames);
            gateIn = false(1, numFrames);
            gateHigh = false(1, numFrames);

            gateLow(20:30) = true;
            gateIn(20:40) = true;
            gateHigh(60:75) = true;
            gateIn(60:80) = true;

            noiseFrames = coincidence_gate(gateLow, gateIn, gateHigh, 2, true);

            expected = false(1, numFrames);
            expected(20:30) = true;
            expected(60:75) = true;
            tc.verifyEqual(noiseFrames, expected);
        end

        function in_band_only_rejected_when_oob_required(tc)
            numFrames = 90;
            gateLow = false(1, numFrames);
            gateHigh = false(1, numFrames);
            gateIn = false(1, numFrames);
            gateIn(10:30) = true;

            noiseFrames = coincidence_gate(gateLow, gateIn, gateHigh, 1, true);
            tc.verifyFalse(any(noiseFrames));

            noiseFramesNoOOB = coincidence_gate(gateLow, gateIn, gateHigh, 1, false);
            tc.verifyTrue(all(noiseFramesNoOOB(10:30)));
        end

        function hysteresis_merges_and_pads_segments(tc)
            numFrames = 120;
            t = (0:numFrames-1) * 0.010;
            frames = false(1, numFrames);
            frames(21:26) = true;
            frames(29:35) = true;
            frames(70:72) = true;

            params = struct( ...
                'MinEventSec', 0.08, ...
                'MaxEventSec', 1.0, ...
                'GapCloseSec', 0.04, ...
                'PrePadSec', 0.05, ...
                'PostPadSec', 0.05 ...
                );

            segments = hysteresis_and_segments(frames, t, params);

            tc.verifyEqual(size(segments, 1), 1);
            tc.verifyEqual(size(segments, 2), 2);

            startExpected = 0.145;
            stopExpected = 0.395;
            tc.verifyLessThan(abs(segments(1, 1) - startExpected), 1e-6);
            tc.verifyLessThan(abs(segments(1, 2) - stopExpected), 1e-6);
        end
    end
end
