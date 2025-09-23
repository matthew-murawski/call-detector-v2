classdef test_mask_and_labels < matlab.unittest.TestCase
    % tests validate the final mask and optional label writer for noise spans.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'noise'));
        end
    end
    % the test block checks mask coverage, empty behaviour, and label output.

    methods (Test)
        function mask_matches_segments(tc)
            params = NoiseParams(48000);
            numFrames = 120;
            t = (0:numFrames-1) * 0.010;
            fused = false(1, numFrames);
            fused(25:40) = true;
            fused(70:84) = true;

            segments = frames_to_noise_segments(fused, t, params);
            mask = noise_segments_to_mask(segments, t);

            expectedMask = false(size(mask));
            for idx = 1:size(segments, 1)
                spans = (t >= segments(idx, 1)) & (t <= segments(idx, 2));
                expectedMask = expectedMask | spans;
            end

            tc.verifyEqual(mask, expectedMask);
            tc.verifyTrue(all(mask(expectedMask)));
            tc.verifyFalse(any(mask & ~expectedMask));
        end

        function empty_segments_return_empty_mask(tc)
            t = 0:0.01:1;
            mask = noise_segments_to_mask([], t);
            tc.verifyEqual(mask, false(size(t)));
        end

        function label_writer_emits_sorted_rows(tc)
            segments = [0.100 0.250; 0.300 0.550; 0.800 0.900];
            outPath = fullfile(tempdir, ['noise_labels_' char(java.util.UUID.randomUUID()) '.txt']);
            cleaner = onCleanup(@() delete_if_exists(outPath));

            write_noise_labels(segments, outPath);

            contents = strtrim(fileread(outPath));
            lines = strsplit(contents, {'\r', '\n'});
            lines = lines(~cellfun('isempty', lines));
            tc.verifyEqual(numel(lines), size(segments, 1));

            starts = zeros(1, numel(lines));
            stops = zeros(1, numel(lines));
            for idx = 1:numel(lines)
                tokens = strsplit(strtrim(lines{idx}), '\t');
                tc.verifyEqual(tokens{3}, 'NOISE');
                starts(idx) = str2double(tokens{1});
                stops(idx) = str2double(tokens{2});
            end

            tc.verifyTrue(all(diff(starts) >= -1e-9));
            tc.verifyTrue(all(diff(stops) >= -1e-9));
            tc.verifyEqual(starts, segments(:, 1).');
            tc.verifyEqual(stops, segments(:, 2).');
        end
    end
end

function delete_if_exists(path)
if exist(path, 'file') == 2 %#ok<EXIST>
    delete(path);
end
end
