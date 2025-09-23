
wavPath = '/Users/matt/Documents/Zhao Lab/audio/little_clip_M93A_c_S178.wav';
outLabelPath = '/Users/matt/Documents/GitHub/call-detector-v2/output/demo/noise.txt';

fs = 48000;
  p = NoiseParams(fs);
  p.BandCoincidence.NRequired = 3;
  p.BandCoincidence.RequireOOB = true;
  p.BandThresholds.kEnter = 0.99;
  p.BandThresholds.kExit  = 0.9;
  p.Coverage.CoverageMin  = 0.12;
  p.Flatness.FlatnessMin  = 0.18;
  p.OOB.RatioMin          = 0.15;
  p.TonalityGuard.Enable  = false;
  p.TonalityGuard.InBandTonalityThresh = 0.999;   % default 0.65
  p.TonalityGuard.Mode = 'soft';

segments = run_noise_on_wav(wavPath, outLabelPath, p, struct('ChunkSec', 300, 'OverlapSec', 2, 'EdgeGuardSec', 0.25));

function segments = run_noise_on_wav(wavPath, outLabelPath, noiseParams, chunkOpts)
% run_noise_on_wav_script runs the stage 0 noise detector on a wav file and writes NOISE labels.
%
% Usage:
%   segments = run_noise_on_wav_script('audio.wav', 'noise.txt');
%   segments = run_noise_on_wav_script('audio.wav', 'noise.txt', NoiseParams(48000));
%   segments = run_noise_on_wav_script('audio.wav', 'noise.txt', [], struct('ChunkSec', 180));
%
% Inputs:
%   wavPath      - path to an audio file readable by audioread
%   outLabelPath - path to write Audacity-compatible NOISE labels
%   noiseParams  - struct from NoiseParams(fs); optional
%   chunkOpts    - struct with fields ChunkSec/OverlapSec/EdgeGuardSec; optional
%
% Output:
%   segments     - Nx2 array of detected noise intervals in seconds

narginchk(2, 4);
if nargin < 3
    noiseParams = [];
end
if nargin < 4
    chunkOpts = struct();
end

script_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(script_dir);
addpath(genpath(fullfile(root_dir, 'src', 'noise')));

validateattributes(wavPath, {'char', 'string'}, {'scalartext'}, mfilename, 'wavPath');
validateattributes(outLabelPath, {'char', 'string'}, {'scalartext'}, mfilename, 'outLabelPath');

wavPath = char(wavPath);
outLabelPath = char(outLabelPath);

if exist(wavPath, 'file') ~= 2
    error('run_noise_on_wav_script:FileNotFound', 'Audio file not found: %s', wavPath);
end

info = audioinfo(wavPath);
fs = info.SampleRate;

if isempty(noiseParams)
    noiseParams = NoiseParams(fs);
end
if ~isstruct(noiseParams) || ~isscalar(noiseParams)
    error('run_noise_on_wav_script:InvalidNoiseParams', 'noiseParams must be a scalar struct.');
end
if ~isfield(noiseParams, 'Output') || isempty(noiseParams.Output)
    noiseParams.Output = struct();
end
noiseParams.SampleRate = fs;
noiseParams.Output.WriteNoiseLabels = true;
noiseParams.Output.LabelPath = outLabelPath;

if ~isfield(chunkOpts, 'ChunkSec') || isempty(chunkOpts.ChunkSec)
    chunkOpts.ChunkSec = 180;
end
if ~isfield(chunkOpts, 'OverlapSec') || isempty(chunkOpts.OverlapSec)
    chunkOpts.OverlapSec = 5;
end
if ~isfield(chunkOpts, 'EdgeGuardSec') || isempty(chunkOpts.EdgeGuardSec)
    chunkOpts.EdgeGuardSec = 1;
end

chunkOpts = validate_chunk_opts(chunkOpts);

[segmentsMask, noiseSegments, ~] = run_detect_noise_chunked(wavPath, noiseParams, chunkOpts);
segments = noiseSegments;

if isempty(segments)
    fprintf('[run_noise_on_wav_script] no noise segments detected in %s\n', wavPath);
else
    fprintf('[run_noise_on_wav_script] detected %d noise segments in %s\n', size(segments, 1), wavPath);
end

if exist(outLabelPath, 'file') == 2
    fprintf('[run_noise_on_wav_script] wrote labels to %s\n', outLabelPath);
else
    warning('run_noise_on_wav_script:LabelWriteMissing', 'Noise label file was not created.');
end
end

function opts = validate_chunk_opts(opts)
validateattributes(opts, {'struct'}, {'scalar'}, mfilename, 'chunkOpts');
validateattributes(opts.ChunkSec, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'chunkOpts.ChunkSec');
validateattributes(opts.OverlapSec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0}, mfilename, 'chunkOpts.OverlapSec');
validateattributes(opts.EdgeGuardSec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0}, mfilename, 'chunkOpts.EdgeGuardSec');
opts.SampleRateOverride = [];
end
