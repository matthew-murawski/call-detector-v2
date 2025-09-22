function model = train_calibrator(Feat, Label, SessionID, opts)
% train_calibrator standardises features, fits a linear probabilistic model, and selects a recall-driven threshold.

narginchk(3, 4);
if nargin < 4 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts) || ~isscalar(opts)
    error('train_calibrator:InvalidOpts', 'opts must be a scalar struct.');
end

opts = fill_defaults(opts);

Feat = double(Feat);
validateattributes(Feat, {'double'}, {'2d', 'nonempty', 'real'}, mfilename, 'Feat');

Label = Label(:);
Label = double(Label);
validateattributes(Label, {'double'}, {'vector', 'numel', size(Feat, 1)}, mfilename, 'Label');
Label = Label ~= 0;

if all(Label == 0) || all(Label == 1)
    error('train_calibrator:SingleClass', 'Labels must contain both positive and negative examples.');
end

SessionID = normalise_session_ids(SessionID, size(Feat, 1));

[mu_full, sigma_full] = compute_scaler(Feat);
Feat_std = standardise(Feat, mu_full, sigma_full);

learner = opts.Learner;
solver = opts.Solver;

fitArgs = {'Learner', learner, 'Solver', solver, 'ClassNames', [0; 1]};
if ~isempty(opts.Lambda)
    fitArgs = [fitArgs, {'Lambda', opts.Lambda}]; %#ok<AGROW>
end

full_model = fitclinear(Feat_std, Label, fitArgs{:});

beta = full_model.Beta;
bias = full_model.Bias;

score_full = Feat_std * beta + bias;
prob_full = sigmoid(score_full);

[cv_probs, cv_labels] = crossval_scores(Feat, Label, SessionID, fitArgs, opts.TargetRecall);
if numel(categories(SessionID)) < 2 || isempty(cv_probs)
    threshold = choose_threshold(prob_full, Label, opts.TargetRecall);
else
    threshold = choose_threshold(cv_probs, cv_labels, opts.TargetRecall);
end

model = struct();
model.Scaler = struct('mu', mu_full, 'sigma', sigma_full);
model.Beta = beta;
model.Bias = bias;
model.Threshold = threshold;
model.TargetRecall = opts.TargetRecall;
model.Learner = learner;
model.Solver = solver;
model.Classes = full_model.ClassNames;
model.AUC = compute_auc(prob_full, Label);

if ~isempty(opts.SavePath)
    save_calibrator(opts.SavePath, model);
end
end

function opts = fill_defaults(opts)
defaults = struct(...
    'TargetRecall', 0.85, ...
    'Learner', 'logistic', ...
    'Solver', 'lbfgs', ...
    'Lambda', [], ...
    'SavePath', 'output' ...
    );
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(opts, name) || isempty(opts.(name))
        opts.(name) = defaults.(name);
    end
end
validateattributes(opts.TargetRecall, {'numeric'}, {'scalar', '>', 0, '<', 1});
validateattributes(opts.Learner, {'char', 'string'}, {'scalartext'});
validateattributes(opts.Solver, {'char', 'string'}, {'scalartext'});
if ~isempty(opts.Lambda)
    validateattributes(opts.Lambda, {'numeric'}, {'scalar', '>=', 0});
end
if ~isempty(opts.SavePath)
    validateattributes(opts.SavePath, {'char', 'string'}, {'scalartext'});
end
opts.Learner = char(opts.Learner);
opts.Solver = char(opts.Solver);
opts.SavePath = char(opts.SavePath);
end

function SessionID = normalise_session_ids(SessionID, n)
if iscategorical(SessionID)
    SessionID = SessionID(:);
elseif isstring(SessionID)
    SessionID = categorical(strtrim(SessionID(:)));
elseif iscellstr(SessionID)
    SessionID = categorical(SessionID(:));
elseif isnumeric(SessionID)
    SessionID = categorical(string(SessionID(:)));
else
    error('train_calibrator:InvalidSessionID', 'Unsupported SessionID type.');
end
if numel(SessionID) ~= n
    error('train_calibrator:SessionCountMismatch', 'SessionID must have one entry per row.');
end
end

function [mu, sigma] = compute_scaler(X)
mu = mean(X, 1);
sigma = std(X, 0, 1);
sigma(~isfinite(sigma) | sigma == 0) = 1;
end

function Xs = standardise(X, mu, sigma)
Xs = bsxfun(@minus, X, mu);
Xs = bsxfun(@rdivide, Xs, sigma);
Xs(~isfinite(Xs)) = 0;
end

function [probs, labels] = crossval_scores(X, y, sessions, fitArgs, targetRecall)
unique_sessions = unique(sessions);
probs = [];
labels = [];

for idx = 1:numel(unique_sessions)
    test_mask = sessions == unique_sessions(idx);
    train_mask = ~test_mask;
    if ~any(test_mask) || sum(train_mask) < 2
        continue;
    end
    y_train = y(train_mask);
    if numel(unique(y_train)) < 2
        continue;
    end
    X_train = X(train_mask, :);
    X_test = X(test_mask, :);

    [mu, sigma] = compute_scaler(X_train);
    X_train_std = standardise(X_train, mu, sigma);

    fold_model = fitclinear(X_train_std, y_train, fitArgs{:});

    X_test_std = standardise(X_test, mu, sigma);
    [~, fold_scores] = predict(fold_model, X_test_std);
    pos_idx = find(fold_model.ClassNames == 1, 1);
    if isempty(pos_idx)
        continue;
    end
    fold_probs = sigmoid(fold_scores(:, pos_idx));

    probs = [probs; fold_probs]; %#ok<AGROW>
    labels = [labels; y(test_mask)]; %#ok<AGROW>
end

end

function thr = choose_threshold(probs, labels, targetRecall)
probs = probs(:);
labels = labels(:);

if isempty(probs) || sum(labels) == 0
    thr = 0.5;
    return;
end

[probs_sorted, order] = sort(probs, 'descend');
labels_sorted = labels(order);

tp = cumsum(labels_sorted);
fp = cumsum(~labels_sorted);
total_pos = sum(labels);

recall = tp / total_pos;

idx = find(recall >= targetRecall, 1, 'first');
if isempty(idx)
    thr = min(probs_sorted);
else
    thr = probs_sorted(idx);
end

thr = min(max(thr, eps), 1 - eps);
end

function val = sigmoid(z)
val = 1 ./ (1 + exp(-z));
end

function auc = compute_auc(prob, label)
label = double(label(:));
if numel(unique(label)) < 2
    auc = NaN;
    return;
end
try
    [~,~,~,auc] = perfcurve(label, prob, 1);
catch
    auc = NaN;
end
end

function save_calibrator(savePath, model)
[folder, ~, ~] = fileparts(savePath);
if ~isempty(folder) && exist(folder, 'dir') ~= 7 && ~isempty(folder)
    mkdir(folder);
end
save(savePath, 'model');
end
