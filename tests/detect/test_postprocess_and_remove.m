classdef test_postprocess_and_remove < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'detect'));
        end
    end

    %% tests
    methods (Test)
        function mvp_segmentation_pipeline(tc)
            % exercise postprocessing and overlap removal on a synthetic case.
            data = test_postprocess_and_remove.synthetic_case();
            segs = postprocess_segments(data.raw, data.params);
            segs = remove_overlaps(segs, data.self);

            tc.verifyEqual(size(segs, 1), size(data.truth, 1));

            for idx = 1:size(data.truth, 1)
                pred = segs(idx, :);
                truth = data.truth(idx, :);
                iou = test_postprocess_and_remove.interval_iou(pred, truth);
                tc.verifyGreaterThan(iou, 0.5);
                tc.verifyLessThanOrEqual(abs(pred(1) - truth(1)), 0.020 + eps);
                tc.verifyLessThanOrEqual(abs(pred(2) - truth(2)), 0.020 + eps);
            end

            for idx = 1:size(segs, 1)
                overlap = test_postprocess_and_remove.max_overlap(segs(idx, :), data.self);
                tc.verifyLessThanOrEqual(overlap, eps);
            end
        end
    end

    methods (Static, Access = private)
        function data = synthetic_case()
            % craft raw detections, ground truth, and self mask intervals.
            params.MinDur = 0.06;
            params.MaxDur = 0.80;
            params.MergeGap = 0.04;
            params.CloseHole = 0.06;

            raw = [
                0.10 0.18;
                0.23 0.31;
                0.36 0.42;
                0.50 0.54;
                0.94 1.05;
                1.08 1.18;
                1.21 1.33;
                1.40 1.48;
                1.88 1.97;
                2.00 2.08;
                2.11 2.17;
                2.30 3.30;
            ];

            truth = [
                0.10 0.42;
                0.94 1.33;
                1.88 2.17;
            ];

            self = [
                1.39 1.50;
                0.60 0.75;
            ];

            data.raw = raw;
            data.truth = truth;
            data.self = self;
            data.params = params;
        end

        function val = interval_iou(a, b)
            % compute intersection-over-union between two intervals.
            inter = max(0.0, min(a(2), b(2)) - max(a(1), b(1)));
            union = max(a(2), b(2)) - min(a(1), b(1));
            val = inter / max(union, eps);
        end

        function val = max_overlap(seg, mask)
            % return maximum positive overlap between a segment and a mask set.
            if isempty(mask)
                val = 0.0;
                return;
            end
            overlaps = min(seg(2), mask(:, 2)) - max(seg(1), mask(:, 1));
            val = max([0.0; overlaps(:)]);
        end
    end
end
