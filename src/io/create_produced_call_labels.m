function create_produced_call_labels(session, outputPath)

behavior = load_session_behavior('M93A', session);

behavior.times = heard;
behavior.labels = repmat("heard", length(heard), 1);

out = export_audacity_labels(behavior, outputPath);

disp(out);
fprintf('wrote %d events to: %s\n', out.n_events_written, out.out_txt);

end