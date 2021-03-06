`ifndef SPIKES_IF
`define SPIKES_IF

class spike_transactor #(NUM_SYNAPSE_ROWS=1,ADDR_WIDTH=16);

	class spike_t;
		logic[NUM_SYNAPSE_ROWS-1:0] rows;
		logic[ADDR_WIDTH-1:0] address;
		integer t;
		integer width;

		function new (integer ti, logic[NUM_SYNAPSE_ROWS-1:0] r, logic[ADDR_WIDTH-1:0] a);
			t = ti;
			rows = r;
			address = a;
			width = 10;
		endfunction

	endclass

	class spike_send_event_t;
		logic[NUM_SYNAPSE_ROWS-1:0] rows;
		logic[ADDR_WIDTH-1:0] address;
		integer t;
		logic on_off;

		function new (integer ti, logic[NUM_SYNAPSE_ROWS-1:0] r, logic[ADDR_WIDTH-1:0] a, logic on);
			t = ti;
			rows = r;
			address = a;
			on_off = on;
		endfunction
	endclass

	virtual spike_if spike_in[NUM_SYNAPSE_ROWS];
	virtual tb_clk_if tb_clk;
	spike_t spikes[$];
	spike_send_event_t start_times[$], stop_times[$];
	integer seed, t;


	function new(virtual spike_if intf[NUM_SYNAPSE_ROWS], virtual tb_clk_if tbck);
		spike_in = intf;
		tb_clk = tbck;
		seed = $random;
		t = 0;

		for (integer r=0;r<NUM_SYNAPSE_ROWS;r++) begin
			spike_in[r].valid = 1'b0;
			spike_in[r].on_off = 1'b1;
		end
	endfunction

	function void append_spike (integer timestamp, logic[NUM_SYNAPSE_ROWS-1:0] input_rows, logic[7:0] address);
		spike_t this_spike = new(timestamp,input_rows,address);
		spikes.push_back(this_spike);
	endfunction

	function void append_poisson(time start, time stop, integer isi, logic[NUM_SYNAPSE_ROWS-1:0] input_rows, fp::fpType address);
		spike_t this_spike;
		time next_fire_time = start;
		while (next_fire_time < stop) begin
			if (next_fire_time > start) begin
				this_spike = new(next_fire_time, input_rows, address);
				spikes.push_back(this_spike);
				//$display("Appending spike at time %d",next_fire_time);
			end
			next_fire_time = next_fire_time + $dist_exponential(seed,isi);
			//$display("Next firing time: %d", next_fire_time);
		end
	endfunction

	function void prepare_spikes();
		spike_send_event_t append_spike;

		spikes.sort() with (item.t);

		foreach(spikes[i]) begin
			append_spike = new(spikes[i].t,spikes[i].rows,spikes[i].address,1'b1);
			start_times.push_back(append_spike);
			append_spike = new(spikes[i].t+spikes[i].width,spikes[i].rows,spikes[i].address,1'b0);
			stop_times.push_back(append_spike);
		end
		$display("Number of start spikes: %d",start_times.size());
		//foreach (start_times[i]) begin
			//$display("%d",start_times[i].t);
		//end
		$display("Number of stop spikes: %d",stop_times.size());
		//foreach (stop_times[i]) begin
			//$display("%d",stop_times[i].t);
		//end
	endfunction

	task no_spike();
		for (integer r=0;r<NUM_SYNAPSE_ROWS;r++)
			spike_in[r].valid = 1'b0;
		@(posedge tb_clk.fast_clk);
		t = t + 1;
	endtask

	task send_spike(spike_send_event_t this_spike);
		//$display("Sending spike @%d",$time);
		for (integer r=0;r<NUM_SYNAPSE_ROWS;r++) begin
			spike_in[r].valid = this_spike.rows[r];
			spike_in[r].address = this_spike.address;
			spike_in[r].on_off = this_spike.on_off;
		end
		@(posedge tb_clk.fast_clk);
		t = t + 1;
	endtask

	function clear_all();
		t = 0;
		spikes = {};
		start_times = {};
		stop_times = {};
	endfunction

	task send_spikes();
		spike_t this_spike;
		logic last_sent_start = 1'b0;

		prepare_spikes();

		while(start_times.size() > 0 || stop_times.size() > 0) begin
			if (start_times.size() == 0) begin
				//$display("Start times empty");
				//$display("Stop times[0].t=%d @t=%d",stop_times[0].t,t);
				if (stop_times[0].t <= t) begin
					// send stop spike
					while (stop_times.size() > 0 && stop_times[0].t <= t) begin
						send_spike(stop_times.pop_front());
					end
				end
				else begin
					no_spike();
				end
			end
			else if (stop_times.size() == 0) begin
				if (start_times[0].t <= t) begin
					// send start spike
					while (start_times.size() > 0 && start_times[0].t <= t) begin
						send_spike(start_times.pop_front());
					end
				end
				else begin
					no_spike();
				end
			end
			else begin
				if (start_times[0].t <= t && stop_times[0].t > t) begin
					// send start spike
					while (start_times.size() > 0 && start_times[0].t <= t) begin
						send_spike(start_times.pop_front());
					end
				end
				else if (start_times[0].t <= t && stop_times[0].t <= t && last_sent_start == 1'b0) begin
					// send start spike
					while (start_times.size() > 0 && start_times[0].t <= t) begin
						send_spike(start_times.pop_front());
					end
					last_sent_start = 1'b1;
				end
				else if (start_times[0].t > t && stop_times[0].t <= t) begin
					// send stop spike
					while (stop_times.size() > 0 && stop_times[0].t <= t) begin
						send_spike(stop_times.pop_front());
					end
				end
				else if (start_times[0].t <= t && stop_times[0].t <= t && last_sent_start == 1'b1) begin
					// send stop spike
					while (stop_times.size() > 0 && stop_times[0].t <= t) begin
						send_spike(stop_times.pop_front());
					end
					last_sent_start = 1'b0;
				end
				else begin
					no_spike();
				end
			end
		end

		for (integer r=0;r<NUM_SYNAPSE_ROWS;r++)
			spike_in[r].valid = 1'b0;

		@(posedge tb_clk.fast_clk);
		//$display("Done sending spikes @%d",$time);
	endtask

endclass

`endif //SPIKES_IF
