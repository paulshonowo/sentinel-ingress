# ==============================================================================
# Sentinel Serverless Event-Driven Architecture - Complete Infrastructure
# Project ID: cloud-scraper-prod
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Variables & Local Constants
# ------------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "GCP Project ID"
  default     = "cloud-scraper-prod"
}

variable "project_number" {
  type        = string
  description = "GCP Project Number"
  default     = "769466474406"
}

variable "region" {
  type        = string
  description = "GCP Deployment Region"
  default     = "us-central1"
}

variable "notification_email" {
  type        = string
  description = "Operations team alert notification email"
  default     = "admin@example.com"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "project" {
  project_id = var.project_id
}

# ------------------------------------------------------------------------------
# 2. Secret Manager Configuration (JWT Auth)
# ------------------------------------------------------------------------------

resource "random_password" "jwt_secret_value" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "sentinel-jwt-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "jwt_secret_version" {
  secret      = google_secret_manager_secret.jwt_secret.id
  secret_data = random_password.jwt_secret_value.result
}

# ------------------------------------------------------------------------------
# 3. Pub/Sub Messaging Topology & Dead-Letter Queue
# ------------------------------------------------------------------------------

# Main Jobs Topic
resource "google_pubsub_topic" "scrape_jobs" {
  name = "sentinel-scrape-jobs"
}

# Dead-Letter Queue (DLQ) Topic
resource "google_pubsub_topic" "scrape_jobs_dlq" {
  name = "sentinel-scrape-jobs-dlq"
}

# Primary Subscription with Dead-Letter Policy
resource "google_pubsub_subscription" "sentinel_jobs_sub" {
  name  = "sentinel-scrape-jobs-sub"
  topic = google_pubsub_topic.scrape_jobs.name

  ack_deadline_seconds = 20

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.scrape_jobs_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# DLQ Subscription for Inspection & Reprocessing
resource "google_pubsub_subscription" "sentinel_jobs_dlq_sub" {
  name  = "sentinel-scrape-jobs-dlq-sub"
  topic = google_pubsub_topic.scrape_jobs_dlq.name

  ack_deadline_seconds = 60
}

# Pub/Sub System Identity Permissions for DLQ Forwarding
resource "google_pubsub_topic_iam_member" "pubsub_dlq_publisher" {
  topic  = google_pubsub_topic.scrape_jobs_dlq.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "pubsub_dlq_subscriber" {
  subscription = google_pubsub_subscription.sentinel_jobs_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ------------------------------------------------------------------------------
# 4. Ingress Service Identities & IAM
# ------------------------------------------------------------------------------

resource "google_service_account" "ingress_sa" {
  account_id   = "sentinel-ingress-sa"
  display_name = "Sentinel Ingress API Service Account"
}

resource "google_pubsub_topic_iam_member" "ingress_publisher" {
  topic  = google_pubsub_topic.scrape_jobs.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.ingress_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "ingress_secret_accessor" {
  secret_id = google_secret_manager_secret.jwt_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.ingress_sa.email}"
}

# ------------------------------------------------------------------------------
# 5. Worker Service Identities & IAM
# ------------------------------------------------------------------------------

resource "google_service_account" "worker_sa" {
  account_id   = "sentinel-worker-sa"
  display_name = "Sentinel Worker Service Account"
}

resource "google_project_iam_member" "worker_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.worker_sa.email}"
}

resource "google_project_iam_member" "worker_pubsub_viewer" {
  project = var.project_id
  role    = "roles/pubsub.viewer"
  member  = "serviceAccount:${google_service_account.worker_sa.email}"
}

# ------------------------------------------------------------------------------
# 6. Cloud Run Services
# ------------------------------------------------------------------------------

# Sentinel Ingress API Service
resource "google_cloud_run_v2_service" "ingress_api" {
  name     = "sentinel-ingress"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.ingress_sa.email

    containers {
      image = "gcr.io/${var.project_id}/sentinel-ingress:latest"

      ports {
        container_port = 8080
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.scrape_jobs.name
      }
      env {
        name  = "JWT_SECRET_NAME"
        value = google_secret_manager_secret.jwt_secret.secret_id
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image
    ]
  }
}

# Allow unauthenticated public invocations for Ingress API boundary
resource "google_cloud_run_v2_service_iam_member" "ingress_public_access" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.ingress_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Sentinel Worker Consumer Service
resource "google_cloud_run_v2_service" "worker_service" {
  name     = "sentinel-worker"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.worker_sa.email

    containers {
      image = "gcr.io/${var.project_id}/sentinel-worker:latest"

      ports {
        container_port = 8080
      }

      env {
        name  = "PUBSUB_SUBSCRIPTION"
        value = google_pubsub_subscription.sentinel_jobs_sub.name
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image
    ]
  }
}

# ------------------------------------------------------------------------------
# 7. Cloud Monitoring & Alerting for DLQ
# ------------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "email_alert" {
  display_name = "Sentinel Operations Team Email"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
}

resource "google_monitoring_alert_policy" "dlq_message_alert" {
  display_name = "Sentinel DLQ Message Alert - Unacked Messages Detected"
  combiner     = "OR"

  conditions {
    display_name = "Pub/Sub DLQ Undelivered Message Count > 0"

    condition_threshold {
      filter          = "resource.type = \"pubsub_subscription\" AND resource.label.subscription_id = \"${google_pubsub_subscription.sentinel_jobs_dlq_sub.name}\" AND metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email_alert.name
  ]

  alert_strategy {
    auto_close = "604800s"
  }

  documentation {
    content   = "Messages have failed 5 delivery attempts on `sentinel-scrape-jobs-sub` and were moved to the Dead-Letter Queue (`sentinel-scrape-jobs-dlq-sub`). Inspect payload contents in the Pub/Sub console."
    mime_type = "text/markdown"
  }
}

# ------------------------------------------------------------------------------
# 8. Stack Outputs
# ------------------------------------------------------------------------------

output "cloud_run_url" {
  value       = google_cloud_run_v2_service.ingress_api.uri
  description = "Ingress API Service Base URL"
}

output "pubsub_topic_id" {
  value       = google_pubsub_topic.scrape_jobs.id
  description = "Main Jobs Pub/Sub Topic ID"
}

output "pubsub_subscription_id" {
  value       = google_pubsub_subscription.sentinel_jobs_sub.id
  description = "Main Jobs Worker Subscription ID"
}

output "pubsub_dlq_topic_id" {
  value       = google_pubsub_topic.scrape_jobs_dlq.id
  description = "Dead-Letter Queue Pub/Sub Topic ID"
}

output "pubsub_dlq_subscription_id" {
  value       = google_pubsub_subscription.sentinel_jobs_dlq_sub.id
  description = "Dead-Letter Queue Subscription ID"
}

output "worker_service_account_email" {
  value       = google_service_account.worker_sa.email
  description = "Dedicated Service Account Email for Sentinel Worker"
}

# ------------------------------------------------------------------------------
# Reprocessor Service Identity & IAM
# ------------------------------------------------------------------------------

resource "google_service_account" "reprocessor_sa" {
  account_id   = "sentinel-reprocessor-sa"
  display_name = "Sentinel DLQ Reprocessor Service Account"
}

resource "google_project_iam_member" "reprocessor_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.reprocessor_sa.email}"
}

resource "google_pubsub_topic_iam_member" "reprocessor_pubsub_publisher" {
  topic  = google_pubsub_topic.scrape_jobs.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.reprocessor_sa.email}"
}

# ------------------------------------------------------------------------------
# Sentinel Reprocessor Cloud Run Service
# ------------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "reprocessor_service" {
  name     = "sentinel-reprocessor"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.reprocessor_sa.email

    containers {
      image = "gcr.io/${var.project_id}/sentinel-reprocessor:latest"

      ports {
        container_port = 8080
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "MAIN_TOPIC"
        value = google_pubsub_topic.scrape_jobs.name
      }
      env {
        name  = "DLQ_SUBSCRIPTION"
        value = google_pubsub_subscription.sentinel_jobs_dlq_sub.name
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image
    ]
  }
}

# Allow unauthenticated invocation for manual testing boundary
resource "google_cloud_run_v2_service_iam_member" "reprocessor_public_access" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.reprocessor_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ------------------------------------------------------------------------------
# 9. Cloud Scheduler - Automated DLQ Reprocessing Trigger
# ------------------------------------------------------------------------------

resource "google_service_account" "scheduler_sa" {
  account_id   = "sentinel-scheduler-sa"
  display_name = "Sentinel Cloud Scheduler Service Account"
}

# Grant Cloud Scheduler permission to invoke the Reprocessor service
resource "google_cloud_run_v2_service_iam_member" "scheduler_reprocessor_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.reprocessor_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

resource "google_cloud_scheduler_job" "reprocess_dlq_cron" {
  name        = "sentinel-reprocess-dlq-job"
  description = "Triggers automated DLQ reprocessing every 15 minutes"
  schedule    = "*/15 * * * *"
  time_zone   = "UTC"

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.reprocessor_service.uri}/api/v1/reprocess"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      maxMessages = 20
    }))

    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }
}

# ------------------------------------------------------------------------------
# 10. Continuous Integration & Deployment (Cloud Build)
# ------------------------------------------------------------------------------

# Service Account for Cloud Build triggers
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "sentinel-cloudbuild-sa"
  display_name = "Sentinel Cloud Build CI/CD Service Account"
}

# IAM permissions required for Cloud Build to deploy Cloud Run & Artifacts
resource "google_project_iam_member" "cloudbuild_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "cloudbuild_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "cloudbuild_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Cloud Build Trigger for GitHub push events on the main branch
resource "google_cloudbuild_trigger" "github_push_trigger" {
  name        = "sentinel-github-main-trigger"
  description = "Builds container images and deploys Cloud Run services on push to main branch"
  filename    = "cloudbuild.yaml"

  github {
    owner = "paulshonowo"
    name  = "sentinel-ingress"

    push {
      branch = "^main$"
    }
  }

  service_account = google_service_account.cloudbuild_sa.id

  substitutions = {
    _REGION = var.region
  }
}