function validate_noise_params(params, fs)
% validate_noise_params ensures the noise detector defaults land in safe bounds.
% supply the current sample rate so frequency checks can assert against nyquist.

narginchk(2, 2);

if ~isstruct(params) || ~isscalar(params)
    error('validate_noise_params:InvalidParams', 'params must be a scalar struct.');
end

validateattributes(fs, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'fs');

expectedFields = {'BandsHz', 'BandCoincidence', 'BandThresholds', 'Coverage', ...
    'Flatness', 'OOB', 'Hysteresis', 'TonalityGuard', 'Output'};
for idx = 1:numel(expectedFields)
    if ~isfield(params, expectedFields{idx})
        error('validate_noise_params:MissingField', 'params.%s must be supplied.', expectedFields{idx});
    end
end

if isfield(params, 'SampleRate')
    validateattributes(params.SampleRate, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
    if abs(params.SampleRate - fs) > 1e-6
        error('validate_noise_params:SampleRateMismatch', 'params.SampleRate must match fs.');
    end
end

% check the band layout so the stage does not operate on overlapping ranges.
bands = params.BandsHz;
if ~isstruct(bands) || ~isscalar(bands)
    error('validate_noise_params:BandsStruct', 'params.BandsHz must be a scalar struct.');
end

bandNames = {'Low', 'In', 'High'};
for idx = 1:numel(bandNames)
    name = bandNames{idx};
    if ~isfield(bands, name)
        error('validate_noise_params:MissingBand', 'params.BandsHz.%s must be supplied.', name);
    end
    edge = bands.(name);
    validateattributes(edge, {'numeric'}, {'vector', 'numel', 2, 'real', 'finite'});
    edge = double(edge(:).');
    if ~(edge(1) < edge(2))
        error('validate_noise_params:BandOrder', 'params.BandsHz.%s must have a lower than upper frequency.', name);
    end
    bands.(name) = edge;
end

lowBand = bands.Low;
inBand = bands.In;
highBand = bands.High;

if lowBand(1) < 0
    error('validate_noise_params:LowBandNegative', 'params.BandsHz.Low must start at or above 0 Hz.');
end
if lowBand(2) >= inBand(1)
    error('validate_noise_params:LowInOverlap', 'params.BandsHz.Low must end below params.BandsHz.In.');
end
if inBand(2) >= highBand(1)
    error('validate_noise_params:InHighOverlap', 'params.BandsHz.In must end below params.BandsHz.High.');
end
if highBand(2) <= highBand(1)
    error('validate_noise_params:HighBandOrder', 'params.BandsHz.High must keep increasing frequencies.');
end

nyquist = fs / 2;
if highBand(2) > nyquist
    warning('validate_noise_params:HighBandBeyondNyquist', ...
        'high band upper edge %.1f Hz exceeds the nyquist limit %.1f Hz.', highBand(2), nyquist);
end
if inBand(2) > nyquist
    warning('validate_noise_params:InBandBeyondNyquist', ...
        'in-band upper edge %.1f Hz exceeds the nyquist limit %.1f Hz.', inBand(2), nyquist);
end

% confirm threshold and gating knobs land within safe numeric ranges.
coincidence = params.BandCoincidence;
if ~isstruct(coincidence) || ~isscalar(coincidence)
    error('validate_noise_params:CoincidenceStruct', 'params.BandCoincidence must be a scalar struct.');
end
validateattributes(coincidence.NRequired, {'numeric'}, {'scalar', 'integer', '>=', 1});
numBands = numel(bandNames);
if coincidence.NRequired > numBands
    error('validate_noise_params:NRequiredTooHigh', 'params.BandCoincidence.NRequired cannot exceed the number of bands.');
end
validateattributes(coincidence.RequireOOB, {'logical'}, {'scalar'});

thresholds = params.BandThresholds;
if ~isstruct(thresholds) || ~isscalar(thresholds)
    error('validate_noise_params:ThresholdStruct', 'params.BandThresholds must be a scalar struct.');
end
if ~isfield(thresholds, 'method') || ~isfield(thresholds, 'kEnter') || ~isfield(thresholds, 'kExit') || ~isfield(thresholds, 'RollingWindowSec')
    error('validate_noise_params:ThresholdFields', 'params.BandThresholds must include method, kEnter, kExit, and RollingWindowSec.');
end
method = thresholds.method;
if isstring(method)
    method = char(method);
end
if ~ischar(method) || isempty(method)
    error('validate_noise_params:ThresholdMethodType', 'params.BandThresholds.method must be a char vector or string.');
end
if ~strcmpi(method, 'MAD')
    error('validate_noise_params:ThresholdMethod', 'params.BandThresholds.method must be "MAD".');
end
validateattributes(thresholds.kEnter, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});
validateattributes(thresholds.kExit, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});
if thresholds.kEnter < thresholds.kExit
    error('validate_noise_params:ThresholdOrder', 'params.BandThresholds.kEnter must be greater than or equal to kExit.');
end
if ~isempty(thresholds.RollingWindowSec)
    validateattributes(thresholds.RollingWindowSec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
end

coverage = params.Coverage;
if ~isstruct(coverage) || ~isscalar(coverage)
    error('validate_noise_params:CoverageStruct', 'params.Coverage must be a scalar struct.');
end
validateattributes(coverage.BinK, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});
validateattributes(coverage.CoverageMin, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});

flatness = params.Flatness;
if ~isstruct(flatness) || ~isscalar(flatness)
    error('validate_noise_params:FlatnessStruct', 'params.Flatness must be a scalar struct.');
end
validateattributes(flatness.FlatnessMin, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});

oob = params.OOB;
if ~isstruct(oob) || ~isscalar(oob)
    error('validate_noise_params:OOBStruct', 'params.OOB must be a scalar struct.');
end
validateattributes(oob.RatioMin, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});

hyst = params.Hysteresis;
if ~isstruct(hyst) || ~isscalar(hyst)
    error('validate_noise_params:HysteresisStruct', 'params.Hysteresis must be a scalar struct.');
end
validateattributes(hyst.MinEventSec, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});
validateattributes(hyst.MaxEventSec, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});
if hyst.MaxEventSec < hyst.MinEventSec
    error('validate_noise_params:HysteresisDuration', 'params.Hysteresis.MaxEventSec must be >= MinEventSec.');
end
validateattributes(hyst.GapCloseSec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
validateattributes(hyst.PrePadSec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
validateattributes(hyst.PostPadSec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});

guard = params.TonalityGuard;
if ~isstruct(guard) || ~isscalar(guard)
    error('validate_noise_params:GuardStruct', 'params.TonalityGuard must be a scalar struct.');
end
validateattributes(guard.Enable, {'logical'}, {'scalar'});
validateattributes(guard.InBandTonalityThresh, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});
mode = guard.Mode;
if isstring(mode)
    mode = char(mode);
end
if ~ischar(mode) || isempty(mode)
    error('validate_noise_params:GuardModeType', 'params.TonalityGuard.Mode must be a char vector or string.');
end
modeLower = lower(mode);
if ~any(strcmp(modeLower, {'soft', 'hard'}))
    error('validate_noise_params:GuardModeValue', 'params.TonalityGuard.Mode must be "soft" or "hard".');
end

outParams = params.Output;
if ~isstruct(outParams) || ~isscalar(outParams)
    error('validate_noise_params:OutputStruct', 'params.Output must be a scalar struct.');
end
validateattributes(outParams.WriteNoiseLabels, {'logical'}, {'scalar'});
end
