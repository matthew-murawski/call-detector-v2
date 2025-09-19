function T = read_audacity_labels(path)
% read tab-separated audacity labels into a table.
%% validate input path
if nargin < 1
    error('read_audacity_labels:MissingInput', 'The path input is required.');
end
if ~(ischar(path) || (isstring(path) && isscalar(path)))
    error('read_audacity_labels:InvalidPath', 'Path must be a character vector or string scalar.');
end
path = char(path);
if exist(path, 'file') ~= 2
    error('read_audacity_labels:FileNotFound', 'File not found: %s', path);
end

%% open file and parse contents
fid = fopen(path, 'r');
if fid == -1
    error('read_audacity_labels:FileOpenFailed', 'Could not open file: %s', path);
end
cleaner = onCleanup(@() fclose(fid));
data = textscan(fid, '%f%f%[^\n\r]', 'Delimiter', '\t', ...
    'MultipleDelimsAsOne', false, 'ReturnOnError', false);

%% handle empty file
onset = data{1};
offset = data{2};
raw_labels = data{3};
if isempty(onset)
    T = table('Size', [0 3], 'VariableTypes', {'double', 'double', 'string'}, ...
        'VariableNames', {'onset', 'offset', 'label'});
    return;
end
if numel(offset) ~= numel(onset) || numel(raw_labels) ~= numel(onset)
    error('read_audacity_labels:InvalidFormat', 'Each row must contain onset, offset, and label.');
end

%% convert data types
onset = double(onset(:));
offset = double(offset(:));
labels = string(raw_labels(:));

%% validate values
if any(~isfinite(onset)) || any(~isfinite(offset))
    error('read_audacity_labels:InvalidNumeric', 'Onset and offset must be finite numeric values.');
end
if any(isnan(onset)) || any(isnan(offset))
    error('read_audacity_labels:InvalidNumeric', 'Onset and offset must be numeric.');
end
if any(onset < 0) || any(offset < 0)
    error('read_audacity_labels:NegativeTime', 'Onset and offset must be nonnegative.');
end
if any(onset > offset)
    error('read_audacity_labels:InvalidOrder', 'Each row must satisfy onset <= offset.');
end
if numel(onset) > 1 && any(diff(onset) < 0)
    error('read_audacity_labels:NonMonotonic', 'Onset times must be nondecreasing.');
end

%% assemble table
T = table(onset, offset, labels, 'VariableNames', {'onset', 'offset', 'label'});
end
