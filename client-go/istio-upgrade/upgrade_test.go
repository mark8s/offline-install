package test

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/c4milo/unpackit"
	"io"
	"istio.io/istio/operator/pkg/apis/istio/v1alpha1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
	log "k8s.io/klog/v2"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sigs.k8s.io/yaml"
	"testing"
)

//go test -v -run TestUpgradeGw upgrade_test.go
func TestUpgradeGw(t *testing.T) {
	log.Info("Ready to upgrade Gateway.")
	var kubeconfig *string
	if home := homedir.HomeDir(); home != "" {
		kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"), "(optional) absolute path to the kubeconfig file")
	} else {
		kubeconfig = flag.String("kubeconfig", "", "absolute path to the kubeconfig file")
	}
	config, _ := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err)
	}

	list, err := clientset.AppsV1().Deployments("istio-system").List(context.TODO(), metav1.ListOptions{LabelSelector: "istio=ingressgateway"})
	if err != nil {
		log.Error(err)
	} else {
		for _, gw := range list.Items {
			labels := gw.Spec.Template.Labels
			labels["istio.io/rev"] = "1-15-1"
			gw.Spec.Template.Labels = labels

			update, err := clientset.AppsV1().Deployments("istio-system").Update(context.TODO(), &gw, metav1.UpdateOptions{})
			if err != nil {
				log.Error("%s upgrade istio-ingressgateway failed： %v", update.Name, err)
			}
		}
	}

	list, err = clientset.AppsV1().Deployments("istio-system").List(context.TODO(), metav1.ListOptions{LabelSelector: "istio=egressgateway"})
	if err != nil {
		log.Error(err)
	} else {
		for _, gw := range list.Items {
			labels := gw.Spec.Template.Labels
			labels["istio.io/rev"] = "1-15-1"
			gw.Spec.Template.Labels = labels

			update, err := clientset.AppsV1().Deployments("istio-system").Update(context.TODO(), &gw, metav1.UpdateOptions{})
			if err != nil {
				log.Error("%s upgrade istio-egressgateway failed： %v", update.Name, err)
			}
		}
	}
}

// go test -v -run TestUninstall upgrade_test.go
func TestUninstall(t *testing.T) {
	cmd := exec.Command("./istioctl", "uninstall", "--revision", "1-15-1", "--kubeconfig", "kconf.yml", "-y")
	commandOutPut(cmd)
}

// go test -v -run TestUpgrade upgrade_test.go
func TestUpgrade(t *testing.T) {
	istioctlUrl := "https://ghproxy.com/https://github.com/istio/istio/releases/download/1.15.1/istioctl-1.15.1-linux-amd64.tar.gz"
	res, err := http.Get(istioctlUrl)
	err = unpackit.Unpack(res.Body, "/root/test")
	if err != nil {
		panic(err)
	}
	step()
	cmd := exec.Command("./istioctl", "install", "--set", "revision=1-15-1", "--set", "tag=1.15.1", "--set", "components.ingressGateways[name:istio-ingressgateway].enabled=false", "--set", "components.egressGateways[name:istio-egressgateway].enabled=false", "-f", "installed-state.yml", "-y")
	commandOutPut(cmd)
}

func commandOutPut(cmd *exec.Cmd) {
	out, err := cmd.StdoutPipe()
	if err != nil {
		return
	}
	defer out.Close()
	// 命令的错误输出和标准输出都连接到同一个管道
	cmd.Stderr = cmd.Stdout

	if err = cmd.Start(); err != nil {
		return
	}
	buff := make([]byte, 8)

	var result []string
	for {
		len, err := out.Read(buff)
		if err == io.EOF {
			break
		}
		result = append(result, string(buff[:len]))
	}
	cmd.Wait()
	for _, str := range result {
		fmt.Print(str)
	}
	fmt.Println()
}

func step() {
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

	istioOperators := istioOperatorlist.Items
	for _, io := range istioOperators {
		ymlName := fmt.Sprintf("%s.yml", io.Name)
		io.ResourceVersion = ""
		io.Annotations = nil
		io.ManagedFields = nil
		io.Name = ""
		io.UID = ""
		resJson, _ := json.Marshal(io)
		yml, err := yaml.JSONToYAML(resJson)

		if err != nil {
			log.Error(err)
			return
		}
		//fmt.Println(string(yml))
		f, _ := os.Create(filepath.Join(".", ymlName))
		_, _ = f.WriteString(string(yml))
	}
}
