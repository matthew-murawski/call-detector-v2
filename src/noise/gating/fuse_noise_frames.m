function fusedFrames = fuse_noise_frames(noiseFrames1, noiseFrames2, tonality, params)
% fuse_noise_frames merges two noise detectors with an optional tonality guard.

narginchk(4, 4);

noiseFrames1 = logical(noiseFrames1(:).');
noiseFrames2 = logical(noiseFrames2(:).');
tonality = double(tonality(:).');

if numel(noiseFrames1) ~= numel(noiseFrames2) || numel(noiseFrames1) ~= numel(tonality)
    error('fuse_noise_frames:LengthMismatch', 'all inputs must share the same length.');
end

if ~isstruct(params) || ~isscalar(params)
    error('fuse_noise_frames:InvalidParams', 'params must be a scalar struct.');
end
if ~isfield(params, 'TonalityGuard')
    error('fuse_noise_frames:MissingTonalityGuard', 'params.TonalityGuard must be supplied.');
end

tonality(~isfinite(tonality)) = 0;

base = noiseFrames1 | noiseFrames2;

if params.TonalityGuard.Enable
    thresh = params.TonalityGuard.InBandTonalityThresh;
    validateattributes(thresh, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
    guardMask = tonality >= thresh;
    guarded = noiseFrames1 & noiseFrames2;
    fusedFrames = base;
    fusedFrames(guardMask) = guarded(guardMask);
else
    fusedFrames = base;
end
end
