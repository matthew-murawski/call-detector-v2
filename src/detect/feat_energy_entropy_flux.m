function feats = feat_energy_entropy_flux(S, f, bands)
% feat_energy_entropy_flux computes energy, entropy, and spectral flux features per frame.

narginchk(3, 3);

%% validate inputs
validateattributes(S, {'numeric'}, {'2d', 'nonempty', 'real', '>=', 0}, mfilename, 'S');
validateattributes(f, {'numeric'}, {'vector', 'numel', size(S, 1)}, mfilename, 'f');
validateattributes(bands, {'struct'}, {'scalar'}, mfilename, 'bands');
if ~isfield(bands, 'energy') || ~isfield(bands, 'entropy')
    error('feat_energy_entropy_flux:MissingBand', 'bands must include energy and entropy fields.');
end
validateattributes(bands.energy, {'numeric'}, {'vector', 'numel', 2}, mfilename, 'bands.energy');
validateattributes(bands.entropy, {'numeric'}, {'vector', 'numel', 2}, mfilename, 'bands.entropy');
S = double(S);
f = double(f(:));

%% compute energy feature
energy_mask = f >= bands.energy(1) & f <= bands.energy(2);
if any(energy_mask)
    energy_vals = sum(S(energy_mask, :), 1).';
else
    energy_vals = zeros(size(S, 2), 1);
end

%% compute entropy feature
entropy_mask = f >= bands.entropy(1) & f <= bands.entropy(2);
entropy_vals = zeros(size(S, 2), 1);
if any(entropy_mask)
    Sb = S(entropy_mask, :);
    total = sum(Sb, 1);
    total_safe = total;
    total_safe(total_safe == 0) = 1;
    p = bsxfun(@rdivide, Sb, total_safe);
    entropy_vals = -sum(p .* log2(p + eps), 1).';
    entropy_vals(total == 0) = 0;
end

%% compute flux feature
flux_mask = energy_mask;
flux_vals = zeros(size(S, 2), 1);
if any(flux_mask)
    Sb = S(flux_mask, :);
    if size(Sb, 2) > 1
        diffs = Sb(:, 2:end) - Sb(:, 1:end-1);
        diffs(diffs < 0) = 0;
        flux_vals(2:end) = sum(diffs, 1).';
    end
end

feats.energy = energy_vals;
feats.entropy = entropy_vals;
feats.flux = flux_vals;
end
