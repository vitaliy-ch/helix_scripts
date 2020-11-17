#!/bin/ksh

#------------------------------------------------------------------------------#
#
# File:          vcs_netrac_include.sh
# Author:        Dubi Moran - dubi@tti-telecom.com
# Last Update:   22-Aug-2002
#
# Description:
# This shell script is to be included by all netrac agent scripts.
# It defines global variables and declares log functions to be called from
# netrac script agents in order to print messages to VCS log.
#
#------------------------------------------------------------------------------#

export VCS_HOME=/root/systemd_helix/vcs_agents

export HALOG=/opt/VRTSvcs/bin/halog

log_err()
{
  $HALOG -add A "Agent $0 Error: $1" 
}


log_warn()
{
  $HALOG -add C "Agent $0 Warning: $1" 
}


log_info()
{
  $HALOG -add E "Agent $0 Info: $1" 
}



OK=0
ERROR=1
ONLINE=110
OFFLINE=100
export OK ERROR ONLINE OFFLINE

