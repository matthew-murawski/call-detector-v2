classdef test_train_calibrator < matlab.unittest.TestCase
    %% setup paths
    methods (TestClassSetup)
        function add_learn_paths(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'learn'));
        end
    end

    %% tests
    methods (Test)
        function logistic_threshold_improves_precision(tc)
            rng(42);
            sessions = categorical([repmat("S1", 60, 1); repmat("S2", 60, 1); repmat("S3", 60, 1); repmat("S4", 60, 1)]);
            labels = [zeros(30, 1); ones(30, 1); zeros(30, 1); ones(30, 1); zeros(30, 1); ones(30, 1); zeros(30, 1); ones(30, 1)];
            labels = labels(1:numel(sessions));

            d = numel(sessions);
            feats = zeros(d, 5);
            for idx = 1:d
                sid = double(sessions(idx) == "S1") + 2 * double(sessions(idx) == "S2") + 3 * double(sessions(idx) == "S3");
                if labels(idx)
                    feats(idx, :) = [2 2 1.5 0.5 0] + 0.5 * randn(1, 5) + sid * 0.1;
                else
                    feats(idx, :) = [0 0 -0.5 0.2 0] + 0.8 * randn(1, 5) + sid * 0.1;
                end
            end

            opts = struct('TargetRecall', 0.85);
            model = train_calibrator(feats, labels, sessions, opts);

            tc.verifyGreaterThan(model.Threshold, 0);
            tc.verifyLessThan(model.Threshold, 1);

            mu = model.Scaler.mu;
            sigma = model.Scaler.sigma;
            sigma(sigma == 0) = 1;
            scores = (feats - mu) ./ sigma * model.Beta + model.Bias;
            probs = 1 ./ (1 + exp(-scores));

            [~, ~, ~, auc] = perfcurve(labels, probs, 1);
            tc.verifyGreaterThan(auc, 0.8);

            hold_mask = sessions == "S4";
            hold_feats = feats(hold_mask, :);
            hold_labels = labels(hold_mask);
            hold_scores = (hold_feats - mu) ./ sigma * model.Beta + model.Bias;
            hold_probs = 1 ./ (1 + exp(-hold_scores));

            base_pred = hold_probs >= 0.5;
            tuned_pred = hold_probs >= model.Threshold;

            [prec_base, rec_base] = test_train_calibrator.prec_rec(base_pred, hold_labels);
            [prec_tuned, rec_tuned] = test_train_calibrator.prec_rec(tuned_pred, hold_labels);

            tc.verifyGreaterThanOrEqual(prec_tuned, prec_base);
            tc.verifyLessThanOrEqual(max(0, rec_base - rec_tuned), 0.1);
        end

        function single_session_threshold_respects_true_positives(tc)
            neg = [-1.0 -1.0; -0.9 -1.2; -1.2 -0.8; -0.95 -1.05; -1.1 -0.9; -0.85 -1.15];
            pos = [1.0 1.0; 1.1 0.9; 0.9 1.2; 1.05 0.95; 1.2 0.85; 0.95 1.1];
            feats = [neg; pos];
            labels = [zeros(size(neg, 1), 1); ones(size(pos, 1), 1)];
            sessions = categorical(repmat("S1", numel(labels), 1));

            opts = struct('TargetRecall', 0.9);
            model = train_calibrator(feats, labels, sessions, opts);

            tc.verifyLessThan(model.Threshold, 1);
            tc.verifyGreaterThan(model.Threshold, 0);

            mu = model.Scaler.mu;
            sigma = model.Scaler.sigma;
            sigma(sigma == 0) = 1;
            scores = (feats - mu) ./ sigma * model.Beta + model.Bias;
            probs = 1 ./ (1 + exp(-scores));

            tp_probs = probs(labels == 1);
            tc.verifyGreaterThanOrEqual(min(tp_probs), model.Threshold);
        end
    end

    methods (Static)
        function [precision, recall] = prec_rec(pred, truth)
            truth = truth(:) ~= 0;
            pred = pred(:) ~= 0;
            tp = sum(pred & truth);
            fp = sum(pred & ~truth);
            fn = sum(~pred & truth);
            if tp + fp == 0
                precision = 0;
            else
                precision = tp / (tp + fp);
            end
            if tp + fn == 0
                recall = 0;
            else
                recall = tp / (tp + fn);
            end
        end
    end
end
