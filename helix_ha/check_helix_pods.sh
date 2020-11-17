#!/bin/bash

# Common OCF definition compatible with Pacemaker monitor
OCF_SUCCESS=0
OCF_ERR_GENERIC=1
OCF_NOT_RUNNING=7
TIMEOUT=${2:-60}

# Just in case
SED="/usr/bin/sed"
TR="/usr/bin/tr"
CUT="/usr/bin/cut"
AWK="/usr/bin/awk"
GREP="/usr/bin/egrep"

KUBECTL_CMD="/usr/local/bin/kubectl"
#HELM_CMD="$BASE_DIR/tti3rd/helm/bin/helm --kubeconfig /etc/kubernetes/admin.conf"
#HELIXNS="default"

# If $1 is not defined then HELIXNS=default, otherwise HELIXNS=$1
HELIXNS=${1:-"default"}


EXIT=$OCF_NOT_RUNNING
EXIT_MSG="No deployments found."

RUNNING=false

SECONDS=0
declare -A DEPL_ERRS
while [ $SECONDS -lt $TIMEOUT ]
do
	OLD_IFS=$IFS
	IFS=$'\n'
	FAILED=false
	#for DEPLOYMENT in `$HELM_CMD list -q --namespace $HELIXNS`
	for DEPLOYMENT in `$KUBECTL_CMD get deployments -n $HELIXNS  2>/dev/null | $SED '1d'`
	do
		RUNNING=true
		DEPL_NAME=`echo $DEPLOYMENT | $TR -s ' ' | $CUT -d' ' -f1`
		DEPL_TOTAL=`echo $DEPLOYMENT | $TR -s ' ' | $CUT -d' ' -f2|$CUT -d'/' -f2`
		DEPL_READY=`echo $DEPLOYMENT | $TR -s ' ' | $CUT -d' ' -f2|$CUT -d'/' -f1`
		if [ $DEPL_READY -lt $DEPL_TOTAL ]
		then
		  if ! $FAILED
		  then
			 FAILED=true
			 EXIT=$OCF_ERR_GENERIC 
			 EXIT_MSG="Not all processes are up: "
		  fi     
		  DEPL_ERRS[$DEPL_NAME]="Only $DEPL_READY of $DEPL_TOTAL of $DEPL_NAME are up. "
		fi
	done
	IFS=$OLD_IFS

	if $RUNNING && ! $FAILED
	then
	   EXIT=$OCF_SUCCESS
	   EXIT_MSG="All processes are up."
	   break 
	else if ! $FAILED
	   then
		  break
	   fi
	fi
	sleep 1
	echo "Waiting for all deployments to be ready ..."
done
if $FAILED; then for DEPL_ERR in "${DEPL_ERRS[@]}"; do EXIT_MSG+=$DEPL_ERR; done; fi
echo -e $EXIT_MSG
exit $EXIT
