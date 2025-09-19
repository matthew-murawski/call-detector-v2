function [keep_idx, scores] = apply_calibrator(model, X)
% apply_calibrator scores feature rows with a trained calibrator and returns keep flags.

validate_model(model);

X = double(X);
validateattributes(X, {'double'}, {'2d', 'nonempty', 'real'}, mfilename, 'X');

mu = model.Scaler.mu;
sigma = model.Scaler.sigma;
if numel(mu) ~= size(X, 2)
    error('apply_calibrator:DimMismatch', 'Feature dimension does not match scaler.');
end

sigma_adj = sigma;
sigma_adj(~isfinite(sigma_adj) | sigma_adj == 0) = 1;

X_std = bsxfun(@minus, X, mu);
X_std = bsxfun(@rdivide, X_std, sigma_adj);
X_std(~isfinite(X_std)) = 0;

scores = sigmoid(X_std * model.Beta + model.Bias);

keep_idx = scores >= model.Threshold;

end

function validate_model(model)
required_fields = {'Scaler', 'Beta', 'Bias', 'Threshold'};
for k = 1:numel(required_fields)
    if ~isfield(model, required_fields{k})
        error('apply_calibrator:InvalidModel', 'Missing field %s.', required_fields{k});
    end
end
if ~isfield(model.Scaler, 'mu') || ~isfield(model.Scaler, 'sigma')
    error('apply_calibrator:InvalidScaler', 'Scaler must include mu and sigma.');
end
end

function y = sigmoid(z)
y = 1 ./ (1 + exp(-z));
end
