#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes) on CentOS

set -euxo pipefail

# Kubernetes Variable Declaration
KUBERNETES_VERSION="v1.30"
CRIO_VERSION="v1.30"
KUBERNETES_INSTALL_VERSION="1.30.0-1.1"

# Disable swap
sudo swapoff -a

# Keeps the swap off during reboot
sudo sed -i '/swap/d' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl params
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Install dependencies
sudo yum install -y yum-utils epel-release

# Install CRI-O Runtime
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo=https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/rpm/

sudo yum install -y cri-o

sudo systemctl daemon-reload
sudo systemctl enable crio --now
sudo systemctl start crio

echo "CRI runtime installed successfully"

# Install kubelet, kubeadm, and kubectl
sudo yum-config-manager --add-repo=https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/rpm/

sudo yum install -y kubelet-$KUBERNETES_INSTALL_VERSION kubeadm-$KUBERNETES_INSTALL_VERSION kubectl-$KUBERNETES_INSTALL_VERSION

# Prevent automatic updates for kubelet, kubeadm, and kubectl
echo "exclude=kubelet kubeadm kubectl" | sudo tee -a /etc/yum.conf

sudo systemctl enable kubelet --now

# Install jq, a command-line JSON processor
sudo yum install -y jq

# Retrieve the local IP address dynamically
local_ip=$(ip -json addr show | jq -r '.[] | .addr_info[] | select(.family == "inet" and .local != "127.0.0.1") | .local' | head -n1)

# Check if local_ip is empty (failsafe)
if [[ -z "$local_ip" ]]; then
    echo "Error: Could not determine local IP address."
    exit 1
fi

# Write the local IP address to the kubelet default configuration file
cat > /etc/sysconfig/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF
