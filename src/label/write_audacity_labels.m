function write_audacity_labels(path, intervals, labels)
    % write audacity label rows with fixed precision.

    if ~(ischar(path) || (isstring(path) && isscalar(path)))
        error('write_audacity_labels:InvalidPath', ...
            'path must be a character vector or scalar string.');
    end

    if isstring(path)
        path = char(path);
    end

    if ~isnumeric(intervals) || ndims(intervals) ~= 2 || size(intervals, 2) ~= 2
        error('write_audacity_labels:InvalidIntervals', ...
            'intervals must be an N-by-2 numeric array.');
    end

    intervals = double(intervals);
    n = size(intervals, 1);

    if isstring(labels)
        labels = labels(:);
    elseif iscell(labels)
        labels = string(labels(:));
    elseif ischar(labels)
        labels = string(cellstr(labels));
    else
        error('write_audacity_labels:InvalidLabels', ...
            'labels must be a string array or cell array of character vectors.');
    end

    if numel(labels) ~= n
        error('write_audacity_labels:LengthMismatch', ...
            'interval count and label count must match.');
    end

    labels = labels(:);

    if any(~isfinite(intervals(:)))
        error('write_audacity_labels:NonFiniteTime', ...
            'intervals must contain finite values.');
    end

    if any(intervals(:, 1) < 0) || any(intervals(:, 2) < 0) || any(intervals(:, 1) > intervals(:, 2))
        error('write_audacity_labels:InvalidOrder', ...
            'intervals must be nonnegative with onset <= offset.');
    end

    % stream formatted rows to disk.
    fid = fopen(path, 'w');
    if fid < 0
        error('write_audacity_labels:OpenFailed', 'unable to open file: %s', path);
    end

    cleaner = onCleanup(@() fclose(fid));
    for i = 1:n
        fprintf(fid, '%.6f\t%.6f\t%s\n', intervals(i, 1), intervals(i, 2), char(labels(i)));
    end
end
