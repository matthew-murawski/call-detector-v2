function [x, fs] = read_audio(input)
% read audio from struct or wav path and return column vector data.
%% handle path input
if ischar(input) || (isstring(input) && isscalar(input))
    path = char(input);
    if exist(path, 'file') ~= 2
        error('read_audio:FileNotFound', 'Audio file not found: %s', path);
    end
    [~, ~, ext] = fileparts(path);
    if ~strcmpi(ext, '.wav')
        error('read_audio:UnsupportedFormat', 'Only .wav files are supported.');
    end
    [raw, fs] = audioread(path);
    if isempty(raw)
        error('read_audio:EmptyAudio', 'Audio file contains no samples.');
    end
    if size(raw, 2) > 1
        raw = mean(raw, 2);
    end
    x = double(raw(:));
    fs = double(fs);
    validateattributes(fs, {'numeric'}, {'scalar', 'positive'}, mfilename, 'fs');
    return;
end

%% handle struct input
if ~isstruct(input)
    error('read_audio:InvalidInput', 'Input must be a wav path or struct with fields x and fs.');
end
if ~isfield(input, 'x') || ~isfield(input, 'fs')
    error('read_audio:MissingFields', 'Struct input must contain fields x and fs.');
end
validateattributes(input.fs, {'numeric'}, {'scalar', 'positive'}, mfilename, 'fs');
validateattributes(input.x, {'numeric'}, {'vector', 'nonempty'}, mfilename, 'x');
fs = double(input.fs);
x = double(input.x(:));
end
