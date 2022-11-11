# client-go 日常记录

#### 获取 自定义CRD
使用 dynamicClient
```go
    var kubeconfig *string
	if home := homedir.HomeDir(); home != "" {
		kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"), "(optional) absolute path to the kubeconfig file")
	} else {
		kubeconfig = flag.String("kubeconfig", "", "absolute path to the kubeconfig file")
	}

	config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		panic(err)
	}
	client, err := dynamic.NewForConfig(config)
	if err != nil {
		panic(err)
	}

	// install.istio.io/v1alpha1
	resource := schema.GroupVersionResource{Group: "install.istio.io", Version: "v1alpha1", Resource: "istiooperators"}

	unstructuredList, err := client.Resource(resource).Namespace("istio-system").List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		panic(err)
	}
	istioOperatorlist := &v1alpha1.IstioOperatorList{}

	err = runtime.DefaultUnstructuredConverter.FromUnstructured(unstructuredList.UnstructuredContent(), istioOperatorlist)
    
```

####

k8s 对象 转 yaml（先转json，再转yaml）
```go
    istioOperators := istioOperatorlist.Items
	for _, io := range istioOperators {
		// 先转 json
		resJson,_ := json.Marshal(io)
		// 再转 yaml
		yml,err := yaml.JSONToYAML(resJson)
		if err != nil {
			log.Error(err)
			return
		}
		fmt.Println(string(yml))
	}
```
结果：

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  creationTimestamp: "2022-10-26T07:17:50Z"
  generation: 1
  managedFields:
  - apiVersion: install.istio.io/v1alpha1
    fieldsType: FieldsV1
    fieldsV1:
      f:metadata:
        f:annotations:
          .: {}
          f:install.istio.io/ignoreReconcile: {}
          f:kubectl.kubernetes.io/last-applied-configuration: {}
      f:spec:
        .: {}
        f:components:
          .: {}
          f:base:
            .: {}
...
```

####


