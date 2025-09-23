function noiseFrames = coincidence_gate(gateLow, gateIn, gateHigh, NRequired, requireOOB)
% coincidence_gate applies n-of-3 band logic with optional out-of-band constraint.

narginchk(5, 5);

[gateLow, gateIn, gateHigh] = sanitise_inputs(gateLow, gateIn, gateHigh);
validateattributes(NRequired, {'numeric'}, {'scalar', 'integer', '>=', 1, '<=', 3}, mfilename, 'NRequired');
validateattributes(requireOOB, {'logical'}, {'scalar'}, mfilename, 'requireOOB');

counts = double(gateLow) + double(gateIn) + double(gateHigh);
noiseFrames = counts >= NRequired;

if requireOOB
    oob = gateLow | gateHigh;
    noiseFrames = noiseFrames & oob;
end
end

function [low, inBand, high] = sanitise_inputs(low, inBand, high)
low = logical(low(:).');
inBand = logical(inBand(:).');
high = logical(high(:).');

lengths = [numel(low), numel(inBand), numel(high)];
if numel(unique(lengths)) ~= 1
    error('coincidence_gate:LengthMismatch', 'all gate inputs must share the same length.');
end
end
