# Customizing Istio Metrics


## Modify the original index and increase the dimension

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

## Create new metrics 

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


