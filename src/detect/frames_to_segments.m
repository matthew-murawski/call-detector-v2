function intervals = frames_to_segments(frame_in, hop)
% frames_to_segments converts frame flags to [start, stop] intervals in seconds.

narginchk(2, 2);

validateattributes(frame_in, {'logical', 'numeric'}, {'vector'}, mfilename, 'frame_in');
validateattributes(hop, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'hop');

frame_in = logical(frame_in(:));
hop = double(hop);
if isempty(frame_in)
    intervals = zeros(0, 2);
    return;
end

changes = diff([false; frame_in; false]);
starts = find(changes == 1);
stops = find(changes == -1) - 1;
if isempty(starts)
    intervals = zeros(0, 2);
    return;
end

start_times = (starts - 1) * hop;
stop_times = stops * hop + hop;
intervals = [start_times, stop_times];
end
