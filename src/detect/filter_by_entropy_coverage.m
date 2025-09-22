function segs = filter_by_entropy_coverage(segs, entropy, hop_seconds, entropy_thr, min_coverage, tonal_ratio, broadband_entropy_thr, broadband_tonal_thr)
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
if nargin < 6 || isempty(tonal_ratio)
    tonal_ratio = [];
else
    validateattributes(tonal_ratio, {'numeric'}, {'vector', 'numel', numel(entropy)}, mfilename, 'tonal_ratio');
    tonal_ratio = double(tonal_ratio(:));
end
if nargin < 7 || isempty(broadband_entropy_thr)
    broadband_entropy_thr = entropy_thr;
end
if nargin < 8 || isempty(broadband_tonal_thr)
    broadband_tonal_thr = -inf;
end

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
    entropy_hits = entropy(hits);
    if isempty(tonal_ratio)
        coverage = mean(entropy_hits < entropy_thr);
    else
        tonal_hits = tonal_ratio(hits);
        low_entropy = entropy_hits < entropy_thr;
        broadband_ok = (tonal_hits <= broadband_tonal_thr) & (entropy_hits <= broadband_entropy_thr);
        coverage = mean(low_entropy | broadband_ok);
    end
    keep(idx) = coverage >= min_coverage;
end
segs = segs(keep, :);
end
