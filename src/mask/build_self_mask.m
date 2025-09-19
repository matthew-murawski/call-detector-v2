function mask = build_self_mask(nFrames, hop, produced_labels, pad_pre, pad_post)
% nframes:int, hop:seconds per frame
% produced_labels [n×2] (s), pad_pre/post (s)
% return logical [nframes×1] marking frames within padded produced windows.

%% validate inputs
if isempty(produced_labels)
    produced_labels = zeros(0, 2);
end
validateattributes(nFrames, {'numeric'}, {'scalar', 'integer', '>=', 0}, mfilename, 'nFrames');
validateattributes(hop, {'numeric'}, {'scalar', 'positive'}, mfilename, 'hop');
validateattributes(produced_labels, {'numeric'}, {'2d', 'ncols', 2}, mfilename, 'produced_labels');
validateattributes(pad_pre, {'numeric'}, {'scalar', '>=', 0}, mfilename, 'pad_pre');
validateattributes(pad_post, {'numeric'}, {'scalar', '>=', 0}, mfilename, 'pad_post');
if any(~isfinite(produced_labels(:)))
    error('build_self_mask:InvalidLabels', 'Labels must be finite.');
end
if any(produced_labels(:, 2) < produced_labels(:, 1))
    error('build_self_mask:InvalidOrder', 'Each label must satisfy onset <= offset.');
end

%% prep constants
nFrames = double(nFrames);
hop = double(hop);
produced_labels = double(produced_labels);
pad_pre = double(pad_pre);
pad_post = double(pad_post);
mask = false(nFrames, 1);
if nFrames == 0 || isempty(produced_labels)
    return;
end

%% build padded intervals and mark frames
padded = [produced_labels(:, 1) - pad_pre, produced_labels(:, 2) + pad_post];
padded = sortrows(padded, 1);
frame_starts = (0:nFrames-1).' .* hop;
frame_ends = frame_starts + hop;
for idx = 1:size(padded, 1)
    window_start = padded(idx, 1);
    window_end = padded(idx, 2);
    hits = (frame_starts < window_end) & (frame_ends > window_start);
    mask = mask | hits;
end
mask = logical(mask);
end
