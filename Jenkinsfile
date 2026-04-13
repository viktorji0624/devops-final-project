pipeline {
  agent any

  triggers {
    pollSCM('H/5 * * * *') // SCM polling every 5 minutes
  }

  stages {
    stage('Checkout') {
      steps {
        // Pipeline script is loaded from SCM; this ensures workspace source is present.
        checkout scm
      }
    }

    stage('Build') {
      steps {
        sh './mvnw clean package -DskipTests'
      }
    }

    stage('SonarQube Analysis') {
      steps {
        withSonarQubeEnv('sonarqube') {
          withCredentials([string(credentialsId: 'sonarqube-token-new', variable: 'SONAR_TOKEN')]) {
            sh './mvnw sonar:sonar -Dsonar.projectKey=spring-petclinic -Dsonar.projectName=spring-petclinic -Dsonar.login=$SONAR_TOKEN'
          }
        }
      }
    }

    stage('Security Scan') {
      steps {
        echo 'Expecting Burp HTML report at burpsuite/report/index.html'
        sh 'mkdir -p burpsuite/report'
        sh 'test -f burpsuite/report/index.html'
        sh 'echo "Burp report found"'
        sh 'ls -la burpsuite/report || true'
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          if ! command -v ansible-playbook >/dev/null 2>&1; then
            echo "ERROR: ansible-playbook not found on this Jenkins agent."
            echo "PATH=$PATH"
            echo "If Jenkins runs in Docker, rebuild/recreate the jenkins service so jenkins/Dockerfile is applied:"
            echo "docker compose build --no-cache jenkins && docker compose up -d --force-recreate jenkins"
            exit 127
          fi

          VAGRANT_KEY=$(find /vagrant-keys/machines/default -name private_key -print -quit 2>/dev/null)
          if [ -z "$VAGRANT_KEY" ]; then
            echo "ERROR: Vagrant private key not found at /vagrant-keys/."
            echo "Ensure the VM is running and docker-compose mounts .vagrant to /vagrant-keys."
            exit 1
          fi

          ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
            --private-key "$VAGRANT_KEY" \
            -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
        '''
      }
    }
  }

  post {
    always {
      junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
      publishHTML([
        reportDir: 'burpsuite/report',
        reportFiles: 'index.html',
        reportName: 'Burp Security Report',
        keepAll: true,
        alwaysLinkToLastBuild: true,
        allowMissing: false
      ])
    }
  }
}
