# Despliegue APP Python con Pipeline de Jenkins con infraestructura gestionada con Terraform

## Autores

Ezequiel Lemos Cárdenas  
Andrés Montoro Venegas

## 1. Repositorio de Python pyinstaller
1. Hacer fork del repositorio https://github.com/jenkins-docs/simple-python-pyinstaller-app
2. Clonar el repositorio forkeado a un directorio de fácil acceso (escritorio mismo).
3. Creamos una rama `main` donde crearemos los archivos.
4. En esta nueva rama, creamos una carpeta `docs` en la raíz del repostitorio.

## 2. Creación de los ficheros necesarios
**Dockerfile**
```Dockerfile
FROM jenkins/jenkins:2.479.2-jdk17  #  Imagen de Jenkins  
USER root
RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \  
https://download.docker.com/linux/debian/gpg  # Añadimos la clave del repositorio Docker

# Agregamos el repositorio de docker
RUN echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list


# Actualizamos y instalamos docker-ce-cli y los plugins de jenkins
RUN apt-get update && apt-get install -y docker-ce-cli
USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow token-macro json-path-api"
```

**Main.tf**
```dockerfile
terraform {
  required_providers {    # Especificamos Docker como proveedor
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"  # Especificamos la versión
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
    internal = 2376   # Declaramos el puerto interno para la API de Docker
    external = 2376   # Mapeamos el puerto para el Host
  }

# Montamos el volumen para poder acceder al certificado Dind
  volumes {
    volume_name    = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
  }

# Montamos el volumen para poder acceder a los datos de jenkins
  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

# Indicamos a la red de forma que Jenkins pueda comunicarse con Dind
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

  env = [   # Configuramos variables de entorno de Jenkins
    "DOCKER_HOST=tcp://172.18.0.2:2376",      
    "DOCKER_CERT_PATH=/certs/client",      
    "DOCKER_TLS_VERIFY=1"    
  ]

  ports {
    internal = 8080   # Declaramos el puerto interno de Jenkins
    external = 8080   # Mapeamos el puerto para el Host
  }

  ports {
    internal = 50000    # Puerto para agentes de Jenkins
    external = 50000    # Mapeamos el puerto para agentes
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
```


## 3. Construcción de la imagen
1. Abrimos la terminal en la dirección donde se encuentra la carpeta `docs` con nuestro `dockerfile` y `main.tf`
2. Creamos la imagen con el comando `docker build -t myjenkins-blueocean .`
3. Iniciamos del contexto de terraform con `terraform init`
4. Creamos la infraestructura con `terraform apply`
5. Subimos los archivos a nuestro repositorio en GitHub  
    5.1. Subimos los archivos al área de preparación con `git add .` desde la rama `main`  
    5.2. Hacemos el commit de los archivos con `git commit -m "Aprovisionamiento de Jenkins"`  
    5.3. Hacemos el push de los archivos del área de preparación con `git push origin main`

## 3. Instalación de Jenkins
1. Accedemos a Jenkins en el puerto 8080.
2. Para ver la contraseña creada por Jenkins automáticamente ejecutamos `docker logs jenkins` o alternativamente podemos acceder a ella a través del documento ubicado en `/var/jenkins_home/secrets/initialAdminPassword`
3. Instalamos los plugins sugeridos por la comunidad.

## 4. Creamos un Jenkinsfile
1. Creamos un nuevo Jenkinsfile en la carpeta `docs` del proyecto forkeado.
2. Copiamos y pegamos el Jenkinsfile del enunciado:
  ```groovy
  pipeline {
    agent none
    options {
      skipStagesAfterUnstable()
    }

    stages {
      stage('Build') {
        agent {
          docker {
            image 'python:3.12.0-alpine3.18'
          }
        }
        steps {
          sh 'python -m py_compile sources/add2vals.py sources/calc.py'
          stash(name: 'compiled-results', includes: 'sources/*.py*')
        }
      }
      stage('Test') {
        agent {
          docker {
            image 'qnib/pytest'
          }
        }
        steps {
          sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
        }
        post {
          always {
            junit 'test-reports/results.xml'
          }
        }
      }
      stage('Deliver') {
        agent any
        environment {
          VOLUME = '$(pwd)/sources:/src'
          IMAGE = 'cdrx/pyinstaller-linux:python2'
        }
        steps {
          dir(path: env.BUILD_ID) {
            unstash(name: 'compiled-results')
            sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'"
          }
        }
        post {
          success {
            archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals"
            sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
          }
        }
      }
    }
  }
  ```

  3. Subimos los cambios a GitHub

## 5. Creación del Pipeline
1. Selecionamos Nueva Tarea debajo del Dashboard en la esquina superior izquierda.
2. Introducimos el nombre del pipeline: "simple-python-pyinstaller-app"
3. Seleccionamos Pipeline y OK.
4. Seleccionamos Pipeline en el panel izquierdo.
5. Seleccionamos Definition y Pipeline Script from SCM (le indica a Jenkins que obtenga el Pipeline del Source Control Management).
6. Elegimos `Git` de las opciones del SCM.
7. Introducimos la URL del repositorio de GitHub.
8. Indicamos que use la rama `main`.
9. En Script Path indicamos el directorio del Jenkinsfile `docs/Jenkinsfile.`
8. Guardamos la configuración.

## 6. Construimos el Pipeline
1. Seleccionamos la opción `Construir ahora` entre las opciones que aparecen en el panel de control del pipeline
2. En la parte `Builds` de este panel aparecera el proceso de construcción del pipeline, accedemos a él.
3. Ahora nos apareceran nuevas opciones como `Pipeline Overview`, en la cual se nos detallará como se va construyendo la build.
4. Comprobamos que el pipeline se ha ejecutado correctamente.
