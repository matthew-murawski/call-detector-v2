classdef test_coverage_flatness_oob_detector < matlab.unittest.TestCase
    % tests combine coverage, flatness, and oob ratio gating with hysteresis.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'noise'));
        end
    end
    % the test block exercises broadband hits, ridge rejection, and segment padding.

    methods (Test)
        function broadband_frames_pass(tc)
            params = NoiseParams(48000);
            numFrames = 120;
            coverage = 0.2 * ones(1, numFrames);
            coverage(30:70) = 0.8;
            flatness = 0.25 * ones(1, numFrames);
            flatness(30:70) = 0.7;
            oob = 0.2 * ones(1, numFrames);
            oob(30:70) = 1.2;

            frames = coverage_flatness_oob_gate(coverage, flatness, oob, params);

            tc.verifyTrue(all(frames(30:70)));
            tc.verifyFalse(any(frames(1:25)));
            tc.verifyFalse(any(frames(80:end)));
        end

        function ridge_is_rejected(tc)
            params = NoiseParams(48000);
            numFrames = 90;
            coverage = 0.04 * ones(1, numFrames);
            coverage(20:30) = 0.06;
            flatness = 0.1 * ones(1, numFrames);
            oob = 0.2 * ones(1, numFrames);

            frames = coverage_flatness_oob_gate(coverage, flatness, oob, params);
            tc.verifyFalse(any(frames));
        end

        function segments_respect_hysteresis(tc)
            params = NoiseParams(48000);
            numFrames = 100;
            coverage = 0.15 * ones(1, numFrames);
            flatness = 0.2 * ones(1, numFrames);
            oob = 0.3 * ones(1, numFrames);

            coverage(30:60) = 0.75;
            coverage(45:46) = 0.58;
            flatness(30:60) = 0.55;
            flatness(45:46) = 0.38;
            oob(30:60) = 0.95;
            oob(45:46) = 0.65;

            frames = coverage_flatness_oob_gate(coverage, flatness, oob, params);
            tc.verifyTrue(all(frames(30:60)));

            t = (0:numFrames-1) * 0.010;
            segments = hysteresis_and_segments(frames, t, params.Hysteresis);
            tc.verifyEqual(size(segments, 1), 1);

            zeroPadParams = params.Hysteresis;
            zeroPadParams.PrePadSec = 0;
            zeroPadParams.PostPadSec = 0;
            baseSegments = hysteresis_and_segments(frames, t, zeroPadParams);

            tc.verifyLessThanOrEqual(segments(1, 1), baseSegments(1, 1));
            tc.verifyGreaterThanOrEqual(segments(1, 2), baseSegments(1, 2));

            expectedStart = max(0, baseSegments(1, 1) - params.Hysteresis.PrePadSec);
            expectedStop = baseSegments(1, 2) + params.Hysteresis.PostPadSec;
            tc.verifyLessThan(abs(segments(1, 1) - expectedStart), 1e-6 + eps); %#ok<EPSFLT>
            tc.verifyLessThan(abs(segments(1, 2) - expectedStop), 1e-6 + eps); %#ok<EPSFLT>
        end
    end
end
