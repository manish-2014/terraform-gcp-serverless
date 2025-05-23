###############################################################################
# provider.tf  –  updated for Cloud Functions service‑agent fix
###############################################################################

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.31"          # keep in lock‑step with google‑beta
    }
    # --- NEW: beta provider -----------------------------------------------
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.31"
    }
    # ----------------------------------------------------------------------
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

###############################################################################
# Default Google provider (GA)
###############################################################################
provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = file(var.service_account_key_path)
}

###############################################################################
# Beta provider – required only for google_project_service_identity
###############################################################################
provider "google-beta" {
  project     = var.project_id
  region      = var.region
  credentials = file(var.service_account_key_path)
}

# The other providers need no extra configuration
provider "random"  {}
provider "archive" {}
provider "time"    {}
