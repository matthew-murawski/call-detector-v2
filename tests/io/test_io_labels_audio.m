classdef test_io_labels_audio < matlab.unittest.TestCase
    methods (TestClassSetup)
        function add_source_to_path(tc)
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'io'));
            addpath(fullfile(root_dir, 'src', 'label'));
        end
    end

    methods (Test)
        function label_roundtrip(tc)
            intervals = [
                0.125 0.500;
                1.000 1.750;
                2.250 3.000
            ];
            labels = [
                "CALL";
                "HEARD";
                "SILENCE"
            ];

            label_path = [tempname '.txt'];
            cleaner = onCleanup(@() test_io_labels_audio.delete_if_exists(label_path));
            write_audacity_labels(label_path, intervals, labels);
            actual = read_audacity_labels(label_path);

            tc.verifyEqual(actual.onset, intervals(:, 1), 'AbsTol', 1e-6);
            tc.verifyEqual(actual.offset, intervals(:, 2), 'AbsTol', 1e-6);
            tc.verifyEqual(actual.label, labels);
            clear cleaner;
        end

        function read_audio_variants(tc)
            struct_input.x = sin(2 * pi * (0:9) / 10);
            struct_input.fs = 16000;

            [x_struct, fs_struct] = read_audio(struct_input);
            tc.verifyEqual(fs_struct, struct_input.fs);
            tc.verifySize(x_struct, [numel(struct_input.x) 1]);
            tc.verifyEqual(x_struct, struct_input.x(:), 'AbsTol', 1e-12);

            fs = 8000;
            t = (0:fs-1).' / fs;
            audio = 0.5 * sin(2 * pi * 440 * t);
            audio_path = [tempname '.wav'];
            cleaner = onCleanup(@() test_io_labels_audio.delete_if_exists(audio_path));
            audiowrite(audio_path, audio, fs);

            [x_file, fs_file] = read_audio(audio_path);
            tc.verifyEqual(fs_file, fs);
            tc.verifySize(x_file, [numel(audio) 1]);
            tc.verifyEqual(x_file, audio, 'AbsTol', 1e-12);
            clear cleaner;
        end
    end

    methods (Static, Access = private)
        function delete_if_exists(path)
            if exist(path, 'file') == 2
                delete(path);
            end
        end
    end
end
