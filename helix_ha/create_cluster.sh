################################## On all nodes #################################
# Add Centos repo to RHEL, not needed for CentOS itself
cat <<'EOF'>>/etc/yum.repos.d/centos7base.repo
[centos-7-base]
name=CentOS-$releasever - Base
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infra
baseurl=http://mirror.mirohost.net/centos/7/os/$basearch/
gpgcheck=1
gpgkey=http://mirror.mirohost.net/centos/RPM-GPG-KEY-CentOS-7
EOF
# Install
yum -y install resource-agents pacemaker pcs  psmisc policycoreutils-python corosync

# Enable
systemctl enable pcsd
systemctl enable corosync
systemctl enable pacemaker

# Start
systemctl start pcsd

# Open firewall
firewall-cmd --permanent --add-service=high-availability
firewall-cmd --add-service=high-availability

# Set password for cluster user
passwd hacluster

###############################END On all nodes #################################

# On any one node
pcs cluster auth pcs-med1-node1 pcs-med1-node2 pcs-web-node1 pcs-web-node2 -u hacluster
pcs cluster setup --name HELIX pcs-med1-node1 pcs-med1-node2 pcs-web-node1 pcs-web-node2

# Enable and start all if needed
pcs cluster enable --all
pcs cluster start --all

# Check cluster
pcs status

# Disable for one node cluster 
# or for multi node cluster until fence devices are configured
pcs property set stonith-enabled=false

# Disable for one node cluster 
pcs property set no-quorum-policy=ignore

# This allows resource to be restarted if failed to start
pcs property set start-failure-is-fatal=false

#Check modified properties
pcs property list

#This is needed to restart 10 time if resource failed to start
#Probably should be decreased to 2 for j2ee resources as they start for a long time
pcs resource defaults migration-threshold=10
#This allows a resource to be back to node with last fail after 300s (depending on stickness and constraints)
#Be careful - if resource was moved and has stickness, it will be back after this timeout
pcs resource defaults failure-timeout=300s
#Check modified defaults
pcs resource defaults
