function S_focus = apply_spectral_focus(S, f, focus_band)
%% tighten spectrogram energy toward a target band while keeping some context.

validateattributes(S, {'numeric'}, {'2d'}, mfilename, 'S');
validateattributes(f, {'numeric'}, {'vector', 'numel', size(S, 1)}, mfilename, 'f');
validateattributes(focus_band, {'numeric'}, {'vector', 'numel', 2}, mfilename, 'focus_band');

if isempty(S)
    S_focus = S;
    return;
end

focus_band = double(focus_band(:).');
if focus_band(2) <= focus_band(1)
    S_focus = S;
    return;
end

f = double(f(:));
center = mean(focus_band);
half_width = (focus_band(2) - focus_band(1)) / 2;
if half_width <= 0
    S_focus = S;
    return;
end

sigma = max(half_width / 2, 1) * 2;
weights = exp(-0.5 * ((f - center) / sigma).^2);
max_weight = max(weights);
if max_weight <= 0
    S_focus = S;
    return;
end

weights = weights / max_weight;
floor_weight = 0.05;
weights = floor_weight + (1 - floor_weight) * weights;

S_focus = S .* weights;
end
