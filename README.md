## AXI-APB Bridge Verification

### File paths
    RTL: designs/bridge.v
    Assertions: designs/bridge*.sva
    Bindings: designs/bindings*.sva
    FPV tcl script: FPV/FPV_axiapb.tcl

### To run Cadence JasperGold
#### To check all properties
    ./run_jg.sh

#### To check safety properties
    ./run_jg.sh safety

#### To check liveness properties
    ./run_jg.sh liveness

#### To check misc properties
    ./run_jg.sh misc