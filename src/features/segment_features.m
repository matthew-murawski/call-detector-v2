function v = segment_features(x, fs, seg, opts)
% segment_features computes summary descriptors for a single audio segment.

narginchk(3, 4);
if nargin < 4
    opts = struct();
elseif isempty(opts)
    opts = struct();
elseif ~isstruct(opts) || ~isscalar(opts)
    error('segment_features:InvalidOpts', 'opts must be a scalar struct.');
end

validateattributes(x, {'numeric'}, {'nonempty'}, mfilename, 'x');
validateattributes(fs, {'numeric'}, {'scalar', 'real', 'positive'}, mfilename, 'fs');
validateattributes(seg, {'numeric'}, {'vector', 'numel', 2, 'real'}, mfilename, 'seg');

x = double(x);
if size(x, 2) > 1
    x = mean(x, 2);
end
x = x(:);
fs = double(fs);
seg = double(seg(:).');

coherence_defaults = struct(...
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
defaults = struct(...
    'Win', 0.025, ...
    'Hop', 0.010, ...
    'EnergyBand', [5000 14000], ...
    'EntropyBand', [6000 10000], ...
    'SubbandLow', [6000 9000], ...
    'SubbandHigh', [9000 12000], ...
    'EnvelopeThreshold', 0.10, ...
    'Coherence', coherence_defaults ...
    );
opts = fill_defaults(opts, defaults);

validate_band(opts.EnergyBand, 'opts.EnergyBand');
validate_band(opts.EntropyBand, 'opts.EntropyBand');
validate_band(opts.SubbandLow, 'opts.SubbandLow');
validate_band(opts.SubbandHigh, 'opts.SubbandHigh');
validateattributes(opts.EnvelopeThreshold, {'numeric'}, {'scalar', 'real', '>=', 0, '<', 1}, mfilename, 'opts.EnvelopeThreshold');
opts.Coherence = fill_coherence_defaults_local(opts.Coherence);

seg_start = max(0, seg(1));
seg_end = min(seg(2), (numel(x) - 1) / fs);
if seg_end <= seg_start || isnan(seg_start) || isnan(seg_end)
    v = zeros(1, 16);
    return;
end

start_idx = max(1, floor(seg_start * fs) + 1);
end_idx = min(numel(x), max(start_idx, ceil(seg_end * fs)));
x_seg = x(start_idx:end_idx);
duration = (end_idx - start_idx + 1) / fs;

if numel(x_seg) < 2
    v = zeros(1, 16);
    v(1) = duration;
    return;
end

win_samples = max(8, round(opts.Win * fs));
hop_samples = max(1, round(opts.Hop * fs));
if hop_samples >= win_samples
    hop_samples = max(1, win_samples - 1);
end

try
[S, f, ~] = frame_spectrogram(x_seg, fs, win_samples, hop_samples);
catch
    S = zeros(0, 0);
    f = zeros(0, 1);
end

if isempty(S)
    energy_feat = zeros(0, 1);
    entropy_feat = zeros(0, 1);
    flux_feat = zeros(0, 1);
else
    hop_seconds = hop_samples / fs;
    [S, ~] = coherence_weight_spectrogram(S, f, hop_seconds, opts.Coherence);
    bands.energy = opts.EnergyBand;
    bands.entropy = opts.EntropyBand;
    feats = feat_energy_entropy_flux(S, f, bands);
    energy_feat = feats.energy;
    entropy_feat = feats.entropy;
    flux_feat = feats.flux;
end

energy_mean = safe_mean(energy_feat);
energy_p10 = safe_quantile(energy_feat, 0.10);
energy_p50 = safe_quantile(energy_feat, 0.50);
energy_p90 = safe_quantile(energy_feat, 0.90);

entropy_mean = safe_mean(entropy_feat);
entropy_p10 = safe_quantile(entropy_feat, 0.10);
entropy_p50 = safe_quantile(entropy_feat, 0.50);
entropy_p90 = safe_quantile(entropy_feat, 0.90);

flux_mean = safe_mean(flux_feat);
flux_p50 = safe_quantile(flux_feat, 0.50);
flux_p90 = safe_quantile(flux_feat, 0.90);

sub_low = band_energy(S, f, opts.SubbandLow);
sub_high = band_energy(S, f, opts.SubbandHigh);
subband_ratio = sub_low / (sub_high + eps);

[envelope_rise, envelope_fall, max_slope] = envelope_metrics(x_seg, fs, opts.EnvelopeThreshold);

v = [duration, ...
    energy_mean, energy_p10, energy_p50, energy_p90, ...
    entropy_mean, entropy_p10, entropy_p50, entropy_p90, ...
    flux_mean, flux_p50, flux_p90, ...
    subband_ratio, envelope_rise, envelope_fall, max_slope];

v = reshape(v, 1, []);
end

function opts = fill_defaults(opts, defaults)
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(opts, name) || isempty(opts.(name))
        opts.(name) = defaults.(name);
    end
end
end

function validate_band(band, name)
validateattributes(band, {'numeric'}, {'vector', 'numel', 2, 'real', 'positive', 'increasing'}, mfilename, name);
end

function val = safe_mean(x)
if isempty(x)
    val = 0;
else
    val = mean(x);
end
end

function q = safe_quantile(x, p)
if isempty(x)
    q = 0;
else
    q = local_quantile(x, p);
end
end

function e = band_energy(S, f, band)
if isempty(S) || isempty(f)
    e = 0;
    return;
end
mask = f >= band(1) & f <= band(2);
if ~any(mask)
    e = 0;
    return;
end
band_power = S(mask, :);
e = sum(band_power(:));
end

function [rise_time, fall_time, max_slope] = envelope_metrics(x, fs, threshold_frac)
if isempty(x)
    rise_time = 0;
    fall_time = 0;
    max_slope = 0;
    return;
end
try
    y = bandpass_5to14k(x, fs);
catch
    y = x;
end
envelope = abs(hilbert(y));
if all(~isfinite(envelope))
    envelope = zeros(size(envelope));
end
peak_val = max(envelope);
if peak_val <= 0 || ~isfinite(peak_val)
    rise_time = 0;
    fall_time = 0;
    max_slope = 0;
    return;
end
level = max(threshold_frac * peak_val, 0);
above = find(envelope >= level);
if isempty(above)
    rise_time = 0;
    fall_time = 0;
else
    peak_idx = find(envelope == peak_val, 1, 'first');
    rise_time = max(0, (peak_idx - above(1)) / fs);
    fall_time = max(0, (above(end) - peak_idx) / fs);
end
if numel(envelope) < 2
    max_slope = 0;
else
    slopes = diff(envelope) * fs;
    max_slope = max(slopes(:));
end
end

function q = local_quantile(x, p)
if isempty(x)
    q = 0;
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

function coherence = fill_coherence_defaults_local(coherence)
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
    if ~isfield(coherence, name) || isempty(coherence.(name))
        coherence.(name) = defaults.(name);
    end
end
validateattributes(coherence.Enabled, {'logical', 'numeric'}, {'scalar'});
coherence.Enabled = logical(coherence.Enabled);
validateattributes(coherence.LogOffset, {'numeric'}, {'scalar', 'real', '>', 0});
if ischar(coherence.GradKernel) || (isstring(coherence.GradKernel) && isscalar(coherence.GradKernel))
    coherence.GradKernel = char(coherence.GradKernel);
else
    error('segment_features:InvalidCoherenceKernel', 'Coherence.GradKernel must be a string.');
end
validateattributes(coherence.SigmaTime, {'numeric'}, {'scalar', '>=', 0});
validateattributes(coherence.SigmaFreq, {'numeric'}, {'scalar', '>=', 0});
validateattributes(coherence.TruncationRadius, {'numeric'}, {'scalar', 'integer', '>=', 1});
validateattributes(coherence.Gain, {'numeric'}, {'scalar', 'real', '>=', 0});
validateattributes(coherence.Exponent, {'numeric'}, {'scalar', 'real', '>=', 0});
if isempty(coherence.Clip)
    coherence.Clip = [-inf inf];
else
    validateattributes(coherence.Clip, {'numeric'}, {'vector', 'numel', 2, 'real'});
    if coherence.Clip(1) > coherence.Clip(2)
        error('segment_features:InvalidCoherenceClip', 'Coherence.Clip bounds must be non-decreasing.');
    end
end
coherence.Clip = double(coherence.Clip);
end
