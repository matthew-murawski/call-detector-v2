function thresholds = robust_band_thresholds(bandEnergy, method, k, rollingWindowFrames)
% robust_band_thresholds derives per-band enter and exit levels using median absolute deviation.

if nargin < 2 || isempty(method)
    method = "MAD";
end
if nargin < 3 || isempty(k)
    k = 1.0;
end
if nargin < 4
    rollingWindowFrames = [];
end

if ~isstruct(bandEnergy) || ~isscalar(bandEnergy)
    error('robust_band_thresholds:InvalidEnergy', 'bandEnergy must be a scalar struct.');
end

method = upper(string(method));
if method ~= "MAD"
    error('robust_band_thresholds:MethodUnsupported', 'only method="MAD" is supported.');
end

[kEnter, kExit] = parse_multipliers(k);
window = parse_window(rollingWindowFrames);

bands = {'Low', 'In', 'High'};
thresholds = struct();

for idx = 1:numel(bands)
    name = bands{idx};
    if ~isfield(bandEnergy, name)
        error('robust_band_thresholds:MissingBand', 'bandEnergy.%s must be supplied.', name);
    end
    energy = sanitize_energy(bandEnergy.(name));
    thresholds.(name) = compute_mad_thresholds(energy, kEnter, kExit, window);
end
end

function energy = sanitize_energy(raw)
if isempty(raw)
    energy = zeros(1, 0);
    return;
end
energy = double(raw(:).');
energy(~isfinite(energy)) = 0;
end

function [kEnter, kExit] = parse_multipliers(k)
if isstruct(k)
    if ~isfield(k, 'Enter') || ~isfield(k, 'Exit')
        error('robust_band_thresholds:InvalidKStruct', 'k struct must include Enter and Exit fields.');
    end
    kEnter = double(k.Enter);
    kExit = double(k.Exit);
elseif isnumeric(k) && isscalar(k)
    kEnter = double(k);
    kExit = double(k);
elseif isnumeric(k) && numel(k) == 2
    kEnter = double(k(1));
    kExit = double(k(2));
else
    error('robust_band_thresholds:InvalidK', 'k must be numeric scalar, numeric pair, or struct.');
end
validateattributes(kEnter, {'numeric'}, {'scalar', 'real', 'finite'}, mfilename, 'kEnter');
validateattributes(kExit, {'numeric'}, {'scalar', 'real', 'finite'}, mfilename, 'kExit');
end

function window = parse_window(value)
if isempty(value)
    window = [];
    return;
end
validateattributes(value, {'numeric'}, {'scalar', 'real', 'finite', '>=', 1}, mfilename, 'rollingWindowFrames');
window = double(round(value));
if window < 1
    window = 1;
end
end

function bandThresholds = compute_mad_thresholds(energy, kEnter, kExit, window)
numFrames = numel(energy);
if numFrames == 0
    bandThresholds = struct('Enter', zeros(1, 0), 'Exit', zeros(1, 0));
    return;
end

madScale = 1.4826;

if isempty(window) || window == 1
    med = median(energy, 'omitnan');
    if isnan(med)
        med = 0;
    end
    absDev = abs(energy - med);
    madVal = median(absDev, 'omitnan') * madScale;
    if isnan(madVal) || madVal <= 0
        madVal = eps(max(1, abs(med)));
    end
    enter = med + kEnter * madVal;
    exit = med + kExit * madVal;
    enter = repmat(enter, 1, numFrames);
    exit = repmat(exit, 1, numFrames);
else
    med = movmedian(energy, window, 'omitnan');
    med(~isfinite(med)) = 0;
    absDev = abs(energy - med);
    madVal = movmedian(absDev, window, 'omitnan') * madScale;
    madVal(~isfinite(madVal)) = 0;
    madVal(madVal <= 0) = eps(max(1, max(abs(med))));
    enter = med + kEnter * madVal;
    exit = med + kExit * madVal;
end

exit = min(exit, enter);
bandThresholds = struct('Enter', reshape(enter, 1, numFrames), 'Exit', reshape(exit, 1, numFrames));
end
