terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.25.0"
    }
  }
}

provider "docker" {}

# Crear la red Docker para conectar ambos contenedores
resource "docker_network" "jenkins_network" {
  name = "jenkins"

  ipam_config {
    subnet = "172.18.0.0/16"
    gateway = "172.18.0.1"
  }
}

# Crear volumen para almacenar certificados Docker
resource "docker_volume" "jenkins_docker_certs" {
  name = "jenkins-docker-certs"
}

# Crear volumen para los datos de Jenkins
resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}

# Crear el contenedor Docker-in-Docker (DinD)
resource "docker_container" "jenkins_docker" {
  name         = "dockerindocker"
  image        = "docker:dind"
  privileged   = true
  restart      = "on-failure"
  network_mode = docker_network.jenkins_network.name

  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]

  ports {
    internal = 2376
    external = 2376
  }

  volumes {
    volume_name    = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
  }

  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["dindcontainer"]
    ipv4_address = "172.18.0.2"
  }
}

resource "docker_container" "jenkins_blueocean" {
  depends_on = [docker_container.jenkins_docker]

  name         = "jenkins-blueocean"
  image        = "myjenkins-blueocean"
  restart      = "on-failure"
  network_mode = docker_network.jenkins_network.name

  env = [
    "DOCKER_HOST=tcp://172.18.0.2:2376",      
    "DOCKER_CERT_PATH=/certs/client",      
    "DOCKER_TLS_VERIFY=1"    
  ]

  ports {
    internal = 8080
    external = 8080
  }

  ports {
    internal = 50000
    external = 50000
  }

  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

  volumes {
    volume_name    = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.jenkins_network.name
  }
}
