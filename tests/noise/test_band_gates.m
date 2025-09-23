classdef test_band_gates < matlab.unittest.TestCase
    % tests exercise robust thresholds and gating against synthetic band energy streams.

    methods (TestClassSetup)
        function add_source_to_path(tc) %#ok<INUSD>
            root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(fullfile(root_dir, 'src', 'noise'));
        end
    end
    % the test block covers burst detection and rolling window stability.

    methods (Test)
        function bursts_toggle_gates(tc)
            rng(0);
            numFrames = 120;
            t = 1:numFrames;
            base = 0.2 + 0.01 * sin(t / 7) + 0.02 * randn(1, numFrames);
            base = max(base, 0.05);

            bandEnergy = struct();
            bandEnergy.Low = base;
            bandEnergy.Low(30:40) = bandEnergy.Low(30:40) + 0.6;
            bandEnergy.In = base;
            bandEnergy.In(60:75) = bandEnergy.In(60:75) + 0.7;
            bandEnergy.High = base;
            bandEnergy.High(90:100) = bandEnergy.High(90:100) + 0.8;

            k = struct('Enter', 3.0, 'Exit', 1.5);
            thresholds = robust_band_thresholds(bandEnergy, 'MAD', k, []);
            [gateLow, gateIn, gateHigh] = band_gates(bandEnergy, thresholds);

            lowIdx = find(gateLow);
            tc.verifyNotEmpty(lowIdx);
            tc.verifyGreaterThanOrEqual(min(lowIdx), 30);
            tc.verifyLessThanOrEqual(max(lowIdx), 46);

            inIdx = find(gateIn);
            tc.verifyNotEmpty(inIdx);
            tc.verifyGreaterThanOrEqual(min(inIdx), 60);
            tc.verifyLessThanOrEqual(max(inIdx), 81);

            highIdx = find(gateHigh);
            tc.verifyNotEmpty(highIdx);
            tc.verifyGreaterThanOrEqual(min(highIdx), 90);
            tc.verifyLessThanOrEqual(max(highIdx), 102);
        end

        function rolling_window_tracks_drift(tc)
            numFrames = 90;
            ramp = linspace(0.1, 0.5, numFrames);
            wobble = 0.01 * sin((1:numFrames) / 3);

            bandEnergy = struct();
            bandEnergy.Low = ramp + wobble;
            bandEnergy.In = ramp + wobble / 2;
            bandEnergy.High = ramp + wobble / 3;

            k = struct('Enter', 3.0, 'Exit', 2.0);
            thresholds = robust_band_thresholds(bandEnergy, 'MAD', k, 21);
            [gateLow, gateIn, gateHigh] = band_gates(bandEnergy, thresholds);

            tc.verifyFalse(any(gateLow));
            tc.verifyFalse(any(gateIn));
            tc.verifyFalse(any(gateHigh));
        end

        function rolling_window_handles_multiple_bursts(tc)
            numFrames = 80;
            base = 0.15 + 0.015 * sin((1:numFrames) / 5);

            bandEnergy = struct();
            bandEnergy.Low = base;
            bandEnergy.In = base;
            bandEnergy.High = base;
            bandEnergy.In(15:20) = bandEnergy.In(15:20) + 1.5;
            bandEnergy.In(40:45) = bandEnergy.In(40:45) + 1.6;

            k = struct('Enter', 1.2, 'Exit', 0.8);
            thresholds = robust_band_thresholds(bandEnergy, 'MAD', k, 11);
            [~, gateIn, ~] = band_gates(bandEnergy, thresholds);

            tc.verifyTrue(any(gateIn(15:20)));
            tc.verifyTrue(any(gateIn(40:45)));
            tc.verifyLessThan(sum(gateIn(1:12)), numFrames * 0.1);
            tc.verifyLessThan(sum(gateIn(55:numFrames)), numFrames * 0.1);
        end
    end
end
