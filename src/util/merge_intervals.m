function out = merge_intervals(intervals, varargin)
% intervals: [N×2] on/off in seconds, on<=off
% options: 'GapMerge', default 0 (merge gaps <= GapMerge)
% returns non-overlapping, sorted intervals [M×2]
%% validate inputs
if nargin < 1
    error('merge_intervals:MissingInput', 'The intervals input is required.');
end
validateattributes(intervals, {'numeric'}, {'2d', 'ncols', 2}, mfilename, 'intervals');
if any(isnan(intervals(:))) || any(~isfinite(intervals(:)))
    error('merge_intervals:InvalidIntervals', 'Intervals must be finite values.');
end
if any(intervals(:, 2) < intervals(:, 1))
    error('merge_intervals:InvalidOrder', 'Each interval must satisfy on <= off.');
end

parser = inputParser;
parser.FunctionName = mfilename;
parser.addParameter('GapMerge', 0, @(x) validateattributes(x, {'numeric'}, {'scalar', '>=', 0}, mfilename, 'GapMerge'));
parser.parse(varargin{:});
gap_merge = double(parser.Results.GapMerge);

%% handle empty input
if isempty(intervals)
    out = zeros(0, 2);
    return;
end

%% sort intervals
intervals = sortrows(double(intervals), 1);

%% merge logic
merged = intervals(1, :);
for idx = 2:size(intervals, 1)
    current = intervals(idx, :);
    last = merged(end, :);

    if current(1) <= last(2) + gap_merge
        merged(end, 2) = max(last(2), current(2));
    else
        merged = [merged; current]; %#ok<AGROW>
    end
end

%% output
out = merged;
end
