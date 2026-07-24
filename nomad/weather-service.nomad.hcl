variable "image_tag" {
  type        = string
  description = "Docker image tag produced by the CI/CD pipeline."
  default     = "1.0"
}

job "weather-service" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    image_tag = var.image_tag
  }

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "2m"
    progress_deadline = "3m"
    auto_revert       = true
  }

  group "weather-service" {
    count          = 1
    shutdown_delay = "5s"

    network {
      port "http" {
        to = 3001
      }
    }

    service {
      name         = "weather-service"
      provider     = "consul"
      port         = "http"
      address_mode = "host"

      tags = [
        "app=weather-service",
        "version=${var.image_tag}"
      ]

      check {
        name         = "weather-service-http-health"
        type         = "http"
        path         = "/health"
        port         = "http"
        address_mode = "host"
        interval     = "10s"
        timeout      = "2s"
      }
    }

    task "weather-service" {
      driver = "docker"

      config {
        image      = "nomad-weather-service:${var.image_tag}"
        force_pull = false
        ports      = ["http"]
      }

      env {
        PORT         = "3001"
        SERVICE_NAME = "weather-service"
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
