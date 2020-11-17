#!/bin/bash
#
#
# Teoco monitor plugin for K8s system pods.
# Vitalii Chebanov, June 2020
#
#######################################################################
# Initialization:
# Command line parameters (not mandatory):
# -n|--namespace - it is a namespace where K8s pods are deployed to. Default is "kube-system".
# -t|--timeout - Time in seconds for waiting until all pods are up if they are up partially. If there is no pods at all, exit with ERR immediately.

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
: ${HELIXNS="kube-system"}

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
        EXIT_MSG="CRITICAL: No pods found."

        RUNNING=false

        SECONDS=0
        declare -A POD_ERRS
        while [ $SECONDS -lt $TIMEOUT ]
        do
                OLD_IFS=$IFS
                IFS=$'\n'
                FAILED=false
                for DEPLOYMENT in `$KUBECTL_CMD --kubeconfig $KUBE_CONFIG get pods -n $HELIXNS 2>/dev/null | $SED '1d'`
                do
                        RUNNING=true
                        POD_NAME=`echo $DEPLOYMENT | $TR -s ' ' | $CUT -d' ' -f1`
                        POD_STATE=`echo $DEPLOYMENT | $TR -s ' ' | $CUT -d' ' -f3`
                        POD_TOTAL=`echo $DEPLOYMENT | $TR -s ' ' | $CUT -d' ' -f2|$CUT -d'/' -f2`
                        POD_READY=`echo $DEPLOYMENT | $TR -s ' ' | $CUT -d' ' -f2|$CUT -d'/' -f1`
                        if [ $POD_READY -lt $POD_TOTAL ]
                        then
                          if ! $FAILED
                          then
                                 FAILED=true
                                 EXIT=$RC_WARN
                                 EXIT_MSG="WARNING: Not all pods are up: "
                          fi
                          POD_ERRS[$POD_NAME]="$POD_NAME is ${POD_STATE}. "
                        fi
                done
                IFS=$OLD_IFS

                if $RUNNING && ! $FAILED
                then
                   EXIT=$RC_OK
                   EXIT_MSG="OK: All pods are up."
                   break
                else if ! $FAILED
                   then
                          break
                   fi
                fi
                sleep 1
                #echo "Waiting for all pods to be ready ..."
        done
        if $FAILED; then for POD_ERR in "${POD_ERRS[@]}"; do EXIT_MSG+=$POD_ERR; done; fi
        echo -e $EXIT_MSG
        return $EXIT
}

helix_agent_monitor
exit $?
