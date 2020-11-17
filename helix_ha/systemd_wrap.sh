#!/bin/bash
# Run any command from systmed with including .profile

CMD=$@
. /teoco/home/helix/.profile
eval "$CMD" &
