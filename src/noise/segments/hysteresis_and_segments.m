function segments = hysteresis_and_segments(noiseFrames, t, params)
% hysteresis_and_segments converts frame gates into padded time segments with gap closing.

narginchk(3, 3);

noiseFrames = logical(noiseFrames(:).');
validateattributes(t, {'numeric'}, {'vector', 'real', 'finite'}, mfilename, 't');
t = double(t(:).');
if numel(noiseFrames) ~= numel(t)
    error('hysteresis_and_segments:LengthMismatch', 'noiseFrames and t must align.');
end

if ~isstruct(params) || ~isscalar(params)
    error('hysteresis_and_segments:InvalidParams', 'params must be a scalar struct.');
end
required = {'MinEventSec', 'MaxEventSec', 'GapCloseSec', 'PrePadSec', 'PostPadSec'};
for idx = 1:numel(required)
    if ~isfield(params, required{idx})
        error('hysteresis_and_segments:MissingField', 'params.%s must be supplied.', required{idx});
    end
end

minDur = double(params.MinEventSec);
maxDur = double(params.MaxEventSec);
gapClose = double(params.GapCloseSec);
prePad = double(params.PrePadSec);
postPad = double(params.PostPadSec);
validateattributes(minDur, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
validateattributes(maxDur, {'numeric'}, {'scalar', 'real', 'finite', '>=', minDur});
validateattributes(gapClose, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
validateattributes(prePad, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
validateattributes(postPad, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});

if isempty(noiseFrames) || ~any(noiseFrames)
    segments = zeros(0, 2);
    return;
end

edges = frame_edges(t);
segments = frames_to_intervals(noiseFrames, edges);

if isempty(segments)
    return;
end

segments = merge_gaps(segments, gapClose);
segments = apply_min_duration(segments, minDur);
if isempty(segments)
    return;
end

segments = apply_max_duration(segments, maxDur, minDur);
segments(:, 1) = max(0, segments(:, 1) - prePad);
segments(:, 2) = segments(:, 2) + postPad;
segments = merge_overlaps(segments);
end

function edges = frame_edges(t)
numFrames = numel(t);
if numFrames == 1
    span = 0.5;
    edges = [max(0, t(1) - span), t(1) + span];
    return;
end

diffs = diff(t);
medianStep = median(diffs);
if ~isfinite(medianStep) || medianStep <= 0
    medianStep = eps + abs(t(end) - t(1)) / max(1, numFrames - 1);
end

edges = zeros(1, numFrames + 1);
firstStep = diffs(1);
if ~isfinite(firstStep) || firstStep <= 0
    firstStep = medianStep;
end
edges(1) = max(0, t(1) - firstStep / 2);

for idx = 2:numFrames
    edges(idx) = (t(idx-1) + t(idx)) / 2;
end

lastStep = diffs(end);
if ~isfinite(lastStep) || lastStep <= 0
    lastStep = medianStep;
end
edges(end) = t(end) + lastStep / 2;
end

function segments = frames_to_intervals(flags, edges)
flags = logical(flags(:).');
changes = diff([false, flags, false]);
starts = find(changes == 1);
stops = find(changes == -1) - 1;
if isempty(starts)
    segments = zeros(0, 2);
    return;
end
segments = zeros(numel(starts), 2);
for idx = 1:numel(starts)
    s = starts(idx);
    e = stops(idx) + 1;
    segments(idx, :) = [edges(s), edges(e)];
end
end

function segments = merge_gaps(segments, gapClose)
if gapClose <= 0 || size(segments, 1) <= 1
    return;
end

merged = segments(1, :);
for idx = 2:size(segments, 1)
    current = segments(idx, :);
    if current(1) - merged(end, 2) <= gapClose
        merged(end, 2) = max(merged(end, 2), current(2));
    else
        merged(end+1, :) = current; %#ok<AGROW>
    end
end
segments = merged;
end

function segments = apply_min_duration(segments, minDur)
if minDur <= 0
    return;
end
lens = segments(:, 2) - segments(:, 1);
segments = segments(lens >= minDur, :);
end

function segments = apply_max_duration(segments, maxDur, minDur)
if maxDur <= 0
    return;
end
result = zeros(0, 2);
for idx = 1:size(segments, 1)
    startTime = segments(idx, 1);
    stopTime = segments(idx, 2);
    duration = stopTime - startTime;
    if duration <= maxDur + eps(maxDur)
        result(end+1, :) = [startTime, stopTime]; %#ok<AGROW>
        continue;
    end
    remaining = duration;
    cursor = startTime;
    while remaining > 0
        slice = min(maxDur, remaining);
        endTime = cursor + slice;
        if slice < minDur && remaining < minDur
            break;
        end
        result(end+1, :) = [cursor, endTime]; %#ok<AGROW>
        cursor = endTime;
        remaining = stopTime - cursor;
    end
end
segments = result;
end

function segments = merge_overlaps(segments)
if isempty(segments)
    return;
end
segments = sortrows(segments, 1);
merged = segments(1, :);
for idx = 2:size(segments, 1)
    current = segments(idx, :);
    if current(1) <= merged(end, 2)
        merged(end, 2) = max(merged(end, 2), current(2));
    else
        merged(end+1, :) = current; %#ok<AGROW>
    end
end
segments = merged;
end
