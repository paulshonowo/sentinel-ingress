Sentinel: Enterprise Event-Driven Serverless Scraping Pipeline
A production-grade, fault-tolerant event-driven scraping pipeline built on Google Cloud Platform (GCP). Designed around zero-trust identity, least-privilege IAM, automated Dead-Letter Queue (DLQ) remediation, and Infrastructure as Code (IaC).

Architectural Overview
Client sends an HTTP POST payload to sentinel-ingress (Cloud Run).

sentinel-ingress validates the JWT signature and publishes the job to the sentinel-scrape-jobs Pub/Sub topic.

The topic pushes messages to sentinel-worker (Cloud Run).

On successful execution, sentinel-worker dispatches a webhook.

On failure (5 maximum retries), Pub/Sub routes the payload to sentinel-scrape-jobs-dlq.

Cloud Scheduler triggers sentinel-reprocessor every 15 minutes via an OIDC-authenticated HTTP request.

sentinel-reprocessor pulls dead-lettered messages, applies remediation metadata, and re-publishes them to sentinel-scrape-jobs.

Key Technical Highlights
Zero-Trust Ingress Security: Serves as the public API entry point, validating incoming payload signatures using dynamic JWT secrets stored directly in GCP Secret Manager.

Least-Privilege Service Isolation: Enforces strict role boundaries via dedicated IAM Service Accounts (sentinel-ingress-sa, sentinel-worker-sa, sentinel-reprocessor-sa, sentinel-scheduler-sa).

Automated Resilience & DLQ Remediation: Out-of-band Pub/Sub Dead-Letter Queue catches undelivered payloads after 5 attempts. A dedicated sentinel-reprocessor service (triggered via Cloud Scheduler OIDC every 15m) inspects, patches, tags execution metadata, and re-publishes payloads.

100% Infrastructure as Code: Managed declaratively via Terraform (terraform/main.tf), including networking perimeters, service identities, and Pub/Sub IAM subscriptions.

Continuous Integration / Delivery: GitHub push triggers integrated with Cloud Build (cloudbuild.yaml) for zero-downtime container image creation and Cloud Run revision deployments.

Summary Specs
Primary Compute: Cloud Run (Managed Serverless Containers)

Message Broker: GCP Pub/Sub (Exponential Backoff: 10s to 600s)

Secret Management: Secret Manager (sentinel-jwt-secret)

Infrastructure Provisioning: Terraform (cloud-scraper-prod workspace)

Remediation Client: Node.js @google-cloud/pubsub (v1.SubscriberClient)
