function frame_in = adaptive_hysteresis(energy, entropy, self_mask, params)
% adaptive_hysteresis performs energy/entropy hysteresis detection per frame.

narginchk(4, 4);

%% normalize inputs
validateattributes(energy, {'numeric'}, {'vector', 'nonempty', 'real'}, mfilename, 'energy');
validateattributes(entropy, {'numeric'}, {'vector', 'nonempty', 'real'}, mfilename, 'entropy');
validateattributes(self_mask, {'logical', 'numeric'}, {'vector', 'numel', numel(energy)}, mfilename, 'self_mask');
validateattributes(params, {'struct'}, {'scalar'}, mfilename, 'params');

energy = double(energy(:));
entropy = double(entropy(:));
self_mask = logical(self_mask(:));
if numel(entropy) ~= numel(energy)
    error('adaptive_hysteresis:SizeMismatch', 'energy and entropy must have the same number of frames.');
end

%% extract parameters with defaults
if ~isfield(params, 'MAD_Tlow') || isempty(params.MAD_Tlow)
    params.MAD_Tlow = 2.0;
end
if ~isfield(params, 'MAD_Thigh') || isempty(params.MAD_Thigh)
    params.MAD_Thigh = 3.5;
end
if ~isfield(params, 'EntropyQuantile') || isempty(params.EntropyQuantile)
    params.EntropyQuantile = 0.20;
end
validateattributes(params.MAD_Tlow, {'numeric'}, {'scalar', 'real', 'nonnegative'}, mfilename, 'params.MAD_Tlow');
validateattributes(params.MAD_Thigh, {'numeric'}, {'scalar', 'real', 'nonnegative', '>=', params.MAD_Tlow}, mfilename, 'params.MAD_Thigh');
validateattributes(params.EntropyQuantile, {'numeric'}, {'scalar', '>', 0, '<', 1}, mfilename, 'params.EntropyQuantile');

%% sanitise feature values
energy(~isfinite(energy)) = 0;
entropy(~isfinite(entropy)) = inf;

%% derive thresholds from background frames
background_mask = ~self_mask;
if ~any(background_mask)
    background_mask = true(size(self_mask));
end
bg_energy = energy(background_mask);
bg_entropy = entropy(background_mask);

energy_med = median(bg_energy);
energy_mad = median(abs(bg_energy - energy_med));

Tlow = energy_med + params.MAD_Tlow * energy_mad;
Thigh = energy_med + params.MAD_Thigh * energy_mad;

entropy_thr = local_quantile(bg_entropy, params.EntropyQuantile);
if isnan(entropy_thr)
    entropy_thr = inf;
end

%% hysteresis evaluation
enter_cond = (energy > Thigh) & (entropy < entropy_thr);
stay_cond = (energy > Tlow) | (entropy < entropy_thr);

frame_in = false(size(energy));
state = false;
for idx = 1:numel(energy)
    if self_mask(idx)
        state = false;
        frame_in(idx) = false;
        continue;
    end
    if ~state
        if enter_cond(idx)
            state = true;
        end
    else
        if ~stay_cond(idx)
            state = false;
        end
    end
    frame_in(idx) = state;
end
end

function q = local_quantile(x, p)
% local_quantile computes an interpolated quantile without toolbox dependencies.
if isempty(x)
    q = nan;
    return;
end
x = sort(x(:));
n = numel(x);
if n == 1
    q = x;
    return;
end
pos = (n - 1) * p + 1;
low_idx = floor(pos);
high_idx = ceil(pos);
frac = pos - low_idx;
low_val = x(max(low_idx, 1));
high_val = x(min(high_idx, n));
q = low_val + frac * (high_val - low_val);
end
