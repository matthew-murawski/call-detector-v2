function segs = filter_by_entropy_coverage(segs, entropy, hop_seconds, entropy_thr, min_coverage)
% drop segments whose low-entropy coverage falls below a minimum fraction.

if isempty(segs) || min_coverage <= 0 || isinf(entropy_thr)
    return;
end
validateattributes(segs, {'numeric'}, {'2d', 'ncols', 2}, mfilename, 'segs');
validateattributes(entropy, {'numeric'}, {'vector', 'nonempty'}, mfilename, 'entropy');
entropy = double(entropy(:));
validateattributes(hop_seconds, {'numeric'}, {'scalar', 'positive'}, mfilename, 'hop_seconds');
validateattributes(entropy_thr, {'numeric'}, {'scalar', 'real'});
validateattributes(min_coverage, {'numeric'}, {'scalar', 'real', '>=', 0, '<=', 1});
frames = numel(entropy);
frame_starts = ((0:frames-1).' * hop_seconds);
frame_ends = frame_starts + hop_seconds;
keep = false(size(segs, 1), 1);
for idx = 1:size(segs, 1)
    seg = segs(idx, :);
    hits = (frame_starts < seg(2)) & (frame_ends > seg(1));
    if ~any(hits)
        continue;
    end
    coverage = mean(entropy(hits) < entropy_thr);
    keep(idx) = coverage >= min_coverage;
end
segs = segs(keep, :);
end
