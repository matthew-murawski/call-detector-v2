function write_noise_labels(segments, outPath)
% write_noise_labels saves noise spans as an audacity-compatible label file.

if nargin < 2 || isempty(outPath)
    error('write_noise_labels:MissingPath', 'outPath must be provided.');
end
if isempty(segments)
    data = zeros(0, 2);
else
    validateattributes(segments, {'numeric'}, {'2d', 'ncols', 2, 'real', 'finite'}, mfilename, 'segments');
    data = double(segments);
end

if isstring(outPath)
    outPath = char(outPath);
elseif ~ischar(outPath)
    error('write_noise_labels:InvalidPathType', 'outPath must be a char vector or string scalar.');
end

[fid, msg] = fopen(outPath, 'w');
if fid == -1
    error('write_noise_labels:FileOpenFailed', 'could not open %s: %s', outPath, msg);
end
cleanup = onCleanup(@() fclose(fid));

for idx = 1:size(data, 1)
    fprintf(fid, '%.6f\t%.6f\tNOISE\n', data(idx, 1), data(idx, 2));
end
end
