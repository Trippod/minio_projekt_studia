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
  }
}

#######################
# ZMIENNE (z hasłem domyślnym)
#######################
variable "minio_root_user" {
  description = "Login administratora MinIO"
  type        = string
  default     = "minioadmin"
}

variable "minio_root_password" {
  description = "Hasło administratora MinIO (≥ 8 znaków)"
  type        = string
  default     = "M0cneHaslo_2025!"   # ← wpisane „na stałe”
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
    volume_name    = "minio-data"   # nazwa wolumenu Docker
  }

  command = ["server", "/data", "--console-address", ":9001"]
}

#######################
# 2) Pauza na start (30 s)
#######################
resource "time_sleep" "wait_minio_ready" {
  depends_on      = [docker_container.minio]
  create_duration = "30s"
}

#######################
# 3) Provider MinIO
#######################
provider "minio" {
  minio_server   = "127.0.0.1:9000"   # IPv4, bez http://
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

#######################
# 5) Outputy
#######################
output "console_url" {
  value = "http://localhost:9001"
}

output "root_user" {
  value = var.minio_root_user
}

output "root_password" {
  value     = var.minio_root_password
  sensitive = true              # nie pojawi się w planie ani w logu
}
