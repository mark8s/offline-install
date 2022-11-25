# Customizing Istio Metrics


## Create metrics and dim by IstioOperator

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: demo
  namespace: istio-system
spec:
  profile: default
  meshConfig:
    accessLogFile: /dev/stdout
    enableTracing: true
    defaultConfig:
      proxyMetadata:
        ISTIO_META_DNS_CAPTURE: "true"
        ISTIO_META_DNS_AUTO_ALLOCATE: "true"
      proxyStatsMatcher:
        inclusionPrefixes:
          - solarmesh
      extraStatTags:
        - istio_version  
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster1
      network: network1
      tracer:
        zipkin:
          address: jaeger.jaeger-infra:9411
    telemetry:
      enabled: true
      v2:
        enabled: true
        prometheus:
          configOverride:
            inboundSidecar:
              definitions:
                - name: solarmesh_requests_total
                  type: "COUNTER"
                  value: "1"
              metrics:
                - name: solarmesh_requests_total
                  dimensions:
                    istio_version: downstream_peer.istio_version
            outboundSidecar:
              definitions:
                - name: solarmesh_requests_total
                  type: "COUNTER"
                  value: "1"
              metrics:
                - name: solarmesh_requests_total
                  dimensions:
                    istio_version: upstream_peer.istio_version
```

prometheus:

```shell
istio_solarmesh_requests_total{app="reviews", instance="10.244.0.27:15020", istio_version="1.12.9", job="kubernetes-pods", kubernetes_namespace="bookinfo", kubernetes_pod_name="reviews-v3-665945dd6f-62d9c", pod_template_hash="665945dd6f", security_istio_io_tlsMode="istio", service_istio_io_canonical_name="reviews", service_istio_io_canonical_revision="v3", topology_istio_io_network="network1", version="v3"}
```

貌似这种方式添加指标和维度，只支持 istio 1.12 及以上。当使用 istio 1.11 的时候，只会创建metrcis，但是metrics中自定义的维度dimensions无法创建成功。

reference: https://github.com/istio/istio/issues/42145

## Create metrics by EnvoyFilter

```
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: solarmesh-request-total
  namespace: istio-system
  labels:
    istio.io/rev: default
spec:
  priority: -1
  configPatches:
  ## Sidecar Inbound 
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_OUTBOUND
      listener:
        filterChain:
          filter:
            name: envoy.filters.network.http_connection_manager
            subFilter:
              name: envoy.filters.http.router
      proxy:
        proxyVersion: ^1\.11.*
    patch:
      operation: INSERT_BEFORE
      value:
        name: istio.stats
        typed_config:
          '@type': type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
          value:
            config:
              configuration:
                '@type': type.googleapis.com/google.protobuf.StringValue
                value: |
                  {
                    "debug": "false",
                    "stat_prefix": "istio",
                    "definitions": [
                      {
                        "name": "solarmesh_requests_total",
                        "type": "COUNTER",
                        "value": "1"                      
                      }
                    ],
                    "metrics": [
                      { 
                        "name": "solarmesh_requests_total",
                        "dimensions": {
                          "istio_version": "upstream_peer.istio_version"
                        }
                      }                    
                    ]
                  }
              root_id: stats_outbound
              vm_config:
                code:
                  local:
                    inline_string: envoy.wasm.stats
                runtime: envoy.wasm.runtime.null
                vm_id: stats_outbound
```
istio configmap:

```
apiVersion: v1
data:
  mesh: |-
    defaultConfig:
      discoveryAddress: istiod.istio-system.svc:15012
      proxyMetadata: {}
      tracing:
        zipkin:
          address: zipkin.istio-system:9411
      proxyStatsMatcher:
        inclusionPrefixes:
          - solarmesh
      extraStatTags:
        - istio_version
    enablePrometheusMerge: true
    rootNamespace: istio-system
    trustDomain: cluster.local
  meshNetworks: 'networks: {}'
kind: ConfigMap
metadata:
  labels:
    install.operator.istio.io/owning-resource: unknown
    install.operator.istio.io/owning-resource-namespace: istio-system
    istio.io/rev: default
    operator.istio.io/component: Pilot
    operator.istio.io/managed: Reconcile
    operator.istio.io/version: 1.12.9
    release: istio
  name: istio
  namespace: istio-system
```


实践： istio 1.12 方可用

prometheus:

```yaml
istio_solarmesh_requests_total{app="productpage", instance="10.244.0.25:15020", istio_version="1.12.9", job="kubernetes-pods", kubernetes_namespace="bookinfo", kubernetes_pod_name="productpage-v1-df566bb97-qs7hb", pod_template_hash="df566bb97", security_istio_io_tlsMode="istio", service_istio_io_canonical_name="productpage", service_istio_io_canonical_revision="v1", version="v1"}
54
istio_solarmesh_requests_total{app="productpage", instance="10.244.0.25:15020", istio_version="unknown", job="kubernetes-pods", kubernetes_namespace="bookinfo", kubernetes_pod_name="productpage-v1-df566bb97-qs7hb", pod_template_hash="df566bb97", security_istio_io_tlsMode="istio", service_istio_io_canonical_name="productpage", service_istio_io_canonical_revision="v1", version="v1"}
3
istio_solarmesh_requests_total{app="reviews", instance="10.244.0.22:15020", istio_version="1.12.9", job="kubernetes-pods", kubernetes_namespace="bookinfo", kubernetes_pod_name="reviews-v2-6d578b5495-sjlgl", pod_template_hash="6d578b5495", security_istio_io_tlsMode="istio", service_istio_io_canonical_name="reviews", service_istio_io_canonical_revision="v2", version="v2"}
17
istio_solarmesh_requests_total{app="reviews", instance="10.244.0.27:15020", istio_version="1.12.9", job="kubernetes-pods", kubernetes_namespace="bookinfo", kubernetes_pod_name="reviews-v3-6d56c97485-24tr7", pod_template_hash="6d56c97485", security_istio_io_tlsMode="istio", service_istio_io_canonical_name="reviews", service_istio_io_canonical_revision="v3", version="v3"}
```

## Create new metrics 

enovyfilter:
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: create-new-envoy-metric-on-ratings
  namespace: bookinfo
spec:
  workloadSelector:
    labels:
      app: ratings
      version: v1
  configPatches:
  ## Sidecar Outbound 
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
      listener:
        filterChain:
          filter:
            name: envoy.filters.network.http_connection_manager
            subFilter:
              name: envoy.filters.http.router
      proxy:
        proxyVersion: ^1\.11.*
    patch:
      operation: INSERT_BEFORE
      value:
        name: istio.stats
        typed_config:
          '@type': type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
          value:
            config:
              configuration:
                '@type': type.googleapis.com/google.protobuf.StringValue
                value: |
                  {
                    "debug": "false",
                    "stat_prefix": "istio",
                    "definitions": [
                      {
                        "name": "solarmesh_metric",
                        "type": "COUNTER",
                        "value": "1"                      
                      }
                    ]
                  }
              root_id: stats_inbound
              vm_config:
                code:
                  local:
                    inline_string: envoy.wasm.stats
                runtime: envoy.wasm.runtime.null
                vm_id: stats_inbound
```

workload:

```yaml
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "true"
        sidecar.istio.io/statsInclusionPrefixes: istio_solarmesh_metric
      creationTimestamp: null
      labels:
        app: ratings
        version: v1
```

log:

```shell
$ kubectl exec -it -n bookinfo deploy/ratings-v1 -c istio-proxy -- curl localhost:15000/stats/prometheus | grep _metric
# TYPE istio_solarmesh_metric counter
istio_solarmesh_metric{} 92
```

## Modify the original index and increase the dimension

envoyfilter:

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: replace-stats-metric
  namespace: bookinfo
spec:
  workloadSelector:
    labels:
      app: productpage
  configPatches:
  ## Sidecar Outbound 
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_OUTBOUND
      listener:
        filterChain:
          filter:
            name: envoy.filters.network.http_connection_manager
            subFilter:
              name: istio.stats
      proxy:
        proxyVersion: ^1\.11.*
    patch:
      operation: REPLACE
      value:
        name: istio.stats
        typed_config:
          '@type': type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
          value:
            config:
              configuration:
                '@type': type.googleapis.com/google.protobuf.StringValue
                value: |
                  {
                    "debug": "false",
                    "stat_prefix": "istio",
                    "metrics": [
                      {
                        "name": "requests_total",
                        "dimensions": {
                          "destination_cluster": "node.metadata['CLUSTER_ID']",
                          "source_cluster": "downstream_peer.cluster_id"
                        },
                        "tags_to_remove": [
                          "connection_security_policy","destination_principal","job","pod_template_hash","security_istio_io_tlsMode","source_principal"
                        ]
                      },                    
                      {
                        "dimensions": {
                          "request_path": "request.path",
                          "request_url_path": "request.url_path"
                        }
                      }
                    ]
                  }
              root_id: stats_outbound
              vm_config:
                code:
                  local:
                    inline_string: envoy.wasm.stats
                runtime: envoy.wasm.runtime.null
                vm_id: stats_outbound
  ## Sidecar Inbound 
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
      listener:
        filterChain:
          filter:
            name: envoy.filters.network.http_connection_manager
            subFilter:
              name: istio.stats
      proxy:
        proxyVersion: ^1\.11.*
    patch:
      operation: REPLACE
      value:
        name: istio.stats
        typed_config:
          '@type': type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
          value:
            config:
              configuration:
                '@type': type.googleapis.com/google.protobuf.StringValue
                value: |
                  {
                    "debug": "false",
                    "stat_prefix": "istio",
                    "metrics": [
                      {
                        "name": "requests_total",
                        "dimensions": {
                          "destination_cluster": "node.metadata['CLUSTER_ID']",
                          "source_cluster": "downstream_peer.cluster_id"
                        },
                        "tags_to_remove": [
                          "connection_security_policy","destination_principal","job","pod_template_hash","security_istio_io_tlsMode","source_principal"       
                        ]
                      },                    
                      {
                        "dimensions": {
                          "request_path": "request.path",
                          "request_url_path": "request.url_path"       
                        }
                      }
                    ]
                  }                  
              root_id: stats_inbound
              vm_config:
                code:
                  local:
                    inline_string: envoy.wasm.stats
                runtime: envoy.wasm.runtime.null
                vm_id: stats_inbound
```

workload:

```yaml
template:
    metadata:
      annotations:
        sidecar.istio.io/extraStatTags: request.path,request.url_path
        sidecar.istio.io/inject: "true"
      creationTimestamp: null
      labels:
        app: productpage
        version: v1
```

log:

```shell
$ kubectl exec -it -n bookinfo deploy/productpage-v1 -c istio-proxy -- curl localhost:15000/stats/prometheus | grep istio_request_
istio_request_duration_milliseconds_sum{response_code="200",reporter="source",source_workload="productpage-v1",source_workload_namespace="bookinfo",source_principal="spiffe://cluster.local/ns/bookinfo/sa/bookinfo-productpage",source_app="productpage",source_version="v1",source_cluster="cluster1",destination_workload="reviews-v3",destination_workload_namespace="bookinfo",destination_principal="spiffe://cluster.local/ns/bookinfo/sa/bookinfo-reviews",destination_app="reviews",destination_version="v3",destination_service="reviews.bookinfo.svc.cluster.local",destination_service_name="reviews",destination_service_namespace="bookinfo",destination_cluster="cluster1",request_protocol="http",response_flags="-",grpc_response_status="",connection_security_policy="unknown",source_canonical_service="productpage",destination_canonical_service="reviews",source_canonical_revision="v1",destination_canonical_revision="v3",request_path="/reviews/0",request_url_path="/reviews/0"} 380.5

istio_request_duration_milliseconds_count{response_code="200",reporter="source",source_workload="productpage-v1",source_workload_namespace="bookinfo",source_principal="spiffe://cluster.local/ns/bookinfo/sa/bookinfo-productpage",source_app="productpage",source_version="v1",source_cluster="cluster1",destination_workload="reviews-v3",destination_workload_namespace="bookinfo",destination_principal="spiffe://cluster.local/ns/bookinfo/sa/bookinfo-reviews",destination_app="reviews",destination_version="v3",destination_service="reviews.bookinfo.svc.cluster.local",destination_service_name="reviews",destination_service_namespace="bookinfo",destination_cluster="cluster1",request_protocol="http",response_flags="-",grpc_response_status="",connection_security_policy="unknown",source_canonical_service="productpage",destination_canonical_service="reviews",source_canonical_revision="v1",destination_canonical_revision="v3",request_path="/reviews/0",request_url_path="/reviews/0"} 9

```


