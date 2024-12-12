# Despliegue APP Python con Pipeline de Jenkins con infraestructura gestionada con Terraform

## Infraestructura de Terraform
1. Dockerfile personalizado de Jenkins con Blueocean.
2. Creo la imagen con el comando `docker build -t myjenkins-blueocean .`
3. Inicio del contexto de terraform con `terraform init`
4. Aprovisionamiento de infraestructura en `main.tf`
5. Creación de infraestructura con `terraform apply`
6. Si necesitamos destruir la infraestructura `terraform destroy`

## Ficheros
**Dockerfile**
```Dockerfile
FROM jenkins/jenkins:2.479.2-jdk17    #  Imagen de Jenkins  
USER root
RUN apt-get update && apt-get install -y lsb-release    # Actualizamos paquetes
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
  https://download.docker.com/linux/debian/gpg    # Añadimos la clave del repositorio Docker

# Agregamos el repositorio de docker
RUN echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

RUN apt-get update && apt-get install -y docker-ce-cli

# Instalacion de Python
RUN apt-get install -y python3 python3-pip && \
  ln -sf /usr/bin/python3 /usr/bin/python && ln -sf /usr/bin/pip3 /usr/bin/pip

# Instalamos pytest y pyinstaler para la realización de las pruebas
RUN apt-get install -y python3-pytest
RUN pip install --break-system-packages pyinstaller


USER jenkins
# Instalamos los plugins necesarios de Jenkins
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow token-macro json-path-api"
```

**Main.tf**
```dockerfile
terraform {
  required_providers {      # Especificamos Docker como proveedor
    docker = {  
    source = "kreuzwerker/docker"
    version = "~> 3.0.1"      # Especificamos la versión
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins_network" {
  name = "jenkins_network"    # Creamos una red Docker
}

resource "docker_container" "dind" {
  image = "docker:dind"     # Usamos la imagen de docker dind
  name = "docker-in-docker"
  network_mode = docker_network.jenkins_network.name    # Conectamos el contenedor

  privileged = true     # Privilegios necesarios para dind
  depends_on = [ docker_network.jenkins_network ]

  env = [    # Configuramos de variables de entorno para dind
    "DOCKER_TLS_CERTDIR=/certs",
    "DOCKER_DRIVER=overlay2"
  ]

  ports {
    internal = 2376     # Declaramos el puerto interno para la API de Docker
    external = 2376     # Mapeamos el puerto para el Host
  }
}

resource "docker_container" "jenkins" {
  image = "myjenkins-blueocean" # Imagen personalizada de Jenkins
  name = "jenkins"
  network_mode = docker_network.jenkins_network.name    # Asignamos el contenedor a la red
  restart = "on-failure"     # Reinicio en caso de fallo

  env = [   # Configuramos variables de entorno de Jenkins
    "DOCKER_HOST=tcp://docker-in-docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1"
  ]

  ports {
    internal = 8080     # Declaramos el puerto interno de Jenkins
    external = 8080     # Mapeamos el puerto para el Host
  }

  ports {
    internal = 50000      # Puerto para agentes de Jenkins
    external = 50000      # Mapeamos el puerto para agentes
  }

  depends_on = [ docker_container.dind ]
}
```

## Repositorio de Python pyinstaller
1. Hacer fork del repositorio https://github.com/jenkins-docs/simple-python-pyinstaller-app
2. Clonar el repositorio forkeado a un directorio de fácil acceso (escritorio mismo).


## Construcción de la imagen
1. Creamos un directorio con el archivo dockerfile y main.tf
2. Creamos la imagen con el comando `docker build -t myjenkins-blueocean .`
3. Iniciamos del contexto de terraform con `terraform init`
4. Creamos la infraestructura con `terraform apply`
5. Subimos los archivos a nuestro repositorio en GitHub  
    5.1. Subimos los archivos al área de preparación con `git add .`  
    5.2. Hacemos el commit de los archivos con `git commit -m "Aprovisionamiento de Jenkins"`  
    5.3. Hacemos el push de los archivos del área de preparación con `git push origin main`

## Instalación de Jenkins
1. Accedemos a Jenkins en el puerto 8080.
2. Para ver la contraseña creada por Jenkins automáticamente ejecutamos `docker logs jenkins` o alternativamente podemos acceder a ella a través del documento ubicado en `/var/jenkins_home/secrets/initialAdminPassword`
3. Instalamos los plugins sugeridos por la comunidad.

## Crear Pipeline
1. Selecionamos Nueva Tarea debajo del Dashboard en la esquina superior izquierda.
2. Introducimos el nombre del pipeline: "simple-python-pyinstaller-app"
3. Seleccionamos Pipeline y OK.
4. Seleccionamos Pipeline en el panel izquierdo.
5. Seleccionamos Definition y Pipeline Script from SCM (le indica a Jenkins que obtenga el Pipeline del Source Control Management).
6. Elegimos Git de las opciones del SCM.
7. Introducimos la URL del repositorio de GitHub.
8. Guardamos la configuración.

## Creamos un Jenkinsfile
1. Creamos un nuevo Jenkinsfile en la raiz del proyecto forkeado.
2. Copiamos y pegamos este fragmento de código:
  ```groovy
    pipeline {
      agent any 
      stages {
        stage('Build') { 
          steps {
            sh 'python -m py_compile sources/add2vals.py sources/calc.py' 
            stash(name: 'compiled-results', includes: 'sources/*.py*') 
          }
        }
      }
    }
  ```
3. Guardamos y hacemos commit y push al repositorio.
4. Construimos el Pipeline.
5. Si pulsamos sobre la build vemos detalles de la build.

    5.1 Luego podemos pulsar en el panel izquierdo Pipeline Overview para ver stages del pipeline.
    
    5.2 Si clicamos en el build stage del pipeline podemos ver más información.

6. Ahora añadimos al Jenkinsfile un nuevo stage para hacer testing.
  ```groovy
    pipeline {
      agent any 
      stages {
        stage('Build') { 
          steps {
            sh 'python -m py_compile sources/add2vals.py sources/calc.py' 
            stash(name: 'compiled-results', includes: 'sources/*.py*') 
          }
        }
        stage('Test') {
          steps {
            sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
          }
          post {
            always {
              junit 'test-reports/results.xml'
            }
          }
        }
      }
    }
  ```
7. Subimos de nuevo a GitHub y ejecutamos otra vez.
8. Ahora vemos en la vista de Stage que hay un stage llamado Test. Si clicas en él puedes ver el output de los tests.

9. Ahora añadimos al Jenkinsfile un nuevo Stage llamado Deliver.
  ```groovy
    pipeline {
    agent any 
    stages {
      stage('Build') { 
        steps {
          sh 'python -m py_compile sources/add2vals.py sources/calc.py' 
          stash(name: 'compiled-results', includes: 'sources/*.py*') 
        }
      }
      stage('Test') {
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
        steps {
          sh "pyinstaller --onefile sources/add2vals.py" 
        }
        post {
          success {
            archiveArtifacts 'dist/add2vals' 
          }
        }
      }
    }
  }
  ```

10. Subimos los cambios al repositorio y volvemos a ejecutar el Pipeline.
11. Podemos ver el Pipeline Overview y ver los resultados de la instalación.