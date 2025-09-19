function [y, fs_out] = resample_if_needed(x, fs_in, fs_target)
%% validate inputs
validateattributes(x, {'numeric'}, {'nonempty'}, mfilename, 'x');
if ndims(x) > 2
    error('resample_if_needed:InvalidInput', 'x must be a vector or 2d matrix.');
end
validateattributes(fs_in, {'numeric'}, {'scalar', 'positive'}, mfilename, 'fs_in');
validateattributes(fs_target, {'numeric'}, {'scalar', 'positive'}, mfilename, 'fs_target');
fs_in = double(fs_in);
fs_target = double(fs_target);

%% perform resampling
if fs_in == fs_target
    y = x;
    fs_out = fs_in;
    return;
end

was_row = isrow(x);
if was_row
    x = x.';
end
x = double(x);
y = resample(x, fs_target, fs_in);
if was_row
    y = y.';
end
fs_out = fs_target;
end
