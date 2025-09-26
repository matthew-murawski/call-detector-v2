% Batch script to generate produced labels and run heard-call detection
% for a list of sessions.
%
% To use, modify the `sessions_to_process` variable below with the
% desired session numbers.
%
% This script assumes that the following functions are available on the
% MATLAB path:
%   - create_produced_call_labels(session_id, output_path)
%   - run_detect_heard_for_session(session_id)

% -----------------------------------------------------------------------------
%                            CONFIGURATION
% -----------------------------------------------------------------------------
% List of session numbers to process. Add your session numbers here.
sessions_to_process = [177, 178, 179];

% Path to the directory where produced labels should be stored.
% This should match the convention expected by `run_detect_heard_for_session`.
labels_dir = '/Users/matt/Documents/GitHub/vocalization/data/labels';


% -----------------------------------------------------------------------------
%                            BATCH PROCESSING
% -----------------------------------------------------------------------------
fprintf('Starting batch processing for %d sessions...\n', numel(sessions_to_process));

for i = 1:numel(sessions_to_process)
    session_num = sessions_to_process(i);
    fprintf('\n--- Processing session %d (%d of %d) ---\n', session_num, i, numel(sessions_to_process));

    % 1. Generate produced call labels for the session.
    % The output path must match the format expected by the detector.
    sess_id_str = sprintf('S%d', session_num);
    produced_labels_path = fullfile(labels_dir, sprintf('M93A_%s_produced.txt', sess_id_str));

    fprintf('Generating produced labels -> %s\n', produced_labels_path);
    try
        create_produced_call_labels(session_num, produced_labels_path);
        fprintf('Successfully created produced labels for session %d.\n', session_num);
    catch ME
        warning('Failed to create produced labels for session %d.', session_num);
        fprintf('Error: %s\n', ME.message);
        % Decide if you want to continue to the next step or next session
        % continue; % Uncomment to skip to the next session on failure
    end

    % 2. Run the heard-call detector for the session.
    % This function will read the produced labels we just created.
    fprintf('Running heard-call detector for session %d...\n', session_num);
    try
        run_detect_heard_for_session(session_num);
        fprintf('Successfully ran heard-call detector for session %d.\n', session_num);
    catch ME
        warning('Failed to run heard-call detector for session %d.', session_num);
        fprintf('Error: %s\n', ME.message);
    end
end

fprintf('\n--- Batch processing complete. ---\n');