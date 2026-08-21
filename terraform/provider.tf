# Copyright 2026 Cisco Systems, Inc. and its affiliates
#
# SPDX-License-Identifier: Apache-2.0
provider "fmc" {
  fmc_username = var.fmc_username
  fmc_password = var.fmc_password
  fmc_host     = var.fmc_url

  # Certificate validation stays on unless you explicitly opt out for a lab FMC.
  fmc_insecure_skip_verify = var.fmc_insecure_skip_verify
}
