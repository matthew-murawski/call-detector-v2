function [gateLow, gateIn, gateHigh] = band_gates(bandEnergy, thresholds)
% band_gates converts band energy streams into boolean gates using hysteresis thresholds.

narginchk(2, 2);

if ~isstruct(bandEnergy) || ~isscalar(bandEnergy)
    error('band_gates:InvalidEnergy', 'bandEnergy must be a scalar struct.');
end
if ~isstruct(thresholds) || ~isscalar(thresholds)
    error('band_gates:InvalidThresholds', 'thresholds must be a scalar struct.');
end

bands = {'Low', 'In', 'High'};
gates = cell(1, numel(bands));

for idx = 1:numel(bands)
    name = bands{idx};
    if ~isfield(bandEnergy, name) || ~isfield(thresholds, name)
        error('band_gates:MissingBand', 'bandEnergy and thresholds must include %s.', name);
    end
    energy = double(bandEnergy.(name)(:).');
    energy(~isfinite(energy)) = 0;
    gates{idx} = apply_hysteresis(energy, thresholds.(name));
end

gateLow = gates{1};
gateIn = gates{2};
gateHigh = gates{3};
end

function gate = apply_hysteresis(energy, thresholdStruct)
if ~isstruct(thresholdStruct) || ~isscalar(thresholdStruct)
    error('band_gates:InvalidBandThreshold', 'thresholds for each band must be a scalar struct.');
end
if ~isfield(thresholdStruct, 'Enter') || ~isfield(thresholdStruct, 'Exit')
    error('band_gates:MissingThresholdFields', 'threshold struct must include Enter and Exit.');
end

enter = double(thresholdStruct.Enter(:).');
exit = double(thresholdStruct.Exit(:).');

numFrames = numel(energy);
if numel(enter) == 1
    enter = repmat(enter, 1, numFrames);
end
if numel(exit) == 1
    exit = repmat(exit, 1, numFrames);
end

if numel(enter) ~= numFrames || numel(exit) ~= numFrames
    error('band_gates:LengthMismatch', 'threshold vectors must align with energy length.');
end

exit = min(exit, enter);

state = false;
gate = false(1, numFrames);

for frameIdx = 1:numFrames
    value = energy(frameIdx);
    if state
        if value < exit(frameIdx)
            state = false;
        end
    end
    if ~state && value >= enter(frameIdx)
        state = true;
    end
    gate(frameIdx) = state;
end
end
