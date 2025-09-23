function noiseMask = noise_segments_to_mask(segments, t)
% noise_segments_to_mask marks frame centers that fall inside any noise segment.

validateattributes(t, {'numeric'}, {'vector', 'real', 'finite'}, mfilename, 't');
time_axis = double(t(:).');
mask = false(1, numel(time_axis));

if isempty(segments)
    noiseMask = mask;
    return;
end

validateattributes(segments, {'numeric'}, {'2d', 'ncols', 2}, mfilename, 'segments');
segments = double(segments);
if any(~isfinite(segments(:)))
    error('noise_segments_to_mask:InvalidSegments', 'segments must contain finite values.');
end

for idx = 1:size(segments, 1)
    start_time = segments(idx, 1);
    stop_time = segments(idx, 2);
    if stop_time <= start_time
        continue;
    end
    frame_hits = (time_axis >= start_time) & (time_axis <= stop_time);
    mask = mask | frame_hits;
end

noiseMask = mask;
end
