# ----------------------------------------
#  Copyright (c) 2017 Cadence Design Systems, Inc. All Rights
#  Reserved.  Unpublished -- rights reserved under the copyright 
#  laws of the United States.
# ----------------------------------------

# Analyze design under verification files
set ROOT_PATH ../designs
set RTL_PATH ${ROOT_PATH}
set SV_PATH ${ROOT_PATH}

analyze -sv \
  ${RTL_PATH}/bridge.v

analyze -sva \
  ${SV_PATH}/bridge.sva \
  ${SV_PATH}/bindings.sva

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

