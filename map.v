module $_ALDFF_PP_ (AD, C, D, L, Q);
    input AD;  // async load input
    input C;   // clock
    input D;   // normal D input
    input L;   // async load / preset
    output Q;  // output

    // Internal wires
    wire mux_out;
    wire nL, AD_and_L, D_and_nL;

    // Build a 2:1 mux using AND, OR, NOT
    not u_not_L (.A(L), .Y(nL));              // nL = !L
    and u_and1 (.A(D), .B(nL), .Y(D_and_nL)); // D & !L
    and u_and2 (.A(AD), .B(L), .Y(AD_and_L)); // AD & L
    or  u_or1  (.A(D_and_nL), .B(AD_and_L), .Y(mux_out)); // mux_out = (D & !L) | (AD & L)

    // Connect to reset-only dff
    dff u_dff (
        .D(mux_out),
        .CK(C),
        .RN(1'b1),   // inactive reset
        .SN(1'b1),   // inactive set
        .Q(Q)
    );

endmodule

module $_ALDFFE_PPP_ (AD, C, D, E, L, Q);
    input AD;  // async load input
    input C;   // clock
    input D;   // normal D input
    input E;   // enable
    input L;   // async load / preset
    output Q;  // output

    // Internal wires
    wire nL, nE;
    wire D_and_E, Q_and_nE;
    wire D_mux, AD_and_L, Dmux_and_nL;
    wire mux_out;

    // Invert controls
    not u_notL (.A(L), .Y(nL));      // nL = !L
    not u_notE (.A(E), .Y(nE));      // nE = !E

    // Enable mux: Dmux = (E ? D : Q)
    and u_and1 (.A(D), .B(E),   .Y(D_and_E));   // D & E
    and u_and2 (.A(Q), .B(nE),  .Y(Q_and_nE));  // Q & !E
    or  u_or1  (.A(D_and_E), .B(Q_and_nE), .Y(D_mux));

    // Load mux: mux_out = (L ? AD : D_mux)
    and u_and3 (.A(D_mux), .B(nL), .Y(Dmux_and_nL)); // Dmux & !L
    and u_and4 (.A(AD),    .B(L),  .Y(AD_and_L));    // AD & L
    or  u_or2  (.A(Dmux_and_nL), .B(AD_and_L), .Y(mux_out));

    // Final synchronous DFF (no async behavior in primitive)
    dff u_dff (
        .D(mux_out),
        .CK(C),
        .RN(1'b1),  // inactive reset
        .SN(1'b1),  // inactive set
        .Q(Q)
    );
    
endmodule


// Approach 2: correct asynchronous implementation (but bad netlist relationship)
// module $_ALDFF_PP_ (AD, C, D, L, Q);
//     input AD;  // async load input
//     input C;   // clock
//     input D;   // normal D input
//     input L;   // async load / preset
//     output Q;  // output

//     wire set = L & AD;
//     wire reset = L & ~AD;

//     dff u_dff (
//         .D(D),
//         .CK(C),
//         .RN(reset),
//         .SN(set),
//         .Q(Q)
//     );

// endmodule