module sync_level_2ff (
    input  logic clk_i,
    input  logic rstn_i,
    input  logic async_i,
    output logic sync_o
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    logic meta_r;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            meta_r <= 1'b0;
            sync_o <= 1'b0;
        end else begin
            meta_r <= async_i;
            sync_o <= meta_r;
        end
    end
endmodule
