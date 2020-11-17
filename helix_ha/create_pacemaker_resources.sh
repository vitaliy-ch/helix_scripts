#!/bin/bash
N2_COMMON="N2RNS:n2_multi_router_parent:N2
MED2:med2_parent:N2RNS
SP:sp_parent:MED2
GD:gd_core_parent:MED2
DVX2:dvx2_parent:GD
SECINF:sec_inf_parent:MED2
N2P:n2p_parent:MED2
N2P_Scheduler:n2_scheduler_parent:N2P
MS:ms_parent:MED2
PMM2:pmm_parent:MED2
PMM2_kpi:kpi_generator_parent:PMM2
EZSPMM2:ezspmm2_parent:MED2
EZS:ezs_parent:MED2
NCI2:nci2_parent:MED2
SNMP_AGENT:snmp_agent_parent_all:MED2
FAM_SERVICES:fam_api_parent:MED2
EASY_PM:easy_pm_parent:MED2
TG:tg_parent:MED2
NCI2_PerHost:nci2_services_parent_per_host:MED2
AD_AGENT:ad_agent_parent:MED2"

EARS="HelixConsole
PM
FE-FH
FamCache1
FM
IMPORT
VIEWS
"
delete_infra() {
pcs resource delete WebIP
pcs resource delete Med1IP
pcs resource delete web_teoco
pcs resource delete web_arsystem
pcs resource delete web_oracle
pcs resource delete med1_teoco
pcs resource delete med1_oracle
}

delete_helix() {
pcs resource delete N2
for i in $N2_COMMON; 
do 
  service_name=`echo $i|cut -d: -f1`
  pcs resource delete $service_name
done
pcs resource delete apache
pcs resource delete wls_admin
pcs resource delete nginx
pcs resource delete remedy
for i in $EARS
do
 pcs resource delete $i
done
pcs resource delete boe
pcs resource delete tomcat

}

create_infra() {
# VIPs
pcs resource create Web1IP ocf:heartbeat:IPaddr2 ip=192.168.253.233 cidr_netmask=32 op monitor interval=30s op stop on-fail=stop --group web1_infra --disabled
pcs resource create Med1IP ocf:heartbeat:IPaddr2 ip=192.168.253.234 cidr_netmask=32 op monitor interval=30s op stop on-fail=stop --group med1_infra --disabled

# Colocate resources
pcs constraint location web1_infra avoids pcs-med1-node1 pcs-med1-node2
pcs constraint location med1_infra avoids pcs-web-node1 pcs-web-node2

pcs resource enable Web1IP
pcs resource enable Med1IP

# NFS
pcs resource create web1_teoco ocf:heartbeat:Filesystem device="192.168.253.162:/teoco/web/teoco" directory="/teoco" fstype="nfs4" fast_stop="no" force_unmount="safe" op stop on-fail=stop timeout=200 op monitor on-fail=stop timeout=200 --group web1_infra
pcs resource create web1_arsystem ocf:heartbeat:Filesystem device="192.168.253.162:/teoco/web/arsystem" directory="/etc/arsystem" fstype="nfs4" fast_stop="no" force_unmount="safe" op stop on-fail=stop timeout=200 op monitor on-fail=stop timeout=200 --group web1_infra
pcs resource create web1_oracle ocf:heartbeat:Filesystem device="192.168.253.162:/teoco/oracle" directory="/OracleSoftware" fstype="nfs4" fast_stop="no" force_unmount="safe" op stop on-fail=stop timeout=200 op monitor on-fail=stop timeout=200 --group web1_infra
pcs resource create med1_teoco ocf:heartbeat:Filesystem device="192.168.253.162:/teoco/med1/teoco" directory="/teoco" fstype="nfs4" fast_stop="no" force_unmount="safe" op stop on-fail=stop timeout=200 op monitor on-fail=stop timeout=200 --group med1_infra
pcs resource create med1_oracle ocf:heartbeat:Filesystem device="192.168.253.162:/teoco/oracle" directory="/OracleSoftware" fstype="nfs4" fast_stop="no" force_unmount="safe" op stop on-fail=stop timeout=200 op monitor on-fail=stop timeout=200 --group med1_infra
}

create_helix() {
# N2
pcs resource create N2 systemd:helix_n2_parent op stop on-fail=stop --group helix_med1 --disabled

# Constraints
pcs constraint colocation add helix_med1 with med1_infra
pcs constraint order med1_infra then helix_med1

for i in $N2_COMMON
do 
  service_name=`echo $i|cut -d: -f1`
  parent_name=`echo $i|cut -d: -f2`
  depends=`echo $i|cut -d: -f3`
  pcs resource create $service_name systemd:helix_n2_common@$parent_name op stop on-fail=stop --group helix_med1 --disabled
done

# Apache
pcs resource create apache systemd:helix_apache meta ordered=false --disabled
# Constraints for Apache
pcs constraint colocation add apache with web1_infra
pcs constraint order web1_infra then apache

# Weblogic
pcs resource create wls_admin systemd:helix_wls_admin meta ordered=false op start timeout=600s op stop timeout=300s on-fail=stop --disabled
# Constraints for Weblogic
pcs constraint colocation add wls_admin with web1_infra
pcs constraint order web1_infra then wls_admin

for i in $EARS
do
  pcs resource create $i systemd:helix_system@$i meta ordered=false --group helix_web1 op start timeout=600s op stop timeout=300s on-fail=stop --disabled
done
pcs resource meta helix_web1 ordered=false
# Constraints for ears
pcs constraint colocation add helix_web1 with wls_admin
pcs constraint order wls_admin then helix_web1

# Remedy
pcs resource create remedy systemd:helix_remedy meta ordered=false op start timeout=600s stop timeout=300s on-fail=stop --disabled
# Constraints for Remedy
pcs constraint colocation add remedy with web1_infra
pcs constraint order web1_infra then remedy

# BOE
pcs resource create boe systemd:helix_boe --group helix_boe op start timeout=600s stop timeout=300s on-fail=stop --disabled
pcs resource create tomcat systemd:helix_tomcat --group helix_boe op start timeout=120s stop timeout=120s on-fail=stop --disabled
pcs resource meta helix_boe ordered=false
# Constraints for BOE
pcs constraint colocation add helix_boe with web1_infra
pcs constraint order web1_infra then helix_boe

# Nginx
pcs resource create nginx systemd:helix_nginx meta ordered=false op start timeout=120s op stop timeout=120s on-fail=stop --disabled
# Constraints for Nginx
pcs constraint colocation add nginx with web1_infra
pcs constraint order web1_infra then nginx
}

enable_helix(){
pcs resource enable apache wls_admin remedy nginx boe tomcat
pcs resource enable N2
for i in $N2_COMMON; 
do 
  service_name=`echo $i|cut -d: -f1`
  pcs resource enable $service_name
done
for i in $EARS
do
 pcs resource enable $i
done
}

enable_fencing() {
# Configure Proxmox fencing
# fence_pve port is a number of VM in Proxmox cluster
# ipaddr is an address of any Proxmox node
# node_name is a Proxmox node where VM is running
# pcmk_host_list is a pacemaker node name which will be fenced
pcs stonith create fence-web-node1 fence_pve port="175" pcmk_host_list="pcs-web-node1" ipaddr="192.168.253.24" login="fence_agent@pve" passwd="qwer90" pcmk_off_action="off" pcmk_reboot_action="reboot" pcmk_host_check="static-list" vmtype="qemu" node_name="rf-pmx-node1"
pcs stonith create fence-med1-node1 fence_pve port="176" pcmk_host_list="pcs-med1-node1" ipaddr="192.168.253.24" login="fence_agent@pve" passwd="qwer90" pcmk_off_action="off" pcmk_reboot_action="reboot" pcmk_host_check="static-list" vmtype="qemu" node_name="rf-pmx-node1"
pcs stonith create fence-web-node2 fence_pve port="173" pcmk_host_list="pcs-web-node2" ipaddr="192.168.253.24" login="fence_agent@pve" passwd="qwer90" pcmk_off_action="off" pcmk_reboot_action="reboot" pcmk_host_check="static-list" vmtype="qemu" node_name="rf-pmx-node2"
pcs stonith create fence-med1-node2 fence_pve port="174" pcmk_host_list="pcs-med1-node2" ipaddr="192.168.253.24" login="fence_agent@pve" passwd="qwer90" pcmk_off_action="off" pcmk_reboot_action="reboot" pcmk_host_check="static-list" vmtype="qemu" node_name="rf-pmx-node2"

# Enable stonith
pcs property set stonith-enabled=true
}

case $1 in
	--dh) delete_helix
            ;;
	--ch) create_helix
            ;;
	--di) delete_infra
            ;;
	--ci) create_infra
            ;;
	--eh) enable_helix
            ;;
	*)  exit
            ;;
esac
