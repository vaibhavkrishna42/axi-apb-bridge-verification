# ----------------------------------------
# Jasper Version Info
# tool      : Jasper 2024.06
# platform  : Linux 4.18.0-553.89.1.el8_10.x86_64
# version   : 2024.06p002 64 bits
# build date: 2024.09.02 16:28:38 UTC
# ----------------------------------------
# started   : 2025-12-12 15:40:44 EST
# hostname  : cadpc04.(none)
# pid       : 1001656
# arguments : '-label' 'session_0' '-console' '//127.0.0.1:35903' '-style' 'windows' '-data' 'AAAAkHicY2RgYLCp////PwMYMD6A0Aw2jAyoAMRnQhUJbEChGRhYYZphSkAaOBh0GdIYChjKgGwZBjeGAIYwhniGRIYKhkwgWcCQxKDHUMKQzJAD1gEAwXENkA==' '-proj' '/homes/user/stud/fall25/vg2651/axi2apb/FPV/jgproject/sessionLogs/session_0' '-init' '-hidden' '/homes/user/stud/fall25/vg2651/axi2apb/FPV/jgproject/.tmp/.initCmds.tcl' 'FPV_axiapb.tcl'
# ----------------------------------------
#  Copyright (c) 2017 Cadence Design Systems, Inc. All Rights
#  Reserved.  Unpublished -- rights reserved under the copyright 
#  laws of the United States.
# ----------------------------------------

# Analyze design under verification files
set ROOT_PATH ../designs
set RTL_PATH ${ROOT_PATH}
set SV_PATH ${ROOT_PATH}

# Mode selection via environment variable JG_MODE
#   all|safety|liveness|misc
set mode "all"
if {[info exists ::env(JG_MODE)]} {
  set mode $::env(JG_MODE)
}

set SVA_FILES {}
switch -- $mode {
  "safety" {
    set SVA_FILES [list \
      ${SV_PATH}/bridge_props_pkg.sv \
      ${SV_PATH}/bridge_env_safety.sva \
      ${SV_PATH}/bindings_safety.sva]
  }
  "liveness" {
    set SVA_FILES [list \
      ${SV_PATH}/bridge_props_pkg.sv \
      ${SV_PATH}/bridge_liveness.sva \
      ${SV_PATH}/bindings_liveness.sva]
  }
  "misc" {
    set SVA_FILES [list \
      ${SV_PATH}/bridge_props_pkg.sv \
      ${SV_PATH}/bridge_misc.sva \
      ${SV_PATH}/bindings_misc.sva]
  }
  default {
    set SVA_FILES [list \
      ${SV_PATH}/bridge_props_pkg.sv \
      ${SV_PATH}/bridge_env_safety.sva \
      ${SV_PATH}/bridge_liveness.sva \
      ${SV_PATH}/bridge_misc.sva \
      ${SV_PATH}/bindings.sva]
  }
}

analyze -sv \
  ${RTL_PATH}/bridge.v

analyze -sva \
  {*}$SVA_FILES

# Elaborate design and properties
elaborate -top bridge

# Set up Clocks and Resets
clock clk
reset ~res_n

# Get design information to check general complexity
get_design_info

# Prove properties
prove -all

# Report proof results
report

