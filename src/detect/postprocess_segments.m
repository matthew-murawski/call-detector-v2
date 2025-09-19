function segs = postprocess_segments(segs, params)
% remove segments outside duration, merge short gaps, close tiny holes.

narginchk(2, 2);
validateattributes(segs, {'numeric'}, {'real', 'finite', 'ncols', 2}, mfilename, 'segs');
validateattributes(params, {'struct'}, {'scalar'}, mfilename, 'params');

% normalize inputs so later operations run on sorted double precision intervals.
if isempty(segs)
    segs = zeros(0, 2);
    return;
end
segs = double(segs);
segs = sortrows(segs, 1);
if any(segs(:, 2) <= segs(:, 1))
    error('calldetector:postprocess_segments:InvalidInterval', ...
        'Each segment must have stop > start.');
end

% filter out segments outside the allowed duration band.
limits = struct('MinDur', 0.0, 'MaxDur', inf, 'MergeGap', 0.0, 'CloseHole', 0.0);
limit_names = fieldnames(limits);
for idx = 1:numel(limit_names)
    name = limit_names{idx};
    if isfield(params, name)
        limits.(name) = params.(name);
    end
end
validateattributes(limits.MinDur, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(limits.MaxDur, {'numeric'}, {'scalar', 'real', 'positive'});
validateattributes(limits.MergeGap, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(limits.CloseHole, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});

mask = (segs(:, 2) - segs(:, 1)) >= limits.MinDur & (segs(:, 2) - segs(:, 1)) <= limits.MaxDur;
segs = segs(mask, :);
if isempty(segs)
    return;
end

% tidy neighbouring intervals by merging gaps and closing tiny dropouts.
segs = merge_with_gap(segs, limits.MergeGap);
if limits.CloseHole > 0 && size(segs, 1) > 1
    segs = close_small_holes(segs, limits.CloseHole);
end
end

function merged = merge_with_gap(intervals, max_gap)
% join intervals whose gaps are within the tolerance.

if isempty(intervals)
    merged = zeros(0, 2);
    return;
end
merged = zeros(size(intervals));
write_idx = 1;
current = intervals(1, :);
for idx = 2:size(intervals, 1)
    gap = intervals(idx, 1) - current(2);
    if gap <= max_gap
        current(2) = max(current(2), intervals(idx, 2));
    else
        merged(write_idx, :) = current;
        write_idx = write_idx + 1;
        current = intervals(idx, :);
    end
end
merged(write_idx, :) = current;
merged = merged(1:write_idx, :);
end

function closed = close_small_holes(intervals, hole)
% close holes by dilating then eroding the intervals.

if isempty(intervals) || hole <= 0 || size(intervals, 1) == 1
    closed = intervals;
    return;
end
half = hole / 2;
expanded = intervals;
expanded(:, 1) = expanded(:, 1) - half;
expanded(:, 2) = expanded(:, 2) + half;
expanded = merge_with_gap(expanded, 0);
closed = expanded;
closed(:, 1) = closed(:, 1) + half;
closed(:, 2) = closed(:, 2) - half;
end
