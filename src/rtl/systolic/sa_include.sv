// ----------------------- //
// --- PACKAGE: SA_PKG --- //
// ----------------------- //
package sa_pkg;
    typedef enum logic [1:0] {  
        IDLE    = 2'b00,
        PRELOAD = 2'b01,
        STREAM  = 2'b10,
        // FLUSH   = 2'b11,
        STATEX  = 2'bxx
    } sa_state_e;
endpackage