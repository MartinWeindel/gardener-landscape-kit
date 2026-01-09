/*
 * SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package landscape

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path"
	"time"

	"github.com/Masterminds/semver/v3"
	fluxcdkustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
	"github.com/fluxcd/pkg/apis/meta"
	client2 "github.com/gardener/gardener-landscape-kit/pkg/client"
	v1beta1constants "github.com/gardener/gardener/pkg/apis/core/v1beta1/constants"
	"github.com/go-logr/logr"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"

	"sigs.k8s.io/controller-runtime/pkg/client"

	"strconv"
	"strings"
)

const (
	// TestE2EUseExistingEnv is name of the environment variable `TEST_E2E_USE_EXISTING_ENV`.
	// If set to true, no kind cluster(s) will be created or deleted, but reused from `make kind-up`.
	TestE2EUseExistingEnv = "TEST_E2E_USE_EXISTING_ENV"
)

// SuiteTestEnv is the test environment for the Landscape E2E tests
type SuiteTestEnv struct {
	DisableStateDump bool

	// GardenRuntimeClient is the Kubernetes client for the Garden runtime cluster.
	GardenRuntimeClient client.Client
	// GardenRuntimeVersion is the Kubernetes version of the Garden runtime cluster.
	GardenRuntimeVersion *semver.Version

	// Log is the logger of the test.
	Log logr.Logger

	workDir           string
	kindClusterPrefix string
}

// NewSuiteTestEnv creates a new SuiteTestEnv.
func NewSuiteTestEnv(process int) *SuiteTestEnv {
	te := &SuiteTestEnv{
		Log: GinkgoLogr,
	}
	te.workDir = te.getWorkDir()
	te.kindClusterPrefix = te.getKindClusterPrefix()
	return te
}

// CreateCluster starts git-server and creates cluster.
func (te *SuiteTestEnv) CreateCluster(ctx context.Context) {
	if !useExistingEnv() {
		// try cleanup first
		Expect(te.KindDown(ctx)).NotTo(HaveOccurred())
		Expect(te.KindUp(ctx)).NotTo(HaveOccurred())
	}
	te.initClient(ctx)
}

// useExistingEnv checks if env variable TEST_E2E_USE_EXISTING_ENV=true.
func useExistingEnv() bool {
	b, _ := strconv.ParseBool(os.Getenv(TestE2EUseExistingEnv))
	return b
}

func (te *SuiteTestEnv) initClient(ctx context.Context) {
	if useExistingEnv() {
		te.initExistingClient(ctx)
		return
	}

	te.GardenRuntimeClient, te.GardenRuntimeVersion = te.createAndCheckClientFromPart(ctx, "single")
}

func (te *SuiteTestEnv) initExistingClient(ctx context.Context) {
	cmd := exec.CommandContext(ctx, "make", "kind-kubeconfig")
	cmd.Dir = te.workDir
	cmd.Env = os.Environ()
	output, err := cmd.Output()
	Expect(err).NotTo(HaveOccurred())
	data := map[string]string{}
	err = json.Unmarshal(output, &data)
	Expect(err).NotTo(HaveOccurred())

	runtimeKubeconfig := data["runtime"]
	Expect(runtimeKubeconfig).NotTo(BeEmpty(), "runtime kubeconfig missing")

	te.GardenRuntimeClient, te.GardenRuntimeVersion = te.createAndCheckClientFromKubeconfig(ctx, runtimeKubeconfig)
}

func (te *SuiteTestEnv) VerifyFluxKustomization(ctx context.Context, namespace, name string, timeout ...time.Duration) {
	GinkgoHelper()

	defaultTimeout, err := time.ParseDuration(os.Getenv("GOMEGA_DEFAULT_EVENTUALLY_TIMEOUT"))
	if err != nil || defaultTimeout <= 10*time.Second {
		defaultTimeout = 30 * time.Second
	}
	timeoutDuration := defaultTimeout
	if len(timeout) > 0 {
		timeoutDuration = timeout[0]
	}

	ns := &corev1.Namespace{}
	err = te.GardenRuntimeClient.Get(ctx, client.ObjectKey{Name: namespace}, ns)
	Expect(err).NotTo(HaveOccurred(), "namespace %s not found", namespace)

	Eventually(func(g Gomega) {
		fluxKustomization := &fluxcdkustomizev1.Kustomization{}
		err = te.GardenRuntimeClient.Get(ctx, client.ObjectKey{Name: name, Namespace: namespace}, fluxKustomization)
		g.Expect(err).NotTo(HaveOccurred(), "kustomization %s/%s not found", namespace, name)

		g.Expect(fluxKustomization.Status.Conditions).NotTo(BeNil())
		FindConditionInList(g, fluxKustomization.Status.Conditions, meta.ReadyCondition, metav1.ConditionTrue, meta.ReconciliationSucceededReason)
	}).WithTimeout(timeoutDuration).Should(Succeed())
}

// FindConditionInList finds a condition in a list of Conditions, checking
// the Name, Value, and Reason. If an empty reason is passed, any Reason will match.
// If an empty status is passed, any Status will match.
func FindConditionInList(g Gomega, conditions []metav1.Condition, condName string, expectedStatus metav1.ConditionStatus, expectedReason string) {
	GinkgoHelper()

	for _, cond := range conditions {
		if cond.Type == condName {
			if expectedStatus != "" {
				g.Expect(cond.Status).To(Equal(expectedStatus), fmt.Sprintf("%s condition Status set to %s, expected %s", condName, cond.Status, expectedStatus))
			}
			if expectedReason != "" {
				g.Expect(cond.Reason).To(Equal(expectedReason), fmt.Sprintf("%s condition Reason set to %s, expected %s", condName, cond.Reason, expectedReason))
			}
			return
		}
	}

	g.Expect(false).To(BeTrue(), fmt.Sprintf("%s condition not found in conditions list [%v]", condName, conditions))
}

// VerifyGardenerOperatorDeployment verifies gardener-operator deployment is up and replicas are ready.
func (te *SuiteTestEnv) VerifyGardenerOperatorDeployment(ctx context.Context) {
	ns := &corev1.Namespace{}
	err := te.GardenRuntimeClient.Get(ctx, client.ObjectKey{Name: v1beta1constants.GardenNamespace}, ns)
	Expect(err).NotTo(HaveOccurred())

	Eventually(func(g Gomega) {
		deploy := &appsv1.Deployment{}
		err = te.GardenRuntimeClient.Get(ctx, client.ObjectKey{Name: v1beta1constants.DeploymentNameGardenerOperator, Namespace: v1beta1constants.GardenNamespace}, deploy)
		g.Expect(err).NotTo(HaveOccurred())

		g.Expect(int(deploy.Status.Replicas)).To(Equal(2))
		g.Expect(int(deploy.Status.ReadyReplicas)).To(Equal(2))
	}).WithTimeout(2 * time.Minute).WithPolling(2 * time.Second).Should(Succeed())
}

func (te *SuiteTestEnv) getWorkDir() string {
	workDir, err := os.Getwd()
	Expect(err).NotTo(HaveOccurred())
	if idx := strings.Index(workDir, "/test/e2e/"); idx > 0 {
		workDir = workDir[:idx]
	}
	if _, err := os.Stat(path.Join(workDir, "Makefile")); err != nil {
		Fail(fmt.Sprintf("must run in gardener-landscape-kit repository root: %s", err))
	}
	return workDir
}

func (te *SuiteTestEnv) createClientKubeconfig(part string) string {
	return path.Join(te.workDir, "dev", fmt.Sprintf("kind-%s-%s-kubeconfig.yaml", te.kindClusterPrefix, part))
}

func (te *SuiteTestEnv) createAndCheckClientFromPart(ctx context.Context, part string) (client.Client, *semver.Version) {
	kubeconfig := te.createClientKubeconfig(part)
	return te.createAndCheckClientFromKubeconfig(ctx, kubeconfig)
}

func (te *SuiteTestEnv) createAndCheckClientFromKubeconfig(ctx context.Context, kubeconfigPath string) (client.Client, *semver.Version) {
	clientConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
		&clientcmd.ClientConfigLoadingRules{ExplicitPath: kubeconfigPath},
		nil,
	)

	config, err := clientConfig.ClientConfig()
	Expect(err).ToNot(HaveOccurred())
	config.Burst = 300
	config.QPS = 50

	clientSet, err := kubernetes.NewForConfig(config)
	Expect(err).ToNot(HaveOccurred())
	serverVersion, err := clientSet.ServerVersion()
	Expect(err).ToNot(HaveOccurred())
	version, err := semver.NewVersion(serverVersion.GitVersion)
	Expect(err).ToNot(HaveOccurred())

	cl, err := client.New(config, client.Options{
		Scheme: client2.ClusterScheme,
	})
	Expect(err).ToNot(HaveOccurred())

	err = cl.List(ctx, &corev1.NamespaceList{})
	Expect(err).NotTo(HaveOccurred())

	return cl, version
}

func (te *SuiteTestEnv) getKindClusterPrefix() string {
	if useExistingEnv() {
		return "glk"
	}
	return "e2e"
}

// ExecMake executes one or multiple make targets.
func (te *SuiteTestEnv) ExecMake(ctx context.Context, targets ...string) error {
	cmd := exec.CommandContext(ctx, "make", targets...)
	cmd.Dir = te.workDir
	for _, key := range []string{"PATH", "GOPATH", "HOME"} {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", key, os.Getenv(key)))
	}
	if !useExistingEnv() {
		cmd.Env = append(cmd.Env,
			fmt.Sprintf("GLK_KIND_CLUSTER_PREFIX=%s", te.kindClusterPrefix),
			fmt.Sprintf("GLK_KIND_CLASS_C=%d", 254), // TODO(MartinWeindel) still needed?
		)
	}
	cmdString := fmt.Sprintf("running make %s with prefix %s", strings.Join(targets, " "), te.kindClusterPrefix)
	te.Log.Info(cmdString)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s failed: %s\n%s", cmdString, err, string(output))
	}
	return nil
}

func (te *SuiteTestEnv) KindUp(ctx context.Context) error {
	return te.ExecMake(ctx, "kind-up")
}

func (te *SuiteTestEnv) KindDown(ctx context.Context) error {
	return te.ExecMake(ctx, "kind-down")
}

func (te *SuiteTestEnv) AfterEach() {
	if CurrentSpecReport().Failed() {
		te.DumpState()
	}

	if !useExistingEnv() {
		if err := te.KindDown(context.Background()); err != nil {
			te.Log.Info("kind down failed: " + err.Error())
		}

		devDir := path.Join(te.workDir, "dev")
		entries, _ := os.ReadDir(devDir)
		part := fmt.Sprintf("-%s-", te.kindClusterPrefix)
		prefix := fmt.Sprintf("%s-", te.kindClusterPrefix)
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			if strings.Contains(entry.Name(), part) || strings.HasPrefix(entry.Name(), prefix) {
				_ = os.Remove(path.Join(devDir, entry.Name()))
			}
		}
	}
}

// DumpState dumps the state of a landscape
// The state includes all k8s components running in the shoot itself as well as the controlplane
func (te *SuiteTestEnv) DumpState() {
	if te.DisableStateDump {
		return
	}

	// TODO
	/*
		if te.landscape != nil {
			log := te.Log.WithValues("landscape", client.ObjectKeyFromObject(te.landscape))
			if err := PrettyPrintObject(te.landscape); err != nil {
				log.Error(err, "Cannot decode landscape")
			}
		}
	*/
}

/* TODO
// PrettyPrintObject prints a object as pretty printed yaml to stdout
func PrettyPrintObject(obj runtime.Object) error {
	d, err := yaml.Marshal(obj)
	if err != nil {
		return err
	}
	fmt.Print(string(d))
	return nil
}
*/
