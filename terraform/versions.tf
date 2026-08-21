# Copyright 2026 Cisco Systems, Inc. and its affiliates
#
# SPDX-License-Identifier: Apache-2.0
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    fmc = {
      source = "CiscoDevNet/fmc"
      # Pinned to a major version so `terraform init` cannot silently pull a
      # breaking release. Bump deliberately after reading the provider changelog.
      version = "~> 2.5"
    }
  }
}
