function T = read_audacity_labels(path)
    % read audacity label rows from a tab-separated file.

    if ~(ischar(path) || (isstring(path) && isscalar(path)))
        error('read_audacity_labels:InvalidPath', ...
            'path must be a character vector or scalar string.');
    end

    if isstring(path)
        path = char(path);
    end

    if exist(path, 'file') ~= 2
        error('read_audacity_labels:MissingFile', 'file not found: %s', path);
    end

    fid = fopen(path, 'r');
    if fid < 0
        error('read_audacity_labels:OpenFailed', 'unable to open file: %s', path);
    end

    cleaner = onCleanup(@() fclose(fid));
    raw = textscan(fid, '%f%f%s', 'Delimiter', '\t', 'Whitespace', '', ...
        'ReturnOnError', false, 'CollectOutput', false);

    onset = raw{1};
    offset = raw{2};
    label = raw{3};

    if isempty(onset)
        onset = zeros(0, 1);
        offset = zeros(0, 1);
        label = cell(0, 1);
    end

    if numel(onset) ~= numel(offset) || numel(onset) ~= numel(label)
        error('read_audacity_labels:ColumnMismatch', ...
            'file must contain exactly three columns.');
    end

    onset = double(onset(:));
    offset = double(offset(:));
    label = string(label(:));

    if any(~isfinite(onset)) || any(~isfinite(offset))
        error('read_audacity_labels:NonFiniteTime', ...
            'onset and offset values must be finite.');
    end

    if any(onset < 0) || any(offset < 0) || any(onset > offset)
        error('read_audacity_labels:InvalidIntervals', ...
            'onset must be nonnegative and no greater than offset.');
    end

    % package validated vectors into a typed table.
    T = table(onset, offset, label, 'VariableNames', {'onset', 'offset', 'label'});
end
