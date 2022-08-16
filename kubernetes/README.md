## Install kubernetes

demo
```shell
./install_k8s.sh -s 10.10.13.87
```

when u run over , you could got a k8s cluster installed by kind.


## Install istio and solarmesh

demo

```shell
./install_solarmesh_demo.sh -v 1.12 -k "/home/ctg/.kube/config"
```

when u run over, you could got a istio and solarmesh .

```shell
kubectl patch svc -n istio-system istio-ingressgateway -p '{"spec":{"externalIPs":["10.10.13.87"]}}'
```
