// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module ibex_counter #(
  parameter int CounterWidth = 32,
  // When set `counter_val_upd_o` provides an incremented version of the counter value, otherwise
  // the output is hard-wired to 0. This is required to allow Xilinx DSP inference to work
  // correctly. When `ProvideValUpd` is set no DSPs are inferred.
  parameter bit ProvideValUpd = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        counter_inc_i,
  input  logic        counterh_we_i,
  input  logic        counter_we_i,
  input  logic [31:0] counter_val_i,
  output logic [63:0] counter_val_o,
  output logic [63:0] counter_val_upd_o
);

  logic [63:0]             counter;
  logic [CounterWidth-1:0] counter_upd;
  logic [63:0]             counter_load;
  logic                    we;
  logic [CounterWidth-1:0] counter_d;

  // Increment
  assign counter_upd = counter[CounterWidth-1:0] + {{CounterWidth - 1{1'b0}}, 1'b1};

  // Update
  always_comb begin
    // Write
    we = counter_we_i | counterh_we_i;
    counter_load[63:32] = counter[63:32];
    counter_load[31:0]  = counter_val_i;
    if (counterh_we_i) begin
      counter_load[63:32] = counter_val_i;
      counter_load[31:0]  = counter[31:0];
    end

    // Next value logic
    if (we) begin
      counter_d = counter_load[CounterWidth-1:0];
    end else if (counter_inc_i) begin
      counter_d = counter_upd[CounterWidth-1:0];
    end else begin
      counter_d = counter[CounterWidth-1:0];
    end
  end

`ifdef FPGA_XILINX
  // Set DSP pragma for supported xilinx FPGAs
  localparam int DspPragma = CounterWidth < 49 ? "yes" : "no";
  (* use_dsp = DspPragma *) logic [CounterWidth-1:0] counter_q;

  if (CounterWidth < 49) begin : g_dsp_counter
    // DSP output register requires synchronous reset.
    `define COUNTER_FLOP_RST posedge clk_i
  end else begin : g_no_dsp_counter
    `define COUNTER_FLOP_RST posedge clk_i or negedge rst_ni
  end
`else
  logic [CounterWidth-1:0] counter_q;

  `define COUNTER_FLOP_RST posedge clk_i or negedge rst_ni
`endif

  // Counter flop
  always_ff @(`COUNTER_FLOP_RST) begin
    if (!rst_ni) begin
      counter_q <= '0;
    end else begin
      counter_q <= counter_d;
    end
  end

  if (CounterWidth < 64) begin : g_counter_narrow
    logic [63:CounterWidth] unused_counter_load;

    assign counter[CounterWidth-1:0]           = counter_q;
    assign counter[63:CounterWidth]            = '0;

    if (ProvideValUpd) begin : g_counter_val_upd_o
      assign counter_val_upd_o[CounterWidth-1:0] = counter_upd;
    end else begin : g_no_counter_val_upd_o
      assign counter_val_upd_o[CounterWidth-1:0] = '0;
    end
    assign counter_val_upd_o[63:CounterWidth]  = '0;
    assign unused_counter_load                 = counter_load[63:CounterWidth];
  end else begin : g_counter_full
    assign counter           = counter_q;

    if (ProvideValUpd) begin : g_counter_val_upd_o
      assign counter_val_upd_o = counter_upd;
    end else begin : g_no_counter_val_upd_o
      assign counter_val_upd_o = '0;
    end
  end

  assign counter_val_o = counter;

endmodule

// Keep helper defines file-local.
`undef COUNTER_FLOP_RST
