% read_audio_clip_info_script

[x, fs] = audioread('/Users/matt/Documents/Zhao Lab/audio/M93A_S105_little_clip.wav');

% bandpass filter for 5–12 kHz
bp = designfilt('bandpassiir', 'FilterOrder', 4, ...
                'HalfPowerFrequency1', 5000, 'HalfPowerFrequency2', 12000, ...
                'SampleRate', fs);
x_bp = filtfilt(bp, x);

% compute energy in dB
frame_len = round(0.02*fs); % 20 ms frames
frames = buffer(x_bp, frame_len, 0, 'nodelay');
frame_energy = sum(frames.^2, 1) / frame_len;

% summarize
medE = median(frame_energy);
madE = mad(frame_energy,1);

fprintf('Median energy = %.3g, MAD = %.3g\n', medE, madE);
