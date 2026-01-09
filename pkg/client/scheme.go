package client

import (
	fluxcdkustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
	operatorv1alpha1 "github.com/gardener/gardener/pkg/apis/operator/v1alpha1"
	resourcesv1alpha1 "github.com/gardener/gardener/pkg/apis/resources/v1alpha1"
	apiextensionsinstall "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/install"
	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	kubernetesscheme "k8s.io/client-go/kubernetes/scheme"
)

var (
	// ClusterScheme is the scheme used in garden runtime and unmanaged seed clusters.
	ClusterScheme = runtime.NewScheme()
)

func init() {
	clusterSchemeBuilder := runtime.NewSchemeBuilder(
		kubernetesscheme.AddToScheme,
		operatorv1alpha1.AddToScheme,
		resourcesv1alpha1.AddToScheme,
		fluxcdkustomizev1.AddToScheme,
	)

	utilruntime.Must(clusterSchemeBuilder.AddToScheme(ClusterScheme))
	apiextensionsinstall.Install(ClusterScheme)
}
