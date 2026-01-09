/*
 * SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package landscape

import (
	"context"
	"time"

	"github.com/gardener/gardener/pkg/logger"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
)

var (
	suiteContext       context.Context
	suiteContextCancel context.CancelFunc

	_ = BeforeSuite(func() {
		suiteCfg, _ := GinkgoConfiguration()
		suiteContext, suiteContextCancel = context.WithTimeout(context.Background(), suiteCfg.Timeout*90/100)
	})

	_ = AfterSuite(func() {
		if suiteContextCancel != nil {
			suiteContextCancel()
		}
	})
)

var _ = Describe("GLK Tests", Label("Local", "default"), func() {
	var testEnv *SuiteTestEnv

	BeforeEach(func() {
		testEnv = NewSuiteTestEnv(GinkgoParallelProcess())
		logf.SetLogger(logger.MustNewZapLogger(logger.InfoLevel, logger.FormatJSON, zap.WriteTo(GinkgoWriter)))
	})

	AfterEach(func() {
		testEnv.AfterEach()
	})

	It("Creates the Landscape on KinD cluster", Offset(1), Label("single"), func() {
		testEnv.CreateCluster(suiteContext)

		By("Prepare", func() {
			Expect(testEnv.ExecMake(suiteContext, "e2e-prepare")).NotTo(HaveOccurred())
		})

		By("VerifyFluxSystem", func() {
			testEnv.VerifyFluxKustomization(suiteContext, "flux-system", "flux-system", 3*time.Minute)
		})
		By("VerifyGardenerOperatorDeployment", func() {
			testEnv.VerifyGardenerOperatorDeployment(suiteContext)
		})
		for _, name := range []string{
			"gardener-operator", "garden", "provider-local", "extension-networking-calico", "extension-networking-cilium",
		} {
			By("Verify"+name+"FluxKustomization", func() {
				testEnv.VerifyFluxKustomization(suiteContext, "garden", name)
			})
		}
	})
})
