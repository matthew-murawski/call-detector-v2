function coverage = spectral_coverage(S, method)
% spectral_coverage measures how much of each spectrum exceeds a mad-based floor on magnitudes.

if nargin < 2 || isempty(method)
    method = struct();
end

validateattributes(S, {'numeric'}, {'2d'}, mfilename, 'S');
mag = abs(double(S));
mag(~isfinite(mag)) = 0;
[numBins, numFrames] = size(mag);
if numBins == 0
    coverage = zeros(1, numFrames);
    return;
end

opts = parse_method(method);

med = median(mag, 1);
absDev = abs(mag - med);
madVal = median(absDev, 1) * 1.4826;
madVal(~isfinite(madVal)) = 0;
replace = eps(max(1, med));
madVal(madVal <= 0) = replace(madVal <= 0);
threshold = med + opts.K * madVal;
mask = mag > threshold;
coverage = sum(mask, 1) ./ numBins;
coverage(~isfinite(coverage)) = 0;
end

function opts = parse_method(method)
if isstruct(method)
    opts = method;
elseif isstring(method) || ischar(method)
    opts = struct('Type', char(method));
else
    error('spectral_coverage:InvalidMethod', 'method must be struct or string.');
end

if ~isfield(opts, 'Type') || isempty(opts.Type)
    opts.Type = 'MAD';
end

if ~strcmpi(opts.Type, 'MAD')
    error('spectral_coverage:UnsupportedMethod', 'only "MAD" is supported.');
end

if ~isfield(opts, 'K') || isempty(opts.K)
    opts.K = 1.0;
end
validateattributes(opts.K, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0});
end
