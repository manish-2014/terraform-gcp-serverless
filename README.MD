# GCP Batch Processing Infrastructure Overview

## Introduction: Why Serverless for Batch Workloads?  
**Serverless** is a cloud‑native model where the provider transparently provisions, scales, and manages compute resources. You pay only for actual usage—no idle servers.  
- **Cost Efficiency**  
  - **Pay‑per‑use**: Billed only for actual CPU, memory, and I/O time.  
  - **No over‑provisioning**: Automatically scales down to zero when idle.  
- **Operational Simplicity**  
  - **No server management**: GCP handles OS updates, patching, and autoscaling.  
  - **Faster deployment**: Focus on code, not infrastructure.  
- **Scalable & Resilient**  
  - **Automatic scaling** under variable batch loads.  
  - **Built‑in retry** and high availability.  

For batch workloads with unpredictable spikes, serverless ensures we never pay for idle capacity and can handle bursts without manual intervention.


## Introduction: Ochestrating Batch Jobs
use the shell script as a guide.


---

## End‑to‑End Workflow  
1. **Shell Script** (`run-batch.sh`)  
   - Invokes the Submitter Function via HTTP.  
2. **Submitter Cloud Function** (`google_cloudfunctions_function.batch_submitter_http_function`)  
   - Validates input, calls Cloud Batch API to launch a job.  
3. **Cloud Batch** (`google_batch_job.batch_job_definition`)  
   - Orchestrates container execution on GCP compute.  
   - Emits lifecycle events (start, success/failure).  
4. **Pub/Sub Topic** (`google_pubsub_topic.batch_status_topic`)  
   - Receives job events from Cloud Batch.  
5. **Eventarc Trigger** (`google_eventarc_trigger.batch_status_to_logger_trigger`)  
   - Routes Pub/Sub messages to the Logger Function.  
6. **Logger Cloud Function** (`google_cloudfunctions_function.batch_status_logger_function`)  
   - Logs state transitions for monitoring and audit.

---

## Main GCP Components & Billing  

| Component                                   | Terraform Resource                                                 | What It Is                                                 | Billing Model                                                           |
|---------------------------------------------|--------------------------------------------------------------------|------------------------------------------------------------|---------------------------------------------------------------------------|
| **Service Account**                         | `module.iam_core.google_service_account.app_sa`                    | Identity under which functions & Batch tasks run           | Free                                                                      |
| **Custom IAM Role**                         | `module.iam_core.google_project_iam_custom_role.bucket_rwl_role`   | Scoped GCS permissions (list, get, create, delete)         | Free                                                                      |
| **Secret Manager Secrets**                  | `module.iam_core.google_secret_manager_secret.*`                   | Stores DB credentials, SSH/PGP keys                        | $0.06 per secret per month + $0.05 per 10K access operations              |
| **Cloud Functions (Submitter & Logger)**    | `google_cloudfunctions_function.batch_submitter_http_function`<br>`google_cloudfunctions_function.batch_status_logger_function` | Event‑driven compute for HTTP & Pub/Sub triggers           | $0.40/million invocations + $0.0000025 per GB‑sec execution + networking  |
| **Cloud Batch**                             | `google_batch_job.batch_job_definition`                            | Managed batch scheduling & execution                       | Charged at underlying VM rates (vCPU, RAM, GPU) only when running        |
| **Pub/Sub Topic**                           | `google_pubsub_topic.batch_status_topic`                           | Asynchronous, at‑least‑once message delivery               | $0.40 per million messages + $0.27 per GB data volume                     |
| **Eventarc Trigger**                        | `google_eventarc_trigger.batch_status_to_logger_trigger`           | Routes events from Pub/Sub → Cloud Function                | $0.10 per million events delivered                                       |
| **GCS Bucket (Function Code)**              | `google_storage_bucket.function_source_code_bucket_cb`             | Stores zipped source artifacts for deployment              | $0.02 per GB‑month storage + network egress                              |

---

## Security Model (Rationale & Details)  
- **Least Privilege**  
  - **`app-sa`** only has roles needed by each workload.  
  - **Custom Role** (`bucket_rwl_role`) limits GCS access to exactly what Functions require.  
- **Separation of Duties**  
  - **Ops SA** (used by Terraform) has `roles/iam.serviceAccountUser` on `app-sa` but **cannot** read secrets or submit jobs directly.  
  - **GCP service agents** (Functions, Batch) impersonate `app-sa` under strict IAM bindings.  
- **Invocation Controls**  
  - **Submitter Function**:  
    - IAM binding in `main.tf`:  
      ```hcl
      resource "google_cloudfunctions_function_iam_member" "invoker" {
        project        = var.project_id
        region         = var.region
        cloud_function = google_cloudfunctions_function.batch_submitter_http_function.name
        role           = "roles/cloudfunctions.invoker"
        member         = "allUsers"  # can be locked down
      }
      ```  
    - Can be scoped to specific IP ranges or VPC Egress.  
  - **Logger Function**:  
    - Only Eventarc service agent can invoke:  
      ```hcl
      resource "google_cloudfunctions_function_iam_member" "eventarc_invoker" {
        cloud_function = google_cloudfunctions_function.batch_status_logger_function.name
        role           = "roles/cloudfunctions.invoker"
        member         = "serviceAccount:service-<proj-number>@gcp-sa-eventarc.iam.gserviceaccount.com"
      }
      ```  
- **Secrets Management**  
  - Defined in `modules/iam_core/main.tf`:  
    ```hcl
    resource "google_secret_manager_secret" "db_password" { … }
    resource "google_secret_manager_secret_version" "db_password_version" { … }
    ```  
  - Only `app-sa` has `roles/secretmanager.secretAccessor` on these secrets.  

---

## Detailed Component Breakdown

### 1. Service Account (`module.iam_core.google_service_account.app_sa`)  
- **What It Is**: A non‑human identity for running functions & tasks.  
- **Roles**:  
  - `roles/batch.jobsEditor` (defined in `modules/batch_deployer/iam.tf`)  
  - `roles/logging.logWriter`, `roles/monitoring.metricWriter`  
  - `roles/secretmanager.secretAccessor` on each secret (`modules/iam_core/secret_iam.tf`)  
- **Billing**: No direct charge for using service accounts.

### 2. Custom IAM Role (`module.iam_core.google_project_iam_custom_role.bucket_rwl_role`)  
- **What It Is**: A scoped set of permissions just for GCS buckets.  
- **Permissions**: `storage.objects.get`, `create`, `delete`, `list`.  
- **Billing**: Free; permissions do not incur cost.

### 3. Secret Manager (`module.iam_core.google_secret_manager_secret.*`)  
- **What It Is**: Managed vault for secrets.  
- **Usage**: Cloud Functions fetch DB credentials at runtime.  
- **Billing**: $0.06/secret‐month + $0.05/10K access operations.

### 4. Submitter Cloud Function  
- **Resource**: `google_cloudfunctions_function.batch_submitter_http_function`  
- **What It Is**:  
  - HTTP endpoint that submits Batch jobs.  
- **Billing**:  
  - Invocations: $0.40/M  
  - Execution: $0.0000025/GB‑s  
  - Networking: Standard egress rates.  
- **Invoke IAM**: `roles/cloudfunctions.invoker` on allUsers (see above).

### 5. Cloud Batch Job Definition  
- **Resource**: `google_batch_job.batch_job_definition`  
- **What It Is**:  
  - Containerized workload specification (image, CPU, memory).  
- **Billing**:  
  - Billed at underlying Compute rates (vCPU $0.010/hr, RAM $0.0014/GB‑hr) only while running.

### 6. Pub/Sub Topic (`google_pubsub_topic.batch_status_topic`)  
- **What It Is**: Messaging channel for job events.  
- **Billing**: $0.40/M messages + $0.27/GB data.

### 7. Eventarc Trigger (`google_eventarc_trigger.batch_status_to_logger_trigger`)  
- **What It Is**: Routes Pub/Sub events to a Cloud Function.  
- **Billing**: $0.10/M events delivered.

### 8. Logger Cloud Function  
- **Resource**: `google_cloudfunctions_function.batch_status_logger_function`  
- **What It Is**:  
  - Logs job state transitions for audit & monitoring.  
- **Billing**: Same as Submitter Function but no public invocation.

---

## Invocation Summary

| Component                    | Invocation Method | Invoker            | Required Invoker Role      |
|------------------------------|-------------------|--------------------|----------------------------|
| Submitter Cloud Function     | HTTP POST         | **User** (script)  | `roles/cloudfunctions.invoker` |
| Logger Cloud Function        | Eventarc          | **System**         | `roles/cloudfunctions.invoker` (Eventarc service account) |
| Terraform Apply              | CLI / CI/CD       | **Ops SA**         |  
|                              |                   |                    | `roles/iam.serviceAccountUser` on `app-sa`<br>`roles/resourcemanager.projectIamAdmin`<br>`roles/serviceusage.serviceUsageAdmin`<br>`roles/cloudfunctions.admin`<br>`roles/batch.admin`<br>`roles/pubsub.admin` |

---


