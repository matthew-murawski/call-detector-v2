function flatness = spectral_flatness(S)
% spectral_flatness reports the geometric-to-arithmetic mean ratio of per-frame power.

validateattributes(S, {'numeric'}, {'2d'}, mfilename, 'S');
powerSpec = abs(double(S)).^2;
powerSpec(~isfinite(powerSpec)) = 0;
[numBins, numFrames] = size(powerSpec);
if numBins == 0
    flatness = zeros(1, numFrames);
    return;
end

geo = exp(mean(log(powerSpec + eps), 1));
arith = mean(powerSpec, 1) + eps;
flatness = geo ./ arith;
flatness(~isfinite(flatness)) = 0;
flatness = max(min(flatness, 1), 0);
end
