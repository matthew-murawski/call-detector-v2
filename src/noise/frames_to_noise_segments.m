function segments = frames_to_noise_segments(fusedFrames, t, params)
% frames_to_noise_segments converts fused noise frames into time spans using hysteresis settings.

narginchk(3, 3);

frames = logical(fusedFrames(:).');
validateattributes(t, {'numeric'}, {'vector', 'real', 'finite'}, mfilename, 't');
time_axis = double(t(:).');
if numel(frames) ~= numel(time_axis)
    error('frames_to_noise_segments:LengthMismatch', 'fusedFrames and t must align.');
end

if ~isstruct(params) || ~isscalar(params) || ~isfield(params, 'Hysteresis')
    error('frames_to_noise_segments:InvalidParams', 'params must include a Hysteresis struct.');
end

segments = hysteresis_and_segments(frames, time_axis, params.Hysteresis);
end
