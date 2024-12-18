/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  ncc_asn = {
    dmz           = 64512
    landing       = 64515
    nva_primary   = 64513
    nva_secondary = 64514
  }
}

resource "google_network_connectivity_hub" "hub_landing" {
  count       = (var.network_mode == "ncc_ra") ? 1 : 0
  name        = "prod-hub-landing"
  description = "Prod hub landing (trusted)"
  project     = module.landing-project.project_id
}

resource "google_network_connectivity_hub" "hub_dmz" {
  count       = (var.network_mode == "ncc_ra") ? 1 : 0
  name        = "prod-hub-dmz"
  description = "Prod hub DMZ (untrusted)"
  project     = module.landing-project.project_id
}

module "ncc-spokes-landing" {
  for_each   = (var.network_mode == "ncc_ra") ? var.regions : {}
  source     = "../../../modules/ncc-spoke-ra"
  name       = "prod-spoke-landing-${local.region_shortnames[each.value]}"
  project_id = module.landing-project.project_id
  region     = each.value

  hub = {
    create = false,
    id     = google_network_connectivity_hub.hub_landing[0].id
  }

  router_appliances = [
    for key, config in local.bgp_nva_configs :
    {
      internal_ip  = module.nva-bgp[key].internal_ips[1]
      vm_self_link = module.nva-bgp[key].self_link
    } if config.region == each.value
  ]

  router_config = {
    asn = local.ncc_asn.landing
    ip_interface0 = cidrhost(
      module.landing-vpc.subnet_ips["${each.value}/landing-default"], 201
    )
    ip_interface1 = cidrhost(
      module.landing-vpc.subnet_ips["${each.value}/landing-default"], 202
    )
    peer_asn = (
      each.key == "primary"
      ? local.ncc_asn.nva_primary
      : local.ncc_asn.nva_secondary
    )
    routes_priority = 100

    custom_advertise = {
      all_subnets = false
      ip_ranges = {
        (var.gcp_ranges.gcp_landing_primary)   = "GCP landing primary."
        (var.gcp_ranges.gcp_landing_secondary) = "GCP landing secondary."
        (var.gcp_ranges.gcp_dev_primary)       = "GCP dev primary.",
        (var.gcp_ranges.gcp_dev_secondary)     = "GCP dev secondary.",
        (var.gcp_ranges.gcp_prod_primary)      = "GCP prod primary.",
        (var.gcp_ranges.gcp_prod_secondary)    = "GCP prod secondary.",
      }
    }
  }

  vpc_config = {
    network_name     = module.landing-vpc.self_link
    subnet_self_link = module.landing-vpc.subnet_self_links["${each.value}/landing-default"]
  }
}

module "ncc-spokes-dmz" {
  for_each   = (var.network_mode == "ncc_ra") ? var.regions : {}
  source     = "../../../modules/ncc-spoke-ra"
  name       = "prod-spoke-dmz-${local.region_shortnames[each.value]}"
  project_id = module.landing-project.project_id
  region     = each.value

  hub = {
    create = false,
    id     = google_network_connectivity_hub.hub_dmz[0].id
  }

  router_appliances = [
    for key, config in local.bgp_nva_configs :
    {
      internal_ip  = module.nva-bgp[key].internal_ips[0]
      vm_self_link = module.nva-bgp[key].self_link
    } if config.region == each.value
  ]

  router_config = {
    asn = local.ncc_asn.dmz
    ip_interface0 = cidrhost(
      module.dmz-vpc.subnet_ips["${each.value}/dmz-default"], 201
    )
    ip_interface1 = cidrhost(
      module.dmz-vpc.subnet_ips["${each.value}/dmz-default"], 202
    )
    peer_asn = (
      each.key == "primary"
      ? local.ncc_asn.nva_primary
      : local.ncc_asn.nva_secondary
    )
    routes_priority = 100

    custom_advertise = {
      all_subnets = false
      ip_ranges   = { "0.0.0.0/0" = "Default route." }
    }
  }

  vpc_config = {
    network_name     = module.dmz-vpc.self_link
    subnet_self_link = module.dmz-vpc.subnet_self_links["${each.value}/dmz-default"]
  }
}
