function [S, f, t] = frame_spectrogram(x, fs, win, hop)
% frame_spectrogram returns power spectrogram (linear), frequency, and time vectors.

narginchk(4, 4);

%% validate inputs
validateattributes(x, {'numeric'}, {'vector', 'nonempty'}, mfilename, 'x');
validateattributes(fs, {'numeric'}, {'scalar', 'positive'}, mfilename, 'fs');
validateattributes(hop, {'numeric'}, {'scalar', 'integer', '>=', 1}, mfilename, 'hop');
fs = double(fs);
hop = double(hop);
x = double(x(:));
if isscalar(win)
    validateattributes(win, {'numeric'}, {'scalar', 'integer', '>=', 1}, mfilename, 'win');
    win_length = double(win);
    if win_length == 1
        win = 1;
    else
        n = (0:win_length-1).';
        win = 0.5 - 0.5 * cos(2 * pi * n / (win_length - 1));
    end
else
    validateattributes(win, {'numeric'}, {'vector', 'nonempty'}, mfilename, 'win');
    win = double(win(:));
    win_length = numel(win);
end
if hop >= win_length
    error('frame_spectrogram:InvalidHop', 'hop must be smaller than the window length.');
end

%% compute spectrogram
noverlap = win_length - hop;
[stft, f, t] = spectrogram(x, win, noverlap, [], fs);
S = abs(stft).^2;
f = f(:);
t = t(:);
end
