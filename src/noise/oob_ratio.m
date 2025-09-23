function ratio = oob_ratio(S, f, inBandHz)
% oob_ratio compares per-frame energy outside the monitored band against in-band energy.

validateattributes(S, {'numeric'}, {'2d'}, mfilename, 'S');
validateattributes(f, {'numeric'}, {'vector', 'nonempty', 'real', 'finite'}, mfilename, 'f');
f = double(f(:));
if size(S, 1) ~= numel(f)
    error('oob_ratio:FrequencyMismatch', 'length of f must match size(S, 1).');
end
validateattributes(inBandHz, {'numeric'}, {'vector', 'numel', 2, 'real', 'finite'}, mfilename, 'inBandHz');
inBandHz = double(inBandHz(:).');

powerSpec = abs(double(S)).^2;
powerSpec(~isfinite(powerSpec)) = 0;
insideMask = f >= inBandHz(1) & f <= inBandHz(2);

insideEnergy = sum(powerSpec(insideMask, :), 1);
outsideEnergy = sum(powerSpec, 1) - insideEnergy;

if ~any(insideMask)
    insideEnergy = eps * ones(1, size(S, 2));
end
denominator = insideEnergy;
denominator(denominator <= 0) = eps;
ratio = outsideEnergy ./ denominator;
ratio(~isfinite(ratio)) = 0;
end
