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

