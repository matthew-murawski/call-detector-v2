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
    x = select_second_channel(raw);
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
validateattributes(input.x, {'numeric'}, {'nonempty', '2d'}, mfilename, 'x');
fs = double(input.fs);
x = select_second_channel(input.x);
end

function x = select_second_channel(data)
data = double(data);
if isvector(data)
    x = data(:);
    return;
end
if size(data, 2) >= 2
    % take channel two when stereo data arrives
    x = data(:, 2);
    x = x(:);
    return;
end
if size(data, 1) >= 2
    x = data(2, :).';
    return;
end
x = data(:);
end
