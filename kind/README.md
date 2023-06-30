# 使用Kind安装k8s集群

kind 依赖docker ，使用 kind 前需要安装好 docker。

### 卸载docker

查询安装docker的文件包

```shell
yum list installed | grep docker
```

删除所有安装docker的文件包
```shell
yum -y remove '包名'
```

### 安装docker

```shell
sudo yum -y update
sudo yum install -y yum-utils  
sudo yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sudo yum -y install docker-ce-20.10.21 docker-ce-cli-20.10.21 containerd.io docker-compose-plugin
```

启动Docker并设置为开机启动
```shell
sudo systemctl start docker
sudo systemctl enable docker
```

### 获取kubelet

```shell
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

```shell
chmod +x kubectl && cp kubectl /usr/local/bin/
```

### 关闭防火墙
很多坑都是防火墙没关闭
```shell
systemctl stop firewalld
systemctl disable firewalld
```

### 指定k8s版本进行安装

```shell
kind create cluster  --image kindest/node:v1.23.6
```

### 指定配置文件安装

如配置文件内容 kind-config 为：$SERVER 为你当前节点ip

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.cloud2go.cn"]
    endpoint = ["http://harbor.cloud2go.cn"]
networking:
  apiServerAddress: $SERVER
  apiServerPort: 6443
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
        authorization-mode: "AlwaysAllow"
  extraPortMappings:
  - containerPort: 80
    hostPort: 20080
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 7575
    hostPort: 7575
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 9090
    hostPort: 9090
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 20001
    hostPort: 20001
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 15443
    hostPort: 15443
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30080
    hostPort: 30080
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30066
    hostPort: 30066
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 35672
    hostPort: 35672
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30880
    hostPort: 30880
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30201
    hostPort: 30201
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30202
    hostPort: 30202
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30203
    hostPort: 30203
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30204
    hostPort: 30204
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30205
    hostPort: 30205
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
```

执行安装：

```shell
kind create cluster  --image kindest/node:v1.23.6  --config kind-config.yaml
```

### HA部署

参考： https://blog.devstream.io/posts/%E7%94%A8kind%E9%83%A8%E7%BD%B2k8s%E7%8E%AF%E5%A2%83/

