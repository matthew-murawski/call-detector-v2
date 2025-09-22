function results = tune_detector_params(corpus, paramGrid, opts)
% tune_detector_params searches detector settings for higher recall while holding precision above a floor.

narginchk(2, 3);
if nargin < 3 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts) || ~isscalar(opts)
    error('tune_detector_params:InvalidOpts', 'opts must be a scalar struct.');
end

opts = fill_defaults(opts);
entries = normalise_corpus(corpus);
grid = expand_param_grid(paramGrid);

if isempty(grid)
    error('tune_detector_params:EmptyGrid', 'paramGrid must include at least one field with values.');
end

numCombos = numel(grid);
summary(numCombos) = struct('Params', [], 'Precision', NaN, 'Recall', NaN, ...
    'TruePositives', 0, 'FalsePositives', 0, 'FPProduced', 0, 'FPSilence', 0, ...
    'HeardCovered', 0, 'HeardTotal', 0, 'PredTotal', 0);

bestIdx = NaN;
bestRecall = -inf;
bestPrecision = -inf;

for idx = 1:numCombos
    params = merge_structs(opts.BaseParams, grid(idx));
    totals = struct('tp', 0, 'fp', 0, 'fp_produced', 0, 'fp_silence', 0, ...
        'heard_total', 0, 'heard_hit', 0, 'pred_total', 0);

    for sessionIdx = 1:numel(entries)
        entry = entries(sessionIdx);
        detected = opts.DetectorFcn(entry.audio, entry.produced, "", params);
        metrics = score_session(detected, entry.heard, entry.produced, entry.silence, opts.OverlapThreshold);

        totals.tp = totals.tp + metrics.tp;
        totals.fp = totals.fp + metrics.fp;
        totals.fp_produced = totals.fp_produced + metrics.fp_produced;
        totals.fp_silence = totals.fp_silence + metrics.fp_silence;
        totals.heard_total = totals.heard_total + metrics.heard_total;
        totals.heard_hit = totals.heard_hit + metrics.heard_hit;
        totals.pred_total = totals.pred_total + metrics.pred_total;
    end

    precision = compute_precision(totals.tp, totals.fp);
    recall = compute_recall(totals.heard_hit, totals.heard_total);

    summary(idx).Params = params;
    summary(idx).Precision = precision;
    summary(idx).Recall = recall;
    summary(idx).TruePositives = totals.tp;
    summary(idx).FalsePositives = totals.fp;
    summary(idx).FPProduced = totals.fp_produced;
    summary(idx).FPSilence = totals.fp_silence;
    summary(idx).HeardCovered = totals.heard_hit;
    summary(idx).HeardTotal = totals.heard_total;
    summary(idx).PredTotal = totals.pred_total;

    if precision + eps < opts.MinPrecision
        continue;
    end

    if recall > bestRecall || (abs(recall - bestRecall) < 1e-12 && precision > bestPrecision)
        bestRecall = recall;
        bestPrecision = precision;
        bestIdx = idx;
    end
end

if isnan(bestIdx)
    [~, bestIdx] = max([summary.Recall]);
    bestRecall = summary(bestIdx).Recall;
    bestPrecision = summary(bestIdx).Precision;
end

bestParams = summary(bestIdx).Params;
results = struct();
results.BestIndex = bestIdx;
results.BestParams = bestParams;
results.BestRecall = bestRecall;
results.BestPrecision = bestPrecision;
results.AllResults = summary;
results.Options = opts;
results.CorpusSize = numel(entries);

persist_best(bestParams, opts.SavePath);
end

function opts = fill_defaults(opts)
defaults = struct(...
    'MinPrecision', 0.7, ...
    'OverlapThreshold', 0.15, ...
    'BaseParams', struct(), ...
    'DetectorFcn', @run_detect_heard, ...
    'SavePath', fullfile('models', 'detector_params.json') ...
    );
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(opts, name) || isempty(opts.(name))
        opts.(name) = defaults.(name);
    end
end
validateattributes(opts.MinPrecision, {'numeric'}, {'scalar', '>=', 0, '<=', 1});
validateattributes(opts.OverlapThreshold, {'numeric'}, {'scalar', '>', 0, '<', 1});
if ~isstruct(opts.BaseParams)
    error('tune_detector_params:InvalidBaseParams', 'BaseParams must be a struct.');
end
if ~(isa(opts.DetectorFcn, 'function_handle') || ischar(opts.DetectorFcn))
    error('tune_detector_params:InvalidDetectorFcn', 'DetectorFcn must be callable.');
end
if ~(ischar(opts.SavePath) || (isstring(opts.SavePath) && isscalar(opts.SavePath)))
    error('tune_detector_params:InvalidSavePath', 'SavePath must be a char vector or string scalar.');
end
opts.SavePath = char(opts.SavePath);
end

function entries = normalise_corpus(corpus)
if ~isstruct(corpus)
    error('tune_detector_params:InvalidCorpus', 'corpus must be a struct array.');
end
required = {'audio', 'heard', 'produced', 'silence'};
entries = corpus(:);
for idx = 1:numel(entries)
    entry = entries(idx);
    for ridx = 1:numel(required)
        name = required{ridx};
        if ~isfield(entry, name)
            error('tune_detector_params:MissingField', 'corpus entry missing field: %s', name);
        end
    end
    entries(idx).audio = entry.audio;
    entries(idx).heard = normalise_intervals(entry.heard);
    entries(idx).produced = normalise_intervals(entry.produced);
    entries(idx).silence = normalise_intervals(entry.silence);
end
end

function intervals = normalise_intervals(value)
if isempty(value)
    intervals = zeros(0, 2);
    return;
end
if isa(value, 'table')
    if ~all(ismember({'onset', 'offset'}, value.Properties.VariableNames))
        error('tune_detector_params:InvalidTable', 'interval tables must include onset and offset.');
    end
    value = [value.onset, value.offset];
end
if iscell(value)
    value = cell2mat(value);
end
validateattributes(value, {'numeric'}, {'2d', 'ncols', 2});
if any(~isfinite(value(:)))
    error('tune_detector_params:InvalidIntervalValues', 'intervals must be finite.');
end
if any(value(:, 2) < value(:, 1))
    error('tune_detector_params:InvalidIntervalOrder', 'intervals must satisfy onset <= offset.');
end
intervals = double(value);
end

function grid = expand_param_grid(paramGrid)
if ~isstruct(paramGrid) || isempty(fieldnames(paramGrid))
    grid = struct([]);
    return;
end
names = fieldnames(paramGrid);
values = cell(numel(names), 1);
for idx = 1:numel(names)
    values{idx} = extract_values(paramGrid.(names{idx}), names{idx});
end

counts = cellfun(@numel, values);
numCombos = prod(counts);
comboCells = cell(numCombos, 1);

indices = ones(1, numel(names));
for comboIdx = 1:numCombos
    combo = struct();
    for dim = 1:numel(names)
        combo.(names{dim}) = values{dim}{indices(dim)};
    end
    comboCells{comboIdx} = combo;

    for dim = numel(names):-1:1
        indices(dim) = indices(dim) + 1;
        if indices(dim) <= counts(dim)
            break;
        end
        indices(dim) = 1;
    end
end

grid = [comboCells{:}];
if isempty(grid)
    grid = struct([]);
end
end

function values = extract_values(raw, name)
if isempty(raw)
    error('tune_detector_params:EmptyField', 'grid field %s has no values.', name);
end
if isnumeric(raw)
    values = num2cell(raw(:)');
elseif iscell(raw)
    values = raw;
elseif isstring(raw)
    values = cellstr(raw(:));
elseif ischar(raw)
    values = {raw};
else
    values = num2cell(raw);
end
end

function merged = merge_structs(base, override)
merged = base;
names = fieldnames(override);
for idx = 1:numel(names)
    merged.(names{idx}) = override.(names{idx});
end
end

function metrics = score_session(predicted, heard, produced, silence, overlapThr)
predicted = normalise_intervals(predicted);
heard = normalise_intervals(heard);
produced = normalise_intervals(produced);
silence = normalise_intervals(silence);

metrics = struct('tp', 0, 'fp', 0, 'fp_produced', 0, 'fp_silence', 0, ...
    'heard_total', size(heard, 1), 'heard_hit', 0, 'pred_total', size(predicted, 1));

if isempty(predicted)
    return;
end

heardHits = false(metrics.heard_total, 1);
tpMask = false(metrics.pred_total, 1);
fpProducedMask = false(metrics.pred_total, 1);
fpSilenceMask = false(metrics.pred_total, 1);

for idx = 1:metrics.pred_total
    seg = predicted(idx, :);
    [heardMatch, heardHitIdx] = overlaps_target(seg, heard, overlapThr);
    if heardMatch
        tpMask(idx) = true;
        heardHits = heardHits | heardHitIdx;
    end

    fpProducedMask(idx) = overlaps_any(seg, produced);
    fpSilenceMask(idx) = overlaps_any(seg, silence);
end

metrics.tp = sum(tpMask);
metrics.fp = metrics.pred_total - metrics.tp;
metrics.fp_produced = sum(fpProducedMask & ~tpMask);
metrics.fp_silence = sum(fpSilenceMask & ~tpMask);
metrics.heard_hit = sum(heardHits);
end

function flag = overlaps_any(seg, intervals)
if isempty(intervals)
    flag = false;
    return;
end
overlap = min(seg(2), intervals(:, 2)) - max(seg(1), intervals(:, 1));
flag = any(overlap > 0);
end

function [flag, hitMask] = overlaps_target(seg, intervals, thr)
hitMask = false(size(intervals, 1), 1);
if isempty(intervals)
    flag = false;
    return;
end
dur = max(seg(2) - seg(1), eps);
overlap = min(seg(2), intervals(:, 2)) - max(seg(1), intervals(:, 1));
overlap = max(overlap, 0);
frac = overlap ./ dur;
hitMask = frac >= thr;
flag = any(hitMask);
end

function precision = compute_precision(tp, fp)
if tp + fp == 0
    precision = 0;
else
    precision = tp / (tp + fp);
end
end

function recall = compute_recall(hit, total)
if total == 0
    recall = 0;
else
    recall = hit / total;
end
end

function persist_best(params, savePath)
if isempty(savePath)
    return;
end
folder = fileparts(savePath);
if ~isempty(folder) && exist(folder, 'dir') ~= 7
    mkdir(folder);
end
payload = jsonencode(params, 'PrettyPrint', true);
fid = fopen(savePath, 'w');
if fid == -1
    error('tune_detector_params:SaveFailed', 'unable to open %s for writing.', savePath);
end
cleaner = onCleanup(@() fclose(fid));
fwrite(fid, payload, 'char');
clear cleaner;
end
