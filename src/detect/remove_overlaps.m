function segs_out = remove_overlaps(segs, self_intervals)
% drop segments that intersect self intervals.

narginchk(2, 2);
validateattributes(segs, {'numeric'}, {'real', 'finite', 'ncols', 2}, mfilename, 'segs');
validateattributes(self_intervals, {'numeric'}, {'real', 'finite', 'ncols', 2}, mfilename, 'self_intervals');
% prepare sorted intervals and handle trivial cases first.

segs = double(segs);
self_intervals = double(self_intervals);
if isempty(segs)
    segs_out = zeros(0, 2);
    return;
end
segs = sortrows(segs, 1);
if any(segs(:, 2) <= segs(:, 1))
    error('calldetector:remove_overlaps:InvalidSegment', ...
        'Each segment must have stop > start.');
end
if isempty(self_intervals)
    segs_out = segs;
    return;
end
self_intervals = sortrows(self_intervals, 1);
if any(self_intervals(:, 2) <= self_intervals(:, 1))
    error('calldetector:remove_overlaps:InvalidMask', ...
        'Each self interval must have stop > start.');
end

% drop any candidate whose overlap with a mask interval is positive.
keep_mask = false(size(segs, 1), 1);
self_idx = 1;
for idx = 1:size(segs, 1)
    seg = segs(idx, :);
    while self_idx <= size(self_intervals, 1) && self_intervals(self_idx, 2) <= seg(1)
        self_idx = self_idx + 1;
    end
    test_idx = self_idx;
    is_blocked = false;
    while test_idx <= size(self_intervals, 1) && self_intervals(test_idx, 1) < seg(2)
        overlap_amount = min(seg(2), self_intervals(test_idx, 2)) - max(seg(1), self_intervals(test_idx, 1));
        if overlap_amount > 0
            is_blocked = true;
            break;
        end
        test_idx = test_idx + 1;
    end
    keep_mask(idx) = ~is_blocked;
end
segs_out = segs(keep_mask, :);
end
