function tonality = inband_tonality_score(S, f, inBandHz)
% inband_tonality_score rates how peaky the spectrum is inside the monitored band.

validateattributes(S, {'numeric'}, {'2d'}, mfilename, 'S');
validateattributes(f, {'numeric'}, {'vector', 'nonempty', 'real', 'finite'}, mfilename, 'f');
f = double(f(:));
if size(S, 1) ~= numel(f)
    error('inband_tonality_score:FrequencyMismatch', 'length of f must match size(S, 1).');
end
validateattributes(inBandHz, {'numeric'}, {'vector', 'numel', 2, 'real', 'finite'}, mfilename, 'inBandHz');
inBandHz = double(inBandHz(:).');

powerSpec = abs(double(S)).^2;
powerSpec(~isfinite(powerSpec)) = 0;
mask = f >= inBandHz(1) & f <= inBandHz(2);

if ~any(mask)
    tonality = zeros(1, size(S, 2));
    return;
end

bandSpec = powerSpec(mask, :);
peak = max(bandSpec, [], 1);
meanTop = mean_of_topk(bandSpec, 5);
meanTop(meanTop <= eps) = eps;
tonality = peak ./ meanTop;
tonality(~isfinite(tonality)) = 0;
end

function m = mean_of_topk(Sb, k)
[numBins, numFrames] = size(Sb);
if numBins <= k
    m = mean(Sb, 1);
    return;
end

m = zeros(1, numFrames);
for idx = 1:numFrames
    column = Sb(:, idx);
    column = sort(column, 'descend');
    m(idx) = mean(column(1:k));
end
end
