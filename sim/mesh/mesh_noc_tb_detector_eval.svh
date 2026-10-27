// Evaluates advance prediction against the independent future-event definition.
    task automatic evaluate_detectors(input integer trace_end);
        integer sample_count;
        integer tfp_tp;
        integer tfp_fp;
        integer tfp_tn;
        integer tfp_fn;
        integer occ_tp;
        integer occ_fp;
        integer occ_tn;
        integer occ_fn;
        integer event_count;
        integer tfp_advance_events;
        integer tfp_missed_events;
        integer occ_advance_events;
        integer occ_missed_events;
        integer tfp_lead_sum;
        integer occ_lead_sum;
        integer consecutive_blocked;
        integer blocked_output_cycles;
        integer network_congested_cycles;
        integer current_network_congested_streak;
        integer max_network_congested_streak;
        integer cycle_has_blockage;
        integer future_event;
        integer last_prediction;
        integer start_cycle;
        real tfp_precision;
        real tfp_recall;
        real tfp_f1;
        real occ_precision;
        real occ_recall;
        real occ_f1;

        sample_count = 0;
        tfp_tp = 0;
        tfp_fp = 0;
        tfp_tn = 0;
        tfp_fn = 0;
        occ_tp = 0;
        occ_fp = 0;
        occ_tn = 0;
        occ_fn = 0;
        event_count = 0;
        tfp_advance_events = 0;
        tfp_missed_events = 0;
        occ_advance_events = 0;
        occ_missed_events = 0;
        tfp_lead_sum = 0;
        occ_lead_sum = 0;
        blocked_output_cycles = 0;
        network_congested_cycles = 0;
        current_network_congested_streak = 0;
        max_network_congested_streak = 0;
        start_cycle = 4;

        for (int cycle_index = start_cycle; cycle_index < trace_end; cycle_index++) begin
            cycle_has_blockage = 0;
            for (int output_index = 0; output_index < NUM_OUTPUTS; output_index++) begin
                if (blocked_trace[output_index][cycle_index]) begin
                    blocked_output_cycles++;
                    cycle_has_blockage = 1;
                end
            end
            if (cycle_has_blockage) begin
                network_congested_cycles++;
                current_network_congested_streak++;
                if (current_network_congested_streak > max_network_congested_streak)
                    max_network_congested_streak = current_network_congested_streak;
            end else begin
                current_network_congested_streak = 0;
            end
        end

        for (int output_index = 0; output_index < NUM_OUTPUTS; output_index++) begin
            for (int cycle_index = start_cycle;
                 cycle_index + EVENT_HORIZON < trace_end;
                 cycle_index++) begin
                consecutive_blocked = 0;
                future_event = 0;
                for (int future_cycle = cycle_index + 1;
                     future_cycle <= cycle_index + EVENT_HORIZON;
                     future_cycle++) begin
                    if (blocked_trace[output_index][future_cycle]) begin
                        consecutive_blocked++;
                        if (consecutive_blocked >= EVENT_BLOCKED_CYCLES)
                            future_event = 1;
                    end else begin
                        consecutive_blocked = 0;
                    end
                end

                sample_count++;
                if (pcr_prediction_trace[output_index][cycle_index]) begin
                    if (future_event) tfp_tp++;
                    else tfp_fp++;
                end else begin
                    if (future_event) tfp_fn++;
                    else tfp_tn++;
                end

                if (occupancy_prediction_trace[output_index][cycle_index]) begin
                    if (future_event) occ_tp++;
                    else occ_fp++;
                end else begin
                    if (future_event) occ_fn++;
                    else occ_tn++;
                end
            end

            for (int onset = start_cycle + 1;
                 onset + EVENT_BLOCKED_CYCLES <= trace_end;
                 onset++) begin
                if (blocked_trace[output_index][onset] &&
                    !blocked_trace[output_index][onset-1] &&
                    blocked_trace[output_index][onset+1] &&
                    blocked_trace[output_index][onset+2] &&
                    blocked_trace[output_index][onset+3]) begin
                    event_count++;

                    last_prediction = -1;
                    for (int prior = onset - EVENT_HORIZON;
                         prior < onset;
                         prior++) begin
                        if (prior >= start_cycle &&
                            pcr_prediction_trace[output_index][prior])
                            last_prediction = prior;
                    end
                    if (last_prediction >= start_cycle) begin
                        tfp_advance_events++;
                        tfp_lead_sum += onset - last_prediction;
                    end else begin
                        tfp_missed_events++;
                    end

                    last_prediction = -1;
                    for (int prior = onset - EVENT_HORIZON;
                         prior < onset;
                         prior++) begin
                        if (prior >= start_cycle &&
                            occupancy_prediction_trace[output_index][prior])
                            last_prediction = prior;
                    end
                    if (last_prediction >= start_cycle) begin
                        occ_advance_events++;
                        occ_lead_sum += onset - last_prediction;
                    end else begin
                        occ_missed_events++;
                    end
                end
            end
        end

        tfp_precision = (tfp_tp + tfp_fp) == 0 ? 0.0 :
            real'(tfp_tp) / real'(tfp_tp + tfp_fp);
        tfp_recall = (tfp_tp + tfp_fn) == 0 ? 0.0 :
            real'(tfp_tp) / real'(tfp_tp + tfp_fn);
        tfp_f1 = (tfp_precision + tfp_recall) == 0.0 ? 0.0 :
            2.0 * tfp_precision * tfp_recall / (tfp_precision + tfp_recall);
        occ_precision = (occ_tp + occ_fp) == 0 ? 0.0 :
            real'(occ_tp) / real'(occ_tp + occ_fp);
        occ_recall = (occ_tp + occ_fn) == 0 ? 0.0 :
            real'(occ_tp) / real'(occ_tp + occ_fn);
        occ_f1 = (occ_precision + occ_recall) == 0.0 ? 0.0 :
            2.0 * occ_precision * occ_recall / (occ_precision + occ_recall);

        $display("EVAL event: >=%0d consecutive output-blocked cycles within next %0d cycles",
                 EVENT_BLOCKED_CYCLES, EVENT_HORIZON);
        $display("EVAL TF-PCR: TP=%0d FP=%0d TN=%0d FN=%0d precision=%0.3f recall=%0.3f F1=%0.3f false-positive/output-cycle=%0.6f",
                 tfp_tp, tfp_fp, tfp_tn, tfp_fn,
                 tfp_precision, tfp_recall, tfp_f1,
                 real'(tfp_fp) / real'(sample_count));
        $display("EVAL Occupancy: TP=%0d FP=%0d TN=%0d FN=%0d precision=%0.3f recall=%0.3f F1=%0.3f false-positive/output-cycle=%0.6f (threshold=3 flits)",
                 occ_tp, occ_fp, occ_tn, occ_fn,
                 occ_precision, occ_recall, occ_f1,
                 real'(occ_fp) / real'(sample_count));
        $display("EVAL Advance-only: events=%0d TF-PCR detected=%0d missed=%0d mean-lead=%0.2f cycles; occupancy detected=%0d missed=%0d mean-lead=%0.2f cycles",
                 event_count, tfp_advance_events, tfp_missed_events,
                 tfp_advance_events == 0 ? 0.0 :
                    real'(tfp_lead_sum) / real'(tfp_advance_events),
                 occ_advance_events, occ_missed_events,
                 occ_advance_events == 0 ? 0.0 :
                    real'(occ_lead_sum) / real'(occ_advance_events));
        $display("EVAL Congestion: blocked-output-cycles=%0d network-congested-cycles=%0d longest-network-congestion=%0d cycles",
                 blocked_output_cycles, network_congested_cycles,
                 max_network_congested_streak);
    endtask
