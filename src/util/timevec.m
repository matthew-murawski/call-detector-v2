function t = timevec(nSamples, fs)
% return column vector [nSamples×1] of times (s) from 0 to (nSamples-1)/fs
% validate inputs; error if fs<=0 or nSamples<1
%% validate inputs
validateattributes(nSamples, {'numeric'}, {'scalar', 'integer', '>=', 1}, mfilename, 'nSamples');
validateattributes(fs, {'numeric'}, {'scalar', 'positive'}, mfilename, 'fs');

%% compute vector
nSamples = double(nSamples);
fs = double(fs);
t = (0:nSamples-1).' ./ fs;
end
