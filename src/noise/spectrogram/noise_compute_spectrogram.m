function [S, f, t] = noise_compute_spectrogram(y, fs, opts)
% noise_compute_spectrogram produces a wideband magnitude spectrogram for stage 0.
% it mirrors core pipeline defaults unless overridden via opts.

narginchk(2, 3);
if nargin < 3 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts) || ~isscalar(opts)
    error('noise_compute_spectrogram:InvalidOpts', 'opts must be a scalar struct.');
end

validateattributes(y, {'numeric'}, {'nonempty'}, mfilename, 'y');
validateattributes(fs, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'fs');
if any(isnan(y(:)))
    error('noise_compute_spectrogram:SignalNaN', 'y must not contain NaN values.');
end

y = double(y);
fs = double(fs);
if size(y, 1) == 1 && size(y, 2) > 1
    y = y.';
end
if size(y, 2) > 1
    y = mean(y, 2);
end
y = y(:);

window_sec = get_field(opts, 'WindowSec', 0.025);
hop_sec = get_field(opts, 'HopSec', 0.010);
nfft = get_field(opts, 'NFFT', []);

validateattributes(window_sec, {'numeric'}, {'scalar', 'real', 'finite', '>', 0}, mfilename, 'opts.WindowSec');
validateattributes(hop_sec, {'numeric'}, {'scalar', 'real', 'finite', '>', 0}, mfilename, 'opts.HopSec');
if ~isempty(nfft)
    validateattributes(nfft, {'numeric'}, {'scalar', 'real', 'finite', '>=', 1}, mfilename, 'opts.NFFT');
end

win_samples = max(2, round(window_sec * fs));
hop_samples = max(1, round(hop_sec * fs));
if hop_samples >= win_samples
    hop_samples = max(1, win_samples - 1);
end

if isempty(nfft)
    nfft = 2^nextpow2(win_samples);
    nfft = max([nfft, win_samples, 256]);
else
    nfft = double(round(nfft));
    if nfft < win_samples
        error('noise_compute_spectrogram:NFFTTooSmall', 'opts.NFFT must be at least the window length.');
    end
end

if numel(y) < win_samples
    y(end+1:win_samples) = 0; %#ok<AGROW>
end

if win_samples == 1
    window = 1;
else
    n = (0:win_samples-1).';
    window = 0.5 - 0.5 * cos(2 * pi * n / (win_samples - 1));
end
noverlap = win_samples - hop_samples;

[stft, f, t] = spectrogram(y, window, noverlap, nfft, fs);
S = abs(stft);
S = real(S);
f = f(:);
t = t(:);
S = max(S, 0);
end

function value = get_field(s, name, default)
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = default;
end
end
