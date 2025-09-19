function write_audacity_labels(path, intervals, labels)
% write audacity label track with 6 decimal places.
%% validate inputs
if nargin < 3
    error('write_audacity_labels:MissingInput', 'All inputs are required.');
end
if ~(ischar(path) || (isstring(path) && isscalar(path)))
    error('write_audacity_labels:InvalidPath', 'Path must be a character vector or string scalar.');
end
validateattributes(intervals, {'numeric'}, {'2d', 'ncols', 2}, mfilename, 'intervals');
if ~(isstring(labels) || iscellstr(labels) || (iscell(labels) && all(cellfun(@ischar, labels))))
    error('write_audacity_labels:InvalidLabels', 'Labels must be a string array or cell array of character vectors.');
end

%% normalize inputs
path = char(path);
intervals = double(intervals);
if iscell(labels)
    labels = string(labels);
else
    labels = string(labels);
end
labels = labels(:);
if size(intervals, 1) ~= numel(labels)
    error('write_audacity_labels:SizeMismatch', 'Intervals and labels must have the same number of rows.');
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
for idx = 1:size(intervals, 1)
    label = labels(idx);
    if ismissing(label)
        label = "";
    end
    fprintf(fid, '%.6f\t%.6f\t%s\n', intervals(idx, 1), intervals(idx, 2), char(label));
end
end
