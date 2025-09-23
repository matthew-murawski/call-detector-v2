function noiseFrames = coverage_flatness_oob_gate(coverage, flatness, oob, params)
% coverage_flatness_oob_gate combines coverage, flatness, and oob ratios with simple hysteresis.

narginchk(4, 4);

[coverage, flatness, oob] = sanitise_inputs(coverage, flatness, oob);
validate_params(params);

covThrEnter = params.Coverage.CoverageMin;
covThrExit = determine_exit(params.Coverage, 'CoverageExitMin', covThrEnter);
flatThrEnter = params.Flatness.FlatnessMin;
flatThrExit = determine_exit(params.Flatness, 'FlatnessExitMin', flatThrEnter);
oobThrEnter = params.OOB.RatioMin;
oobThrExit = determine_exit(params.OOB, 'RatioExitMin', oobThrEnter);

enterMask = (coverage >= covThrEnter) & (flatness >= flatThrEnter) & (oob >= oobThrEnter);
stayMask = (coverage >= covThrExit) & (flatness >= flatThrExit) & (oob >= oobThrExit);

noiseFrames = apply_hysteresis(enterMask, stayMask);
end

function [coverage, flatness, oob] = sanitise_inputs(coverage, flatness, oob)
coverage = double(coverage(:).');
flatness = double(flatness(:).');
oob = double(oob(:).');

if numel(coverage) ~= numel(flatness) || numel(coverage) ~= numel(oob)
    error('coverage_flatness_oob_gate:LengthMismatch', 'all feature vectors must share the same length.');
end

coverage(~isfinite(coverage)) = 0;
flatness(~isfinite(flatness)) = 0;
oob(~isfinite(oob)) = 0;
end

function validate_params(params)
if ~isstruct(params) || ~isscalar(params)
    error('coverage_flatness_oob_gate:InvalidParams', 'params must be a scalar struct.');
end
requiredTop = {'Coverage', 'Flatness', 'OOB'};
for idx = 1:numel(requiredTop)
    if ~isfield(params, requiredTop{idx})
        error('coverage_flatness_oob_gate:MissingField', 'params.%s must be supplied.', requiredTop{idx});
    end
end

validateattributes(params.Coverage.CoverageMin, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});
validateattributes(params.Flatness.FlatnessMin, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});
validateattributes(params.OOB.RatioMin, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
end

function exitThr = determine_exit(structVal, fieldName, enterThr)
scale = 0.9;
if isfield(structVal, fieldName) && ~isempty(structVal.(fieldName))
    exitThr = double(structVal.(fieldName));
else
    exitThr = enterThr * scale;
end
exitThr = min(exitThr, enterThr);
if exitThr < 0
    exitThr = 0;
end
end

function gate = apply_hysteresis(enterMask, stayMask)
numFrames = numel(enterMask);
gate = false(1, numFrames);
state = false;
for idx = 1:numFrames
    if state
        if ~stayMask(idx)
            state = false;
        end
    end
    if ~state && enterMask(idx)
        state = true;
    end
    gate(idx) = state;
end
end
