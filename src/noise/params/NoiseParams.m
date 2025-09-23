function params = NoiseParams(fs)
% noiseparams returns defaults for stage 0 noise detection.
% it accepts the audio sample rate so band placements adjust to the nyquist limit.

if nargin < 1 || isempty(fs)
    fs = 48000;
end

validateattributes(fs, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'fs');

nyquist = fs / 2;
high_upper = min(0.45 * fs, nyquist);
min_high_span = 2000;
target_high_low = 16000;
band_low = [0 800];
band_in = [5000 14000];

high_lower = target_high_low;
if high_upper - high_lower < min_high_span
    high_lower = high_upper - min_high_span;
end
if ~isfinite(high_lower) || high_lower < 0
    high_lower = max(0, high_upper * 0.5);
end
if high_lower >= high_upper
    high_lower = max(0, high_upper * 0.5);
end

% assemble the parameter struct with defaults tuned for broadband noise gating.
params = struct();
params.BandsHz = struct( ...
    'Low', band_low, ...
    'In', band_in, ...
    'High', [high_lower, high_upper] ...
    );

params.BandCoincidence = struct('NRequired', 2, 'RequireOOB', true);

params.BandThresholds = struct( ...
    'method', 'MAD', ...
    'kEnter', 1.2, ...
    'kExit', 0.8, ...
    'RollingWindowSec', [] ...
    );

params.Coverage = struct('BinK', 1.0, 'CoverageMin', 0.60);

params.Flatness = struct('FlatnessMin', 0.4);

params.OOB = struct('RatioMin', 0.7);

params.Hysteresis = struct( ...
    'MinEventSec', 0.08, ...
    'MaxEventSec', 5.0, ...
    'GapCloseSec', 0.04, ...
    'PrePadSec', 0.05, ...
    'PostPadSec', 0.05 ...
    );

params.TonalityGuard = struct( ...
    'Enable', true, ...
    'InBandTonalityThresh', 0.65, ...
    'Mode', 'soft' ...
    );

params.Output = struct('WriteNoiseLabels', false);

params.SampleRate = fs;
end
