function write_audacity_labels(path, intervals, labels)
% write audacity label track with 6 decimal places.
% if labels are not provided, only write start/end columns (no third column).

%% validate inputs
if nargin < 2
    error('write_audacity_labels:MissingInput', 'Path and intervals are required.');
end
if ~(ischar(path) || (isstring(path) && isscalar(path)))
    error('write_audacity_labels:InvalidPath', 'Path must be a character vector or string scalar.');
end
validateattributes(intervals, {'numeric'}, {'2d', 'ncols', 2}, mfilename, 'intervals');

labels_provided = (nargin >= 3) && ~isempty(labels);
if labels_provided
    if ~(isstring(labels) || iscellstr(labels) || (iscell(labels) && all(cellfun(@ischar, labels))))
        error('write_audacity_labels:InvalidLabels', 'Labels must be a string array or cell array of character vectors.');
    end
end

%% normalize inputs
path = char(path);
intervals = double(intervals);
if labels_provided
    if size(intervals, 1) ~= numel(labels)
        error('write_audacity_labels:SizeMismatch', 'Intervals and labels must have the same number of rows.');
    end
    labels = string(labels); % normalize to string array
end

%% validate values
if any(~isfinite(intervals(:)))
    error('write_audacity_labels:InvalidIntervals', 'Intervals must contain finite numeric values.');
end
if any(intervals(:, 1) < 0) || any(intervals(:, 2) < 0)
    error('write_audacity_labels:NegativeTime', 'Onset and offset must be nonnegative.');
end
if any(intervals(:, 1) > intervals(:, 2))
    error('write_audacity_labels:InvalidOrder', 'Each interval must satisfy onset <= offset.');
end
if size(intervals, 1) > 1 && any(diff(intervals(:, 1)) < 0)
    error('write_audacity_labels:NonMonotonic', 'Onset times must be nondecreasing.');
end

%% write file
fid = fopen(path, 'w');
if fid == -1
    error('write_audacity_labels:FileOpenFailed', 'Could not open file for writing: %s', path);
end
cleaner = onCleanup(@() fclose(fid));

if labels_provided
    for idx = 1:size(intervals, 1)
        lbl = labels(idx);
        if ismissing(lbl)
            lbl = "";
        end
        % strip any newline/tab just in case
        lbl = replace(replace(lbl, newline, ' '), sprintf('\t'), ' ');
        fprintf(fid, '%.6f\t%.6f\t%s\n', intervals(idx, 1), intervals(idx, 2), char(lbl));
    end
else
    % no labels: write only start/end columns
    for idx = 1:size(intervals, 1)
        fprintf(fid, '%.6f\t%.6f\n', intervals(idx, 1), intervals(idx, 2));
    end
end
end