function [frame_in, stats] = adaptive_hysteresis(energy, entropy, flux, tonal_ratio, flatness, self_mask, params)
% adaptive_hysteresis performs energy/entropy/flux/tonality/flatness hysteresis detection per frame and returns optional thresholds.

narginchk(7, 7);

%% normalize inputs
validateattributes(energy, {'numeric'}, {'vector', 'nonempty', 'real'}, mfilename, 'energy');
validateattributes(entropy, {'numeric'}, {'vector', 'nonempty', 'real'}, mfilename, 'entropy');
validateattributes(flux, {'numeric'}, {'vector', 'nonempty', 'real'}, mfilename, 'flux');
validateattributes(tonal_ratio, {'numeric'}, {'vector', 'nonempty', 'real'}, mfilename, 'tonal_ratio');
validateattributes(flatness, {'numeric'}, {'vector', 'nonempty', 'real'}, mfilename, 'flatness');
validateattributes(self_mask, {'logical', 'numeric'}, {'vector', 'numel', numel(energy)}, mfilename, 'self_mask');
validateattributes(params, {'struct'}, {'scalar'}, mfilename, 'params');

energy = double(energy(:));
entropy = double(entropy(:));
flux = double(flux(:));
tonal_ratio = double(tonal_ratio(:));
flatness = double(flatness(:));
self_mask = logical(self_mask(:));
if numel(entropy) ~= numel(energy)
    error('adaptive_hysteresis:SizeMismatch', 'energy and entropy must have the same number of frames.');
end
if numel(flux) ~= numel(energy)
    error('adaptive_hysteresis:FluxSizeMismatch', 'energy and flux must have the same number of frames.');
end
if numel(tonal_ratio) ~= numel(energy)
    error('adaptive_hysteresis:TonalSizeMismatch', 'energy and tonal_ratio must have the same number of frames.');
end
if numel(flatness) ~= numel(energy)
    error('adaptive_hysteresis:FlatnessSizeMismatch', 'energy and flatness must have the same number of frames.');
end

%% extract parameters with defaults
if ~isfield(params, 'MAD_Tlow') || isempty(params.MAD_Tlow)
    params.MAD_Tlow = 2.0;
end
if ~isfield(params, 'MAD_Thigh') || isempty(params.MAD_Thigh)
    params.MAD_Thigh = 3.5;
end
if ~isfield(params, 'BackgroundTrim') || isempty(params.BackgroundTrim)
    params.BackgroundTrim = 0.95;
end
if ~isfield(params, 'EntropyQuantile') || isempty(params.EntropyQuantile)
    params.EntropyQuantile = 0.20;
end
if ~isfield(params, 'FluxQuantileEnter') || isempty(params.FluxQuantileEnter)
    params.FluxQuantileEnter = 0.70;
end
if ~isfield(params, 'FluxQuantileStay') || isempty(params.FluxQuantileStay)
    params.FluxQuantileStay = 0.40;
end
if ~isfield(params, 'TonalityQuantileEnter') || isempty(params.TonalityQuantileEnter)
    params.TonalityQuantileEnter = 0.80;
end
if ~isfield(params, 'TonalityQuantileStay') || isempty(params.TonalityQuantileStay)
    params.TonalityQuantileStay = 0.60;
end
if ~isfield(params, 'BroadbandEntropySlack') || isempty(params.BroadbandEntropySlack)
    params.BroadbandEntropySlack = 0;
end
if ~isfield(params, 'BroadbandTonalityQuantile') || isempty(params.BroadbandTonalityQuantile)
    params.BroadbandTonalityQuantile = 0;
end
if ~isfield(params, 'FlatnessQuantile') || isempty(params.FlatnessQuantile)
    params.FlatnessQuantile = 0.90;
end
if ~isfield(params, 'FlatnessSlack') || isempty(params.FlatnessSlack)
    params.FlatnessSlack = 0.10;
end
validateattributes(params.MAD_Tlow, {'numeric'}, {'scalar', 'real', 'nonnegative'}, mfilename, 'params.MAD_Tlow');
validateattributes(params.MAD_Thigh, {'numeric'}, {'scalar', 'real', 'nonnegative', '>=', params.MAD_Tlow}, mfilename, 'params.MAD_Thigh');
validateattributes(params.BackgroundTrim, {'numeric'}, {'scalar', '>', 0, '<=', 1}, mfilename, 'params.BackgroundTrim');
validateattributes(params.EntropyQuantile, {'numeric'}, {'scalar', '>', 0, '<', 1}, mfilename, 'params.EntropyQuantile');
validateattributes(params.FluxQuantileEnter, {'numeric'}, {'scalar', '>', 0, '<', 1}, mfilename, 'params.FluxQuantileEnter');
validateattributes(params.FluxQuantileStay, {'numeric'}, {'scalar', '>', 0, '<', 1}, mfilename, 'params.FluxQuantileStay');
if params.FluxQuantileStay > params.FluxQuantileEnter
    error('adaptive_hysteresis:InvalidFluxQuantiles', 'FluxQuantileStay must be <= FluxQuantileEnter.');
end
validateattributes(params.TonalityQuantileEnter, {'numeric'}, {'scalar', '>', 0, '<', 1}, mfilename, 'params.TonalityQuantileEnter');
validateattributes(params.TonalityQuantileStay, {'numeric'}, {'scalar', '>', 0, '<', 1}, mfilename, 'params.TonalityQuantileStay');
if params.TonalityQuantileStay > params.TonalityQuantileEnter
    error('adaptive_hysteresis:InvalidTonalityQuantiles', 'TonalityQuantileStay must be <= TonalityQuantileEnter.');
end
validateattributes(params.BroadbandEntropySlack, {'numeric'}, {'scalar', '>=', 0}, mfilename, 'params.BroadbandEntropySlack');
validateattributes(params.BroadbandTonalityQuantile, {'numeric'}, {'scalar', '>=', 0, '<=', 1}, mfilename, 'params.BroadbandTonalityQuantile');
validateattributes(params.FlatnessQuantile, {'numeric'}, {'scalar', '>', 0, '<=', 1}, mfilename, 'params.FlatnessQuantile');
validateattributes(params.FlatnessSlack, {'numeric'}, {'scalar', '>=', 0}, mfilename, 'params.FlatnessSlack');

%% sanitise feature values
energy(~isfinite(energy)) = 0;
entropy(~isfinite(entropy)) = inf;
flux(~isfinite(flux)) = 0;
tonal_ratio(~isfinite(tonal_ratio)) = 0;
flatness(~isfinite(flatness)) = 1;

%% derive thresholds from background frames
background_mask = ~self_mask;
if ~any(background_mask)
    background_mask = true(size(self_mask));
end
bg_energy = energy(background_mask);
bg_entropy = entropy(background_mask);
bg_flux = flux(background_mask);
bg_tonal = tonal_ratio(background_mask);
bg_flatness = flatness(background_mask);

trim_q = params.BackgroundTrim;
if trim_q < 1 && ~isempty(bg_energy)
    energy_cut = local_quantile(bg_energy, trim_q);
    trimmed = bg_energy(bg_energy <= energy_cut);
    if ~isempty(trimmed)
        bg_energy = trimmed;
    end
end
if trim_q < 1 && ~isempty(bg_entropy)
    entropy_cut = local_quantile(bg_entropy, trim_q);
    trimmed = bg_entropy(bg_entropy <= entropy_cut);
    if ~isempty(trimmed)
        bg_entropy = trimmed;
    end
end
if trim_q < 1 && ~isempty(bg_flux)
    flux_cut = local_quantile(bg_flux, trim_q);
    trimmed = bg_flux(bg_flux <= flux_cut);
    if ~isempty(trimmed)
        bg_flux = trimmed;
    end
end
if trim_q < 1 && ~isempty(bg_tonal)
    tonal_cut = local_quantile(bg_tonal, trim_q);
    trimmed = bg_tonal(bg_tonal <= tonal_cut);
    if ~isempty(trimmed)
        bg_tonal = trimmed;
    end
end
if trim_q < 1 && ~isempty(bg_flatness)
    flatness_cut = local_quantile(bg_flatness, trim_q);
    trimmed = bg_flatness(bg_flatness <= flatness_cut);
    if ~isempty(trimmed)
        bg_flatness = trimmed;
    end
end

energy_med = median(bg_energy);
energy_mad = median(abs(bg_energy - energy_med));

Tlow = energy_med + params.MAD_Tlow * energy_mad;
Thigh = energy_med + params.MAD_Thigh * energy_mad;

entropy_thr = local_quantile(bg_entropy, params.EntropyQuantile);
if isnan(entropy_thr)
    entropy_thr = inf;
end
flux_enter_thr = local_quantile(bg_flux, params.FluxQuantileEnter);
if isnan(flux_enter_thr)
    flux_enter_thr = 0;
end
flux_stay_thr = local_quantile(bg_flux, params.FluxQuantileStay);
if isnan(flux_stay_thr)
    flux_stay_thr = 0;
end
tonal_enter_thr = local_quantile(bg_tonal, params.TonalityQuantileEnter);
if isnan(tonal_enter_thr)
    tonal_enter_thr = 0;
end
tonal_stay_thr = local_quantile(bg_tonal, params.TonalityQuantileStay);
if isnan(tonal_stay_thr)
    tonal_stay_thr = 0;
end

if isempty(bg_flatness)
    flatness_thr_raw = 1;
else
    flatness_thr_raw = local_quantile(bg_flatness, params.FlatnessQuantile);
    if isnan(flatness_thr_raw)
        flatness_thr_raw = 1;
    end
end
flatness_thr = max(min(flatness_thr_raw - params.FlatnessSlack, 1), 0);
flatness_active = flatness_thr < 1;

broadband_entropy_thr = entropy_thr + params.BroadbandEntropySlack;
if params.BroadbandTonalityQuantile > 0
    broadband_tonal_thr = local_quantile(bg_tonal, params.BroadbandTonalityQuantile);
    if isnan(broadband_tonal_thr)
        broadband_tonal_thr = 0;
    end
else
    broadband_tonal_thr = -inf;
end

%% hysteresis evaluation
tonal_relaxed_enter = (params.BroadbandTonalityQuantile > 0) & (tonal_ratio <= broadband_tonal_thr);
entropy_relaxed = (params.BroadbandEntropySlack > 0) & tonal_relaxed_enter & (entropy <= broadband_entropy_thr);
tonal_relaxed_stay = tonal_relaxed_enter;

entropy_ok_enter = (entropy < entropy_thr) | ((energy > Thigh) & (flux > flux_enter_thr) & entropy_relaxed);
tonal_ok_enter = (tonal_ratio > tonal_enter_thr) | ((energy > Thigh) & (flux > flux_enter_thr) & tonal_relaxed_enter);
flatness_ok_enter = (~flatness_active) | (flatness <= flatness_thr) | ((energy > Thigh) & (tonal_ratio > tonal_enter_thr));

enter_cond = (energy > Thigh) & (flux > flux_enter_thr) & entropy_ok_enter & tonal_ok_enter & flatness_ok_enter;

stay_energy_flux = (energy > Tlow) & (flux > flux_stay_thr);
entropy_relaxed_stay = (params.BroadbandEntropySlack > 0) & tonal_relaxed_stay & (entropy <= broadband_entropy_thr);
entropy_ok_stay = (entropy < entropy_thr) | (stay_energy_flux & entropy_relaxed_stay);
tonal_ok_stay = (tonal_ratio > tonal_stay_thr) | (stay_energy_flux & tonal_relaxed_stay);
flatness_ok_stay = (~flatness_active) | (flatness <= flatness_thr) | (tonal_ratio > tonal_stay_thr);

stay_cond = (stay_energy_flux | entropy_ok_stay) & tonal_ok_stay & flatness_ok_stay;

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

if nargout > 1
    stats = struct('Tlow', Tlow, 'Thigh', Thigh, 'entropy_thr', entropy_thr, ...
        'flux_enter_thr', flux_enter_thr, 'flux_stay_thr', flux_stay_thr, ...
        'tonal_enter_thr', tonal_enter_thr, 'tonal_stay_thr', tonal_stay_thr, ...
        'broadband_entropy_thr', broadband_entropy_thr, 'broadband_tonal_thr', broadband_tonal_thr, ...
        'flatness_thr', flatness_thr);
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
