#!/bin/bash
#
#
# Teoco monitor plugin for Helix K8s deployments.
# Vitalii Chebanov, April 2020
#
#######################################################################
# Initialization:
# Command line parameters (not mandatory):
# -n|--namespace - it is a namespace where Helix pods are deployed to. Currently "default", it is going to be changed in the future.
# -t|--timeout - Time in seconds for waiting until all deployments are up if they are up partially. If there is no deployments at all, exit with ERR immediately.

PARAMS=""
while (( "$#" )); do
  case "$1" in
    -t|--timeout)
      TIMEOUT=$2
      shift 2
      ;;
    -n|--namespace)
      HELIXNS=$2
      shift 2
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

# If TIMEOIUT is not an integer unset it
[[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] && unset TIMEOUT

# Default values if not defined
: ${TIMEOUT=30}
: ${HELIXNS="default"}

RC_OK=0
RC_WARN=1
RC_ERR=2

#######################################################################

helix_agent_monitor() {

        # Just in case. There is a very small chance that anything is changed in commands below:
        SED="/usr/bin/sed"
        TR="/usr/bin/tr"
        CUT="/usr/bin/cut"
        AWK="/usr/bin/awk"
        GREP="/usr/bin/egrep"
        # Can be changed only if K8s was installed manually or with some manual changes in kubespray_offline.
        KUBE_CONFIG="/etc/kubernetes/admin.conf"
        KUBECTL_CMD="/usr/local/bin/kubectl"
        EXIT=$RC_ERR
        EXIT_MSG="CRITICAL: No deployments found."

        RUNNING=false

        SECONDS=0
        declare -A DEPL_ERRS
        while [ $SECONDS -lt $TIMEOUT ]
        do
                OLD_IFS=$IFS
                IFS=$'\n'
                FAILED=false
                for DEPLOYMENT in `$KUBECTL_CMD --kubeconfig $KUBE_CONFIG get deployments -n $HELIXNS 2>/dev/null | $SED '1d'`
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
                                 EXIT=$RC_WARN
                                 EXIT_MSG="WARNING: Not all processes are up: "
                          fi
                          DEPL_ERRS[$DEPL_NAME]="Only $DEPL_READY of $DEPL_TOTAL of $DEPL_NAME are up. "
                        fi
                done
                IFS=$OLD_IFS

                if $RUNNING && ! $FAILED
                then
                   EXIT=$RC_OK
                   EXIT_MSG="OK: All processes are up."
                   break
                else if ! $FAILED
                   then
                          break
                   fi
                fi
                sleep 1
                #echo "Waiting for all deployments to be ready ..."
        done
        if $FAILED; then for DEPL_ERR in "${DEPL_ERRS[@]}"; do EXIT_MSG+=$DEPL_ERR; done; fi
        echo -e $EXIT_MSG
        return $EXIT
}

helix_agent_monitor
exit $?
