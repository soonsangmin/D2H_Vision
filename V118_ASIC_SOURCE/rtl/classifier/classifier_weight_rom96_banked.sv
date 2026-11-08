// ASIC portability replacement of the Quartus M10K altsyncram ROM.
// Inferred synchronous ROM; same 1-cycle read-enable behavior as V6.23.
// WARNING: standard-cell synthesis of ~1 Mbit ROM is likely large.
// Relative HEX paths resolved by running ORFS from a directory with rtl/ symlink.
module classifier_weight_rom96_banked #(
    parameter integer ROM_KIND = 0,
    parameter integer BANK_COUNT = 5
)(
    input wire clk,
    input wire rd_en,
    input wire [12:0] rd_addr,
    output wire [95:0] rd_data
);
    wire [2:0] bank_sel = rd_addr[12:10];
    reg [2:0] bank_sel_q;
    always @(posedge clk) if (rd_en) bank_sel_q <= bank_sel;
    wire [95:0] bank_q [0:5];
    genvar g;
    generate for (g=0; g<6; g=g+1) begin : banks
        if (g < BANK_COUNT) begin : active
            wire en = rd_en && (bank_sel == g);
            if (ROM_KIND == 0) begin : exp_rom
                if (g == 0) begin : exp0
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/exp_weight_bank1024_0.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 1) begin : exp1
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/exp_weight_bank1024_1.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 2) begin : exp2
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/exp_weight_bank1024_2.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 3) begin : exp3
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/exp_weight_bank1024_3.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 4) begin : exp4
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/exp_weight_bank1024_4.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else begin : unused_exp
                    assign bank_q[g] = 96'd0;
                end
            end else begin : proj_rom
                if (g == 0) begin : proj0
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/proj_weight_bank1024_0.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 1) begin : proj1
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/proj_weight_bank1024_1.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 2) begin : proj2
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/proj_weight_bank1024_2.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 3) begin : proj3
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/proj_weight_bank1024_3.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 4) begin : proj4
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/proj_weight_bank1024_4.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
                else if (g == 5) begin : proj5
                    reg [95:0] mem [0:1023];
                    reg [95:0] q;
                    initial $readmemh("rtl/classifier/hex_weights/proj_weight_bank1024_5.hex", mem);
                    always @(posedge clk) if (en) q <= mem[rd_addr[9:0]];
                    assign bank_q[g] = q;
                end
            end
        end else begin : unused
            assign bank_q[g] = 96'd0;
        end
    end endgenerate
    assign rd_data = bank_q[bank_sel_q];
endmodule
