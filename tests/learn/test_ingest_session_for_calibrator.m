classdef test_ingest_session_for_calibrator < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_learn_paths(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'learn'));
        end
    end

    %% tests
    methods (Test)
        function ignore_unlabeled_drops_segments(tc)
            fs = 48000;
            x = zeros(fs, 1);
            wav_path = [tempname '.wav'];
            audiowrite(wav_path, x, fs);
            cleaner = onCleanup(@() delete(wav_path));

            produced = [0.20 0.40];
            heard = [0.25 0.35];
            silence = [0.50 0.60];
            candidates = [0.26 0.32; 0.70 0.72];

            opts = struct('DetectorCandidates', candidates, 'IgnoreUnlabeled', true);

            tbl = ingest_session_for_calibrator(wav_path, produced, heard, silence, struct(), opts);

            tc.verifyEqual(sum(tbl.source == categorical("detected")), 1);
            tc.verifyEqual(sum(abs(tbl.onset - 0.70) < 1e-6), 0);

            clear cleaner;
        end

        function legacy_mode_keeps_unlabeled(tc)
            fs = 48000;
            x = zeros(fs, 1);
            wav_path = [tempname '.wav'];
            audiowrite(wav_path, x, fs);
            cleaner = onCleanup(@() delete(wav_path));

            produced = [0.20 0.40];
            heard = [0.25 0.35];
            silence = [0.50 0.60];
            candidates = [0.26 0.32; 0.70 0.72];

            opts = struct('DetectorCandidates', candidates, 'IgnoreUnlabeled', false);

            tbl = ingest_session_for_calibrator(wav_path, produced, heard, silence, struct(), opts);

            tc.verifyEqual(sum(tbl.source == categorical("detected")), 2);
            tc.verifyEqual(sum(abs(tbl.onset - 0.70) < 1e-6), 1);

            clear cleaner;
        end
    end
end
