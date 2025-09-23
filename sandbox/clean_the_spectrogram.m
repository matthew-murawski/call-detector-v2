viz_clean_spectrogram('/Users/matt/Documents/Zhao Lab/audio/little_clip_M93A_c_S178.wav');

function viz_clean_spectrogram(wav_path, varargin)
% visualize a "cleaned" spectrogram that suppresses broadband noise and highlights calls (5–15 khz).
% produces two panels: plain log-spectrogram and frequency-whitened (with optional broadband penalty).

    % options
    p = inputParser;
    addParameter(p, 'Fmin', 5e3);
    addParameter(p, 'Fmax', 15e3);
    addParameter(p, 'Win', 0.025);   % 25 ms
    addParameter(p, 'Hop', 0.010);   % 10 ms
    addParameter(p, 'Nfft', 2048);
    addParameter(p, 'FreqSmoothHz', 1000);  % width of freq median smoother
    addParameter(p, 'BgHz', [500 3000; 16000 22000]); % out-of-band probes
    parse(p, varargin{:});
    o = p.Results;

    % read audio
    [x, fs] = audioread(wav_path);
    if size(x,2) > 1, x = mean(x,2); end  % mono for display

    % compute log-magnitude spectrogram
    wlen = round(o.Win*fs);
    hop  = round(o.Hop*fs);
    nfft = o.Nfft;
    [S, f, t] = spectrogram(x, hann(wlen,'periodic'), wlen-hop, nfft, fs);
    L = 20*log10(abs(S)+1e-12);  % dB

    % select freq band for display
    band = f >= o.Fmin & f <= o.Fmax;
    fB = f(band); LB = L(band,:);

    % build frequency smoother (median over ~1 khz)
    df = mean(diff(f));
    kf = max(3, round(o.FreqSmoothHz/df));

    % frequency-whiten per frame: subtract median-smoothed baseline and divide by MAD
    LB_smooth = movmedian(LB, [floor(kf/2) floor(kf/2)], 1, 'omitnan'); % along freq
    R = LB - LB_smooth;
    madF = mad(R, 1, 1);              % mad across freq, per frame
    madF(madF < 1e-6) = 1e-6;         % avoid divide by zero
    Z = R ./ madF;                    % z-like units

    % gentle broadband penalty using out-of-band probes
    isProbe = false(numel(f),1);
    for i = 1:size(o.BgHz,1)
        isProbe = isProbe | (f >= o.BgHz(i,1) & f <= o.BgHz(i,2));
    end
    probe = L(isProbe,:);                          % out-of-band energy
    bbScore = mean(probe,1) - prctile(probe, 20, 1); % elevation vs a low quantile
    bbScore = rescale(bbScore, 0, 1);              % 0..1
    penalty = (1 - 0.5*bbScore);                   % 1 (no bb) → 0.5 (strong bb)
    Zp = Z .* penalty;                             % down-weight bb frames softly

    % display
    figure('Color','w','Position',[100 100 1200 450]);

    % top: plain log-magnitude for reference
    subplot(2,1,1);
    imagesc(t, fB/1e3, LB); axis xy tight;
    title('log-magnitude (dB)'); ylabel('freq (khz)'); xlabel('time (s)');
    caxis([prctile(LB(:), 5), prctile(LB(:), 95)]);

    % bottom: frequency-whitened with broadband penalty
    subplot(2,1,2);
    clim = [-3 6];  % clamp for contrast
    imagesc(t, fB/1e3, max(min(Zp,clim(2)),clim(1))); axis xy tight;
    title('freq-whitened (per-frame median/MAD) + soft broadband penalty');
    ylabel('freq (khz)'); xlabel('time (s)'); caxis(clim); colorbar;

end
