function segs = run_detect_heard_chunked(wavPath, producedInput, outLabelPath, params, chunkSeconds)
% run_detect_heard_chunked runs the heard-call detector over a long wav by chunking in time.

narginchk(1, 5);
add_chunk_paths();
if nargin < 2
    producedInput = [];
end
if nargin < 3
    outLabelPath = "";
end
if nargin < 4 || isempty(params)
params = struct();
end
if nargin < 5 || isempty(chunkSeconds)
    chunkSeconds = 300;
end

validateattributes(wavPath, {'char', 'string'}, {'scalartext'}, mfilename, 'wavPath');
validateattributes(chunkSeconds, {'numeric'}, {'scalar', 'real', 'positive'}, mfilename, 'chunkSeconds');

wavPath = char(wavPath);

info = audioinfo(wavPath);
fs = info.SampleRate;
totalSamples = info.TotalSamples;
chunkSamples = max(1, round(chunkSeconds * fs));
totalChunks = max(1, ceil(totalSamples / chunkSamples));

produced_all = normalise_intervals(producedInput);

segs = zeros(0, 2);

useNoiseMask = isfield(params, 'UseNoiseMask') && logical(params.UseNoiseMask);
writeNoiseLabels = false;
if useNoiseMask && isfield(params, 'NoiseLabelPath')
    labelStr = params.NoiseLabelPath;
    if isstring(labelStr)
        writeNoiseLabels = strlength(labelStr) > 0;
    elseif ischar(labelStr)
        writeNoiseLabels = ~isempty(labelStr);
    end
end

paramsChunk = params;
if useNoiseMask
    paramsChunk.NoiseLabelPath = "";
    if isfield(paramsChunk, 'NoiseParams') && isstruct(paramsChunk.NoiseParams)
        paramsChunk.NoiseParams = disable_noise_label(paramsChunk.NoiseParams);
    end
end

offsetSamples = 0;
chunkIndex = 0;
while offsetSamples < totalSamples
    startSample = offsetSamples + 1;
    stopSample = min(totalSamples, offsetSamples + chunkSamples);

    chunkIndex = chunkIndex + 1;

    [xChunk, fsChunk] = audioread(wavPath, [startSample, stopSample]);
    chunkStartTime = (startSample - 1) / fs;
    chunkEndTime = stopSample / fs;

    produced_chunk = trim_intervals(produced_all, chunkStartTime, chunkEndTime);
    produced_chunk = produced_chunk - chunkStartTime;

    audioStruct = struct('x', xChunk, 'fs', fsChunk);
    segs_chunk = run_detect_heard(audioStruct, produced_chunk, "", paramsChunk);

    if ~isempty(segs_chunk)
        segs_chunk = segs_chunk + chunkStartTime;
        segs = [segs; segs_chunk]; %#ok<AGROW>
    end

    offsetSamples = stopSample;

    fprintf('[call-detector] chunk %d/%d (%.1f%%%%)\n', chunkIndex, totalChunks, 100 * stopSample / totalSamples);
end

if strlength(outLabelPath) > 0
    labels = repmat("HEARD", size(segs, 1), 1);
    write_audacity_labels(char(outLabelPath), segs, labels);
end

if useNoiseMask && writeNoiseLabels
    noiseParamsLabel = params.NoiseParams;
    if ~isstruct(noiseParamsLabel) || ~isscalar(noiseParamsLabel)
        noiseParamsLabel = NoiseParams(fs);
    end
    if ~isfield(noiseParamsLabel, 'Output') || isempty(noiseParamsLabel.Output)
        noiseParamsLabel.Output = struct();
    end
    noiseParamsLabel.SampleRate = fs;
    noiseParamsLabel.Output.WriteNoiseLabels = true;
    noiseParamsLabel.Output.LabelPath = char(params.NoiseLabelPath);

    edgeGuardNoise = min(chunkSeconds / 4, max(0.5, chunkSeconds * 0.05));
    overlapNoise = max(2 * edgeGuardNoise, min(chunkSeconds / 2, 5));
    if overlapNoise >= chunkSeconds
        overlapNoise = max(chunkSeconds * 0.8, chunkSeconds - 1e-3);
    end
    noiseChunkOpts = struct('ChunkSec', chunkSeconds, ...
        'OverlapSec', overlapNoise, ...
        'EdgeGuardSec', edgeGuardNoise);

    run_detect_noise_chunked(wavPath, noiseParamsLabel, noiseChunkOpts); %#ok<NASGU>
end

fprintf('[call-detector] completed %d chunks over %.1f minutes of audio\n', chunkIndex, totalSamples / fs / 60);
end

function add_chunk_paths()
persistent has_paths
if isempty(has_paths)
    script_dir = fileparts(mfilename('fullpath'));
    root_dir = fileparts(script_dir);
    addpath(fullfile(root_dir, 'scripts'));
    addpath(genpath(fullfile(root_dir, 'src', 'noise')));
    has_paths = true;
end
end

function intervals = normalise_intervals(input)
if isempty(input)
    intervals = zeros(0, 2);
    return;
end
if isa(input, 'table')
    required = {'onset', 'offset'};
    if ~all(ismember(required, input.Properties.VariableNames))
        error('run_detect_heard_chunked:InvalidTable', 'Produced table must include onset and offset columns.');
    end
    input = [input.onset, input.offset];
elseif ischar(input) || (isstring(input) && isscalar(input))
    tbl = read_audacity_labels(char(input));
    input = [tbl.onset, tbl.offset];
elseif ~isnumeric(input)
    error('run_detect_heard_chunked:InvalidProducedInput', 'Produced labels must be numeric, table, or label path.');
end
validateattributes(input, {'numeric'}, {'2d', 'ncols', 2, 'real'}, mfilename, 'produced');
intervals = double(input);
intervals = sortrows(intervals, 1);
end

function out = disable_noise_label(noiseParams)
if ~isstruct(noiseParams) || ~isscalar(noiseParams)
    out = NoiseParams();
else
    out = noiseParams;
end
if ~isfield(out, 'Output') || isempty(out.Output)
    out.Output = struct();
end
out.Output.WriteNoiseLabels = false;
out.Output.LabelPath = "";
end

function trimmed = trim_intervals(intervals, startTime, endTime)
if isempty(intervals)
    trimmed = zeros(0, 2);
    return;
end
mask = (intervals(:, 2) > startTime) & (intervals(:, 1) < endTime);
if ~any(mask)
    trimmed = zeros(0, 2);
    return;
end
trimmed = intervals(mask, :);
trimmed(:, 1) = max(trimmed(:, 1), startTime);
trimmed(:, 2) = min(trimmed(:, 2), endTime);
end
