variable "image_tag" {
  type        = string
  description = "Docker image tag produced by the CI/CD pipeline."
  default     = "1.0"
}

job "weather-gateway" {
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

  group "weather-gateway" {
    count          = 1
    shutdown_delay = "5s"

    network {
      port "http" {
        static = 8080
        to     = 3000
      }
    }

    service {
      name         = "weather-gateway"
      provider     = "consul"
      port         = "http"
      address_mode = "host"

      tags = [
        "app=weather-gateway",
        "version=${var.image_tag}"
      ]

      check {
        name         = "weather-gateway-http-health"
        type         = "http"
        path         = "/health"
        port         = "http"
        address_mode = "host"
        interval     = "10s"
        timeout      = "2s"
      }
    }

    task "weather-gateway" {
      driver = "docker"

      config {
        image      = "nomad-weather-gateway:${var.image_tag}"
        force_pull = false
        ports      = ["http"]
      }

      env {
        PORT                  = "3000"
        SERVICE_NAME          = "weather-gateway"
        UPSTREAM_SERVICE_NAME = "weather-service"
        REQUEST_TIMEOUT_MS    = "3000"
      }

      template {
        destination = "secrets/upstream.env"
        env         = true
        change_mode = "restart"

        data = <<-EOH
        {{- range service "weather-service|passing" }}
        WEATHER_SERVICE_URL=http://{{ .Address }}:{{ .Port }}
        {{- end }}
        EOH
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
