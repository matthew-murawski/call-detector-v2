function [x, fs] = read_audio(input)
    % read audio from a file path or struct and ensure column output.

    if isstruct(input)
        if ~isfield(input, 'x') || ~isfield(input, 'fs')
            error('read_audio:MissingFields', ...
                'struct input must contain fields "x" and "fs".');
        end

        x = input.x;
        fs = input.fs;
    elseif ischar(input) || (isstring(input) && isscalar(input))
        if isstring(input)
            input = char(input);
        end

        if exist(input, 'file') ~= 2
            error('read_audio:MissingFile', 'file not found: %s', input);
        end

        [x, fs] = audioread(input);
    else
        error('read_audio:InvalidInput', ...
            'input must be a file path or struct with fields x and fs.');
    end

    if ~isnumeric(x)
        error('read_audio:InvalidSamples', 'audio samples must be numeric.');
    end

    if ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error('read_audio:InvalidRate', 'sampling rate must be a positive finite scalar.');
    end

    x = double(x);
    fs = double(fs);

    if isempty(x)
        x = zeros(0, 1);
    else
        if ndims(x) > 2
            error('read_audio:InvalidShape', 'audio array must be one- or two-dimensional.');
        end

        if isvector(x)
            x = x(:);
        else
            % average multiple channels into a single mono track.
            x = mean(x, 2);
            x = x(:);
        end
    end

    if any(~isfinite(x))
        error('read_audio:NonFiniteSamples', 'audio samples must be finite.');
    end
end
