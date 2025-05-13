########################################
# main.tf – MinIO + Docker + Terraform
########################################
terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    minio = {
      source  = "aminueza/minio"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

#######################
# ZMIENNE
#######################
variable "minio_root_user" {
  description = "Login administratora MinIO"
  type        = string
  default     = "minioadmin"
}

variable "minio_root_password" {
  description = "Hasło administratora MinIO (≥ 8 znaków)"
  type        = string
  default     = "M0cneHaslo_2025!"
  sensitive   = true

  validation {
    condition     = length(var.minio_root_password) >= 8
    error_message = "minio_root_password musi mieć co najmniej 8 znaków."
  }
}

#######################
# 1) Obraz i kontener
#######################
resource "docker_image" "minio" {
  name = "minio/minio:RELEASE.2025-04-22T22-12-26Z"
}

resource "docker_container" "minio" {
  name    = "minio"
  image   = docker_image.minio.image_id
  restart = "unless-stopped"

  env = [
    "MINIO_ROOT_USER=${var.minio_root_user}",
    "MINIO_ROOT_PASSWORD=${var.minio_root_password}"
  ]

  ports {
    internal = 9000
    external = 9000
  }

  ports {
    internal = 9001
    external = 9001
  }

  volumes {
    container_path = "/data"
    volume_name    = "minio-data"
  }

  command = ["server", "/data", "--console-address", ":9001"]
}

#######################
# 2) Pauza na start
#######################
resource "time_sleep" "wait_minio_ready" {
  depends_on      = [docker_container.minio]
  create_duration = "30s"
}

#######################
# 3) Provider MinIO
#######################
provider "minio" {
  minio_server   = "127.0.0.1:9000"
  minio_user     = var.minio_root_user
  minio_password = var.minio_root_password
  minio_ssl      = false
}

#######################
# 4) Bucket + wersjonowanie
#######################
resource "minio_s3_bucket" "raw" {
  depends_on = [time_sleep.wait_minio_ready]
  bucket     = "raw-data"
  acl        = "private"
}

resource "minio_s3_bucket_versioning" "raw_versioning" {
  depends_on = [time_sleep.wait_minio_ready]
  bucket     = minio_s3_bucket.raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

############################
# 5) ROLE IAM
############################
resource "random_password" "admin_secret" {
  length  = 36
  special = false
}

resource "minio_iam_user" "administrator" {
  depends_on = [time_sleep.wait_minio_ready]
  name       = "administrator"
  secret     = random_password.admin_secret.result
}

resource "minio_iam_policy" "AdministratorPolicy" {
  name   = "AdministratorPolicy"
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:*"],
      Resource = ["arn:aws:s3:::*"]
    }]
  })
}

resource "minio_iam_user_policy_attachment" "admin_attach" {
  user_name   = minio_iam_user.administrator.name
  policy_name = minio_iam_policy.AdministratorPolicy.name
}

resource "random_password" "viewer_secret" {
  length  = 30
  special = false
}

resource "minio_iam_user" "viewer" {
  depends_on = [time_sleep.wait_minio_ready]
  name       = "viewer"
  secret     = random_password.viewer_secret.result
}

resource "minio_iam_policy" "ViewerPolicy" {
  name   = "ViewerPolicy"
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = ["arn:aws:s3:::raw-data"]
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject"],
        Resource = ["arn:aws:s3:::raw-data/*"]
      }
    ]
  })
}

resource "minio_iam_user_policy_attachment" "viewer_attach" {
  user_name   = minio_iam_user.viewer.name
  policy_name = minio_iam_policy.ViewerPolicy.name
}

resource "random_password" "uploader_secret" {
  length  = 30
  special = false
}

resource "minio_iam_user" "uploader" {
  depends_on = [time_sleep.wait_minio_ready]
  name       = "uploader"
  secret     = random_password.uploader_secret.result
}

resource "minio_iam_policy" "UploaderPolicy" {
  name   = "UploaderPolicy"
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = ["arn:aws:s3:::raw-data"]
      },
      {
        Effect   = "Allow",
        "Action"   = [
		  "s3:PutObject",
		  "s3:ListMultipartUploadParts",
		  "s3:AbortMultipartUpload"
			],
        Resource = ["arn:aws:s3:::raw-data/*"]
      }
    ]
  })
}

resource "minio_iam_user_policy_attachment" "uploader_attach" {
  user_name   = minio_iam_user.uploader.name
  policy_name = minio_iam_policy.UploaderPolicy.name
}

#######################
# 6) Outputy
#######################
output "console_url" {
  value = "http://localhost:9001"
}

output "root_user" {
  value = var.minio_root_user
}

output "root_password" {
  value     = var.minio_root_password
  sensitive = true
}

output "admin_access_key" {
  value = minio_iam_user.administrator.name
}

output "admin_secret_key" {
  value     = random_password.admin_secret.result
  sensitive = true
}

output "viewer_access_key" {
  value = minio_iam_user.viewer.name
}

output "viewer_secret_key" {
  value     = random_password.viewer_secret.result
  sensitive = true
}

output "uploader_access_key" {
  value = minio_iam_user.uploader.name
}

output "uploader_secret_key" {
  value     = random_password.uploader_secret.result
  sensitive = true
}
