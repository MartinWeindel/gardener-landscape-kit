/*
 * SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package components

import (
	"fmt"

	configv1alpha1 "github.com/gardener/gardener-landscape-kit/pkg/apis/config/v1alpha1"
	glkComponents "github.com/gardener/gardener-landscape-kit/pkg/components"
	"github.com/gardener/gardener-landscape-kit/pkg/registry"
)

type helperRegistry struct {
	ocm2glk map[string][]string
}

var _ registry.Interface = &helperRegistry{}

func (h *helperRegistry) RegisterComponent(name string, component glkComponents.Interface) {
	if ocmName := component.OCMName(); ocmName != "" {
		h.ocm2glk[ocmName] = append(h.ocm2glk[ocmName], name)
	}
}

func (h *helperRegistry) GenerateBase(_ glkComponents.Options) error {
	return fmt.Errorf("not supported")
}

func (h *helperRegistry) GenerateLandscape(_ glkComponents.LandscapeOptions) error {
	return fmt.Errorf("not supported")
}

func collectRequestedOCMComponentNames(cfg *configv1alpha1.LandscapeKitConfiguration) (map[string][]string, error) {
	helper := &helperRegistry{ocm2glk: map[string][]string{}}
	if err := registry.RegisterAllComponents(helper, cfg); err != nil {
		return nil, err
	}
	return helper.ocm2glk, nil
}
