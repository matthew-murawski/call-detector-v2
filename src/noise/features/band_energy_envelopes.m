function [bandEnergy, bandsUsed] = band_energy_envelopes(S, f, bandsHz)
% band_energy_envelopes averages magnitudes inside configured bands for each frame.
% it returns per-band envelopes aligned with the time axis of S.

narginchk(3, 3);

validateattributes(S, {'numeric'}, {'2d'}, mfilename, 'S');
validateattributes(f, {'numeric'}, {'vector', 'nonempty', 'real', 'finite'}, mfilename, 'f');
if size(S, 1) ~= numel(f)
    error('band_energy_envelopes:FrequencyMismatch', 'length of f must match size(S, 1).');
end
if ~isstruct(bandsHz) || ~isscalar(bandsHz)
    error('band_energy_envelopes:InvalidBands', 'bandsHz must be a scalar struct.');
end
requiredFields = {'Low', 'In', 'High'};
for idx = 1:numel(requiredFields)
    if ~isfield(bandsHz, requiredFields{idx})
        error('band_energy_envelopes:MissingBand', 'bandsHz.%s must be supplied.', requiredFields{idx});
    end
    band = bandsHz.(requiredFields{idx});
    validateattributes(band, {'numeric'}, {'vector', 'numel', 2, 'real', 'finite'}, mfilename, ['bandsHz.' requiredFields{idx}]);
    if ~(band(1) <= band(2))
        error('band_energy_envelopes:BandOrder', 'bandsHz.%s must be nondecreasing.', requiredFields{idx});
    end
end

S = abs(double(S));
S(~isfinite(S)) = 0;
f = double(f(:));
numFrames = size(S, 2);

bandEnergy = struct();
bandsUsed = struct();

for idx = 1:numel(requiredFields)
    name = requiredFields{idx};
    band = double(bandsHz.(name));
    mask = f >= band(1) & f <= band(2);
    bandsUsed.(name) = band;
    if ~any(mask)
        bandEnergy.(name) = zeros(1, numFrames);
        continue;
    end
    bandSlice = S(mask, :);
    counts = size(bandSlice, 1);
    averaged = sum(bandSlice, 1) ./ counts;
    bandEnergy.(name) = reshape(averaged, 1, numFrames);
end
end
