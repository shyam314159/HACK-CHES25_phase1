// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// AES cipher core implementation
//
// This module contains the AES cipher core including, state register, full key and decryption key
// registers as well as key expand module and control unit.
//
//
// Masking
// -------
//
// If the parameter "Masking" is set to one, first-order masking is applied to the entire
// cipher core including key expand module. For details, see Rivain et al., "Provably secure
// higher-order masking of AES" available at https://eprint.iacr.org/2010/441.pdf .
//
//
// Details on the data formats
// ---------------------------
//
// This implementation uses 4-dimensional SystemVerilog arrays to represent the AES state:
//
//   logic [3:0][3:0][7:0] state_q [NumShares];
//
// The fourth dimension (unpacked) corresponds to the different shares. The first element holds the
// (masked) data share whereas the other elements hold the masks (masked implementation only).
// The three packed dimensions correspond to the 128-bit state matrix per share. This
// implementation uses the same encoding as the Advanced Encryption Standard (AES) FIPS Publication
// 197 available at https://www.nist.gov/publications/advanced-encryption-standard-aes (see Section
// 3.4). An input sequence of 16 bytes (128-bit, left most byte is the first one)
//
//   b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14 b15
//
// is mapped to the state matrix as
//
//   [ b0  b4  b8  b12 ]
//   [ b1  b5  b9  b13 ]
//   [ b2  b6  b10 b14 ]
//   [ b3  b7  b11 b15 ] .
//
// This is mapped to three packed dimensions of SystemVerilog array as follows:
// - The first dimension corresponds to the rows. Thus, state_q[0] gives
//   - The first row of the state matrix       [ b0   b4  b8  b12 ], or
//   - A 32-bit packed SystemVerilog array 32h'{ b12, b8, b4, b0  }.
//
// - The second dimension corresponds to the columns. To access complete columns, the state matrix
//   must be transposed first. Thus state_transposed = aes_pkg::aes_transpose(state_q) and then
//   state_transposed[1] gives
//   - The second column of the state matrix   [ b4  b5  b6  b7 ], or
//   - A 32-bit packed SystemVerilog array 32h'{ b7, b6, b5, b4 }.
//
// - The third dimension corresponds to the bytes.
//
// Note that the CSRs are little-endian. The input sequence above is provided to 32-bit DATA_IN_0 -
// DATA_IN_3 registers as
//                   MSB            LSB
// - DATA_IN_0 32h'{ b3 , b2 , b1 , b0  }
// - DATA_IN_1 32h'{ b7 , b6 , b4 , b4  }
// - DATA_IN_2 32h'{ b11, b10, b9 , b8  }
// - DATA_IN_3 32h'{ b15, b14, b13, b12 } .
//
// The input state can thus be obtained by transposing the content of the DATA_IN_0 - DATA_IN_3
// registers.
//
// Similarly, the implementation uses a 3-dimensional array to represent the AES keys:
//
//   logic     [7:0][31:0] key_full_q [NumShares]
//
// The third dimension (unpacked) corresponds to the different shares. The first element holds the
// (masked) key share whereas the other elements hold the masks (masked implementation only).
// The two packed dimensions correspond to the 256-bit key per share. This implementation uses
// the same encoding as the Advanced Encryption Standard (AES) FIPS Publication
// 197 available at https://www.nist.gov/publications/advanced-encryption-standard-aes .
//
// The first packed dimension corresponds to the 8 key words. The second packed dimension
// corresponds to the 32 bits per key word. A key sequence of 32 bytes (256-bit, left most byte is
// the first one)
//
//   b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14 b15 ... ... b28 b29 b30 b31
//
// is mapped to the key words and registers (little-endian) as
//                      MSB            LSB
// - KEY_SHARE0_0 32h'{ b3 , b2 , b1 , b0  }
// - KEY_SHARE0_1 32h'{ b7 , b6 , b4 , b4  }
// - KEY_SHARE0_2 32h'{ b11, b10, b9 , b8  }
// - KEY_SHARE0_3 32h'{ b15, b14, b13, b12 }
// - KEY_SHARE0_4 32h'{  .    .    .    .  }
// - KEY_SHARE0_5 32h'{  .    .    .    .  }
// - KEY_SHARE0_6 32h'{  .    .    .    .  }
// - KEY_SHARE0_7 32h'{ b31, b30, b29, b28 } .

`include "prim_assert.sv"

module aes_cipher_core import aes_pkg::*;
#(
  parameter bit          AES192Enable         = 1,
  parameter bit          CiphOpFwdOnly        = 0,
  parameter bit          SecMasking           = 1,
  parameter sbox_impl_e  SecSBoxImpl          = SBoxImplDom,
  parameter bit          SecAllowForcingMasks = 0,
  parameter bit          SecSkipPRNGReseeding = 0,
  parameter int unsigned EntropyWidth         = edn_pkg::ENDPOINT_BUS_WIDTH,

  localparam int         NumShares            = SecMasking ? 2 : 1, // derived parameter

  parameter masking_lfsr_seed_t RndCnstMaskingLfsrSeed = RndCnstMaskingLfsrSeedDefault,
  parameter masking_lfsr_perm_t RndCnstMaskingLfsrPerm = RndCnstMaskingLfsrPermDefault
) (
  input  logic                        clk_i,
  input  logic                        rst_ni,

  // Input handshake signals
  input  sp2v_e                       in_valid_i,
  output sp2v_e                       in_ready_o,

  // Output handshake signals
  output sp2v_e                       out_valid_o,
  input  sp2v_e                       out_ready_i,

  // Control and sync signals
  input  logic                        cfg_valid_i, // Used for gating assertions only.
  input  ciph_op_e                    op_i,
  input  key_len_e                    key_len_i,
  input  sp2v_e                       crypt_i,
  output sp2v_e                       crypt_o,
  input  sp2v_e                       dec_key_gen_i,
  output sp2v_e                       dec_key_gen_o,
  input  logic                        prng_reseed_i,
  output logic                        prng_reseed_o,
  input  logic                        key_clear_i,
  output logic                        key_clear_o,
  input  logic                        data_out_clear_i, // Re-use the cipher core muxes.
  output logic                        data_out_clear_o,
  input  logic                        alert_fatal_i,
  output logic                        alert_o,

  // Pseudo-random data for register clearing
  input  logic        [3:0][3:0][7:0] prd_clearing_state_i [NumShares],
  input  logic            [7:0][31:0] prd_clearing_key_i [NumShares],

  // Masking PRNG
  input  logic                        force_masks_i, // Useful for SCA only.
  output logic        [3:0][3:0][7:0] data_in_mask_o,
  output logic                        entropy_req_o,
  input  logic                        entropy_ack_i,
  input  logic     [EntropyWidth-1:0] entropy_i,

  // I/O data & initial key
  input  logic        [3:0][3:0][7:0] state_init_i [NumShares],
  input  logic            [7:0][31:0] key_init_i [NumShares],
  output logic        [3:0][3:0][7:0] state_o [NumShares]
);

  // Signals
  logic               [3:0][3:0][7:0] state_d [NumShares];
  logic               [3:0][3:0][7:0] state_q [NumShares];
  sp2v_e                              state_we_ctrl;
  sp2v_e                              state_we;
  logic           [StateSelWidth-1:0] state_sel_raw;
  state_sel_e                         state_sel_ctrl;
  state_sel_e                         state_sel;
  logic                               state_sel_err;

  sp2v_e                              sub_bytes_en;
  sp2v_e                              sub_bytes_out_req;
  sp2v_e                              sub_bytes_out_ack;
  logic                               sub_bytes_err;
  logic               [3:0][3:0][7:0] sub_bytes_out;
  logic               [3:0][3:0][7:0] sb_in_mask;
  logic               [3:0][3:0][7:0] sb_out_mask;
  logic               [3:0][3:0][7:0] shift_rows_in [NumShares];
  logic               [3:0][3:0][7:0] shift_rows_out [NumShares];
  logic               [3:0][3:0][7:0] mix_columns_out [NumShares];
  logic               [3:0][3:0][7:0] add_round_key_in [NumShares];
  logic               [3:0][3:0][7:0] add_round_key_out [NumShares];
  logic           [AddRKSelWidth-1:0] add_rk_sel_raw;
  add_rk_sel_e                        add_rk_sel_ctrl;
  add_rk_sel_e                        add_rk_sel;
  logic                               add_rk_sel_err;

  logic                   [7:0][31:0] key_full_d [NumShares];
  logic                   [7:0][31:0] key_full_q [NumShares];
  sp2v_e                              key_full_we_ctrl;
  sp2v_e                              key_full_we;
  logic         [KeyFullSelWidth-1:0] key_full_sel_raw;
  key_full_sel_e                      key_full_sel_ctrl;
  key_full_sel_e                      key_full_sel;
  logic                               key_full_sel_err;
  logic                   [7:0][31:0] key_dec_d [NumShares];
  logic                   [7:0][31:0] key_dec_q [NumShares];
  sp2v_e                              key_dec_we_ctrl;
  sp2v_e                              key_dec_we;
  logic          [KeyDecSelWidth-1:0] key_dec_sel_raw;
  key_dec_sel_e                       key_dec_sel_ctrl;
  key_dec_sel_e                       key_dec_sel;
  logic                               key_dec_sel_err;
  logic                   [7:0][31:0] key_expand_out [NumShares];
  ciph_op_e                           key_expand_op;
  sp2v_e                              key_expand_en;
  logic                               key_expand_prd_we;
  sp2v_e                              key_expand_out_req;
  sp2v_e                              key_expand_out_ack;
  logic                               key_expand_err;
  logic                               key_expand_clear;
  logic                         [3:0] key_expand_round;
  logic        [KeyWordsSelWidth-1:0] key_words_sel_raw;
  key_words_sel_e                     key_words_sel_ctrl;
  key_words_sel_e                     key_words_sel;
  logic                               key_words_sel_err;
  logic                   [3:0][31:0] key_words [NumShares];
  logic               [3:0][3:0][7:0] key_bytes [NumShares];
  logic               [3:0][3:0][7:0] key_mix_columns_out [NumShares];
  logic               [3:0][3:0][7:0] round_key [NumShares];
  logic        [RoundKeySelWidth-1:0] round_key_sel_raw;
  round_key_sel_e                     round_key_sel_ctrl;
  round_key_sel_e                     round_key_sel;
  logic                               round_key_sel_err;

  logic                               cfg_valid;
  logic                               mux_sel_err;
  logic                               sp_enc_err_d, sp_enc_err_q;
  logic                               op_err;

  // Pseudo-random data for masking purposes
  logic         [WidthPRDMasking-1:0] prd_masking;
  logic  [3:0][3:0][WidthPRDSBox-1:0] prd_sub_bytes_d;
  logic  [3:0][3:0][WidthPRDSBox-1:0] prd_sub_bytes_q;
  logic             [WidthPRDKey-1:0] prd_key_expand;
  logic                               prd_masking_upd;
  logic                               prd_masking_rsd_req;
  logic                               prd_masking_rsd_ack;

  logic               [3:0][3:0][7:0] data_in_mask;

  // op_i is one-hot encoded. Check the provided value and trigger an alert upon detecing invalid
  // encodings.
  assign op_err    = ~(op_i == CIPH_FWD || op_i == CIPH_INV);
  assign cfg_valid = cfg_valid_i & ~op_err;

  //////////
  // Data //
  //////////

  // SEC_CM: DATA_REG.SEC_WIPE
  // State registers
  always_comb begin : state_mux
    unique case (state_sel)
      STATE_INIT:  state_d = state_init_i;
      STATE_ROUND: state_d = add_round_key_out;
      STATE_CLEAR: state_d = add_round_key_out;
      default:     state_d = prd_clearing_state_i;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : state_reg
    if (!rst_ni) begin
      state_q <= '{default: '0};
    end else if (state_we == SP2V_HIGH) begin
      state_q <= state_d;
    end
  end

  // Masking
  if (!SecMasking) begin : gen_no_masks
    // The masks are ignored anyway, they can be 0.
    assign sb_in_mask  = '0;
    assign prd_masking = '0;

    // Tie-off unused signals.
    logic unused_entropy_ack;
    logic [EntropyWidth-1:0] unused_entropy;
    assign unused_entropy_ack = entropy_ack_i;
    assign unused_entropy     = entropy_i;
    assign entropy_req_o      = 1'b0;

    logic unused_force_masks;
    logic unused_prd_masking_upd;
    logic unused_prd_masking_rsd_req;
    assign unused_force_masks         = force_masks_i;
    assign unused_prd_masking_upd     = prd_masking_upd;
    assign unused_prd_masking_rsd_req = prd_masking_rsd_req;
    assign prd_masking_rsd_ack        = 1'b0;

    logic [3:0][3:0][7:0] unused_sb_out_mask;
    assign unused_sb_out_mask = sb_out_mask;

  end else begin : gen_masks
    // The input mask is the mask share of the state.
    assign sb_in_mask  = state_q[1];

    // The masking PRNG generates:
    // - the pseudo-random data (PRD) required by SubBytes,
    // - the PRD required by the key expand module (has 4 S-Boxes internally).
    aes_prng_masking #(
      .Width                ( WidthPRDMasking        ),
      .EntropyWidth         ( EntropyWidth           ),
      .SecAllowForcingMasks ( SecAllowForcingMasks   ),
      .SecSkipPRNGReseeding ( SecSkipPRNGReseeding   ),
      .RndCnstLfsrSeed      ( RndCnstMaskingLfsrSeed ),
      .RndCnstLfsrPerm      ( RndCnstMaskingLfsrPerm )
    ) u_aes_prng_masking (
      .clk_i         ( clk_i               ),
      .rst_ni        ( rst_ni              ),
      .force_masks_i ( force_masks_i       ),
      .data_update_i ( prd_masking_upd     ),
      .data_o        ( prd_masking         ),
      .reseed_req_i  ( prd_masking_rsd_req ),
      .reseed_ack_o  ( prd_masking_rsd_ack ),
      .entropy_req_o ( entropy_req_o       ),
      .entropy_ack_i ( entropy_ack_i       ),
      .entropy_i     ( entropy_i           )
    );
  end

  // Extract randomness for key expand module and SubBytes.
  //
  // The masking PRNG output has the following shape:
  // prd_masking = { prd_key_expand, prd_sub_bytes_d }
  assign prd_key_expand  = prd_masking[WidthPRDMasking-1 -: WidthPRDKey];
  assign prd_sub_bytes_d = prd_masking[WidthPRDData-1 -: WidthPRDData];

  // PRD buffering
  if (!SecMasking) begin : gen_no_prd_buffer
    // The masks are ignored anyway.
    assign prd_sub_bytes_q = prd_sub_bytes_d;

  end else begin : gen_prd_buffer
    // PRD buffer stage to:
    // 1. Make sure the S-Boxes get always presented new data/mask inputs together with fresh PRD
    //    for remasking.
    // 2. Prevent glitches originating from inside the masking PRNG from propagating into the
    //    masked S-Boxes.
    always_ff @(posedge clk_i or negedge rst_ni) begin : prd_sub_bytes_reg
      if (!rst_ni) begin
        prd_sub_bytes_q <= '0;
      end else if (state_we == SP2V_HIGH) begin
        prd_sub_bytes_q <= prd_sub_bytes_d;
      end
    end
  end

  // Convert the 3-dimensional prd_sub_bytes_q array to a 1-dimensional packed array for the
  // aes_prd_get_lsbs() function used below.
  logic [WidthPRDData-1:0] prd_sub_bytes;
  assign prd_sub_bytes = prd_sub_bytes_q;

  // Extract randomness for masking the input data.
  //
  // The masking PRNG is used for generating both the PRD for the S-Boxes/SubBytes operation as
  // well as for the input data masks. When using any of the masked Canright S-Box implementations,
  // it is important that the SubBytes input masks (generated by the PRNG in Round X-1) and the
  // SubBytes output masks (generated by the PRNG in Round X) are independent. This can be achieved
  // by using e.g. an unrolled Bivium stream cipher primitive inside the PRNG. Since the input data
  // masks become the SubBytes input masks in the first round, we select the same 8 bit lanes for
  // the input data masks which are also used to form the SubBytes output mask for the masked
  // Canright S-Box implementations, i.e., the 8 LSBs of the per S-Box PRD. In particular, we have:
  //
  // prd_masking = { prd_key_expand, ... , sb_prd[4], sb_out_mask[4], sb_prd[0], sb_out_mask[0] }
  //
  // Where sb_out_mask[x] contains the SubBytes output mask for byte x (when using a masked
  // Canright S-Box implementation) and sb_prd[x] contains additional PRD consumed by SubBytes for
  // byte x.
  //
  // When using a masked S-Box implementation other than Canright, we still select the 8 LSBs of
  // the per-S-Box PRD to form the input data mask of the corresponding byte. We do this to
  // distribute the input data masks over all output bits the masking PRNG. We do the extraction on
  // a row basis.
  localparam int unsigned WidthPRDRow = 4*WidthPRDSBox;
  for (genvar i = 0; i < 4; i++) begin : gen_in_mask
    assign data_in_mask[i] = aes_prd_get_lsbs(prd_sub_bytes[i * WidthPRDRow +: WidthPRDRow]);
  end

  // Rotate the data input masks by 64 bits to ensure the data input masks are independent
  // from the PRD fed to the S-Boxes/SubBytes operation.
  assign data_in_mask_o = {data_in_mask[1], data_in_mask[0], data_in_mask[3], data_in_mask[2]};

  // Cipher data path
  aes_sub_bytes #(
    .SecSBoxImpl ( SecSBoxImpl )
  ) u_aes_sub_bytes (
    .clk_i     ( clk_i             ),
    .rst_ni    ( rst_ni            ),
    .en_i      ( sub_bytes_en      ),
    .out_req_o ( sub_bytes_out_req ),
    .out_ack_i ( sub_bytes_out_ack ),
    .op_i      ( op_i              ),
    .data_i    ( state_q[0]        ),
    .mask_i    ( sb_in_mask        ),
    .prd_i     ( prd_sub_bytes_q   ),
    .data_o    ( sub_bytes_out     ),
    .mask_o    ( sb_out_mask       ),
    .err_o     ( sub_bytes_err     )
  );

  for (genvar s = 0; s < NumShares; s++) begin : gen_shares_shift_mix
    if (s == 0) begin : gen_shift_in_data
      // The (masked) data share
      assign shift_rows_in[s] = sub_bytes_out;
    end else begin : gen_shift_in_mask
      // The mask share
      assign shift_rows_in[s] = sb_out_mask;
    end

    aes_shift_rows u_aes_shift_rows (
      .op_i   ( op_i              ),
      .data_i ( shift_rows_in[s]  ),
      .data_o ( shift_rows_out[s] )
    );

    aes_mix_columns u_aes_mix_columns (
      .op_i   ( op_i               ),
      .data_i ( shift_rows_out[s]  ),
      .data_o ( mix_columns_out[s] )
    );
  end

  always_comb begin : add_round_key_in_mux
    unique case (add_rk_sel)
      ADD_RK_INIT:  add_round_key_in = state_q;
      ADD_RK_ROUND: add_round_key_in = mix_columns_out;
      ADD_RK_FINAL: add_round_key_in = shift_rows_out;
      default:      add_round_key_in = state_q;
    endcase
  end

  for (genvar s = 0; s < NumShares; s++) begin : gen_shares_add_round_key
    assign add_round_key_out[s] = add_round_key_in[s] ^ round_key[s];
  end

  /////////
  // Key //
  /////////

  // SEC_CM: KEY.SEC_WIPE
  // Full Key registers
  always_comb begin : key_full_mux
    unique case (key_full_sel)
      KEY_FULL_ENC_INIT: key_full_d = key_init_i;
      KEY_FULL_DEC_INIT: key_full_d = !CiphOpFwdOnly ? key_dec_q : prd_clearing_key_i;
      KEY_FULL_ROUND:    key_full_d = key_expand_out;
      KEY_FULL_CLEAR:    key_full_d = key_expand_out;
      default:           key_full_d = prd_clearing_key_i;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : key_full_reg
    if (!rst_ni) begin
      key_full_q <= '{default: '0};
    end else if (key_full_we == SP2V_HIGH) begin
      key_full_q <= key_full_d;
    end
  end

  if (!CiphOpFwdOnly) begin : gen_key_dec
    // SEC_CM: KEY.SEC_WIPE
    // Decryption Key registers
    always_comb begin : key_dec_mux
      unique case (key_dec_sel)
        KEY_DEC_EXPAND: key_dec_d = key_expand_out;
        KEY_DEC_CLEAR:  key_dec_d = key_expand_out;
        default:        key_dec_d = prd_clearing_key_i;
      endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : key_dec_reg
      if (!rst_ni) begin
        key_dec_q <= '{default: '0};
      end else if (key_dec_we == SP2V_HIGH) begin
        key_dec_q <= key_dec_d;
      end
    end
  end else begin : gen_no_key_dec
    // No Decryption Key registers
    assign key_dec_q = '{default: '0};
    assign key_dec_d = key_dec_q;

    // Tie-off unused signals.
    logic unused_key_dec;
    always_comb begin
      unused_key_dec = ^{key_dec_sel, key_dec_we};
      for (int s = 0; s < NumShares; s++) begin
        unused_key_dec ^= ^{key_dec_d[s]};
      end
    end
  end

  // Make sure that whenever the data/mask inputs of the S-Boxes update, the internally buffered
  // PRD is updated in sync.
  assign key_expand_prd_we = (key_full_we == SP2V_HIGH) ? 1'b1 : 1'b0;

  // Key expand data path
  aes_key_expand #(
    .AES192Enable ( AES192Enable ),
    .SecMasking   ( SecMasking   ),
    .SecSBoxImpl  ( SecSBoxImpl  )
  ) u_aes_key_expand (
    .clk_i       ( clk_i              ),
    .rst_ni      ( rst_ni             ),
    .cfg_valid_i ( cfg_valid          ),
    .op_i        ( key_expand_op      ),
    .en_i        ( key_expand_en      ),
    .prd_we_i    ( key_expand_prd_we  ),
    .out_req_o   ( key_expand_out_req ),
    .out_ack_i   ( key_expand_out_ack ),
    .clear_i     ( key_expand_clear   ),
    .round_i     ( key_expand_round   ),
    .key_len_i   ( key_len_i          ),
    .key_i       ( key_full_q         ),
    .key_o       ( key_expand_out     ),
    .prd_i       ( prd_key_expand     ),
    .err_o       ( key_expand_err     )
  );

  for (genvar s = 0; s < NumShares; s++) begin : gen_shares_round_key
    always_comb begin : key_words_mux
      unique case (key_words_sel)
        KEY_WORDS_0123: key_words[s] = key_full_q[s][3:0];
        KEY_WORDS_2345: key_words[s] = AES192Enable ? key_full_q[s][5:2] : '0;
        KEY_WORDS_4567: key_words[s] = key_full_q[s][7:4];
        KEY_WORDS_ZERO: key_words[s] = '0;
        default:        key_words[s] = '0;
      endcase
    end

    // Convert words to bytes (every key word contains one column).
    assign key_bytes[s] = aes_transpose(key_words[s]);

    aes_mix_columns u_aes_key_mix_columns (
      .op_i   ( CIPH_INV               ),
      .data_i ( key_bytes[s]           ),
      .data_o ( key_mix_columns_out[s] )
    );
  end

  always_comb begin : round_key_mux
    unique case (round_key_sel)
      ROUND_KEY_DIRECT: round_key = key_bytes;
      ROUND_KEY_MIXED:  round_key = !CiphOpFwdOnly ? key_mix_columns_out : key_bytes;
      default:          round_key = key_bytes;
    endcase
  end

  if (CiphOpFwdOnly) begin : gen_unused_key_mix_columns_out
    // Tie-off unused signals.
    logic unused_key_mix_columns_out;
    always_comb begin
      unused_key_mix_columns_out = 1'b0;
      for (int s = 0; s < NumShares; s++) begin
        unused_key_mix_columns_out ^= ^{key_mix_columns_out[s]};
      end
    end
  end

  /////////////
  // Control //
  /////////////

  // Control
  aes_cipher_control #(
    .CiphOpFwdOnly ( CiphOpFwdOnly ),
    .SecMasking    ( SecMasking    ),
    .SecSBoxImpl   ( SecSBoxImpl   )
  ) u_aes_cipher_control (
    .clk_i                ( clk_i               ),
    .rst_ni               ( rst_ni              ),

    .in_valid_i           ( in_valid_i          ),
    .in_ready_o           ( in_ready_o          ),

    .out_valid_o          ( out_valid_o         ),
    .out_ready_i          ( out_ready_i         ),

    .cfg_valid_i          ( cfg_valid           ),
    .op_i                 ( op_i                ),
    .key_len_i            ( key_len_i           ),
    .crypt_i              ( crypt_i             ),
    .crypt_o              ( crypt_o             ),
    .dec_key_gen_i        ( dec_key_gen_i       ),
    .dec_key_gen_o        ( dec_key_gen_o       ),
    .prng_reseed_i        ( prng_reseed_i       ),
    .prng_reseed_o        ( prng_reseed_o       ),
    .key_clear_i          ( key_clear_i         ),
    .key_clear_o          ( key_clear_o         ),
    .data_out_clear_i     ( data_out_clear_i    ),
    .data_out_clear_o     ( data_out_clear_o    ),
    .mux_sel_err_i        ( mux_sel_err         ),
    .sp_enc_err_i         ( sp_enc_err_q        ),
    .op_err_i             ( op_err              ),
    .alert_fatal_i        ( alert_fatal_i       ),
    .alert_o              ( alert_o             ),

    .prng_update_o        ( prd_masking_upd     ),
    .prng_reseed_req_o    ( prd_masking_rsd_req ),
    .prng_reseed_ack_i    ( prd_masking_rsd_ack ),

    .state_sel_o          ( state_sel_ctrl      ),
    .state_we_o           ( state_we_ctrl       ),
    .sub_bytes_en_o       ( sub_bytes_en        ),
    .sub_bytes_out_req_i  ( sub_bytes_out_req   ),
    .sub_bytes_out_ack_o  ( sub_bytes_out_ack   ),
    .add_rk_sel_o         ( add_rk_sel_ctrl     ),

    .key_expand_op_o      ( key_expand_op       ),
    .key_full_sel_o       ( key_full_sel_ctrl   ),
    .key_full_we_o        ( key_full_we_ctrl    ),
    .key_dec_sel_o        ( key_dec_sel_ctrl    ),
    .key_dec_we_o         ( key_dec_we_ctrl     ),
    .key_expand_en_o      ( key_expand_en       ),
    .key_expand_out_req_i ( key_expand_out_req  ),
    .key_expand_out_ack_o ( key_expand_out_ack  ),
    .key_expand_clear_o   ( key_expand_clear    ),
    .key_expand_round_o   ( key_expand_round    ),
    .key_words_sel_o      ( key_words_sel_ctrl  ),
    .round_key_sel_o      ( round_key_sel_ctrl  )
  );

  ///////////////
  // Selectors //
  ///////////////

  // We use sparse encodings for these mux selector signals and must ensure that:
  // 1. The synthesis tool doesn't optimize away the sparse encoding.
  // 2. The selector signal is always valid. More precisely, an alert or SVA is triggered if a
  //    selector signal takes on an invalid value.
  // 3. The alert signal remains asserted until reset even if the selector signal becomes valid
  //    again. This is achieved by driving the control FSM into the terminal error state whenever
  //    any mux selector signal becomes invalid.
  //
  // If any mux selector signal becomes invalid, the cipher core further immediately de-asserts
  // the out_valid_o signal to prevent any data from being released.

  aes_sel_buf_chk #(
    .Num      ( StateSelNum   ),
    .Width    ( StateSelWidth ),
    .EnSecBuf ( 1'b1          )
  ) u_aes_state_sel_buf_chk (
    .clk_i  ( clk_i          ),
    .rst_ni ( rst_ni         ),
    .sel_i  ( state_sel_ctrl ),
    .sel_o  ( state_sel_raw  ),
    .err_o  ( state_sel_err  )
  );
  assign state_sel = state_sel_e'(state_sel_raw);

  aes_sel_buf_chk #(
    .Num      ( AddRKSelNum   ),
    .Width    ( AddRKSelWidth ),
    .EnSecBuf ( 1'b1          )
  ) u_aes_add_rk_sel_buf_chk (
    .clk_i  ( clk_i           ),
    .rst_ni ( rst_ni          ),
    .sel_i  ( add_rk_sel_ctrl ),
    .sel_o  ( add_rk_sel_raw  ),
    .err_o  ( add_rk_sel_err  )
  );
  assign add_rk_sel = add_rk_sel_e'(add_rk_sel_raw);

  aes_sel_buf_chk #(
    .Num      ( KeyFullSelNum   ),
    .Width    ( KeyFullSelWidth ),
    .EnSecBuf ( 1'b1            )
  ) u_aes_key_full_sel_buf_chk (
    .clk_i  ( clk_i             ),
    .rst_ni ( rst_ni            ),
    .sel_i  ( key_full_sel_ctrl ),
    .sel_o  ( key_full_sel_raw  ),
    .err_o  ( key_full_sel_err  )
  );
  assign key_full_sel = key_full_sel_e'(key_full_sel_raw);

  aes_sel_buf_chk #(
    .Num      ( KeyDecSelNum   ),
    .Width    ( KeyDecSelWidth ),
    .EnSecBuf ( 1'b1           )
  ) u_aes_key_dec_sel_buf_chk (
    .clk_i  ( clk_i            ),
    .rst_ni ( rst_ni           ),
    .sel_i  ( key_dec_sel_ctrl ),
    .sel_o  ( key_dec_sel_raw  ),
    .err_o  ( key_dec_sel_err  )
  );
  assign key_dec_sel = key_dec_sel_e'(key_dec_sel_raw);

  aes_sel_buf_chk #(
    .Num      ( KeyWordsSelNum   ),
    .Width    ( KeyWordsSelWidth ),
    .EnSecBuf ( 1'b1             )
  ) u_aes_key_words_sel_buf_chk (
    .clk_i  ( clk_i              ),
    .rst_ni ( rst_ni             ),
    .sel_i  ( key_words_sel_ctrl ),
    .sel_o  ( key_words_sel_raw  ),
    .err_o  ( key_words_sel_err  )
  );
  assign key_words_sel = key_words_sel_e'(key_words_sel_raw);

  aes_sel_buf_chk #(
    .Num      ( RoundKeySelNum   ),
    .Width    ( RoundKeySelWidth ),
    .EnSecBuf ( 1'b1             )
  ) u_aes_round_key_sel_buf_chk (
    .clk_i  ( clk_i              ),
    .rst_ni ( rst_ni             ),
    .sel_i  ( round_key_sel_ctrl ),
    .sel_o  ( round_key_sel_raw  ),
    .err_o  ( round_key_sel_err  )
  );
  assign round_key_sel = round_key_sel_e'(round_key_sel_raw);

  // Signal invalid mux selector signals to control FSM which will lock up and trigger an alert.
  assign mux_sel_err = state_sel_err | add_rk_sel_err | key_full_sel_err |
      key_dec_sel_err | key_words_sel_err | round_key_sel_err;

  //////////////////////////////
  // Sparsely Encoded Signals //
  //////////////////////////////

  // We use sparse encodings for various critical signals and must ensure that:
  // 1. The synthesis tool doesn't optimize away the sparse encoding.
  // 2. The sparsely encoded signal is always valid. More precisely, an alert or SVA is triggered
  //    if a sparse signal takes on an invalid value.
  // 3. The alert signal remains asserted until reset even if the sparse signal becomes valid again
  //    This is achieved by driving the control FSM into the terminal error state whenever any
  //    sparsely encoded signal becomes invalid.
  //
  // If any sparsely encoded signal becomes invalid, the cipher core further immediately de-asserts
  // the out_valid_o signal to prevent any data from being released.

  // We use vectors of sparsely encoded signals to reduce code duplication.
  localparam int unsigned NumSp2VSig = 3;
  sp2v_e [NumSp2VSig-1:0]                sp2v_sig;
  sp2v_e [NumSp2VSig-1:0]                sp2v_sig_chk;
  logic  [NumSp2VSig-1:0][Sp2VWidth-1:0] sp2v_sig_chk_raw;
  logic  [NumSp2VSig-1:0]                sp2v_sig_err;

  assign sp2v_sig[0] = state_we_ctrl;
  assign sp2v_sig[1] = key_full_we_ctrl;
  assign sp2v_sig[2] = key_dec_we_ctrl;

  // All signals inside sp2v_sig are eventually converted to single-rail signals.
  localparam bit [NumSp2VSig-1:0] Sp2VEnSecBuf = {NumSp2VSig{1'b1}};

  // Individually check sparsely encoded signals.
  for (genvar i = 0; i < NumSp2VSig; i++) begin : gen_sel_buf_chk
    aes_sel_buf_chk #(
      .Num      ( Sp2VNum         ),
      .Width    ( Sp2VWidth       ),
      .EnSecBuf ( Sp2VEnSecBuf[i] )
    ) u_aes_sp2v_sig_buf_chk_i (
      .clk_i  ( clk_i               ),
      .rst_ni ( rst_ni              ),
      .sel_i  ( sp2v_sig[i]         ),
      .sel_o  ( sp2v_sig_chk_raw[i] ),
      .err_o  ( sp2v_sig_err[i]     )
    );
    assign sp2v_sig_chk[i] = sp2v_e'(sp2v_sig_chk_raw[i]);
  end

  assign state_we    = sp2v_sig_chk[0];
  assign key_full_we = sp2v_sig_chk[1];
  assign key_dec_we  = sp2v_sig_chk[2];

  // Collect encoding errors.
  // We instantiate the checker modules as close as possible to where the sparsely encoded signals
  // are used. Here, we collect also encoding errors detected in other places of the cipher core.
  assign sp_enc_err_d = |sp2v_sig_err | sub_bytes_err | key_expand_err;

  // We need to register the collected error signal to avoid circular loops in the cipher core
  // controller related to out_valid_o and detecting errors in state_we_o and sub_bytes_out_ack.
  always_ff @(posedge clk_i or negedge rst_ni) begin : reg_sp_enc_err
    if (!rst_ni) begin
      sp_enc_err_q <= 1'b0;
    end else if (sp_enc_err_d) begin
      sp_enc_err_q <= 1'b1;
    end
  end

  /////////////
  // Outputs //
  /////////////

  // The output of the last round is not stored into the state register but forwarded directly.
  assign state_o = add_round_key_out;

  ////////////////
  // Assertions //
  ////////////////

// Typically assertions already contain this macro, which ensures that assertions are only compiled
// in simulation and FPV. However, we wrap the entire assertion section with INC_ASSERT so that the
// helper logic below is not synthesized either, since that could cause issues in DC.
`ifdef INC_ASSERT
  //VCS coverage off
  // pragma coverage off

  // Create a lint error to reduce the risk of accidentally disabling the masking.
  `ASSERT_STATIC_LINT_ERROR(AesSecMaskingNonDefault, SecMasking == 1)

  // Cipher core masking requires a masked SBox and vice versa.
  `ASSERT_INIT(AesMaskedCoreAndSBox,
      (SecMasking &&
      (SecSBoxImpl == SBoxImplCanrightMasked ||
       SecSBoxImpl == SBoxImplCanrightMaskedNoreuse ||
       SecSBoxImpl == SBoxImplDom)) ||
      (!SecMasking &&
      (SecSBoxImpl == SBoxImplLut ||
       SecSBoxImpl == SBoxImplCanright)))

  // Signals used for assertions only.
  logic prd_clearing_equals_output, unused_prd_clearing_equals_output;
  assign prd_clearing_equals_output = (prd_clearing_state_i == add_round_key_out);
  assign unused_prd_clearing_equals_output = prd_clearing_equals_output;

  // Ensure that the state register gets cleared with pseudo-random data at the end of the last
  // round. The following two scenarios are unlikely but not illegal:
  // 1. The newly loaded initial state matches the previous output (the round counter is only
  //    cleared upon loading the new initial state).
  // 2. The previous pseudo-random data is equal to the previous output.
  // Otherwise, we must see an alert e.g. because the state multiplexer got glitched.
  `ASSERT(AesSecCmDataRegKeySca, (state_we == SP2V_HIGH) &&
      ((key_len_i == AES_128 && u_aes_cipher_control.rnd_ctr == 4'd10) ||
       (key_len_i == AES_192 && u_aes_cipher_control.rnd_ctr == 4'd12) ||
       (key_len_i == AES_256 && u_aes_cipher_control.rnd_ctr == 4'd14)) |=>
      (state_q != $past(add_round_key_out)) ||
      (state_q == $past(state_init_i)) ||
      $past(prd_clearing_equals_output) || alert_o)

  if (SecMasking) begin : gen_sec_cm_key_masking_svas
      // The number of clock cycles a regular AES round takes - only used for assertions.
      localparam int unsigned NumCyclesPerRound = (SecSBoxImpl == SBoxImplDom) ? 5 : 1;
      logic unused_param;
      assign unused_param = (NumCyclesPerRound == 1);
      // Ensure that SubBytes gets fresh PRD input for every evaluation unless mask forcing is
      // enabled. We effectively check that the PRNG has been updated at least once within the
      // last NumCyclesPerRound cycles. This also holds for the very first round, as the PRNG
      // is always updated in the last cycle of the IDLE state and/or the first cycle of the
      // INIT state.
      `ASSERT(AesSecCmKeyMaskingPrdSubBytes,
          sub_bytes_en == SP2V_HIGH && ($past(sub_bytes_en) == SP2V_LOW ||
              ($past(sub_bytes_out_req) == SP2V_HIGH &&
               $past(sub_bytes_out_ack) == SP2V_HIGH)) |=>
          $past(prd_sub_bytes_q) != $past(prd_sub_bytes_q, NumCyclesPerRound + 1) ||
          SecAllowForcingMasks && force_masks_i)

      // Ensure that the PRNG has been updated between masking the input and starting the first
      // SubBytes evaluation/KeyExpand operation unless mask forcing is enabled. For AES-256,
      // we just spend 1 cycle in the INIT state and KeyExpand isn't evaluating its S-Boxes,
      // i.e., no fresh randomness is required. For the other key lengths, KeyExpand evaluates
      // its S-Boxes which takes NumCyclesPerRound cycles. When computing the start key for
      // decryption, the input isn't loaded and the PRNG is thus not advanced.
      `ASSERT(AesSecCmKeyMaskingInitialPrngUpdateSubBytes,
          sub_bytes_en == SP2V_HIGH && $past(sub_bytes_en) == SP2V_LOW |=>
          (key_len_i == AES_256 &&
              $past(prd_masking) != $past(prd_masking, 3)) ||
          ((key_len_i == AES_128 || key_len_i == AES_192) &&
              $past(prd_masking) != $past(prd_masking, NumCyclesPerRound + 2)) ||
          (SecAllowForcingMasks && force_masks_i))
      `ASSERT(AesSecCmKeyMaskingInitialPrngUpdateKeyExpand,
          key_expand_en == SP2V_HIGH && $past(key_expand_en) == SP2V_LOW |=>
          (key_len_i == AES_256 &&
              $past(prd_masking) != $past(prd_masking, 3)) ||
          ((key_len_i == AES_128 || key_len_i == AES_192) &&
              $past(prd_masking) != $past(prd_masking, 2)) ||
          (SecAllowForcingMasks && force_masks_i) || dec_key_gen_o == SP2V_HIGH)

      // Ensure none of the state shares keeps being constant during encryption/decryption
      // unless mask forcing is enabled. Even though unlikely it's not impossible that one
      // share remains constant throughout one round. The SVAs thus only fire if a share
      // remains constant across two rounds.
      for (genvar s = 0; s < NumShares; s++) begin : gen_sec_cm_key_masking_share_svas
        `ASSERT(AesSecCmKeyMaskingStateShare, state_we == SP2V_HIGH &&
            (crypt_i == SP2V_HIGH || crypt_o == SP2V_HIGH) |=>
            state_q[s] != $past(state_q[s], NumCyclesPerRound) ||
            $past(state_q[s], NumCyclesPerRound) != $past(state_q[s], 2*NumCyclesPerRound) ||
            (SecAllowForcingMasks && force_masks_i) || dec_key_gen_o == SP2V_HIGH)
        `ASSERT(AesSecCmKeyMaskingOutputShare,
            (out_valid_o == SP2V_HIGH && $past(out_valid_o) == SP2V_LOW) &&
            (crypt_o == SP2V_HIGH) |=>
            $past(state_o[s]) != $past(state_q[s], NumCyclesPerRound) ||
            $past(state_q[s], NumCyclesPerRound) != $past(state_q[s], 2*NumCyclesPerRound) ||
            (SecAllowForcingMasks && force_masks_i) || dec_key_gen_o == SP2V_HIGH)
      end
  end

  // Make sure the output of the masking PRNG is properly extracted without creating overlaps
  // in the data input masks, or between the PRD fed to the key expand module and SubBytes.
  if (WidthPRDSBox > 8) begin : gen_prd_extract_assert
    // For one row of the state matrix, extract the WidthPRDSBox-8 MSBs of the per-S-Box PRD from
    // the PRNG output.
    function automatic logic [3:0][(WidthPRDSBox-8)-1:0] aes_prd_get_msbs(
      logic [(4*WidthPRDSBox)-1:0] in
    );
      logic [3:0][(WidthPRDSBox-8)-1:0] prd_msbs;
      for (int i = 0; i < 4; i++) begin
        prd_msbs[i] = in[(i*WidthPRDSBox) + 8 +: (WidthPRDSBox-8)];
      end
      return prd_msbs;
    endfunction

    // For one row of the state matrix, undo the extraction of LSBs and MSBs of the per-S-Box PRD
    // from the PRNG output. This can be used to verify proper extraction (no overlap of output
    // masks and PRD for masked Canright S-Box implementations, no unused PRNG output).
    function automatic logic [4*WidthPRDSBox-1:0] aes_prd_concat_bits(
      logic [3:0]                 [7:0] prd_lsbs,
      logic [3:0][(WidthPRDSBox-8)-1:0] prd_msbs
    );
      logic [(4*WidthPRDSBox)-1:0] prd;
      for (int i = 0; i < 4; i++) begin
        prd[(i*WidthPRDSBox) +: WidthPRDSBox] = {prd_msbs[i], prd_lsbs[i]};
      end
      return prd;
    endfunction

    // Check for correct extraction of masking PRNG output without overlaps.
    logic            [WidthPRDMasking-1:0] unused_prd_masking;
    logic [3:0][3:0][(WidthPRDSBox-8)-1:0] unused_prd_msbs;
    for (genvar i = 0; i < 4; i++) begin : gen_unused_prd_msbs
      assign unused_prd_msbs[i] = aes_prd_get_msbs(prd_masking[i * WidthPRDRow +: WidthPRDRow]);
    end
    for (genvar i = 0; i < 4; i++) begin : gen_unused_prd_masking
      assign unused_prd_masking[i * WidthPRDRow +: WidthPRDRow] =
          aes_prd_concat_bits(data_in_mask[i], unused_prd_msbs[i]);
    end
    assign unused_prd_masking[WidthPRDMasking-1 -: WidthPRDKey] = prd_key_expand;
    `ASSERT(AesMskgPrdExtraction, prd_masking == unused_prd_masking)
  end
  //VCS coverage on
  // pragma coverage on
`endif

endmodule
