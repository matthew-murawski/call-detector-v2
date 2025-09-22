% demo_coherence_boost.m
% visualize original vs coherence-boosted spectrogram for a .wav file.

%% parse input or prompt
% this section reads a wav file; if none is provided, a file dialog opens.
if ~exist('wav_path', 'var') || isempty(wav_path)
    [fname, fpath] = uigetfile({'*.wav','WAV files'}, 'select audio file');
    if isequal(fname,0); error('no file selected.'); end
    wav_path = fullfile(fpath, fname);
end
[x, fs] = audioread(wav_path);
if size(x,2) > 1
    x = x(:,1); % use first channel by default
end
x = double(x(:));

%% analysis knobs (feel free to edit)
% this section defines reasonable defaults for marmoset calls.
band_hz   = [5000 12000];  % focus band (set [] to disable)
win_s     = 0.025;         % 25 ms window
hop_s     = 0.010;         % 10 ms hop
nfft      = [];            % [] → pick from window length
sigma_t   = 2;             % gaussian smoothing in frames
sigma_f   = 2;             % gaussian smoothing in bins
alpha     = 1.0;           % weighting exponent

%% compute coherence-boosted spectrogram
% this section computes original and boosted spectrograms (magnitude + log view).
[S_enh, C, t, f, S] = enhance_spectrogram_coherence( ...
    x, fs, 'Band', band_hz, 'Win', win_s, 'Hop', hop_s, ...
    'NFFT', nfft, 'SigmaT', sigma_t, 'SigmaF', sigma_f, 'Alpha', alpha);

Slog    = log1p(S);
Slog_en = log1p(S_enh);

%% report parameters used
% this section prints the key parameters to the command window.
fprintf('\ncoherence boost parameters:\n');
if isempty(band_hz)
    fprintf('  band: full bandwidth\n');
else
    fprintf('  band: [%g %g] Hz\n', band_hz(1), band_hz(2));
end
fprintf('  window: %.0f ms, hop: %.0f ms\n', win_s*1e3, hop_s*1e3);
fprintf('  nfft: %d\n', size(S,1)*2 - 2);
fprintf('  gaussian sigmas (time, freq): (%.2f frames, %.2f bins)\n', sigma_t, sigma_f);
fprintf('  alpha: %.2f\n\n', alpha);

%% plot original vs enhanced spectrograms
% this section shows the two spectrograms stacked, with matched axes.
figure('Color','w'); 
tlim = [t(1) t(end)];
flim = [f(1) f(end)];

subplot(2,1,1);
imagesc(t, f/1e3, Slog); axis xy;
xlabel('time (s)'); ylabel('frequency (kHz)');
title('original spectrogram (log magnitude)'); 
colorbar;

subplot(2,1,2);
imagesc(t, f/1e3, Slog_en); axis xy;
xlabel('time (s)'); ylabel('frequency (kHz)');
title('coherence-boosted spectrogram (log magnitude)');
colorbar;

colormap(turbo);

%% ---------------- local helpers below ----------------

function [S_enh, c, t, f, S] = enhance_spectrogram_coherence(x, fs, varargin)
% enhance a spectrogram by emphasizing coherent spectro-temporal contours.

    % options
    p = inputParser;
    addParameter(p, 'Band', []);        % [fmin fmax] Hz
    addParameter(p, 'Win', 0.025);      % s
    addParameter(p, 'Hop', 0.010);      % s
    addParameter(p, 'NFFT', []);
    addParameter(p, 'SigmaT', 2);       % gaussian smoothing (frames)
    addParameter(p, 'SigmaF', 2);       % gaussian smoothing (bins)
    addParameter(p, 'Alpha', 1);
    parse(p, varargin{:});
    band = p.Results.Band; win_s = p.Results.Win; hop_s = p.Results.Hop;
    nfft = p.Results.NFFT; sigT = p.Results.SigmaT; sigF = p.Results.SigmaF;
    alpha = p.Results.Alpha;

    % optional bandpass to focus on species band
    if ~isempty(band)
        d = designfilt('bandpassiir','FilterOrder',6, ...
            'HalfPowerFrequency1',band(1),'HalfPowerFrequency2',band(2), ...
            'SampleRate',fs);
        x = filtfilt(d,x);
    end

    % stft (use MATLAB stft if available; fall back to spectrogram)
    win = hann(round(win_s*fs),'periodic');
    hop = round(hop_s*fs);
    if isempty(nfft), nfft = 2^nextpow2(numel(win)); end

    if exist('stft','file') == 2
        [S_complex,f,t] = stft(x,fs,'Window',win,'OverlapLength',numel(win)-hop,'FFTLength',nfft);
        S = abs(S_complex); S = S(1:floor(end/2)+1,:); f = f(1:floor(end/2)+1);
    else
        [S_complex,f,t] = spectrogram(x, win, numel(win)-hop, nfft, fs);
        S = abs(S_complex); S = S(1:floor(end/2)+1,:); f = f(1:floor(end/2)+1);
    end

    % work in log domain for gradients
    Slog = log1p(S);

    % gradients (freq = rows, time = cols)
    df = conv2(Slog,[1;0;-1]/2,'same');   % finite difference in frequency
    dt = conv2(Slog,[1 0 -1]/2,'same');   % finite difference in time

    % structure tensor with gaussian smoothing
    G = gaussian2d(sigF, sigT);
    Jff = conv2(df.^2,   G, 'same');
    Jtt = conv2(dt.^2,   G, 'same');
    Jft = conv2(df.*dt,  G, 'same');

    % eigenvalues of 2x2 tensor
    tr   = Jff + Jtt;
    detJ = Jff.*Jtt - Jft.^2;
    disc = sqrt(max(tr.^2 - 4*detJ, 0));
    lambda1 = 0.5*(tr + disc);
    lambda2 = 0.5*(tr - disc);

    % coherence in [0,1]
    c = (lambda1 - lambda2) ./ (lambda1 + lambda2 + eps);

    % apply weighting
    S_enh = S .* (1 + c).^alpha;
end

function G = gaussian2d(sigF, sigT)
% build a separable 2-d gaussian kernel over (freq bins, time frames).
    gF = max(1,ceil(3*sigF));
    gT = max(1,ceil(3*sigT));
    f = (-gF:gF);
    t = (-gT:gT);
    g1 = exp(-0.5*(f/sigF).^2); g1 = g1/sum(g1);
    g2 = exp(-0.5*(t/sigT).^2); g2 = g2/sum(g2);
    G = g1(:) * g2(:).';
end
