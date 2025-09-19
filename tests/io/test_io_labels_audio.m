classdef test_io_labels_audio < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'io'));
            addpath(fullfile(root_dir, 'src', 'label'));
        end
    end

    %% tests
    methods (Test)
        function labels_round_trip(tc)
            intervals = [
                0.123456 0.654321;
                1.234567 2.345678;
                3.456789 4.567890
            ];
            labels = [
                "call one";
                "call two";
                "call three"
            ];
            label_path = [tempname(), '.txt'];
            cleanup_obj = onCleanup(@() delete_if_exists(label_path)); %#ok<NASGU>

            write_audacity_labels(label_path, intervals, labels);
            tbl = read_audacity_labels(label_path);

            tc.verifyEqual(tbl.onset, intervals(:, 1), 'AbsTol', 1e-6);
            tc.verifyEqual(tbl.offset, intervals(:, 2), 'AbsTol', 1e-6);
            tc.verifyEqual(tbl.label, labels);
            tc.verifyClass(tbl.label, 'string');

            labels_cell = {
                'call one';
                'call two';
                'call three'
            };
            write_audacity_labels(label_path, intervals, labels_cell);
            tbl_cell = read_audacity_labels(label_path);

            tc.verifyEqual(tbl_cell.onset, intervals(:, 1), 'AbsTol', 1e-6);
            tc.verifyEqual(tbl_cell.offset, intervals(:, 2), 'AbsTol', 1e-6);
            tc.verifyEqual(tbl_cell.label, string(labels_cell));
        end

        function read_audio_struct_and_wav(tc)
            fs = 8000;
            t = (0:fs-1).' / fs;
            waveform = sin(2 * pi * 440 * t);

            audio_struct.x = waveform.';
            audio_struct.fs = fs;

            [x_struct, fs_struct] = read_audio(audio_struct);
            tc.verifyEqual(fs_struct, fs);
            tc.verifySize(x_struct, size(waveform));
            tc.verifyEqual(x_struct, waveform, 'AbsTol', 1e-12);

            wav_path = [tempname(), '.wav'];
            cleanup_wav = onCleanup(@() delete_if_exists(wav_path)); %#ok<NASGU>
            audiowrite(wav_path, waveform, fs, 'BitsPerSample', 32);

            [x_file, fs_file] = read_audio(wav_path);
            tc.verifyEqual(fs_file, fs);
            tc.verifySize(x_file, size(waveform));
            tc.verifyEqual(x_file, waveform, 'AbsTol', 1e-6);
        end
    end
end

function delete_if_exists(path)
if ~(ischar(path) || (isstring(path) && isscalar(path)))
    return;
end
path = char(path);
if exist(path, 'file') == 2
    delete(path);
end
end
