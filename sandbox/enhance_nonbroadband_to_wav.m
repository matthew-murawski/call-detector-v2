
% script
enhanced = enhance_nonbroadband_to_wav_function('/Users/matt/Documents/Zhao Lab/audio/little_clip_M93A_c_S178.wav', '/Users/matt/Documents/Zhao Lab/audio');

function out_path = enhance_nonbroadband_to_wav_function(wav_in, out_dir, varargin)
% emphasize narrow, time-coherent ridges (5–15 khz) while keeping broadband in check.
% adds a multi-scale peakiness (DoG) term + temporal hysteresis so faint-but-sharp calls get boosted.

    % -------- options
    p = inputParser;
    addParameter(p, 'Fmin', 5e3);
    addParameter(p, 'Fmax', 15e3);

    % stft
    addParameter(p, 'Win', 0.025);        % 25 ms
    addParameter(p, 'Hop', 0.010);        % 10 ms
    addParameter(p, 'Nfft', 4096);        % finer freq bins

    % contrast + normalization
    addParameter(p, 'FreqSmoothHz', 2000);% envelope removal bandwidth (median)
    addParameter(p, 'Theta_dB', 0.4);     % contrast threshold to start boosting
    addParameter(p, 'Boost_dB', 10);      % max in-band boost
    addParameter(p, 'MinBoost_dB', 4);    % floor for bins rescued by hysteresis

    % multi-scale peakiness (difference of gaussians along frequency)
    addParameter(p, 'DoG_Narrow_Hz', 150);  % ~peak width
    addParameter(p, 'DoG_Wide_Hz',   900);  % local background
    addParameter(p, 'DoG_Weight',    0.6);  % contribution of peakiness (0..1)

    % temporal hysteresis (rescues faint but continuous ridges)
    addParameter(p, 'Hyst_Tlow',  0.30);    % low threshold on combined score (0..1)
    addParameter(p, 'Hyst_Thigh', 0.60);    % high threshold on combined score (0..1)

    % broadband control (framewise; relaxed when peakiness is high)
    addParameter(p, 'UseFlatnessGate', true);
    addParameter(p, 'FlatnessTau', 0.55);
    addParameter(p, 'FlatnessStrength', 0.6); % 0..1

    % out-of-band attenuation
    addParameter(p, 'OutOfBandCut_dB', -12);

    parse(p, varargin{:});
    o = p.Results;

    % -------- read audio
    [x, fs] = audioread(wav_in);
    if size(x,2) > 1, x = mean(x,2); end

    % -------- stft params
    wlen = round(o.Win*fs);
    hop  = round(o.Hop*fs);
    nfft = o.Nfft;
    if (nfft/2 + 1) < wlen
        nfft = 2^nextpow2(2*wlen);
    end
    win = hann(wlen,'periodic');

    % -------- stft
    [S, f, ~] = spectrogram(x, win, wlen-hop, nfft, fs);
    P = abs(S) + 1e-12;
    L = 20*log10(P);

    % -------- band + scales
    inBand = (f >= o.Fmin) & (f <= o.Fmax);
    df = mean(diff(f));
    dt = hop / fs;

    % -------- frequency envelope removal (median) → contrast
    kf = max(3, round(o.FreqSmoothHz/df));
    LB = L(inBand,:);
    LB_env = movmedian(LB, [floor(kf/2) floor(kf/2)], 1, 'omitnan');
    R = LB - LB_env;

    % -------- map contrast to [0,1] via robust scaling
    Rpos = max(R - o.Theta_dB, 0);
    sR = prctile(Rpos(:), 95);
    if ~isfinite(sR) || sR <= 0, sR = 1; end
    C = min(Rpos./sR, 1);  % 0..1

    % -------- multi-scale peakiness (DoG along frequency)
    % section: narrow and wide gaussian smoothing then subtract
    sigN = max(o.DoG_Narrow_Hz/df, 1);
    sigW = max(o.DoG_Wide_Hz/df,   3);
    gk = @(sig) exp(-0.5*(((-ceil(3*sig):ceil(3*sig)))./sig).^2);
    gN = gk(sigN); gN = gN/sum(gN);
    gW = gk(sigW); gW = gW/sum(gW);

    LN = conv2(LB, gN, 'same');
    LW = conv2(LB, gW, 'same');
    DoG = LN - LW;

    % map DoG to [0,1] robustly
    DoGpos = max(DoG, 0);
    sK = prctile(DoGpos(:), 95);
    if ~isfinite(sK) || sK <= 0, sK = 1; end
    K = min(DoGpos./sK, 1);  % 0..1

    % -------- combine contrast and peakiness
    % section: soft-or between C and K so faint-but-sharp bins get score
    Scomb = (1 - (1 - C).*(1 - o.DoG_Weight*K)); % 0..1

    % -------- temporal hysteresis along time (per frequency bin)
    % section: promote segments above low that contain any high
    [nf_in, nt] = size(Scomb);
    keep = false(nf_in, nt);
    aboveL = Scomb >= o.Hyst_Tlow;
    aboveH = Scomb >= o.Hyst_Thigh;
    for ii = 1:nf_in
        vL = aboveL(ii,:);
        if ~any(vL), continue; end
        dv = diff([false vL false]);
        starts = find(dv == 1);
        stops  = find(dv == -1) - 1;
        for k = 1:numel(starts)
            s0 = starts(k); e0 = stops(k);
            if any(aboveH(ii, s0:e0))
                keep(ii, s0:e0) = true;
            end
        end
    end

    % -------- base boost from Scomb; enforce a floor where hysteresis keeps bins
    boost_inband = o.Boost_dB * Scomb;                 % 0..Boost_dB
    boost_inband(keep & boost_inband < o.MinBoost_dB) = o.MinBoost_dB;

    % -------- framewise flatness gate (relaxed when peakiness is strong)
    if o.UseFlatnessGate
        PB = P(inBand,:);
        gm = exp(mean(log(PB), 1));
        am = mean(PB, 1);
        sfm = gm ./ max(am, 1e-12);                    % 0..1
        tau = o.FlatnessTau;
        taper = max((sfm - tau) ./ max(1 - tau, eps), 0); % 0..1
        % relax gate where median peakiness is strong in the band
        Kmed = median(K, 1);                           % 1×T
        relax = 1 - 0.7*Kmed;                          % strong K → smaller reduction
        gate = 1 - (o.FlatnessStrength * taper .* relax);
        boost_inband = boost_inband .* gate;
        boost_inband = movmean(boost_inband, max(3, round(0.03/dt)), 2);
    end

    % -------- assemble full-band gains (dB)
    GdB = o.OutOfBandCut_dB * ones(size(L), 'like', L);
    GdB(inBand,:) = min(boost_inband, o.Boost_dB);     % in-band: boost only

    % light 2d smoothing
    GdB = conv2(GdB, ones(3,3,'like',GdB)/9, 'same');

    % -------- apply and invert
    G = 10.^(GdB/20);
    Sout = S .* G;

    y = istft(Sout, fs, ...
        'Window', win, ...
        'OverlapLength', wlen-hop, ...
        'FFTLength', nfft, ...
        'ConjugateSymmetric', true);

    y = real(y);
    m = max(abs(y));
    if m > 0, y = y/(1.01*m); end

    % -------- write
    if nargin < 2 || isempty(out_dir), out_dir = fileparts(wav_in); end
    [~,base,~] = fileparts(wav_in);
    out_path = fullfile(out_dir, [base '_enhanced.wav']);
    audiowrite(out_path, y, fs);

    fprintf('wrote %s (fs=%d, nfft=%d, win=%d, hop=%d)\n', out_path, fs, nfft, wlen, hop);
end