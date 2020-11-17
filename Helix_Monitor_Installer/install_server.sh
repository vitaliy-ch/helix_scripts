#!/bin/bash
#
# Copyright (C) 2020 Teoco. All rights reserved.
#
# This file is part of Helix Monitor installation.
#
# Author: Vitalii Chebanov <vitalii.chebanov@teoco.com>

# Just in case
set +o noclobber

USAGE="Usage: $0 [-s source_dir] [-u|-f] [-p all|grafana|influx|python|telegraf], \nwhere -s source_dir is directory with installation files or directory where $0 is run from, \n-u is an upgrade mode, \n-f is a force reinstall of existing products. \
\n-p is a product for upgarde/reinstall"

# It is better to unset all variables which might not be defined in server.cfg before including it
unset HELIX_MONITOR_HOST
unset GRAFANA_ADMIN_PASS
unset GRAFANA_USER
unset GRAFANA_USER_EMAIL
unset GRAFANA_PASS
unset SOURCE_DIR
unset PRODUCT_NAME
unset UPGRADE_MODE
unset FORCE_MODE

while getopts "ufhs:p:" OPTION; do
    case $OPTION in
    s)
        SOURCE_DIR=$OPTARG
        [[ $SOURCE_DIR =~ -u|-f|- ]] && {
            echo -e "[ERROR] Invalid source directory. \n$USAGE"
            exit 1
        }
        ;;
    p)
        PRODUCT_NAME=$OPTARG
        [[ ! $PRODUCT_NAME =~ ^all$|^grafana$|^influx$|^python$|^telegraf$ ]] && {
            echo -e "[ERROR] Invalid product for upgrade/reinstall. \n$USAGE"
            exit 1
        }
        ;;
    u)
        UPGRADE_MODE="true"
        ;;
    f)
        FORCE_MODE="true"
        ;;
    h)
        echo -e $USAGE && exit 0
        ;;
    *)
        echo -e "[ERROR] Incorrect options provided. \n$USAGE"
        exit 1
        ;;
    esac
done

if [ "$UPGRADE_MODE" == "true" ] && [ "$FORCE_MODE" == "true" ] 
 then
   echo -e "[ERROR] Upgrade mode is incompatible with force mode. \n$USAGE" 
   exit 1
fi

if [ "$UPGRADE_MODE" == "true" ] || [ "$FORCE_MODE" == "true" ] && [ -z $PRODUCT_NAME ]
 then
   echo -e "[ERROR] Upgrade or force mode requires product name. \n$USAGE" 
   exit 1
fi

[ "$UPGRADE_MODE" == "true" ] &&  [[ $PRODUCT_NAME =~ ^all$|^influx$ ]] && UPGRADE_INFLUXDB="true"
[ "$FORCE_MODE" == "true" ] &&  [[ $PRODUCT_NAME =~ ^all$|^influx$ ]] && FORCE_INFLUX="true"
[ "$UPGRADE_MODE" == "true" ] &&  [[ $PRODUCT_NAME =~ ^all$|^grafana$ ]] && UPGRADE_GRAFANA="true"
[ "$FORCE_MODE" == "true" ] &&  [[ $PRODUCT_NAME =~ ^all$|^grafana$ ]] && FORCE_GRAFANA="true"
[ "$UPGRADE_MODE" == "true" ] &&  [[ $PRODUCT_NAME =~ ^all$|^python$ ]] && UPGRADE_PYTHON="true"
[ "$FORCE_MODE" == "true" ] &&  [[ $PRODUCT_NAME =~ ^all$|^python$ ]] && FORCE_PYTHON="true"
[ "$UPGRADE_MODE" == "true" ] &&  [[ $PRODUCT_NAME =~ ^all$|^telegraf$ ]] && UPGRADE_TELEGRAF="true"
[ "$FORCE_MODE" == "true" ] &&  [[ $PRODUCT_NAME =~ ^all$|^telegraf$ ]] && FORCE_TELEGRAF="true"

# Define locations of installation files
[ -z "$SOURCE_DIR" ] && SOURCE_DIR=`dirname $0`
SERVER_CFG=$SOURCE_DIR/install_server.cfg
INSTALL_FILES=$SOURCE_DIR/files
JQ=$INSTALL_FILES/jq
# For upgrade: folders to be saved during the upgrade - configuration, data
INFLUXDB_DIRS_TO_SAVE="etc,var"
GRAFANA_DIRS_TO_SAVE="conf,data"
TELEGRAF_DIRS_TO_SAVE="etc,plugins,var"

## Default values for Grafana HTTP API
API_USER=admin
API_PASS=admin

[ ! -f $SERVER_CFG ] &&  echo "Server configuration file not found, exit." &&  exit 1 || source $SERVER_CFG
[ -z "$HELIX_MONITOR_HOST" ] && HELIX_MONITOR_HOST=`hostname`
[ -z "$HELIX_ENV_TAG" ] && HELIX_ENV_TAG=$HELIX_MONITOR_HOST

######################### Defining functions ##############################
######################### Create infra ####################################
function create_infra {

mkdir -p $PRODUCT_DIR/tmp
mkdir -p $PRODUCT_DIR/scripts

if [ -f $SOURCE_DIR/files/helix_monitor.sh.tmpl ]
  then
    cp -a $SOURCE_DIR/files/helix_monitor.sh.tmpl $PRODUCT_DIR/scripts/helix_monitor.sh
    chmod a+x $PRODUCT_DIR/scripts/helix_monitor.sh
    sed -i "s#{{PRODUCT_DIR}}#$PRODUCT_DIR#" $PRODUCT_DIR/scripts/helix_monitor.sh
  else
    echo "[ERROR] $SOURCE_DIR/files/helix_monitor.sh file not found, exit."
    exit 1
fi
}
######################### Create infra ####################################

######################### Create https certificate ########################
function create_https_certs() {
# Generate new https certs
CERTS_HOSTNAMES=$1
CERTS_DIR=$2

if ! command -v openssl &>/dev/null
  then
    echo "[ERROR] openssl command not found!"
    exit 1
fi

[ -z "$CERTS_HOSTNAMES" ] && echo "[ERROR] CERTS_HOSTNAMES variable is not defined!" && exit 1
mkdir -p $CERTS_DIR

# Split words to parameters, $1 will be first hostname and used as filename
set -- $CERTS_HOSTNAMES
CERT_FILE_NAME=$1

rm -f $CERTS_DIR/${CERT_FILE_NAME}.key
rm -f $CERTS_DIR/${CERT_FILE_NAME}.crt
export PASSPHRASE=$(head -c 128 /dev/urandom | openssl enc -base64 |  tr "\n" "d")
CERTS_KEY="$CERTS_DIR/${CERT_FILE_NAME}.key"
CERTS_TMP_KEY="$CERTS_DIR/${CERT_FILE_NAME}.tmp.key"
CERTS_CSR="$CERTS_DIR/${CERT_FILE_NAME}.tmp.csr"
CERTS_EXT="$CERTS_DIR/${CERT_FILE_NAME}.ext.cnf"
CERTS_CRT="$CERTS_DIR/${CERT_FILE_NAME}.crt"

openssl genrsa -des3 -out $CERTS_TMP_KEY -passout env:PASSPHRASE 2048
openssl req        \
	-new           \
	-batch         \
	-subj "/C=US/ST=VA/O=Teoco/localityName=Fairfax/organizationalUnitName=$1" \
	-key $CERTS_TMP_KEY  \
	-out $CERTS_CSR      \
	-passin env:PASSPHRASE
openssl rsa -in $CERTS_TMP_KEY -out $CERTS_KEY -passin env:PASSPHRASE

cat << EOF > $CERTS_EXT
basicConstraints=CA:TRUE
subjectAltName=@my_subject_alt_names
subjectKeyIdentifier = hash

[ my_subject_alt_names ]
EOF

n=1
for CERTS_HOST in $CERTS_HOSTNAMES
do
	echo "DNS.$n = $CERTS_HOST" >> "$CERTS_EXT"
        let n=n+1
done

openssl x509 -req -sha256 -days 3650 -in $CERTS_CSR -signkey $CERTS_KEY -out $CERTS_CRT -dates -extfile $CERTS_EXT
rm -f $CERTS_TMP_KEY $CERTS_CSR $CERTS_EXT
chmod 0600 $CERTS_KEY
}
######################### Create https certificate ########################

######################### Install InfluxDB ################################
function install_influxdb {

# Wipe existing installation
[ -f $PRODUCT_DIR/scripts/influxdb.sh ] && $PRODUCT_DIR/scripts/influxdb.sh stop

if [ -d $PRODUCT_DIR/influxdb ] 
  then if [ "$UPGRADE_INFLUXDB" != "true" ]
    then
      echo "Deleting existing installation"
      rm -rf $PRODUCT_DIR/influxdb
    else
      echo "Removing binaries for the upgrade"
      for DIR_FOR_DELETE in `find $PRODUCT_DIR/influxdb/* -maxdepth 0`
      do
        IFS=$','
        IS_DELETED="true"
        for EXCLUDE_DIR in $INFLUXDB_DIRS_TO_SAVE
        do 
          if [ "$EXCLUDE_DIR" == `basename $DIR_FOR_DELETE` ]
          then
            IS_DELETED="false"
          fi
        done
        unset IFS
        [ "$IS_DELETED" == "true" ] && rm -rf $DIR_FOR_DELETE
      done
  fi
fi

if [ ! -f $INSTALL_FILES/$INFLUXDB_INST_FILE ]
  then
    echo "[ERROR] $INFLUXDB_INST_FILE file not found, exit."
    exit 1 
fi

if [ ! -f $INSTALL_FILES/influxdb.sh.tmpl ] && [ "$UPGRADE_INFLUXDB" != "true" ]
  then
    echo "[ERROR] $INSTALL_FILES/influxdb.sh.tmpl file not found, exit."
    exit 1
fi

mkdir -p $PRODUCT_DIR/influxdb
TMPINST_DIR=`mktemp -d -p $PRODUCT_DIR/tmp`
tar zxf $INSTALL_FILES/$INFLUXDB_INST_FILE -C $TMPINST_DIR
INFLUXDB_SRC_DIR=`find $TMPINST_DIR -maxdepth 1 -type d | grep -m 1 influxdb`

if [ "$UPGRADE_INFLUXDB" == "true" ]
then
  IFS=$','
  for EXCLUDE_DIR in $INFLUXDB_DIRS_TO_SAVE
   do
     echo "Not copying source file $INFLUXDB_SRC_DIR/$EXCLUDE_DIR in upgrade mode"
     rm -rf $INFLUXDB_SRC_DIR/$EXCLUDE_DIR
   done
  unset IFS
fi

cp -a $INFLUXDB_SRC_DIR/* $PRODUCT_DIR/influxdb/
rm -rf $TMPINST_DIR

chmod a+x $PRODUCT_DIR/influxdb/usr/bin/*

# Only if not upgrade mode
if [ "$UPGRADE_INFLUXDB" != "true" ]
  then
    cp -a $INSTALL_FILES/influxdb.sh.tmpl $PRODUCT_DIR/scripts/influxdb.sh
    chmod a+x $PRODUCT_DIR/scripts/influxdb.sh 
    sed -i "s#{{PRODUCT_DIR}}#$PRODUCT_DIR#" $PRODUCT_DIR/scripts/influxdb.sh

    # Generate influxdb.conf
    if [ ! -f $INSTALL_FILES/influxdb.conf.tmpl ]
      then
        echo "[ERROR] influxdb.conf.tmpl file not found, exit."
        exit 1
    fi
    sed -e "s#{{PRODUCT_DIR}}#$PRODUCT_DIR#" \
        -e "s#{{SSL_CERT}}#$PRODUCT_DIR/ssl/$HELIX_MONITOR_HOST.crt#" \
        -e "s#{{INFLUXDB_PORT}}#$INFLUXDB_PORT#" \
        -e "s#{{SSL_KEY}}#$PRODUCT_DIR/ssl/$HELIX_MONITOR_HOST.key#" $INSTALL_FILES/influxdb.conf.tmpl > $PRODUCT_DIR/influxdb/etc/influxdb/influxdb.conf
fi

$PRODUCT_DIR/scripts/influxdb.sh start
echo "Waiting for InfluxDB to be ready"
TIMEOUT=$((SECONDS+120))
while [ $SECONDS -lt $TIMEOUT ]; do
  printf "."
  curl -k https://localhost:${INFLUXDB_PORT}/ping > /dev/null 2>&1
  RC=$?
  if [ $RC -eq 0 ]; then break; fi
  sleep 1
done
if [ $RC -ne 0 ]; 
  then
    printf "\n[ERROR] InfluxDB falied to start within expected time. Exit.\n"
    exit 1
fi
printf "\n[SUCCESS] InfluxDB has been started.\n"
}
######################### Install InfluxDB ################################

######################### Configure InfluxDB ##############################
function configure_influxdb {
echo "Creating database monitoring"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -execute "create database monitoring"
echo "Creating retention policies"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -database "monitoring" -execute "CREATE RETENTION POLICY "monitoring" ON "monitoring" DURATION 1d REPLICATION 1 DEFAULT"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -database "monitoring" -execute "CREATE RETENTION POLICY "long_retention" ON "monitoring" DURATION 7d REPLICATION 1"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -database "monitoring" -execute "CREATE RETENTION POLICY "forever" ON "monitoring" DURATION 0d REPLICATION 1"
echo "Configuring retention policies"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -database "monitoring" -execute "insert into forever helix_alert_severity,num=1,text=Minor dummy=0"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -database "monitoring" -execute "insert into forever helix_alert_severity,num=2,text=Major dummy=0"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -database "monitoring" -execute "insert into forever helix_alert_severity,num=3,text=Critical dummy=0"
echo "Creating users"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -execute "create user admin with password '$INFLUXDB_ADMIN_PASSWORD' with all privileges"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -execute "create user $INFLUXDB_USER_NAME with password '$INFLUXDB_USER_PASSWORD'"
$PRODUCT_DIR/influxdb/usr/bin/influx -port $INFLUXDB_PORT -ssl -unsafeSsl -database "monitoring" -execute "grant all on monitoring to $INFLUXDB_USER_NAME"

# Enable http authorization
sed -i 's/#\s*auth-enabled\s*=\s*false/auth-enabled = true/' $PRODUCT_DIR/influxdb/etc/influxdb/influxdb.conf

echo -e "\n[SUCCESS] InfluxDB has been configured sucessfully\n"

echo "Restarting the database"
$PRODUCT_DIR/scripts/influxdb.sh stop
$PRODUCT_DIR/scripts/influxdb.sh start
}
######################### Configure InfluxDB ##############################

######################### Grafana API wrapper #############################
function grafana_api {
# Params: $1 - command (GET|POST|PUT), $2 - api uri, $3 - optional JSON file to PUT/POST
local TMPJSON=`mktemp -p $PRODUCT_DIR/tmp`
local JSON_FILE
if [ "$1" != "GET" ] 
  then
    HEADERS='-H "Content-Type: application/json"'
    if [ -f "$3" ] 
      then
        cp "$3" $TMPJSON
        JSON_FILE="-d @$TMPJSON"
    fi
fi
eval "curl -s -k --user ${API_USER}:${API_PASS} -X $1 $HEADERS https://${HELIX_MONITOR_HOST}:${HTTP_PORT}${2} $JSON_FILE"
rm -f $TMPJSON
}
######################### Grafana API wrapper #############################

######################### Install Grafana #################################
function install_grafana {

# Wipe existing installation
[ -f $PRODUCT_DIR/scripts/grafana.sh ] && $PRODUCT_DIR/scripts/grafana.sh stop
if [ -d $PRODUCT_DIR/grafana ] 
  then if [ "$UPGRADE_GRAFANA" != "true" ]
    then
      echo "Deleting existing installation"
      rm -rf $PRODUCT_DIR/grafana
    else
      echo "Removing binaries for the upgrade"
      for DIR_FOR_DELETE in `find $PRODUCT_DIR/grafana/* -maxdepth 0`
      do
        IFS=$','
        IS_DELETED="true"
        for EXCLUDE_DIR in $GRAFANA_DIRS_TO_SAVE
        do 
          if [ "$EXCLUDE_DIR" == `basename $DIR_FOR_DELETE` ]
          then
            IS_DELETED="false"
          fi
        done
        unset IFS
        [ "$IS_DELETED" == "true" ] && rm -rf $DIR_FOR_DELETE
      done
  fi
fi

if [ ! -f $INSTALL_FILES/$GRAFANA_INST_FILE ]
  then
    echo "[ERROR] $GRAFANA_INST_FILE file not found, exit."
    exit 1 
fi

if [ ! -f $INSTALL_FILES/grafana.sh.tmpl ] && [ "$UPGRADE_GRAFANA" != "true" ]
  then
    echo "[ERROR] $INSTALL_FILES/grafana.sh.tmpl file not found, exit."
    exit 1
fi

mkdir -p $PRODUCT_DIR/grafana
TMPINST_DIR=`mktemp -d -p $PRODUCT_DIR/tmp`
tar zxf $INSTALL_FILES/$GRAFANA_INST_FILE -C $TMPINST_DIR
GRAFANA_SRC_DIR=`find $TMPINST_DIR -maxdepth 1 -type d | grep -m 1 grafana`

if [ "$UPGRADE_GRAFANA" == "true" ]
then
  IFS=$','
  for EXCLUDE_DIR in $GRAFANA_DIRS_TO_SAVE
   do
     echo "Not copying source file $GRAFANA_SRC_DIR/$EXCLUDE_DIR in upgrade mode"
     rm -rf $GRAFANA_SRC_DIR/$EXCLUDE_DIR
   done
  unset IFS
fi

cp -a $GRAFANA_SRC_DIR/* $PRODUCT_DIR/grafana/
rm -rf $TMPINST_DIR

chmod a+x $PRODUCT_DIR/grafana/bin/*

# Only if not upgrade mode
if [ "$UPGRADE_GRAFANA" != "true" ]
  then
    mkdir -p $PRODUCT_DIR/grafana/data
    cp -a $INSTALL_FILES/grafana.sh.tmpl $PRODUCT_DIR/scripts/grafana.sh
    chmod a+x $PRODUCT_DIR/scripts/grafana.sh
    sed -i "s#{{PRODUCT_DIR}}#$PRODUCT_DIR#" $PRODUCT_DIR/scripts/grafana.sh

    # Generate grafana.ini
    if [ ! -f $INSTALL_FILES/grafana.ini.tmpl ]
      then
        echo "[ERROR] $INSTALL_FILES/grafana.ini.tmpl file not found, exit."
        exit 1
    fi

    sed -e "s#{{HELIX_MONITOR_HOST}}#$HELIX_MONITOR_HOST#" \
        -e "s#{{HTTP_PORT}}#$HTTP_PORT#" \
        -e "s#{{GRAFANA_SMTP_HOST}}#$GRAFANA_SMTP_HOST#" \
        -e "s#{{GRAFANA_SMTP_PORT}}#$GRAFANA_SMTP_PORT#" \
        -e "s#{{GRAFANA_MAIL_FROM}}#$GRAFANA_MAIL_FROM#" \
        -e "s#{{SSL_CERT}}#$PRODUCT_DIR/ssl/$HELIX_MONITOR_HOST.crt#" \
        -e "s#{{SSL_KEY}}#$PRODUCT_DIR/ssl/$HELIX_MONITOR_HOST.key#" $INSTALL_FILES/grafana.ini.tmpl > $PRODUCT_DIR/grafana/conf/grafana.ini
fi

# Install/Update plugins folder
[ -f $INSTALL_FILES/grafana_plugins.tgz ] && tar -zxf $INSTALL_FILES/grafana_plugins.tgz -C $PRODUCT_DIR/grafana/data
 
# Set custom icon
[ -f $INSTALL_FILES/grafana_icon.svg ] && cp -a $INSTALL_FILES/grafana_icon.svg $PRODUCT_DIR/grafana/public/img/grafana_icon.svg

$PRODUCT_DIR/scripts/grafana.sh start

echo "Waiting for Grafana to be ready"
TIMEOUT=$((SECONDS+120))
while [ $SECONDS -lt $TIMEOUT ]; do
  printf "."
  RC=`grafana_api GET /api/org | $JQ .id`
  if [ "$RC" == "1" ]; then break; fi
  sleep 1
done
if [ "$RC" != "1" ]; 
  then
    printf "\n[ERROR] Grafana falied to start within expected time. Exit.\n"
    exit 1
fi
printf "\n[SUCCESS] Grafana has been started.\n"
}
######################### Install Grafana #################################

######################### Configure Grafana ###############################
function configure_grafana {
echo "Configuring Grafana"

TMPFILE=`mktemp -p $PRODUCT_DIR/tmp`
TMPJSON=`mktemp -p $PRODUCT_DIR/tmp`

if [  -n "$GRAFANA_ADMIN_PASS" ]
  then
    echo "Changing default admin password"
    echo -e "{\"oldPassword\": \"admin\",\"newPassword\": \"$GRAFANA_ADMIN_PASS\"}" > $TMPJSON
    grafana_api PUT /api/user/password "$TMPJSON" | $JQ > $TMPFILE
    RC=`cat $TMPFILE | $JQ .message|tr -d '"'`
    if [ "$RC" != "User password changed" ]
      then 
        echo "Password was not changed:"
        cat $TMPFILE
      else
        API_PASS=$GRAFANA_ADMIN_PASS
    fi  
fi

if [ -f $INSTALL_FILES/ds_influxdb.json.tmpl ]
  then
    echo "Adding InfluxDB datasource"
    sed -e "s#{{HELIX_MONITOR_HOST}}#$HELIX_MONITOR_HOST#" \
        -e "s#{{INFLX_PASS}}#$INFLUXDB_USER_PASSWORD#" \
        -e "s#{{INFLUXDB_PORT}}#$INFLUXDB_PORT#" \
        -e "s#{{INFLX_USER}}#$INFLUXDB_USER_NAME#" $INSTALL_FILES/ds_influxdb.json.tmpl > $TMPJSON
    grafana_api POST /api/datasources "$TMPJSON" | $JQ > $TMPFILE
    RC=`cat $TMPFILE | $JQ .message|tr -d '"'`
    
    if [[ "$RC" != "Datasource added" && "$RC" != "Data source with the same name already exists" ]]
       then
         echo "[ERROR] Datasource has not been created:"
         cat $TMPFILE
         rm -f $TMPFILE
         rm -f $TMPJSON
         exit 1
    fi

  else
    echo "[ERROR] ds_influxdb.json.tmpl file not found, exit."
    rm -f $TMPFILE
    rm -f $TMPJSON
    exit 1
fi
rm -f $TMPJSON

if [ -d $INSTALL_FILES/dashboards ]
  then
    OLD_IFS=$IFS
    IFS=$'\n'
    for DASHBOARD in `find $INSTALL_FILES/dashboards -type f`
      do
        echo "Importing `basename $DASHBOARD` dashboard"
        grafana_api POST /api/dashboards/db "$DASHBOARD" | $JQ > $TMPFILE
        RC=`cat $TMPFILE | $JQ .status|tr -d '"'`

        if [[ "$RC" != "success" && "$RC" != "name-exists" ]]
          then
            echo "[ERROR] Dashboard `basename $DASHBOARD` has not been imported:"
            cat $TMPFILE
            rm -f $TMPFILE
            #exit 1
       fi
      done
      IFS=$OLD_IFS
  else
    echo "[ERROR] Dashboards directory is missing. Exit."
    rm -f $TMPFILE
    #exit 1
fi

# Adding Grafan user if set
if [  -n "$GRAFANA_USER" ]
  then
    echo "Creating $GRAFANA_USER user"
    [ -z "$GRAFANA_USER_EMAIL" ] && GRAFANA_USER_EMAIL="helix@teoco.com"
    [ -z "$GRAFANA_PASS" ] && GRAFANA_PASS="qwer90"
    echo -e "{\"name\":\"$GRAFANA_USER\",\"email\":\"$GRAFANA_USER_EMAIL\",\"login\":\"$GRAFANA_USER\",\"password\":\"$GRAFANA_PASS\",\"OrgId\": 1}" > $TMPJSON
    grafana_api POST /api/admin/users "$TMPJSON" | $JQ > $TMPFILE
    RC=`cat $TMPFILE | $JQ .message|tr -d '"'`
    NEW_USER_UID=`cat $TMPFILE | $JQ .id|tr -d '"'`
    if [ "$RC" != "User created" ]
      then 
        echo "User $GRAFANA_USER has not been created:"
        cat $TMPFILE
      else
        echo "Changing $GRAFANA_USER to Editor"
        echo -e "{\"role\": \"Editor\"}" > $TMPJSON
        grafana_api PATCH /api/org/users/${NEW_USER_UID} "$TMPJSON" | $JQ > $TMPFILE
        RC=`cat $TMPFILE | $JQ .message|tr -d '"'`
        if [ "$RC" != "Organization user updated" ]
          then
            echo "$GRAFANA_USER has not been updated and still have a role Viewer:" 
            cat $TMPFILE
        fi
        API_USER=$GRAFANA_USER
        API_PASS=$GRAFANA_PASS
    fi  
fi
rm -f $TMPJSON

echo "Starring Main alerts screen"
grafana_api POST /api/user/stars/dashboard/`grafana_api GET /api/search?query=Main%20alerts%20screen | $JQ '.[0].id'` | $JQ .message | tr -d '"'

echo "Setting Main alerts screen as home dashboard"
echo "{\"homeDashboardId\": `grafana_api GET /api/search?query=Main%20alerts%20screen | $JQ '.[0].id'`}" > $TMPFILE
grafana_api PUT /api/user/preferences "$TMPFILE" | $JQ .message | tr -d '"'

rm -f $TMPFILE
echo -e "\n[SUCCESS] Grafana has been configured sucessfully\n"
echo -e "\n\n[ URL: https://${HELIX_MONITOR_HOST}:${HTTP_PORT} ]\n\n[ User: $API_USER ]\n\n[ Password: $API_PASS ]\n\n"
}
######################### Configure Grafana ###############################

######################### Install Python ##################################
function install_python {
[ ! -f $INSTALL_FILES/$PYTHON_INST_FILE ] && echo "Python installation file not found, skipping Python installation." && return 1
TMPINST_DIR=`mktemp -d -p $PRODUCT_DIR/tmp`
tar -xf $INSTALL_FILES/$PYTHON_INST_FILE -C $TMPINST_DIR
$TMPINST_DIR/install.sh "" $PRODUCT_DIR/python "" ""
rm -rf $TMPINST_DIR
$PRODUCT_DIR/python/bin/pip install $INSTALL_FILES/influxdb-5.3.1-py2.py3-none-any.whl
}
######################### Install Python ##################################

######################### Install Telegraf ################################
function install_telegraf {

# Wipe existing installation
[ -f $PRODUCT_DIR/scripts/telegraf.sh ] && $PRODUCT_DIR/scripts/telegraf.sh stop

if [ -d $PRODUCT_DIR/telegraf ] 
  then if [ "$UPGRADE_TELEGRAF" != "true" ]
    then
      echo "Deleting existing installation"
      rm -rf $PRODUCT_DIR/telegraf
    else
      echo "Removing binaries for the upgrade"
      for DIR_FOR_DELETE in `find $PRODUCT_DIR/telegraf/* -maxdepth 0`
      do
        IFS=$','
        IS_DELETED="true"
        for EXCLUDE_DIR in $TELEGRAF_DIRS_TO_SAVE
        do 
          if [ "$EXCLUDE_DIR" == `basename $DIR_FOR_DELETE` ]
          then
            IS_DELETED="false"
          fi
        done
        unset IFS
        [ "$IS_DELETED" == "true" ] && rm -rf $DIR_FOR_DELETE
      done
  fi
fi

if [ ! -f $INSTALL_FILES/$TELEGRAF_INST_FILE ]
  then
    echo "[ERROR] $TELEGRAF_INST_FILE file not found, exit."
    exit 1 
fi

if [ ! -f $INSTALL_FILES/telegraf.sh.tmpl ] && [ "$UPGRADE_TELEGRAF" != "true" ]
  then
    echo "[ERROR] $INSTALL_FILES/telegraf.sh.tmpl file not found, exit."
    exit 1
fi

mkdir -p $PRODUCT_DIR/telegraf
TMPINST_DIR=`mktemp -d -p $PRODUCT_DIR/tmp`
tar zxf $INSTALL_FILES/$TELEGRAF_INST_FILE -C $TMPINST_DIR
TELEGRAF_SRC_DIR=`find $TMPINST_DIR -maxdepth 1 -type d | grep -m 1 telegraf`

if [ "$UPGRADE_TELEGRAF" == "true" ]
then
  IFS=$','
  for EXCLUDE_DIR in $TELEGRAF_DIRS_TO_SAVE
   do
     echo "Not copying source file $TELEGRAF_SRC_DIR/$EXCLUDE_DIR in upgrade mode"
     rm -rf $TELEGRAF_SRC_DIR/$EXCLUDE_DIR
   done
  unset IFS
fi

cp -a $TELEGRAF_SRC_DIR/* $PRODUCT_DIR/telegraf/
rm -rf $TMPINST_DIR

chmod a+x $PRODUCT_DIR/telegraf/usr/bin/*

# Only if not upgrade mode
if [ "$UPGRADE_TELEGRAF" != "true" ]
  then
    cp -a $INSTALL_FILES/telegraf.sh.tmpl $PRODUCT_DIR/scripts/telegraf.sh
    chmod a+x $PRODUCT_DIR/scripts/telegraf.sh 
    sed -i "s#{{PRODUCT_DIR}}#$PRODUCT_DIR#" $PRODUCT_DIR/scripts/telegraf.sh

    # Generate telegraf.conf
    if [ ! -f $INSTALL_FILES/telegraf.conf.tmpl ]
      then
        echo "[ERROR] telegraf.conf.tmpl file not found, exit."
        exit 1
    fi
    sed -e "s#{{PRODUCT_DIR}}#$PRODUCT_DIR#" \
        -e "s#{{HELIX_MONITOR_HOST}}#$HELIX_MONITOR_HOST#" \
	-e "s#{{HELIX_ENV_TAG}}#$HELIX_ENV_TAG#" \
        -e "s#{{INFLUXDB_PORT}}#$INFLUXDB_PORT#" \
        -e "s#{{INFLUXDB_USER_NAME}}#$INFLUXDB_USER_NAME#" \
        -e "s#{{INFLUXDB_USER_PASSWORD}}#$INFLUXDB_USER_PASSWORD#" $INSTALL_FILES/telegraf.conf.tmpl > $PRODUCT_DIR/telegraf/etc/telegraf/telegraf.conf

   # Install plugins folder
   [ -f $INSTALL_FILES/telegraf_plugins.tgz ] && tar -zxf $INSTALL_FILES/telegraf_plugins.tgz -C $PRODUCT_DIR/telegraf
   find  $PRODUCT_DIR/telegraf/plugins/ -name "*.sh" -exec chmod ugo+x {} \;
   find  $PRODUCT_DIR/telegraf/plugins/ -name "*.py" -exec chmod ugo+x {} \;
   rm -f $PRODUCT_DIR/telegraf/plugins/config/env.cfg
   rm -f $PRODUCT_DIR/telegraf/plugins/config/mail_notifications.cfg

   sed -e "s#{{HELIX_MONITOR_HOST}}#$HELIX_MONITOR_HOST#" \
       -e "s#{{HELIX_ENV_TAG}}#$HELIX_ENV_TAG#" \
       -e "s#{{INFLUXDB_PORT}}#$INFLUXDB_PORT#" $INSTALL_FILES/telegraf_env.cfg.tmpl > $PRODUCT_DIR/telegraf/plugins/config/env.cfg

   sed -e "s#{{GRAFANA_SMTP_HOST}}#$GRAFANA_SMTP_HOST#" \
       -e "s#{{GRAFANA_SMTP_PORT}}#$GRAFANA_SMTP_PORT#" \
       -e "s#{{TELEGRAF_MAIL_FROM}}#$TELEGRAF_MAIL_FROM#" \
       -e "s#{{TELEGRAF_RECIPIENTS_LIST}}#$TELEGRAF_RECIPIENTS_LIST#" $INSTALL_FILES/telegraf_mail_notifications.cfg.tmpl > $PRODUCT_DIR/telegraf/plugins/config/mail_notifications.cfg

fi

$PRODUCT_DIR/scripts/telegraf.sh start
}
######################### Install Telegraf ################################

######################### End of functions ################################
create_infra

######################### Install certificates ############################
if [ ! -f $PRODUCT_DIR/ssl/${HELIX_MONITOR_HOST}.crt ] || [ ! -f $PRODUCT_DIR/ssl/${HELIX_MONITOR_HOST}.key ]
 then
   echo "HTTPS certificates are missing, creating them"
   create_https_certs "$HELIX_MONITOR_HOST" $PRODUCT_DIR/ssl 
 else
   echo "HTTPS certificates already exist, skipping creating them."
fi

######################### Install Python ##################################
if [ -d $PRODUCT_DIR/python ] && [ ! -z "$(ls -A $PRODUCT_DIR/python)" ]
  then
    [ "$FORCE_PYTHON" == "true" ] && echo "Reinstalling Python"
    [ "$UPGRADE_PYTHON" == "true" ]  && echo "Upgrading Python"
  else 
    FORCE_PYTHON="true"
    UPGRADE_PYTHON="false"
    echo "Installing Python"
fi

if [ "$FORCE_PYTHON" == "true" ] || [ "$UPGRADE_PYTHON" == "true" ]
  then
    install_python   
  else
    echo "Python directory is not empty, skipping installation."
fi
echo ""

######################### Install Telegraf ################################
if [ -d $PRODUCT_DIR/telegraf ] && [ ! -z "$(ls -A $PRODUCT_DIR/telegraf)" ]
  then
    [ "$FORCE_TELEGRAF" == "true" ] && echo "Reinstalling Telegraf"
    [ "$UPGRADE_TELEGRAF" == "true" ] && echo "Upgrading Telegraf"
  else 
    FORCE_TELEGRAF="true"
    UPGRADE_TELEGRAF="false"
    echo "Installing Telegraf"
fi

if [ "$FORCE_TELEGRAF" == "true" ] || [ "$UPGRADE_TELEGRAF" == "true" ]
  then
    install_telegraf
    if [ "$UPGRADE_TELEGRAF" != "true" ] 
      then 
        # Cenerate logrotate config file and crontab record if needed
        echo -e "$PRODUCT_DIR/telegraf/var/log/telegraf/* {\n\tdaily\n\trotate 7\n\tmissingok\n\tdateext\n\tcopytruncate\nnotifempty\n\tcompress\n}" > $PRODUCT_DIR/telegraf/etc/logrotate.d/telegraf
        if [ "$TELEGRAF_LOGROTATE" == "Y" ]
          then
            TMPCRON=`mktemp -p $PRODUCT_DIR/tmp`
            crontab -l 2>/dev/null > $TMPCRON
            grep -q "logrotate.*telegraf" $TMPCRON
            if [ $? -ne 0 ] 
              then
                echo -e "\nAdding Telegraf log rotation to user crontab file"
                echo -e "# Log rotation for Telegraf\n0 0 * * * /usr/sbin/logrotate -s $PRODUCT_DIR/telegraf/var/logrotate.state $PRODUCT_DIR/telegraf/etc/logrotate.d/telegraf" >> $TMPCRON
                crontab $TMPCRON
                if [ $? -ne 0 ] 
                  then 
                    echo "[WARNING] It seems you are not allowed to use cron. Please check /etc/cron.allow"
                    echo -e "[WARNING] Fix the issue and add the following line to user crontab file:\n0 0 * * * /usr/sbin/logrotate -s $PRODUCT_DIR/telegraf/var/logrotate.state $PRODUCT_DIR/telegraf/etc/logrotate.d/telegraf"
                fi
            fi
          else 
            echo -e "[INFO] In order to rotate Telegraf log file you can add the following line to user crontab file:\n0 0 * * * /usr/sbin/logrotate -s $PRODUCT_DIR/telegraf/var/logrotate.state $PRODUCT_DIR/telegraf/etc/logrotate.d/telegraf"
        fi 
        rm -f $TMPCRON
        echo -e "\n"
    fi
  else
    echo "Telegraf directory is not empty, skipping Telegraf installation." 
fi
######################### Install InfluxDB ################################
if [ -d $PRODUCT_DIR/influxdb ] && [ ! -z "$(ls -A $PRODUCT_DIR/influxdb)" ]
  then
    [ "$FORCE_INFLUX" == "true" ] && echo "Reinstalling InfluxDB"
    [ "$UPGRADE_INFLUXDB" == "true" ] && echo "Upgrading InfluxDB"
  else 
    FORCE_INFLUX="true"
    UPGRADE_INFLUXDB="false"
    echo "Installing InfluxDB"
fi

if [ "$FORCE_INFLUX" == "true" ] || [ "$UPGRADE_INFLUXDB" == "true" ]
  then
    install_influxdb
    if [ "$UPGRADE_INFLUXDB" != "true" ] 
      then 
        configure_influxdb
        # Cenerate logrotate config file and crontab record if needed
        echo -e "$PRODUCT_DIR/influxdb/var/log/influxdb/* {\n\tdaily\n\trotate 7\n\tmissingok\n\tdateext\n\tcopytruncate\n\tcompress\n}" > $PRODUCT_DIR/influxdb/etc/logrotate.d/influxdb
        if [ "$INFLUXDB_LOGROTATE" == "Y" ]
          then
            TMPCRON=`mktemp -p $PRODUCT_DIR/tmp`
            crontab -l 2>/dev/null > $TMPCRON
            grep -q "logrotate.*influxdb" $TMPCRON
            if [ $? -ne 0 ] 
              then
                echo -e "\nAdding InfluxDB log rotation to user crontab file"
                echo -e "# Log rotation for InfluxDB\n0 0 * * * /usr/sbin/logrotate -s $PRODUCT_DIR/influxdb/var/logrotate.state $PRODUCT_DIR/influxdb/etc/logrotate.d/influxdb" >> $TMPCRON
                crontab $TMPCRON
                if [ $? -ne 0 ] 
                  then 
                    echo "[WARNING] It seems you are not allowed to use cron. Please check /etc/cron.allow"
                    echo -e "[WARNING] Fix the issue and add the following line to user crontab file:\n0 0 * * * /usr/sbin/logrotate -s $PRODUCT_DIR/influxdb/var/logrotate.state $PRODUCT_DIR/influxdb/etc/logrotate.d/influxdb"
                fi
            fi
          else 
            echo -e "[INFO] In order to rotate InfluxDB log file you can add the following line to user crontab file:\n0 0 * * * /usr/sbin/logrotate -s $PRODUCT_DIR/influxdb/var/logrotate.state $PRODUCT_DIR/influxdb/etc/logrotate.d/influxdb"
        fi 
        rm -f $TMPCRON
        echo -e "\n"
    fi
  else
    echo "InfluxDB directory is not empty, skipping InfluxDB installation." 
fi

######################### Install Grafana #################################
if [ -d $PRODUCT_DIR/grafana ] && [ ! -z "$(ls -A $PRODUCT_DIR/grafana)" ]
  then
    [ "$FORCE_GRAFANA" == "true" ] && echo "Reinstalling Grafana"
    [ "$UPGRADE_GRAFANA" == "true" ]  && echo "Upgrading Grafana"
  else 
    FORCE_GRAFANA="true"
    UPGRADE_GRAFANA="false"
    echo "Installing Grafana"
fi

if [ "$FORCE_GRAFANA" == "true" ] || [ "$UPGRADE_GRAFANA" == "true" ]
  then
    install_grafana
    [ "$UPGRADE_GRAFANA" != "true" ] && configure_grafana
  else
    echo "Grafana directory is not empty, skipping Grafana installation."
fi

echo -e "\nInstalled products:"
$PRODUCT_DIR/influxdb/usr/bin/influx -version
$PRODUCT_DIR/grafana/bin/grafana-cli -v
$PRODUCT_DIR/telegraf/usr/bin/telegraf --version
