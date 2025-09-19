function y = bandpass_5to14k(x, fs)
%% validate inputs
validateattributes(x, {'numeric'}, {'nonempty'}, mfilename, 'x');
if ndims(x) > 2
    error('bandpass_5to14k:InvalidInput', 'x must be a vector or 2d matrix.');
end
validateattributes(fs, {'numeric'}, {'scalar', 'positive'}, mfilename, 'fs');
fs = double(fs);
nyquist = fs / 2;
if nyquist <= 14000
    error('bandpass_5to14k:NyquistTooLow', 'nyquist must exceed 14 kHz.');
end

%% filter waveform
[b, a] = butter(4, [5000 14000] / nyquist, 'bandpass');
was_row = isrow(x);
if was_row
    x = x.';
end
x = double(x);
y = filtfilt(b, a, x);
if was_row
    y = y.';
end
end
