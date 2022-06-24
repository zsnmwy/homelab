#!/usr/bin/env bash
cloud-init status --wait > /tmp/wait

IP=$(ip -j -p a | jq  '.[].addr_info | .[] | select(.label == "ens192") | .local' | cut -d '"' -f2)

hostnamectl set-hostname "ubuntu-$(echo $IP | tr '.' '-')"

modprobe overlay
modprobe br_netfilter
sysctl --system

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i s/'SystemdCgroup = false'/'SystemdCgroup = true'/ /etc/containerd/config.toml
sed -i s/'k8s.gcr.io'/'k8s-gcr.m.daocloud.io'/ /etc/containerd/config.toml
sed -i 's/config_path = ""/config_path = "\/etc\/containerd\/certs.d"/' /etc/containerd/config.toml

systemctl restart containerd

# containerd mirror
mkdir -p /etc/containerd/certs.d/docker.io
cat<<EOF>/etc/containerd/certs.d/docker.io/hosts.toml
server = "https://docker.io"

[host."http://192.168.1.202:5000"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF

mkdir -p /etc/containerd/certs.d/k8s.gcr.io
cat<<EOF>/etc/containerd/certs.d/k8s.gcr.io/hosts.toml
server = "https://k8s.gcr.io"

[host."https://k8s.dockerproxy.com"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF

mkdir -p /etc/containerd/certs.d/registry.aliyuncs.com
cat<<EOF>/etc/containerd/certs.d/registry.aliyuncs.com/hosts.toml
server = "https://registry.aliyuncs.com"

[host."http://192.168.1.202:5001"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF

mkdir -p /etc/containerd/certs.d/gcr.io
cat<<EOF>/etc/containerd/certs.d/gcr.io/hosts.toml
server = "https://gcr.io"

[host."https://gcr.dockerproxy.com"]
  capabilities = ["pull", "resolve"]
EOF

mkdir -p /etc/containerd/certs.d/quay.io
cat<<EOF>/etc/containerd/certs.d/quay.io/hosts.toml
server = "https://quay.io"

[host."https://quay.dockerproxy.com"]
  capabilities = ["pull", "resolve"]
EOF
