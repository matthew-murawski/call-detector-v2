function [S_weighted, coherence] = coherence_weight_spectrogram(S, f, hop_seconds, params)
% coherence_weight_spectrogram emphasises oriented ridges in a power spectrogram.

narginchk(3, 4);
if nargin < 4 || isempty(params)
    params = struct();
elseif ~isstruct(params) || ~isscalar(params)
    error('coherence_weight_spectrogram:InvalidParams', 'params must be a scalar struct.');
end

validateattributes(S, {'numeric'}, {'2d', 'nonempty', 'real', '>=', 0}, mfilename, 'S');
validateattributes(f, {'numeric'}, {'vector', 'numel', size(S, 1)}, mfilename, 'f');
validateattributes(hop_seconds, {'numeric'}, {'scalar', 'real', 'positive'}, mfilename, 'hop_seconds');

params = fill_defaults(params);

if ~params.Enabled
    S_weighted = S;
    if nargout > 1
        coherence = zeros(size(S), 'like', double(S));
    end
    return;
end

orig_class = class(S);
S = double(S);

log_mag = log10(S + params.LogOffset);

[gx, gy] = gradients(log_mag, params.GradKernel);

J11 = gx .^ 2;
J22 = gy .^ 2;
J12 = gx .* gy;

[g_time, g_freq] = gaussian_kernels(params.SigmaTime, params.SigmaFreq, params.TruncationRadius);

J11 = smooth_tensor(J11, g_time, g_freq);
J22 = smooth_tensor(J22, g_time, g_freq);
J12 = smooth_tensor(J12, g_time, g_freq);

trace_val = J11 + J22;
det_term = (J11 - J22) .^ 2 + 4 * (J12 .^ 2);
det_term(det_term < 0) = 0;
root_term = sqrt(det_term);

lambda1 = 0.5 * (trace_val + root_term);
lambda2 = 0.5 * (trace_val - root_term);

coherence = (lambda1 - lambda2) ./ (lambda1 + lambda2 + eps);

if ~isempty(params.Clip)
    coherence = max(params.Clip(1), min(params.Clip(2), coherence));
end

if params.Exponent ~= 1
    coherence = coherence .^ max(params.Exponent, eps);
end

weight = 1 + params.Gain * coherence;
S_weighted = S .* weight;

if nargout > 1
    coherence = cast(coherence, orig_class);
end

S_weighted = cast(S_weighted, orig_class);
end

function params = fill_defaults(params)
defaults = struct(...
    'Enabled', true, ...
    'LogOffset', 1e-8, ...
    'GradKernel', 'central', ...
    'SigmaTime', 1.0, ...
    'SigmaFreq', 1.0, ...
    'TruncationRadius', 3, ...
    'Gain', 1.0, ...
    'Exponent', 1.0, ...
    'Clip', [0 1] ...
    );
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(params, name) || isempty(params.(name))
        params.(name) = defaults.(name);
    end
end

validateattributes(params.Enabled, {'logical', 'numeric'}, {'scalar'});
params.Enabled = logical(params.Enabled);
validateattributes(params.LogOffset, {'numeric'}, {'scalar', 'real', '>', 0});
if ischar(params.GradKernel) || (isstring(params.GradKernel) && isscalar(params.GradKernel))
    params.GradKernel = char(params.GradKernel);
else
    error('coherence_weight_spectrogram:InvalidGradKernel', 'GradKernel must be a string.');
end
validateattributes(params.SigmaTime, {'numeric'}, {'scalar', '>=', 0});
validateattributes(params.SigmaFreq, {'numeric'}, {'scalar', '>=', 0});
validateattributes(params.TruncationRadius, {'numeric'}, {'scalar', 'integer', '>=', 1});
validateattributes(params.Gain, {'numeric'}, {'scalar', 'real', '>=', 0});
validateattributes(params.Exponent, {'numeric'}, {'scalar', 'real', '>=', 0});
if isempty(params.Clip)
    params.Clip = [-inf inf];
else
    validateattributes(params.Clip, {'numeric'}, {'vector', 'numel', 2, 'real'});
    if params.Clip(1) > params.Clip(2)
        error('coherence_weight_spectrogram:InvalidClip', 'Clip bounds must be non-decreasing.');
    end
end
params.Clip = double(params.Clip);
end

function [gx, gy] = gradients(X, kernel_name)
switch lower(kernel_name)
    case 'central'
        kt = [-0.5 0 0.5];
        kf = kt';
    case 'sobel'
        kt = 0.25 * [1 0 -1; 2 0 -2; 1 0 -1];
        kf = kt';
    otherwise
        error('coherence_weight_spectrogram:UnknownKernel', 'Unsupported GradKernel: %s', kernel_name);
end

if ndims(X) ~= 2
    error('coherence_weight_spectrogram:InvalidSpectrogram', 'S must be 2-D.');
end

gx = conv2(X, kt, 'same');
gy = conv2(X, kf, 'same');
end

function [g_time, g_freq] = gaussian_kernels(sigma_time, sigma_freq, radius)
g_time = gaussian_kernel_1d(sigma_time, radius);
g_freq = gaussian_kernel_1d(sigma_freq, radius).';
end

function g = gaussian_kernel_1d(sigma, radius)
if sigma <= 0
    g = 1;
    return;
end
idx = -radius:radius;
g = exp(-(idx .^ 2) / (2 * sigma ^ 2));
g = g / sum(g);
end

function J = smooth_tensor(J, g_time, g_freq)
J = conv2(J, g_freq, 'same');
J = conv2(J, g_time, 'same');
end
