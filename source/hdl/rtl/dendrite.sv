
module dendrite(
	input logic clk,
	input logic reset,
	config_if.slave cfg_in,
	config_if.master cfg_out,
	output fp::fpType upper_vmem,
	input fp::fpType upper_current,
	input fp::fpType lower_vmem,
	output fp::fpType lower_current,
	synapse_dendrite_if synapse0,
	synapse_dendrite_if synapse1,
	input fp::fpType E_l
);

	localparam right_shift_decay_vmem = 15;
	// a membrane difference multiplied by a conductances,
	// i.e. U(7,9) * A(8,7) and it will be added to a voltage again
	localparam right_shift_lower_current = 9;

	// neuron model parameters
	//fp::fpType E_l;
	fp::fpType tau_mem, g_int;

	logic carry_synadd, carry_add_vmem, carry_add_all;
	fp::fpType vmem, sum_syn_current, new_vmem, vmem_synin, vmem_decay_synin;
	logic[fp::WORD_LENGTH*2+1-1:0] decay_vmem, current_to_lower;
	fp::fpType E_l_vmem_diff, decay_vmem_shifted, compartment_difference;
	assign synapse0.vmem = vmem;
	assign synapse1.vmem = vmem;
	assign decay_vmem_shifted = (decay_vmem>>right_shift_decay_vmem)&16'hffff;
	assign upper_vmem = vmem;

	assign cfg_out.data_clk = cfg_in.data_clk;
	always_ff @(posedge cfg_in.data_clk) begin
		//E_l <= cfg_in.data_in;
		//tau_mem <= E_l;
		tau_mem <= cfg_in.data_in;
		g_int <= tau_mem;
		cfg_out.data_in <= g_int;
	end

	// TC
	DW01_add #(.width(fp::WORD_LENGTH)) add_synapses (
		.A(synapse0.output_current),
		.B(synapse1.output_current),
		.CI(1'b0),
		.CO(carry_synadd),
		.SUM(sum_syn_current)
	);
	DW01_add #(.width(fp::WORD_LENGTH)) add_vmem (
		.A(sum_syn_current),
		.B(vmem),
		.CO(carry_add_vmem),
		.CI(carry_synadd),
		.SUM(vmem_synin)
	);

	// TC
	DW01_sub #(.width(fp::WORD_LENGTH)) sub_El_vmem(
		.A(E_l),
		.B(vmem),
		.CI(1'b0),
		.CO(),
		.DIFF(E_l_vmem_diff)
	);
	// tau_mem implicitely converted to TC
	DW02_mult #(.A_width(fp::WORD_LENGTH),.B_width(fp::WORD_LENGTH+1)) mult_decay_mem (
		.A(E_l_vmem_diff),
		.B({1'b0,tau_mem}),
		.PRODUCT(decay_vmem),
		.TC(1'b1)
	);

	DW01_add #(.width(fp::WORD_LENGTH)) add_all (
		.A(vmem_synin),
		.B(decay_vmem_shifted),
		.CO(carry_add_all),
		.CI(carry_add_vmem),
		.SUM(vmem_decay_synin)
	);

	DW01_add #(.width(fp::WORD_LENGTH)) add_upper (
		.A(vmem_decay_synin),
		.B(upper_current),
		.CO(carry_add_final),
		.CI(carry_add_all),
		.SUM(new_vmem)
	);

	// calculate current into lower dendrite compartment
	// These are both membrane potentials of the type A(9,6) 
	DW01_sub #(.width(fp::WORD_LENGTH)) sub_lower (
		.A(vmem),
		.B(lower_vmem),
		.CO(add_lower_carry),
		.CI(1'b0),
		.DIFF(compartment_difference)
	);
	// g_int implicitely converted to TC
	// Here, we are multiplying two values of the type A(9,6) and A(0,16)
	// 16 + 17 = 33 bits (both have a sign bit that is not explicitely given),
	// resulting in type A(10,22) which has 33 bits
	// Therefore, the result has to be shifted by 16 bits.
	DW02_mult #(.A_width(fp::WORD_LENGTH),.B_width(fp::WORD_LENGTH+1)) mult_comp_diff (
		.A(compartment_difference),
		.B({1'b0,g_int}),
		.PRODUCT(current_to_lower),
		.TC(1'b1)
	);
	assign lower_current = (current_to_lower >> right_shift_lower_current) & 16'hffff;

	// store latest calculation result
	always_ff @(posedge clk) begin
		if (reset) begin
			vmem <= 0;
		end
		else begin
			if (decay_vmem != 0 || synapse0.output_current || synapse1.output_current || upper_current != 0) begin
				vmem <= new_vmem;
			end
			//else begin
			//	vmem <= new_vmem;
			//end
		end
	end

endmodule
