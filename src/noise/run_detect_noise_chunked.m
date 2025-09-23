function [noiseMask, noiseSegments, meta] = run_detect_noise_chunked(wavPathOrAudio, noiseParams, chunkOpts)
% run_detect_noise_chunked runs the noise detector over long audio by chunking with overlap.

narginchk(1, 3);
if nargin < 2 || isempty(noiseParams)
    noiseParams = [];
end
if nargin < 3 || isempty(chunkOpts)
    chunkOpts = struct();
end

opts = parse_chunk_opts(chunkOpts);
[sourceType, fs, totalSamples, reader] = resolve_source(wavPathOrAudio, opts.SampleRateOverride);

overlapSamples = round(opts.OverlapSec * fs);
chunkSamples = max(1, round(opts.ChunkSec * fs));
if chunkSamples <= overlapSamples
    error('run_detect_noise_chunked:InvalidChunkSetup', 'ChunkSec must be larger than OverlapSec.');
end
if overlapSamples < 2 * round(opts.EdgeGuardSec * fs)
    error('run_detect_noise_chunked:InvalidOverlap', 'OverlapSec must be at least twice EdgeGuardSec.');
end
hopSamples = chunkSamples - overlapSamples;

if isempty(noiseParams)
    noiseParams = NoiseParams(fs);
else
    if isfield(noiseParams, 'SampleRate') && abs(noiseParams.SampleRate - fs) > 1e-6
        warning('run_detect_noise_chunked:SampleRateMismatch', 'noiseParams.SampleRate adjusted to match audio.');
    end
    noiseParams.SampleRate = fs;
end

writeLabels = false;
labelPath = "";
if isfield(noiseParams, 'Output') && isfield(noiseParams.Output, 'WriteNoiseLabels') && noiseParams.Output.WriteNoiseLabels
    writeLabels = true;
    if isfield(noiseParams.Output, 'LabelPath')
        labelPath = noiseParams.Output.LabelPath;
    end
end

noiseParamsChunk = noiseParams;
if isfield(noiseParamsChunk, 'Output')
    noiseParamsChunk.Output.WriteNoiseLabels = false;
    if isfield(noiseParamsChunk.Output, 'LabelPath')
        noiseParamsChunk.Output.LabelPath = "";
    end
end

aggregatedSegments = zeros(0, 2);
allTimes = [];
allMask = [];
chunkSummaries = struct('StartTime', {}, 'EndTime', {}, 'IncludeWindow', {}, 'Time', {}, 'Mask', {}, 'Segments', {});

totalTime = totalSamples / fs;
startSample = 1;
chunkIdx = 0;
while startSample <= totalSamples
    chunkIdx = chunkIdx + 1;
    stopSample = min(totalSamples, startSample + chunkSamples - 1);
    chunkStartTime = (startSample - 1) / fs;
    chunkEndTime = stopSample / fs;
    isLast = stopSample >= totalSamples;

    yChunk = reader(startSample, stopSample);

    [chunkMask, chunkSegments, chunkMeta] = run_detect_noise(yChunk, fs, noiseParamsChunk);

    includeStart = chunkStartTime;
    includeEnd = chunkEndTime;
    if chunkIdx > 1
        includeStart = includeStart + opts.EdgeGuardSec;
    end
    if ~isLast
        includeEnd = includeEnd - opts.EdgeGuardSec;
    end
    if includeEnd <= includeStart
        startSample = startSample + hopSamples;
        continue;
    end

    absTime = chunkStartTime + chunkMeta.Time;
    keepFrames = absTime >= includeStart & absTime <= includeEnd;

    keptTime = absTime(keepFrames);
    keptMask = chunkMask(keepFrames);
    allTimes = [allTimes, keptTime]; %#ok<AGROW>
    allMask = [allMask, keptMask]; %#ok<AGROW>

    segmentsAbs = chunkSegments;
    if ~isempty(segmentsAbs)
        segmentsAbs = segmentsAbs + chunkStartTime;
        segmentsAbs = trim_segments(segmentsAbs, includeStart, includeEnd);
        aggregatedSegments = [aggregatedSegments; segmentsAbs]; %#ok<AGROW>
    end

    summary = struct();
    summary.StartTime = chunkStartTime;
    summary.EndTime = chunkEndTime;
    summary.IncludeWindow = [includeStart, includeEnd];
    summary.Time = keptTime;
    summary.Mask = keptMask;
    summary.Segments = segmentsAbs;
    chunkSummaries(end+1) = summary; %#ok<AGROW>

    if isLast
        break;
    end

    startSample = startSample + hopSamples;
end

[allTimes, order] = sort(allTimes);
allMask = allMask(order);
if isempty(allTimes)
    allTimes = zeros(1, 0);
    allMask = false(1, 0);
end

if numel(allTimes) > 1
    [uniqueTimes, ~, ic] = unique(allTimes);
    if numel(uniqueTimes) < numel(allTimes)
        icCol = ic(:);
        maskCol = double(allMask(:));
        combined = accumarray(icCol, maskCol, [], @(x) any(x));
        allMask = logical(combined.');
        allTimes = uniqueTimes.';
    else
        allTimes = allTimes;
        allMask = logical(allMask);
    end
else
    allTimes = allTimes;
    allMask = logical(allMask);
end

allTimes = allTimes(:).';
allMask = allMask(:).';
noiseSegments = merge_segments(aggregatedSegments);
if isempty(allTimes)
    noiseMask = false(1, 0);
else
    noiseMask = noise_segments_to_mask(noiseSegments, allTimes);
end

meta = struct();
meta.SampleRate = fs;
meta.Params = noiseParams;
meta.Time = allTimes;
meta.Mask = noiseMask;
meta.Chunks = chunkSummaries;
meta.TotalDuration = totalTime;

if writeLabels && ~isempty(noiseSegments)
    if ~(ischar(labelPath) || (isstring(labelPath) && isscalar(labelPath)))
        error('run_detect_noise_chunked:InvalidLabelPath', 'noiseParams.Output.LabelPath must be char or string.');
    end
    write_noise_labels(noiseSegments, char(labelPath));
end
end

function opts = parse_chunk_opts(opts)
if ~isstruct(opts) || ~isscalar(opts)
    error('run_detect_noise_chunked:InvalidChunkOpts', 'chunkOpts must be a scalar struct.');
end
if ~isfield(opts, 'ChunkSec') || isempty(opts.ChunkSec)
    opts.ChunkSec = 180;
end
if ~isfield(opts, 'OverlapSec') || isempty(opts.OverlapSec)
    opts.OverlapSec = 5;
end
if ~isfield(opts, 'EdgeGuardSec') || isempty(opts.EdgeGuardSec)
    opts.EdgeGuardSec = 1;
end
if ~isfield(opts, 'SampleRateOverride')
    opts.SampleRateOverride = [];
end
validateattributes(opts.ChunkSec, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'chunkOpts.ChunkSec');
validateattributes(opts.OverlapSec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0}, mfilename, 'chunkOpts.OverlapSec');
validateattributes(opts.EdgeGuardSec, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0}, mfilename, 'chunkOpts.EdgeGuardSec');
if ~isempty(opts.SampleRateOverride)
    validateattributes(opts.SampleRateOverride, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'chunkOpts.SampleRateOverride');
end
end

function [sourceType, fs, totalSamples, reader] = resolve_source(input, sampleRateOverride)
if ischar(input) || (isstring(input) && isscalar(input))
    wavPath = char(input);
    info = audioinfo(wavPath);
    fs = info.SampleRate;
    totalSamples = info.TotalSamples;
    sourceType = 'file';
    reader = @(startSample, stopSample) audioread(wavPath, [startSample, stopSample]);
elseif isnumeric(input)
    if isempty(sampleRateOverride)
        error('run_detect_noise_chunked:MissingSampleRate', 'chunkOpts.SampleRateOverride required for numeric input.');
    end
    fs = double(sampleRateOverride);
    data = double(input(:));
    totalSamples = numel(data);
    sourceType = 'array';
    reader = @(startSample, stopSample) data(startSample:stopSample);
elseif isstruct(input)
    if ~isfield(input, 'x') || ~isfield(input, 'fs')
        error('run_detect_noise_chunked:InvalidStruct', 'struct input must include x and fs fields.');
    end
    data = double(input.x(:));
    fs = double(input.fs);
    totalSamples = numel(data);
    sourceType = 'struct';
    reader = @(startSample, stopSample) data(startSample:stopSample);
else
    error('run_detect_noise_chunked:UnsupportedInput', 'input must be wav path, numeric vector, or struct with x/fs.');
end
end

function segments = trim_segments(segments, startTime, endTime)
if isempty(segments)
    return;
end
mask = (segments(:, 2) > startTime) & (segments(:, 1) < endTime);
segments = segments(mask, :);
if isempty(segments)
    return;
end
segments(:, 1) = max(segments(:, 1), startTime);
segments(:, 2) = min(segments(:, 2), endTime);
segments = segments(segments(:, 2) > segments(:, 1), :);
end

function merged = merge_segments(segments)
if isempty(segments)
    merged = zeros(0, 2);
    return;
end
segments = sortrows(segments, 1);
merged = segments(1, :);
for idx = 2:size(segments, 1)
    current = segments(idx, :);
    if current(1) <= merged(end, 2)
        merged(end, 2) = max(merged(end, 2), current(2));
    else
        merged(end+1, :) = current; %#ok<AGROW>
    end
end
end
