// Common property definitions for bridge checkers
package bridge_props_pkg;
  parameter IDLE        = 4'b0000;
  parameter SETUP_M     = 4'b0001;
  parameter SETUP_S     = 4'b0010;
  parameter ACCESS_S    = 4'b0011;
  parameter PREACCESS_M = 4'b0100;
  parameter ACCESS_M    = 4'b0101;
  parameter WSETUP_M    = 4'b0110;
  parameter WPREACCESS_M= 4'b0111;
  parameter WACCESS_M   = 4'b1000;
  parameter WTERMINATE  = 4'b1001;
  parameter WSETUP_S    = 4'b1010;
  parameter WACCESS_S   = 4'b1011;
endpackage
